# Codex 桌面版 · 自定义模型与 API URL

让 **OpenAI Codex 桌面应用**（即内置 Codex 的 ChatGPT 桌面客户端）——以及共享同一配置的 CLI 和 IDE 插件——接入任意 OpenAI 兼容的模型网关。

[English →](README.md)

> ⚠️ **安全第一**：绝不要把真实 API Key 或私有端点提交到公开仓库。密钥请用环境变量。下文示例均使用占位符。

---

## 原理

Codex 桌面应用、Codex CLI、Codex IDE 插件三者读取**同一份用户级配置文件**：

| 系统 | 路径 |
|------|------|
| Windows | `%USERPROFILE%\.codex\config.toml` |
| macOS / Linux | `~/.codex/config.toml` |

要接入你自己的网关，就新增一个 `model_providers` 条目，再用 `model_provider` 选中它。

**关键点：** provider 定义**必须**放在*用户级*配置里。项目级 `.codex/config.toml` 中的 `model_provider`、`model_providers`、`openai_base_url`、`profile`、`notify`、`otel` 都会被忽略。

---

## 快速上手

### 1. 验证网关是否兼容

Codex 强制走 **Responses API**（`/v1/responses`），只支持 `/v1/chat/completions` 是不够的。运行自带的检查脚本：

```powershell
# Windows PowerShell
.\scripts\check-provider.ps1 -BaseUrl "https://你的网关/v1" -ApiKey "sk-xxxx" -Model "你的模型ID"
```

```bash
# macOS / Linux
./scripts/check-provider.sh "https://你的网关/v1" "sk-xxxx" "你的模型ID"
```

脚本会测试 `/v1/models` 和 `/v1/responses`。若 `/v1/responses` 返回 200，即兼容。

### 2. 编辑 `config.toml`

在用户级 `config.toml` 的**顶部**加入：

```toml
model = "你的模型ID"
model_provider = "custom111"
preferred_auth_method = "apikey"

[model_providers.custom111]
name = "Custom Gateway"
base_url = "https://你的网关/v1"   # 必须以 /v1 结尾
wire_api = "responses"
env_key = "CUSTOM_GATEWAY_KEY"     # 存放密钥的环境变量名（不是密钥本身）
```

把密钥设为环境变量（比硬编码更安全）：

```powershell
# Windows（持久化，用户级）
[Environment]::SetEnvironmentVariable("CUSTOM_GATEWAY_KEY", "sk-xxxx", "User")
```

```bash
# macOS / Linux
export CUSTOM_GATEWAY_KEY="sk-xxxx"
```

> **另一种方式（内联密钥）：** 若无法管理环境变量，可在 `[model_providers.*]` 块内用
> `experimental_bearer_token = "sk-xxxx"` 代替 `env_key`。更简单，但密钥是明文存储——
> 仅在可信的单用户机器上使用，并确保该文件不进入任何仓库。

### 3. 重启应用

完全退出并重启 Codex 桌面应用（配置**不会**热加载）。

---

## 配置字段对照表

| 字段 | 含义 |
|------|------|
| `model` | 网关暴露的模型 ID（如 `gpt-5.6-sol`、`claude-sonnet-5`） |
| `model_provider` | 指向你的 `[model_providers.*]` 块的 ID |
| `preferred_auth_method` | 设为 `"apikey"` 强制走 API Key，而非 ChatGPT 登录 |
| `base_url` | 网关 URL，**必须以 `/v1` 结尾** |
| `wire_api` | 目前仅支持 `"responses"` |
| `env_key` | 存放密钥的环境变量**名**（不是密钥本身） |
| `experimental_bearer_token` | 内联 API Key（`env_key` 的替代；明文，谨慎使用） |
| `http_headers` | 可选的额外请求头 |
| `query_params` | 可选的额外查询参数 |
| `model_reasoning_effort` | 可选：`low` / `medium` / `high` |

### 自定义请求

可以加请求头和查询参数，但**无法向请求体注入任意 JSON**：

```toml
[model_providers.custom111.http_headers]
X-Custom-Header = "value"

[model_providers.custom111.query_params]
api-version = "2026-01-01"
```

---

## 排障

### 桌面版模型下拉框不显示我的模型
已知的客户端显示问题：模型目录可能已加载，但桌面选择器过滤掉了自定义模型。若 CLI 能用（`codex` → `/model` 能列出）而桌面下拉框不显示，**直接在 `config.toml` 里写死 `model` 和 `model_provider`**——即使选择器隐藏，配置依然生效。

### 请求返回 400 / 工具调用失败
你的网关很可能只支持 `/v1/chat/completions`，不支持 `/v1/responses`。Codex 强制走 Responses API。要么换支持的网关，要么在前面架一个协议转换代理。

### 登录态冲突（ChatGPT 登录 vs API Key）
若你用 ChatGPT 订阅账号登录，自定义 provider 可能被忽略。设置 `preferred_auth_method = "apikey"`，在应用里退出 ChatGPT 账号，然后重启。

### 应用自身无法更新
若 Codex 是从 **Microsoft Store（MSIX）** 安装的，`WindowsApps\` 下的安装目录写保护，应用内自更新会失败。请通过 **Microsoft Store → 库 → 获取更新**，或 `winget upgrade` 更新。这与代理/网络无关。

---

## 仓库结构

```
codex-desktop-custom-model/
├── README.md            # 英文版
├── README.zh-CN.md      # 本文件（中文）
├── skills/
│   └── codex-desktop-custom-model/
│       └── SKILL.md     # 可导入 Qoder / AI 助手的 skill
└── scripts/
    ├── check-provider.ps1   # Windows 兼容性检查
    └── check-provider.sh    # macOS / Linux 兼容性检查
```

## 许可证

MIT
