# capi — Claude Code & Codex CLI API 配置管理工具

一个 zsh 工具，统一管理 **Claude Code** 和 **Codex CLI** 的 API 配置。支持多 API 源切换、账号登录 / API Key 双模式、可用性检测与自动 fallback。

## 安装

```sh
# 复制文件
cp capi.zsh ~/.claude/capi.zsh
cp apis.json.example ~/.claude/apis.json

# 加载到 shell
echo 'source ~/.claude/capi.zsh' >> ~/.zshrc
source ~/.zshrc
```

依赖：`jq`、`curl`（建议安装 `flock` 以启用并发写保护）

## 配置文件

配置文件路径：`~/.claude/apis.json`
仓库提供示例：`apis.json.example`（本地真实配置建议放 `apis.json`，已默认 `.gitignore`）

```json
{
  "claude": {
    "active": "aws",
    "fallback_order": ["aws", "kiro-pool", "login"],
    "apis": {
      "login": { "name": "账号订阅", "mode": "login" },
      "aws": { "name": "NewCLI AWS", "url": "https://example.com/claude/aws", "key": "<YOUR_KEY>", "test_model": "claude-sonnet-4-20250514" },
      "kiro-pool": { "name": "Kiro Pool", "url": "https://example.com/api", "key": "<YOUR_KEY>", "test_model": "claude-sonnet-4-20250514" }
    }
  },
  "codex": {
    "active": "infiniteai",
    "fallback_order": ["infiniteai", "chatgpt"],
    "apis": {
      "chatgpt": { "name": "ChatGPT Pro", "mode": "login" },
      "infiniteai": { "name": "InfiniteAI", "url": "https://api.example.com/v1", "key": "<YOUR_KEY>", "wire_api": "responses", "test_model": "gpt-5" }
    }
  }
}
```

**两种模式：**
- `"mode": "login"` — 账号登录模式，不需要 URL 和 Key
- `"url"` + `"key"` — API Key 模式，通过第三方 API 端点访问

**字段说明：**
- `active` — 当前激活的 API 标识
- `fallback_order` — fallback 优先级顺序
- `wire_api` — Codex 专用，指定 API 协议（`responses` 或 `chat`）
- `test_model` — 健康检查时使用的模型名（未配置时使用内置默认值）

## 命令

```sh
capi [claude|codex] <command>
```

| 命令 | 说明 | 示例 |
|------|------|------|
| `list` | 列出所有 API 配置 | `capi list` / `capi claude list` |
| `use [id]` | 切换 API（交互式或指定 id） | `capi claude use aws` |
| `add [id]` | 添加新 API | `capi codex add my-api` |
| `rm <id>` | 删除 API（不能删除当前激活的） | `capi claude rm old-api` |
| `test [id]` | 检测 API 可用性 | `capi test` / `capi claude test aws` |
| `fallback` | 当前不可用时自动切换到下一个 | `capi fallback` |
| `current` | 显示当前激活的 API 详情 | `capi current` |
| `version` | 显示 capi 版本号 | `capi version` |
| `help` | 显示帮助 | `capi help` |

不指定 `claude`/`codex` 时，`list`、`test`、`fallback`、`current` 会同时显示两者。

## Fallback 机制

运行 `capi fallback` 时：

1. 测试当前激活的 API
2. 如果可用 → 保持不变
3. 如果不可用 → 按 `fallback_order` 顺序逐个测试（跳过 login 模式）
4. 找到可用的 → 自动切换并加载配置
5. 全部不可用 → 提示错误，并给出可切换 login 模式的命令（若配置中存在 login entry）

## 工作原理

- **Claude**：切换时设置 `ANTHROPIC_BASE_URL`、`ANTHROPIC_API_KEY`、`ANTHROPIC_AUTH_TOKEN` 环境变量，并更新 `~/.claude/config.json` 中的 `primaryApiKey`
- **Codex**：切换时更新 `~/.codex/config.toml` 中的 `model_provider` 及对应配置段
- **Login 模式**：清除环境变量和配置，回退到官方账号登录
- **`ktp_*` Key**：自动使用 `Authorization: Bearer` 认证头
- **健康检查模型**：`test`/`fallback` 会读取每个 API 的 `test_model`，未配置时回落到默认模型
- **Codex 健康检查协议**：`wire_api=responses` 走 `/responses`，`wire_api=chat` 走 `/chat/completions`
- **并发写入**：配置写入优先使用 `flock` 加锁（未安装时降级为无锁并提示）

## 常见问题

- **API 不可用**：运行 `capi claude test` 检查，确认 URL 和 Key 正确
- **切换后未生效**：需要重启 Claude Code / Codex CLI（`source ~/.zshrc` 仅更新环境变量）
- **安全提醒**：不要将真实 Key 提交到仓库，配置文件中使用 `<YOUR_KEY>` 占位
- **`current` 显示 Key 太短**：默认仅暴露前 4 + 后 2，其余用 `...` 脱敏

---

# capi — Claude Code & Codex CLI API Config Manager

A zsh tool for managing API configurations for **Claude Code** and **Codex CLI**. Supports multiple API sources, account login / API key modes, connectivity testing, and automatic fallback.

## Installation

```sh
cp capi.zsh ~/.claude/capi.zsh
cp apis.json.example ~/.claude/apis.json
echo 'source ~/.claude/capi.zsh' >> ~/.zshrc
source ~/.zshrc
```

Requires: `jq`, `curl` (`flock` recommended for concurrent write locking)

## Configuration

Config file: `~/.claude/apis.json`
Template in repo: `apis.json.example` (local `apis.json` is gitignored by default)

Two modes per API entry:
- `"mode": "login"` — account login, no URL/key needed
- `"url"` + `"key"` — API key mode via third-party endpoint

Key fields:
- `active` — currently active API id
- `fallback_order` — failover priority order
- `wire_api` — Codex-only, specifies API protocol (`responses` or `chat`)
- `test_model` — model name used for health checks (falls back to built-in defaults when omitted)

English config example:

```json
{
  "claude": {
    "active": "aws",
    "fallback_order": ["aws", "kiro-pool", "login-main"],
    "apis": {
      "aws": {
        "name": "NewCLI AWS",
        "url": "https://example.com/claude/aws",
        "key": "<YOUR_KEY>",
        "test_model": "claude-sonnet-4-20250514"
      },
      "login-main": {
        "name": "Claude Login",
        "mode": "login"
      }
    }
  },
  "codex": {
    "active": "infiniteai",
    "fallback_order": ["infiniteai", "login-main"],
    "apis": {
      "infiniteai": {
        "name": "InfiniteAI",
        "url": "https://api.example.com/v1",
        "key": "<YOUR_KEY>",
        "wire_api": "responses",
        "test_model": "gpt-5"
      },
      "login-main": {
        "name": "Codex Login",
        "mode": "login"
      }
    }
  }
}
```

## Commands

```sh
capi [claude|codex] <command>
```

| Command | Description | Example |
|---------|-------------|---------|
| `list` | List all API configs | `capi list` |
| `use [id]` | Switch API (interactive or by id) | `capi claude use aws` |
| `add [id]` | Add new API | `capi codex add my-api` |
| `rm <id>` | Remove API (cannot remove active) | `capi claude rm old-api` |
| `test [id]` | Test API connectivity | `capi test` |
| `fallback` | Auto-switch if current is down | `capi fallback` |
| `current` | Show active API details | `capi current` |
| `version` | Show capi version | `capi version` |
| `help` | Show help | `capi help` |

Omitting `claude`/`codex` runs `list`, `test`, `fallback`, `current` for both.

## Fallback

`capi fallback` tests the active API first. If unavailable, it tries each entry in `fallback_order` (skipping login mode) until a working one is found and auto-switches. If all API-key entries fail, it prints a login-mode switch hint when a login entry exists.

## How It Works

- **Claude**: Sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` env vars and updates `~/.claude/config.json`
- **Codex**: Updates `model_provider` in `~/.codex/config.toml`
- **Login mode**: Clears env vars/config, falls back to official account login
- **`ktp_*` keys**: Automatically use `Authorization: Bearer` header
- **Health-check model**: `test`/`fallback` read per-API `test_model`, with safe defaults when not configured
- **Codex health-check protocol**: `wire_api=responses` calls `/responses`; `wire_api=chat` calls `/chat/completions`
- **Concurrent writes**: Uses `flock` when available (falls back to unlocked writes with warning)

## Troubleshooting

- **API unreachable**: Run `capi claude test`, verify URL and key
- **Changes not taking effect**: Restart Claude Code / Codex CLI
- **Security**: Never commit real API keys — use `<YOUR_KEY>` placeholders
- **`current` output too short**: Key display is intentionally masked to first 4 + last 2
