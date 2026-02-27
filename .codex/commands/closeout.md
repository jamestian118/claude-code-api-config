# /closeout

目标：milestone / stop / CLI 切换前的统一收尾。

## Checklist
1. 运行 verify：
   ```bash
   ./scripts/verify
   ```

2. 更新 `.ai/handoff.md`（必须包含）：
   - Goal/DoD
   - branch/commit + git status 摘要
   - 验证命令与关键输出
   - Done + Next Steps（3-8 条）

## Pass/Fail
- Pass：verify 通过 + handoff 证据链完整
- Fail：verify 失败 或 handoff 缺失
