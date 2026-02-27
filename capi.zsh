#!/usr/bin/env zsh
# capi - Claude Code & Codex CLI API 统一管理工具
# 配置文件: ~/.claude/apis.json
# 用法: capi [claude|codex] <command>

_CAPI_FILE="$HOME/.claude/apis.json"
_CAPI_VERSION="0.1.0"
_CAPI_TOOLS=(claude codex)
_CAPI_LOCK_WARNED=0
_CAPI_DEFAULT_TEST_MODEL_CLAUDE="claude-sonnet-4-20250514"
_CAPI_DEFAULT_TEST_MODEL_CODEX="gpt-5"

# ─── 内部工具函数 ───

# 读取指定工具的字段
_capi_get() { jq -r ".$1" "$_CAPI_FILE" 2>/dev/null; }

_capi_tool_usage() {
  local IFS='|'
  echo "${_CAPI_TOOLS[*]}"
}

_capi_is_supported_tool() {
  local candidate="$1"
  local t
  for t in "${_CAPI_TOOLS[@]}"; do
    [[ "$candidate" == "$t" ]] && return 0
  done
  return 1
}

# 对目标文件执行带锁操作；若缺少 flock，降级为无锁写入并提示一次
_capi_with_lock() {
  local target_file="$1"
  shift
  local lock_file="${target_file}.lock"

  if command -v flock >/dev/null 2>&1; then
    (
      flock -x 9 || exit 1
      "$@"
    ) 9>"$lock_file"
    return $?
  fi

  if [[ $_CAPI_LOCK_WARNED -eq 0 ]]; then
    echo "⚠ 未找到 flock，降级为无锁写入（建议安装：brew install flock）" >&2
    _CAPI_LOCK_WARNED=1
  fi
  "$@"
}

_capi_secure_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  chmod 600 "$file" 2>/dev/null || true
}

_capi_write_with_jq() {
  local file="$1"
  local tmp="$2"
  shift 2
  jq "$@" "$file" > "$tmp"
}

_capi_write_unlocked() {
  local file="$1"
  local writer="$2"
  shift 2

  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/capi-write.XXXXXX") || return 1

  (
    trap 'rm -f "$tmp"' EXIT INT TERM HUP
    "$writer" "$file" "$tmp" "$@" || exit 1
    mv "$tmp" "$file" || exit 1
  ) || return 1

  _capi_secure_file "$file"
}

_capi_write() {
  local file="$1"
  shift
  _capi_with_lock "$file" _capi_write_unlocked "$file" _capi_write_with_jq "$@"
}

_capi_api_ids() {
  local tool="$1"
  jq -r --arg tool "$tool" '.[$tool].apis | keys[]' "$_CAPI_FILE" 2>/dev/null
}

_capi_fallback_order() {
  local tool="$1"
  jq -r --arg tool "$tool" '.[$tool].fallback_order[]' "$_CAPI_FILE" 2>/dev/null
}

_capi_find_login_id() {
  local tool="$1"
  jq -r --arg tool "$tool" '.[$tool].apis | to_entries[] | select(.value.mode=="login") | .key' "$_CAPI_FILE" 2>/dev/null | head -n 1
}

_capi_update_claude_config_unlocked() {
  local config_file="$1"
  local mode="$2"
  local key="$3"
  [[ ! -f "$config_file" ]] && return 0

  if [[ "$mode" == "login" ]]; then
    _capi_write_unlocked "$config_file" _capi_write_with_jq 'del(.primaryApiKey)'
  else
    _capi_write_unlocked "$config_file" _capi_write_with_jq --arg k "$key" '.primaryApiKey=$k'
  fi
}

_capi_update_codex_toml_unlocked() {
  local toml="$1"
  local mode="$2"
  local active="$3"
  local name="$4"
  local url="$5"
  local key="$6"
  local wire="$7"

  if [[ "$mode" == "login" ]]; then
    sed -i '' 's/^model_provider = .*/model_provider = ""/' "$toml"
    return 0
  fi

  # 全局替换所有 model_provider 行（全局 + profile 级别）
  sed -i '' "s/^model_provider = .*/model_provider = \"${active}\"/" "$toml"

  # 确保 [model_providers.xxx] 段存在
  if ! grep -q "^\[model_providers\.${active}\]" "$toml"; then
    printf '\n[model_providers.%s]\nname = "%s"\nbase_url = "%s"\nexperimental_bearer_token = "%s"\nwire_api = "%s"\n' \
      "$active" "$name" "$url" "$key" "$wire" >> "$toml"
  fi
}

_capi_mask_key() {
  local key="$1"
  local len=${#key}
  if (( len <= 2 )); then
    echo "$key"
  elif (( len <= 6 )); then
    echo "${key:0:1}...${key: -1}"
  else
    echo "${key:0:4}...${key: -2}"
  fi
}

# 构造 Claude messages endpoint
_capi_claude_endpoint() {
  local url="${1%/}"
  [[ "$url" == */v1 ]] && echo "$url/messages" || echo "$url/v1/messages"
}

# 测试单个 API，返回 0=成功 1=失败
_capi_test_one() {
  local tool="$1" id="$2"
  local mode=$(_capi_get "${tool}.apis.\"${id}\".mode // empty")
  [[ "$mode" == "login" ]] && return 2  # 登录模式跳过

  local url=$(_capi_get "${tool}.apis.\"${id}\".url")
  local key=$(_capi_get "${tool}.apis.\"${id}\".key")
  local tmpbody
  tmpbody=$(mktemp) || return 1
  local http_code=""

  if [[ "$tool" == "claude" ]]; then
    local test_model=$(_capi_get "${tool}.apis.\"${id}\".test_model // \"${_CAPI_DEFAULT_TEST_MODEL_CLAUDE}\"")
    local endpoint=$(_capi_claude_endpoint "$url")
    local auth_header="x-api-key: $key"
    local payload
    payload=$(jq -cn --arg model "$test_model" '{"model":$model,"max_tokens":1,"messages":[{"role":"user","content":"hi"}]}') || {
      rm -f "$tmpbody"
      return 1
    }
    # ktp_ 开头用 Bearer
    [[ "$key" == ktp_* ]] && auth_header="Authorization: Bearer $key"
    http_code=$(curl -s -o "$tmpbody" -w '%{http_code}' --max-time 8 \
      "$endpoint" \
      -H "$auth_header" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "$payload" 2>/dev/null)
  elif [[ "$tool" == "codex" ]]; then
    local wire_api=$(_capi_get "${tool}.apis.\"${id}\".wire_api // \"responses\"")
    local test_model=$(_capi_get "${tool}.apis.\"${id}\".test_model // \"${_CAPI_DEFAULT_TEST_MODEL_CODEX}\"")
    local endpoint="${url%/}/responses"
    local payload
    if [[ "$wire_api" == "chat" ]]; then
      endpoint="${url%/}/chat/completions"
      payload=$(jq -cn --arg model "$test_model" '{"model":$model,"messages":[{"role":"user","content":"hi"}],"max_tokens":1}') || {
        rm -f "$tmpbody"
        return 1
      }
    else
      payload=$(jq -cn --arg model "$test_model" '{"model":$model,"input":"hi","max_output_tokens":1}') || {
        rm -f "$tmpbody"
        return 1
      }
    fi
    http_code=$(curl -s -o "$tmpbody" -w '%{http_code}' --max-time 8 \
      "$endpoint" \
      -H "Authorization: Bearer $key" \
      -H "content-type: application/json" \
      -d "$payload" 2>/dev/null)
  fi

  local result=1
  [[ "$http_code" =~ ^2 ]] && result=0

  if [[ $result -ne 0 ]]; then
    _CAPI_LAST_ERR=$(jq -r '.error.message // .error.type // empty' "$tmpbody" 2>/dev/null)
    [[ ${#_CAPI_LAST_ERR} -gt 80 ]] && _CAPI_LAST_ERR="${_CAPI_LAST_ERR:0:77}..."
    [[ -z "$_CAPI_LAST_ERR" ]] && _CAPI_LAST_ERR="HTTP $http_code"
  fi
  rm -f "$tmpbody"
  return $result
}

# ─── 加载配置 ───

_capi_load_claude() {
  [[ ! -f "$_CAPI_FILE" ]] && return 1
  local active=$(_capi_get 'claude.active')
  local mode=$(_capi_get "claude.apis.\"${active}\".mode // empty")
  local config_file="$HOME/.claude/config.json"
  local key=$(_capi_get "claude.apis.\"${active}\".key")

  if [[ "$mode" == "login" ]]; then
    unset ANTHROPIC_BASE_URL ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
    [[ -f "$config_file" ]] && _capi_with_lock "$config_file" _capi_update_claude_config_unlocked "$config_file" "$mode" "$key"
  else
    local url=$(_capi_get "claude.apis.\"${active}\".url")
    if [[ "$url" != "null" && "$key" != "null" ]]; then
      export ANTHROPIC_BASE_URL="$url"
      export ANTHROPIC_API_KEY="$key"
      export ANTHROPIC_AUTH_TOKEN="$key"
      [[ -f "$config_file" ]] && _capi_with_lock "$config_file" _capi_update_claude_config_unlocked "$config_file" "$mode" "$key"
    fi
  fi
}

_capi_load_codex() {
  [[ ! -f "$_CAPI_FILE" ]] && return 1
  local active=$(_capi_get 'codex.active')
  local mode=$(_capi_get "codex.apis.\"${active}\".mode // empty")
  local toml="$HOME/.codex/config.toml"
  [[ ! -f "$toml" ]] && return 1
  local name=$(_capi_get "codex.apis.\"${active}\".name // empty")
  local url=$(_capi_get "codex.apis.\"${active}\".url // empty")
  local key=$(_capi_get "codex.apis.\"${active}\".key // empty")
  local wire=$(_capi_get "codex.apis.\"${active}\".wire_api // \"responses\"")

  _capi_with_lock "$toml" _capi_update_codex_toml_unlocked "$toml" "$mode" "$active" "$name" "$url" "$key" "$wire"
}

_capi_load() {
  _capi_secure_file "$_CAPI_FILE"
  local t loader
  for t in "${_CAPI_TOOLS[@]}"; do
    loader="_capi_load_${t}"
    if typeset -f "$loader" >/dev/null 2>&1; then
      "$loader"
    fi
  done
}

# ─── 主命令 ───

capi() {
  local tool="" cmd=""
  local tool_usage="$(_capi_tool_usage)"

  # 解析参数：capi [tool] <command> [args...]
  if _capi_is_supported_tool "${1:-}"; then
    tool="$1"; shift
  fi
  cmd="${1:-list}"; shift 2>/dev/null

  local tools=()
  if [[ -n "$tool" ]]; then
    tools=("$tool")
  else
    tools=("${_CAPI_TOOLS[@]}")
  fi

  case "$cmd" in
    list|ls)
      for t in "${tools[@]}"; do
        local active=$(_capi_get "${t}.active")
        echo "${t:u} API 列表:"
        echo "─────────────────────────────────"
        local ids=($(_capi_api_ids "$t"))
        for id in "${ids[@]}"; do
          local name=$(_capi_get "${t}.apis.\"${id}\".name")
          local mode=$(_capi_get "${t}.apis.\"${id}\".mode // empty")
          local url=$(_capi_get "${t}.apis.\"${id}\".url // empty")
          local mark="  "
          [[ "$id" == "$active" ]] && mark="● "
          echo "  ${mark}${id}  ($name)"
          [[ "$mode" == "login" ]] && echo "      [账号登录]" || echo "      $url"
        done
        echo "─────────────────────────────────"
        echo "当前: $active"
        echo ""
      done
      ;;

    use|switch)
      [[ ${#tools[@]} -gt 1 ]] && { echo "用法: capi <${tool_usage}> use [id]"; return 1; }
      local t="${tools[1]}" id="$1"
      if [[ -z "$id" ]]; then
        local active=$(_capi_get "${t}.active")
        local ids=($(_capi_api_ids "$t"))
        echo "选择 ${t:u} API:"
        local i=1
        for aid in "${ids[@]}"; do
          local name=$(_capi_get "${t}.apis.\"${aid}\".name")
          local mark=" "
          [[ "$aid" == "$active" ]] && mark="●"
          echo "  $mark $i) $aid ($name)"
          ((i++))
        done
        echo -n "输入编号或名称: "
        read choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ids[@]} )); then
          id="${ids[$choice]}"
        else
          id="$choice"
        fi
      fi
      local exists=$(_capi_get "${t}.apis.\"${id}\" // empty")
      [[ -z "$exists" ]] && { echo "✗ API '$id' 不存在"; return 1; }
      _capi_write "$_CAPI_FILE" --arg tool "$t" --arg id "$id" '.[$tool].active = $id' || {
        echo "✗ 写入配置失败"
        return 1
      }
      _capi_load_${t}
      echo "✓ 已切换 ${t:u} 到: $id ($(_capi_get "${t}.apis.\"${id}\".name"))"
      echo "  重启 ${t:u} 生效。"
      ;;

    add)
      [[ ${#tools[@]} -gt 1 ]] && { echo "用法: capi <${tool_usage}> add [id]"; return 1; }
      local t="${tools[1]}" id="$1"
      [[ -z "$id" ]] && { echo -n "API 标识: "; read id; }
      local exists=$(_capi_get "${t}.apis.\"${id}\" // empty")
      [[ -n "$exists" ]] && { echo "✗ '$id' 已存在"; return 1; }
      echo -n "显示名称: "; read name
      echo -n "API URL: "; read url
      echo -n "API Key: "; read -s key; echo
      if [[ "$t" == "codex" ]]; then
        echo -n "wire_api (responses/chat): "
        read wire
        _capi_write "$_CAPI_FILE" \
          --arg tool "$t" \
          --arg id "$id" \
          --arg name "$name" \
          --arg url "$url" \
          --arg key "$key" \
          --arg wire "${wire:-responses}" \
          '.[$tool].apis[$id] = {"name":$name,"url":$url,"key":$key,"wire_api":$wire} | .[$tool].fallback_order += [$id]' || {
          echo "✗ 写入配置失败"
          return 1
        }
      else
        _capi_write "$_CAPI_FILE" \
          --arg tool "$t" \
          --arg id "$id" \
          --arg name "$name" \
          --arg url "$url" \
          --arg key "$key" \
          '.[$tool].apis[$id] = {"name":$name,"url":$url,"key":$key} | .[$tool].fallback_order += [$id]' || {
          echo "✗ 写入配置失败"
          return 1
        }
      fi
      echo "✓ 已添加: $id ($name)"
      ;;

    rm|remove|del)
      [[ ${#tools[@]} -gt 1 ]] && { echo "用法: capi <${tool_usage}> rm <id>"; return 1; }
      local t="${tools[1]}" id="$1"
      [[ -z "$id" ]] && { echo "用法: capi $t rm <id>"; return 1; }
      local active=$(_capi_get "${t}.active")
      [[ "$id" == "$active" ]] && { echo "✗ 不能删除当前激活的 API"; return 1; }
      _capi_write "$_CAPI_FILE" --arg tool "$t" --arg id "$id" 'del(.[$tool].apis[$id]) | .[$tool].fallback_order -= [$id]' || {
        echo "✗ 写入配置失败"
        return 1
      }
      echo "✓ 已删除: $id"
      ;;

    test|check)
      local target_id="$1"
      for t in "${tools[@]}"; do
        local active=$(_capi_get "${t}.active")
        local ids
        [[ -n "$target_id" ]] && ids=("$target_id") || ids=($(_capi_api_ids "$t"))
        echo "检测 ${t:u} API 可用性..."
        echo "─────────────────────────────────"
        for aid in "${ids[@]}"; do
          local name=$(_capi_get "${t}.apis.\"${aid}\".name")
          local mark=" "
          [[ "$aid" == "$active" ]] && mark="●"
          echo -n "  $mark $aid ($name) ... "
          local start_s=$(date +%s)
          _CAPI_LAST_ERR=""
          _capi_test_one "$t" "$aid"
          local rc=$?
          local elapsed=$(( $(date +%s) - start_s ))
          if [[ $rc -eq 0 ]]; then
            echo "✓ UP (${elapsed}s)"
          elif [[ $rc -eq 2 ]]; then
            echo "⊘ 跳过（登录模式）"
          else
            echo "✗ DOWN — $_CAPI_LAST_ERR"
          fi
        done
        echo "─────────────────────────────────"
        echo ""
      done
      ;;

    fallback|fb)
      for t in "${tools[@]}"; do
        local active=$(_capi_get "${t}.active")
        echo -n "${t:u}: 测试当前 ($active) ... "

        _CAPI_LAST_ERR=""
        _capi_test_one "$t" "$active"
        local rc=$?
        if [[ $rc -eq 0 ]]; then
          echo "✓ 正常"
          continue
        elif [[ $rc -eq 2 ]]; then
          echo "⊘ 登录模式，跳过"
          continue
        fi
        echo "✗ 不可用 — $_CAPI_LAST_ERR"

        # 按 fallback_order 尝试
        local order=($(_capi_fallback_order "$t"))
        local switched=0
        for fid in "${order[@]}"; do
          [[ "$fid" == "$active" ]] && continue
          local mode=$(_capi_get "${t}.apis.\"${fid}\".mode // empty")
          [[ "$mode" == "login" ]] && continue
          echo -n "  尝试 $fid ... "
          _CAPI_LAST_ERR=""
          _capi_test_one "$t" "$fid"
          if [[ $? -eq 0 ]]; then
            _capi_write "$_CAPI_FILE" --arg tool "$t" --arg id "$fid" '.[$tool].active = $id' || {
              echo "✗ 写入配置失败"
              continue
            }
            _capi_load_${t}
            echo "✓"
            echo "  ⚡ 已自动切换到: $fid ($(_capi_get "${t}.apis.\"${fid}\".name"))"
            switched=1
            break
          else
            echo "✗ $_CAPI_LAST_ERR"
          fi
        done
        if [[ $switched -eq 0 ]]; then
          echo "  ✗ 所有 API 均不可用"
          local login_id=$(_capi_find_login_id "$t")
          if [[ -n "$login_id" ]]; then
            echo "  提示: 可切换到登录模式：capi $t use $login_id"
          fi
        fi
      done
      ;;

    current|status)
      for t in "${tools[@]}"; do
        local active=$(_capi_get "${t}.active")
        local name=$(_capi_get "${t}.apis.\"${active}\".name")
        local mode=$(_capi_get "${t}.apis.\"${active}\".mode // empty")
        echo "${t:u}: $active ($name)"
        if [[ "$mode" == "login" ]]; then
          echo "  [账号登录]"
        else
          local url=$(_capi_get "${t}.apis.\"${active}\".url")
          local key=$(_capi_get "${t}.apis.\"${active}\".key")
          echo "  URL: $url"
          echo "  Key: $(_capi_mask_key "$key")"
        fi
        echo ""
      done
      ;;

    version|--version|-v)
      echo "capi ${_CAPI_VERSION}"
      ;;

    help|--help|-h)
      cat <<EOF
capi - Claude Code & Codex CLI API 统一管理工具

用法: capi [${tool_usage}] <command>

命令:
  list              列出 API 配置
  use [id]          切换 API（需指定工具）
  add [id]          添加 API（需指定工具）
  rm <id>           删除 API（需指定工具）
  test [id]         检测可用性
  fallback          自动 fallback（当前不可用则切换）
  current           显示当前配置
  version           显示 capi 版本
  help              帮助

示例:
  capi                      查看全部配置
  capi claude use aws       切换 Claude 到 aws
  capi codex use infiniteai 切换 Codex 到 infiniteai
  capi test                 测试所有 API
  capi fallback             自动 fallback
EOF
      ;;

    *)
      echo "未知命令: $cmd。用 capi help 查看帮助。"
      return 1
      ;;
  esac
}

# 启动时自动加载
_capi_load
