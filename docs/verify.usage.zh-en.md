# scripts/verify Usage (中文 + English)

## 中文

### 前置条件
- macOS/Linux shell 环境
- 可用 `bash`、`zsh` 与 `python3`
- 在仓库根目录下执行

### 命令
```bash
./scripts/verify
```

### 检查内容
1. `capi.zsh` 语法检查（`bash -n`）
2. 关键文件存在性（`README.md`、`apis.json.example`、`tests/test_capi.zsh`）
3. `apis.json.example` JSON 解析
4. 运行 `tests/test_capi.zsh` 回归测试（JSON 操作 + fallback 逻辑）

### 输出与退出码
- 成功：输出 `[verify] OK`，退出码 `0`
- 失败：在对应步骤中断，退出码非 `0`

### 常见问题
- `bash: command not found`
  - 安装或启用 bash 后重试
- `zsh: command not found`
  - 安装或启用 zsh 后重试
- `python3: command not found`
  - 安装 Python 3 后重试
- `JSONDecodeError`
  - 修复 `apis.json.example` 格式后重试
- `[test_capi] FAIL: ...`
  - 查看失败断言并检查 `capi.zsh` 对 JSON 写入与 fallback 切换行为

## English

### Prerequisites
- macOS/Linux shell environment
- `bash`, `zsh`, and `python3` available
- Run from repository root

### Command
```bash
./scripts/verify
```

### Checks
1. `capi.zsh` syntax check (`bash -n`)
2. Required files (`README.md`, `apis.json.example`, `tests/test_capi.zsh`)
3. JSON parsing for `apis.json.example`
4. Regression suite via `tests/test_capi.zsh` (JSON operations + fallback logic)

### Output and Exit Code
- Success: prints `[verify] OK`, exits with `0`
- Failure: stops at failed step, exits non-zero

### Troubleshooting
- `bash: command not found`
  - Install/enable bash and rerun
- `zsh: command not found`
  - Install/enable zsh and rerun
- `python3: command not found`
  - Install Python 3 and rerun
- `JSONDecodeError`
  - Fix `apis.json.example` format and rerun
- `[test_capi] FAIL: ...`
  - Inspect the failing assertion and check `capi.zsh` behavior for JSON updates and fallback switching
