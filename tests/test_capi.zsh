#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/capi-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  print -u2 -- "[test_capi] FAIL: $*"
  exit 1
}

assert_jq() {
  local desc="$1"
  shift
  jq -e "$@" >/dev/null || fail "$desc"
}

prepare_home() {
  local name="$1"
  local home="$TMP_ROOT/$name/home"
  mkdir -p "$home/.claude" "$home/.codex"
  cp "$REPO_ROOT/apis.json.example" "$home/.claude/apis.json"
  cat > "$home/.codex/config.toml" <<'EOF'
model_provider = "infiniteai"
EOF
  cat > "$home/.claude/config.json" <<'EOF'
{"primaryApiKey":"dummy"}
EOF
  print -r -- "$home"
}

test_json_operations() {
  local home
  home="$(prepare_home json)"
  (
    export HOME="$home"
    source "$REPO_ROOT/capi.zsh"

    local id='evil"]|.pwned=true|["x'
    capi codex add "$id" <<'EOF' >/dev/null
Injected Name
https://api.unit.test/v1
sk-test-12345
responses
EOF

    assert_jq "add should create a literal-key codex entry" \
      --arg id "$id" '.codex.apis[$id].name == "Injected Name"' "$_CAPI_FILE"
    assert_jq "add should append fallback_order" \
      --arg id "$id" '(.codex.fallback_order | index($id)) != null' "$_CAPI_FILE"
    assert_jq "add should not inject top-level fields" \
      '.pwned == null' "$_CAPI_FILE"

    capi codex rm "$id" >/dev/null
    assert_jq "rm should delete codex entry" \
      --arg id "$id" '.codex.apis[$id] == null' "$_CAPI_FILE"
    assert_jq "rm should remove fallback_order entry" \
      --arg id "$id" '(.codex.fallback_order | index($id)) == null' "$_CAPI_FILE"

    capi codex use chatgpt >/dev/null
    assert_jq "use should update active api id" \
      '.codex.active == "chatgpt"' "$_CAPI_FILE"
  )
}

test_fallback_logic() {
  local home
  home="$(prepare_home fallback)"
  (
    export HOME="$home"
    source "$REPO_ROOT/capi.zsh"

    _capi_write "$_CAPI_FILE" \
      '.codex.active = "infiniteai"
       | .codex.apis.backup = {"name":"Backup","url":"https://backup.example/v1","key":"sk-backup","wire_api":"responses"}
       | .codex.fallback_order = ["infiniteai","chatgpt","backup"]' || fail "prepare fallback fixture failed"

    typeset -gA CAPI_TEST_RC=()
    typeset -gA CAPI_TEST_CALLS=()
    CAPI_TEST_RC["codex:infiniteai"]=1
    CAPI_TEST_RC["codex:backup"]=0
    CAPI_TEST_RC["codex:chatgpt"]=0

    _capi_test_one() {
      local key="$1:$2"
      CAPI_TEST_CALLS["$key"]=$(( ${CAPI_TEST_CALLS["$key"]:-0} + 1 ))
      local rc="${CAPI_TEST_RC["$key"]:-1}"
      (( rc != 0 )) && _CAPI_LAST_ERR="stub-down-$key"
      return "$rc"
    }

    _capi_load_codex() { :; }

    set +e
    capi codex fallback >/dev/null
    set -e

    assert_jq "fallback should switch to backup when active is down" \
      '.codex.active == "backup"' "$_CAPI_FILE"
    (( ${CAPI_TEST_CALLS["codex:infiniteai"]:-0} >= 1 )) || fail "fallback should test active id first"
    (( ${CAPI_TEST_CALLS["codex:chatgpt"]:-0} == 0 )) || fail "fallback should skip login-mode entries"
    (( ${CAPI_TEST_CALLS["codex:backup"]:-0} >= 1 )) || fail "fallback should probe backup id"
  )
}

test_healthcheck_model_and_wire_api() {
  local home
  home="$(prepare_home health)"
  (
    export HOME="$home"
    source "$REPO_ROOT/capi.zsh"

    _capi_write "$_CAPI_FILE" \
      '.claude.active = "aws"
       | .claude.apis.aws.test_model = "claude-3-5-haiku-latest"
       | .codex.apis.infiniteai.test_model = "gpt-4.1-mini"
       | .codex.apis.chatwire = {"name":"ChatWire","url":"https://chat.example/v1","key":"sk-chat","wire_api":"chat","test_model":"gpt-4.1"}' || fail "prepare health fixture failed"

    local mock_bin="$home/mock-bin"
    mkdir -p "$mock_bin"
    cat > "$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out_file=""
url=""
data=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out_file="${2:-}"
      shift 2
      ;;
    -d)
      data="${2:-}"
      shift 2
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "${CAPI_TEST_CURL_URL_FILE:-}" ]] && printf '%s' "$url" > "$CAPI_TEST_CURL_URL_FILE"
[[ -n "${CAPI_TEST_CURL_DATA_FILE:-}" ]] && printf '%s' "$data" > "$CAPI_TEST_CURL_DATA_FILE"
[[ -n "$out_file" ]] && printf '{"ok":true}' > "$out_file"
printf '200'
EOF
    chmod +x "$mock_bin/curl"
    export PATH="$mock_bin:$PATH"
    export CAPI_TEST_CURL_URL_FILE="$home/curl.url"
    export CAPI_TEST_CURL_DATA_FILE="$home/curl.data"

    _capi_test_one "claude" "aws" >/dev/null || fail "claude health check should succeed"
    local last_url="$(cat "$CAPI_TEST_CURL_URL_FILE")"
    local last_data="$(cat "$CAPI_TEST_CURL_DATA_FILE")"
    [[ "$last_url" == "https://example.com/claude/aws/v1/messages" ]] || fail "claude should hit messages endpoint (actual: $last_url)"
    assert_jq "claude should use configured test_model" \
      --arg m "claude-3-5-haiku-latest" '.model == $m' <(print -r -- "$last_data")

    _capi_test_one "codex" "infiniteai" >/dev/null || fail "codex responses health check should succeed"
    last_url="$(cat "$CAPI_TEST_CURL_URL_FILE")"
    last_data="$(cat "$CAPI_TEST_CURL_DATA_FILE")"
    [[ "$last_url" == "https://api.example.com/v1/responses" ]] || fail "responses wire_api should hit /responses (actual: $last_url)"
    assert_jq "codex responses should use configured test_model" \
      --arg m "gpt-4.1-mini" '.model == $m and .input == "hi"' <(print -r -- "$last_data")

    _capi_test_one "codex" "chatwire" >/dev/null || fail "codex chat health check should succeed"
    last_url="$(cat "$CAPI_TEST_CURL_URL_FILE")"
    last_data="$(cat "$CAPI_TEST_CURL_DATA_FILE")"
    [[ "$last_url" == "https://chat.example/v1/chat/completions" ]] || fail "chat wire_api should hit /chat/completions (actual: $last_url)"
    assert_jq "codex chat should use configured test_model" \
      --arg m "gpt-4.1" '.model == $m and (.messages | length) == 1' <(print -r -- "$last_data")
  )
}

test_fallback_all_fail_login_hint() {
  local home
  home="$(prepare_home fallback-all-fail)"
  (
    export HOME="$home"
    source "$REPO_ROOT/capi.zsh"

    _capi_write "$_CAPI_FILE" \
      '.codex.active = "infiniteai"
       | .codex.apis.backup = {"name":"Backup","url":"https://backup.example/v1","key":"sk-backup","wire_api":"responses"}
       | .codex.fallback_order = ["infiniteai","backup","chatgpt"]' || fail "prepare fallback-all-fail fixture failed"

    _capi_test_one() {
      local mode=$(_capi_get "$1.apis.\"$2\".mode // empty")
      if [[ "$mode" == "login" ]]; then
        return 2
      fi
      _CAPI_LAST_ERR="stub-down-$1:$2"
      return 1
    }

    _capi_load_codex() { :; }

    local out
    set +e
    out="$(capi codex fallback 2>&1)"
    local rc=$?
    set -e
    (( rc == 0 )) || fail "fallback command should keep exit code 0 when all probes fail"
    [[ "$out" == *"所有 API 均不可用"* ]] || fail "fallback should report all APIs down"
    [[ "$out" == *"可切换到登录模式"* ]] || fail "fallback should hint login mode availability"
    [[ "$out" == *"capi codex use chatgpt"* ]] || fail "fallback should print actionable login switch command"
  )
}

test_json_operations
test_fallback_logic
test_healthcheck_model_and_wire_api
test_fallback_all_fail_login_hint

echo "[test_capi] OK"
