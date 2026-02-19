#!/usr/bin/env zsh
# capi - Claude Code & Codex CLI API 统一管理工具
# 配置文件: ~/.claude/apis.json
# 用法: capi [claude|codex] <command>

_CAPI_FILE="$HOME/.claude/apis.json"
_CAPI_TOOLS=(claude codex)

# ─── 内部工具函数 ───

# 读取指定工具的字段
_capi_get() { jq -r ".$1" "$_CAPI_FILE" 2>/dev/null; }

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
  local tmpbody=$(mktemp)
  local http_code=""

  if [[ "$tool" == "claude" ]]; then
    local endpoint=$(_capi_claude_endpoint "$url")
    local auth_header="x-api-key: $key"
    # ktp_ 开头用 Bearer
    [[ "$key" == ktp_* ]] && auth_header="Authorization: Bearer $key"
    http_code=$(curl -s -o "$tmpbody" -w '%{http_code}' --max-time 8 \
      "$endpoint" \
      -H "$auth_header" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d '{"model":"claude-sonnet-4-20250514","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' 2>/dev/null)
  elif [[ "$tool" == "codex" ]]; then
    http_code=$(curl -s -o "$tmpbody" -w '%{http_code}' --max-time 8 \
      "${url%/}/responses" \
      -H "Authorization: Bearer $key" \
      -H "content-type: application/json" \
      -d '{"model":"gpt-5","input":"hi","max_output_tokens":1}' 2>/dev/null)
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

  if [[ "$mode" == "login" ]]; then
    unset ANTHROPIC_BASE_URL ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
    [[ -f "$config_file" ]] && { local tmp=$(mktemp); jq 'del(.primaryApiKey)' "$config_file" > "$tmp" && mv "$tmp" "$config_file"; }
  else
    local url=$(_capi_get "claude.apis.\"${active}\".url")
    local key=$(_capi_get "claude.apis.\"${active}\".key")
    if [[ "$url" != "null" && "$key" != "null" ]]; then
      export ANTHROPIC_BASE_URL="$url"
      export ANTHROPIC_API_KEY="$key"
      export ANTHROPIC_AUTH_TOKEN="$key"
      [[ -f "$config_file" ]] && { local tmp=$(mktemp); jq --arg k "$key" '.primaryApiKey=$k' "$config_file" > "$tmp" && mv "$tmp" "$config_file"; }
    fi
  fi
}

_capi_load_codex() {
  [[ ! -f "$_CAPI_FILE" ]] && return 1
  local active=$(_capi_get 'codex.active')
  local mode=$(_capi_get "codex.apis.\"${active}\".mode // empty")
  local toml="$HOME/.codex/config.toml"
  [[ ! -f "$toml" ]] && return 1

  if [[ "$mode" == "login" ]]; then
    # 登录模式：清除 model_provider
    sed -i '' 's/^model_provider = .*/model_provider = ""/' "$toml"
  else
    local url=$(_capi_get "codex.apis.\"${active}\".url")
    local key=$(_capi_get "codex.apis.\"${active}\".key")
    local wire=$(_capi_get "codex.apis.\"${active}\".wire_api // \"responses\"")

    # 全局替换所有 model_provider 行（全局 + profile 级别）
    sed -i '' "s/^model_provider = .*/model_provider = \"${active}\"/" "$toml"

    # 确保 [model_providers.xxx] 段存在
    if ! grep -q "^\[model_providers\.${active}\]" "$toml"; then
      printf '\n[model_providers.%s]\nname = "%s"\nbase_url = "%s"\nexperimental_bearer_token = "%s"\nwire_api = "%s"\n' \
        "$active" "$(_capi_get "codex.apis.\"${active}\".name")" "$url" "$key" "$wire" >> "$toml"
    fi
  fi
}

_capi_load() {
  _capi_load_claude
  _capi_load_codex
}

# ─── 主命令 ───

capi() {
  local tool="" cmd=""

  # 解析参数：capi [claude|codex] <command> [args...]
  if [[ "$1" == "claude" || "$1" == "codex" ]]; then
    tool="$1"; shift
  fi
  cmd="${1:-list}"; shift 2>/dev/null

  local tools=("${tool:-claude}" "${tool:-codex}")
  [[ -n "$tool" ]] && tools=("$tool")

  case "$cmd" in
    list|ls)
      for t in "${tools[@]}"; do
        local active=$(_capi_get "${t}.active")
        echo "${t:u} API 列表:"
        echo "─────────────────────────────────"
        local ids=($(jq -r ".${t}.apis | keys[]" "$_CAPI_FILE"))
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
      [[ ${#tools[@]} -gt 1 ]] && { echo "用法: capi <claude|codex> use [id]"; return 1; }
      local t="${tools[1]}" id="$1"
      if [[ -z "$id" ]]; then
        local active=$(_capi_get "${t}.active")
        local ids=($(jq -r ".${t}.apis | keys[]" "$_CAPI_FILE"))
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
      local tmp=$(mktemp)
      jq ".${t}.active = \"${id}\"" "$_CAPI_FILE" > "$tmp" && mv "$tmp" "$_CAPI_FILE"
      _capi_load_${t}
      echo "✓ 已切换 ${t:u} 到: $id ($(_capi_get "${t}.apis.\"${id}\".name"))"
      echo "  重启 ${t:u} 生效。"
      ;;

    add)
      [[ ${#tools[@]} -gt 1 ]] && { echo "用法: capi <claude|codex> add [id]"; return 1; }
      local t="${tools[1]}" id="$1"
      [[ -z "$id" ]] && { echo -n "API 标识: "; read id; }
      local exists=$(_capi_get "${t}.apis.\"${id}\" // empty")
      [[ -n "$exists" ]] && { echo "✗ '$id' 已存在"; return 1; }
      echo -n "显示名称: "; read name
      echo -n "API URL: "; read url
      echo -n "API Key: "; read -s key; echo
      local entry="{\"name\":\"$name\",\"url\":\"$url\",\"key\":\"$key\"}"
      [[ "$t" == "codex" ]] && { echo -n "wire_api (responses/chat): "; read wire; entry="{\"name\":\"$name\",\"url\":\"$url\",\"key\":\"$key\",\"wire_api\":\"${wire:-responses}\"}"; }
      local tmp=$(mktemp)
      jq ".${t}.apis.\"${id}\" = ${entry} | .${t}.fallback_order += [\"${id}\"]" "$_CAPI_FILE" > "$tmp" && mv "$tmp" "$_CAPI_FILE"
      echo "✓ 已添加: $id ($name)"
      ;;

    rm|remove|del)
      [[ ${#tools[@]} -gt 1 ]] && { echo "用法: capi <claude|codex> rm <id>"; return 1; }
      local t="${tools[1]}" id="$1"
      [[ -z "$id" ]] && { echo "用法: capi $t rm <id>"; return 1; }
      local active=$(_capi_get "${t}.active")
      [[ "$id" == "$active" ]] && { echo "✗ 不能删除当前激活的 API"; return 1; }
      local tmp=$(mktemp)
      jq "del(.${t}.apis.\"${id}\") | .${t}.fallback_order -= [\"${id}\"]" "$_CAPI_FILE" > "$tmp" && mv "$tmp" "$_CAPI_FILE"
      echo "✓ 已删除: $id"
      ;;

    test|check)
      local target_id="$1"
      for t in "${tools[@]}"; do
        local active=$(_capi_get "${t}.active")
        local ids
        [[ -n "$target_id" ]] && ids=("$target_id") || ids=($(jq -r ".${t}.apis | keys[]" "$_CAPI_FILE"))
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
        local order=($(jq -r ".${t}.fallback_order[]" "$_CAPI_FILE"))
        local switched=0
        for fid in "${order[@]}"; do
          [[ "$fid" == "$active" ]] && continue
          local mode=$(_capi_get "${t}.apis.\"${fid}\".mode // empty")
          [[ "$mode" == "login" ]] && continue
          echo -n "  尝试 $fid ... "
          _CAPI_LAST_ERR=""
          _capi_test_one "$t" "$fid"
          if [[ $? -eq 0 ]]; then
            local tmp=$(mktemp)
            jq ".${t}.active = \"${fid}\"" "$_CAPI_FILE" > "$tmp" && mv "$tmp" "$_CAPI_FILE"
            _capi_load_${t}
            echo "✓"
            echo "  ⚡ 已自动切换到: $fid ($(_capi_get "${t}.apis.\"${fid}\".name"))"
            switched=1
            break
          else
            echo "✗ $_CAPI_LAST_ERR"
          fi
        done
        [[ $switched -eq 0 ]] && echo "  ✗ 所有 API 均不可用"
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
          echo "  Key: ${key:0:8}...${key: -4}"
        fi
        echo ""
      done
      ;;

    help|--help|-h)
      cat <<'EOF'
capi - Claude Code & Codex CLI API 统一管理工具

用法: capi [claude|codex] <command>

命令:
  list              列出 API 配置
  use [id]          切换 API（需指定工具）
  add [id]          添加 API（需指定工具）
  rm <id>           删除 API（需指定工具）
  test [id]         检测可用性
  fallback          自动 fallback（当前不可用则切换）
  current           显示当前配置
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
