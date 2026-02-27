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
