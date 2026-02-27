# scripts/secrets-check Usage (中文 + English)

## 中文

### 前置条件
- 在仓库根目录执行
- 可用 `bash` 与 `grep`

### 命令
```bash
./scripts/secrets-check
```

### 说明
- 启发式扫描常见 secrets 模式。
- 默认排除 `apis.json.example`（样例配置文件，避免样例 token 误报）。

### 输出与退出码
- 成功：`[secrets-check] OK`，退出码 `0`
- 失败：输出匹配位置并返回非 `0`

## English

### Prerequisites
- Run from repository root
- `bash` and `grep` available

### Command
```bash
./scripts/secrets-check
```

### Notes
- Runs heuristic scans for common secret patterns.
- Excludes `apis.json.example` by default to avoid sample-token false positives.

### Output and Exit Code
- Success: `[secrets-check] OK`, exit code `0`
- Failure: prints matching paths and exits non-zero
