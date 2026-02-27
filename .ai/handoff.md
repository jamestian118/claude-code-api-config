# capi 项目交接状态

## Goal / DoD
- 完成 Phase 1 CAPI 任务（唯一 ownership）：
  1. `.gitignore` + `apis.json` -> `apis.json.example`
  2. `add` 命令改为 `jq --arg`，移除字符串拼接注入风险
  3. `_capi_load` 增加 `chmod 600`（保护 `~/.claude/apis.json`）
  4. `current` key 显示脱敏改为前 4 + 后 2
  5. 文件写入增加 `flock` 并发保护（缺少 `flock` 时降级并提示）
- 必跑命令：strict、`./scripts/verify`、`./scripts/secrets-check`（不存在需记录）

## 当前状态（2026-02-27 Phase 1）
- branch: `ai/20260227-phase0-upgrade`
- base commit: `ff9f8ae` (`chore(phase0): add harness skeleton and version baseline`)
- git status 摘要：
  - modified: `README.md`, `capi.zsh`, `docs/scripts.md`, `docs/verify.usage.zh-en.md`, `scripts/verify`, `.ai/handoff.md`
  - deleted: `apis.json`
  - added: `.gitignore`, `apis.json.example`
  - untracked (未纳入改动): `.DS_Store`

## 验证命令与关键输出
- strict:
  - 命令：`/Users/Zhuanz/Documents/Code/universal-harness-kit/scripts/agent-policy-stack --tool codex --cwd "$PWD" --strict --strict-profile harness`
  - 关键结果：`strict_result=pass`
- verify:
  - 命令：`./scripts/verify`
  - 关键输出：
    - `[verify] bash syntax: capi.zsh`
    - `[verify] required files`
    - `[verify] json parse: apis.json.example`
    - `[verify] OK`
- secrets-check:
  - 命令：`./scripts/secrets-check`
  - 关键输出：`zsh:1: no such file or directory: ./scripts/secrets-check`（exit 127）

## Done
- 已将仓库模板配置切换为 `apis.json.example`，并通过 `.gitignore` 忽略本地 `apis.json`。
- `capi.zsh` 已完成：`jq --arg` 写入、`chmod 600`、key 脱敏（前 4 + 后 2）、写入加锁（`flock`）。
- `scripts/verify` 与双语 usage 文档已同步更新到 `apis.json.example`。

## Next Steps
1. 提交当前变更（排除 `.DS_Store`）。
2. 如需强制加锁，可在运行环境安装 `flock`（当前实现已带降级提示）。
3. 可补充 `scripts/secrets-check` 以满足仓库完整安全检查闭环。

## 当前状态（2026-02-27 Phase 2 CAPI）
- branch: `ai/20260227-phase0-upgrade`
- base commit: `3bd5a28`
- git status 摘要（本次任务后，提交前）：
  - modified: `README.md`, `capi.zsh`
  - added: `LICENSE`
  - untracked (忽略): `.DS_Store`

## 验证命令与关键输出（Phase 2）
- verify:
  - 命令：`./scripts/verify`
  - 关键输出：`[verify] OK`
- secrets-check:
  - 命令：`./scripts/secrets-check`
  - 关键输出：`[secrets-check] OK`

## Done（Phase 2）
- 新增 `LICENSE`（MIT）。
- `capi.zsh` 新增 `_CAPI_VERSION="0.1.0"` 与 `version|--version|-v` 子命令。
- 统一工具参数解析与默认工具集合为 `_CAPI_TOOLS` 驱动，替换原有硬编码分支。
- 双语 usage 已同步更新（`README.md` 命令表新增 `version`）。

## Next Steps（Phase 2）
1. 提交本次变更（排除 `.DS_Store`）。
2. 如需发版，可同步 bump `VERSION` 与 `_CAPI_VERSION`。

## Gate 3 支持摘要（2026-02-27 20:35:56 +0800）
- lane: CAPI Phase 3 support（唯一 ownership）
- scope: 仅执行验证与证据记录；未改业务代码
- branch: `ai/20260227-phase0-upgrade`
- commit(before append): `1856b7c`

### 验证证据
- strict
  - 命令：`/Users/Zhuanz/Documents/Code/universal-harness-kit/scripts/agent-policy-stack --tool codex --cwd "/Users/Zhuanz/Documents/Code/claude-code-api-config" --strict --strict-profile harness`
  - exit code：`0`
  - 关键输出：`strict_result=pass`
- verify
  - 命令：`./scripts/verify`
  - exit code：`0`
  - 关键输出：`[verify] OK`
- secrets-check
  - 命令：`./scripts/secrets-check`
  - exit code：`0`
  - 关键输出：`[secrets-check] OK`

### 备注
- 本轮仅新增 handoff 证据记录，便于 Gate 3 审核引用。

## Phase 4 CAPI 4.13（2026-02-27 20:55:21 +0800）
- lane: CAPI Phase 4（重启任务）
- scope: 新增 `tests/test_capi.zsh`（JSON 操作 + fallback 逻辑）并接入 `scripts/verify`
- branch: `ai/20260227-phase0-upgrade`
- commit(before append): `e104f24`

### 当前状态
- 已新增：`tests/test_capi.zsh`
- 已修改：`scripts/verify`、`docs/verify.usage.zh-en.md`、`docs/scripts.md`
- git status 摘要（提交前）：
  - modified: `docs/scripts.md`, `docs/verify.usage.zh-en.md`, `scripts/verify`
  - added: `tests/test_capi.zsh`
  - untracked(忽略): `.DS_Store`

### 验证证据
- strict
  - 命令：`/Users/Zhuanz/Documents/Code/universal-harness-kit/scripts/agent-policy-stack --tool codex --cwd "$PWD" --strict --strict-profile harness`
  - exit code: `0`
  - 关键输出：`strict_result=pass`
- verify
  - 命令：`./scripts/verify`
  - exit code: `0`
  - 关键输出：
    - `[verify] zsh regression: tests/test_capi.zsh`
    - `[test_capi] OK`
    - `[verify] OK`
- secrets-check
  - 命令：`./scripts/secrets-check`
  - exit code: `0`
  - 关键输出：`[secrets-check] OK`

### 下一步
1. 提交本次变更（建议 message：`test: add zsh regression suite for capi`）。
2. 如需消除 verify 日志中的降级告警，可安装 `flock`（`brew install flock`）。

### 已知问题
- 测试环境未安装 `flock` 时会输出一次降级提示（不影响退出码与测试通过）。

## Phase 5 CAPI 5.20-5.23（2026-02-27 21:08:16 +0800）
- lane: CAPI Phase 5（唯一 ownership）
- scope: 健康检查模型配置化 + Codex wire_api endpoint 选择 + `_capi_write` 抽象与写入路径统一 + fallback 全失败 login 提示
- branch: `ai/20260227-phase0-upgrade`
- commit(before append): `467b2eb`

### 当前状态（提交前）
- modified: `README.md`, `apis.json.example`, `capi.zsh`, `tests/test_capi.zsh`
- untracked(忽略): `.DS_Store`

### 验证证据
- strict
  - 命令：`/Users/Zhuanz/Documents/Code/universal-harness-kit/scripts/agent-policy-stack --tool codex --cwd "$PWD" --strict --strict-profile harness`
  - exit code: `0`
  - 关键输出：`strict_result=pass`
- verify
  - 命令：`./scripts/verify`
  - exit code: `0`
  - 关键输出：`[test_capi] OK`、`[verify] OK`
- secrets-check
  - 命令：`./scripts/secrets-check`
  - exit code: `0`
  - 关键输出：`[secrets-check] OK`

### Done
1. `apis.json.example` 新增 `test_model` 示例字段（Claude/Codex）。
2. `capi.zsh` 健康检查支持读取 `test_model`，并在 Codex 场景按 `wire_api` 选择 `/responses` 或 `/chat/completions`。
3. `capi.zsh` 抽象 `_capi_write`（原子写 + `trap` 清理临时文件），统一写入路径并替换原 `_capi_jq_write` 调用点。
4. `capi.zsh` fallback 全失败后，若存在 login entry，提示 `capi <tool> use <login_id>`。
5. `tests/test_capi.zsh` 扩充回归：`test_model`、`wire_api` endpoint、fallback login 提示。
6. `README.md`（中文 + English）同步更新字段与行为说明。

### Next Steps
1. 提交本次变更（建议 message：`feat(refactor): harden capi health and write path`）。
2. 如需减少测试日志告警，可在执行环境安装 `flock`（`brew install flock`）。

## 2026-02-27 Phase 7 CAPI lane（7.10）

### Scope
- 7.10 参数化 policy-stack 路径：`AGENTS.md` 改为使用 `UHK_ROOT` 环境变量，不再固定绝对路径。

### Changes
- modified: `AGENTS.md`

### Verification Commands
- `/Users/Zhuanz/Documents/Code/universal-harness-kit/scripts/agent-policy-stack --tool codex --cwd "$PWD" --strict --strict-profile harness`
- `./scripts/verify`
- `./scripts/secrets-check`

### Key Outputs
- strict: `strict_result=pass`
- verify: `[test_capi] OK` + `[verify] OK`
- secrets-check: `[secrets-check] OK`

### Notes
- `.DS_Store` 为本地未跟踪噪音文件，未纳入提交。
- 本 lane 由主线程在 agent thread limit 约束下补齐执行。
