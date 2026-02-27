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

    _capi_jq_write "$_CAPI_FILE" \
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

test_json_operations
test_fallback_logic

echo "[test_capi] OK"
