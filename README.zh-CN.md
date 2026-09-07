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
| `model_catalog_json` | 可选：自定义模型目录 JSON 的绝对路径，启动时替换内置目录（见上文专节） |

### 自定义请求

可以加请求头和查询参数，但**无法向请求体注入任意 JSON**：

```toml
[model_providers.custom111.http_headers]
X-Custom-Header = "value"

[model_providers.custom111.query_params]
api-version = "2026-01-01"
```

---

## 让桌面版选择器显示网关全部模型（`model_catalog_json`）

**为什么上游新增了模型，桌面版却看不到：** Codex 桌面版对自定义 provider **从不请求 `/v1/models`**（日志可证：网关只收到过 `/v1/responses` 请求）。选择器的列表来自 app-server 的 `model/list`，它只读本地缓存 `~/.codex/models_cache.json`，且在 API Key 模式下（无 ChatGPT 登录态）不会发生在线目录刷新。于是选择器永远只显示内置目录 + config 里写死的那个 `model`——上游新模型自然不可见。

**解决方案：** 顶层配置键 `model_catalog_json`（codex ≥ 0.124 支持，已在 0.151 验证）——指向一个 JSON 文件，启动时加载并**替换内置目录**，选择器从此镜像你的网关列表：

```toml
# 放在 config.toml 顶部、第一个 [table] 之前
model_catalog_json = 'C:\Users\<你>\.codex\gateway-model-catalog.json'
```

生成/更新目录文件用自带脚本（自动从 config.toml 读 provider 的 base_url 与密钥）：

```powershell
.\scripts\sync-model-catalog.ps1   # Windows
./scripts/sync-model-catalog.sh    # macOS / Linux
```

脚本拉取 `/v1/models`，把每个模型 ID 基于一份**完整模板条目**（`scripts/model-entry-template.json`）克隆生成，写出无 BOM 的 UTF-8 JSON。上游更新模型后：重跑脚本 → 完全退出并重启桌面版。

### 目录 JSON 的三个坑（任何一条都会让整个 config 加载失败）

1. **每个条目必须带 `base_instructions` 或 `model_messages.instructions_template` 之一。** 手写精简条目会报 `model ... is missing both base_instructions and model_messages.instructions_template`——务必用模板克隆，不要手写最小条目。
2. **文件不能带 UTF-8 BOM。** Windows PowerShell 5.1 的 `Set-Content -Encoding UTF8` 会写 BOM，codex 的 serde_json 直接拒绝解析。写文件用：`[IO.File]::WriteAllText($p, $json, [Text.UTF8Encoding]::new($false))`。
3. **目录解析失败 = 整个 config 无效。** 桌面版会卡在 "Finish Windows setup · config_load" 并反复重试，表现为连续弹 UAC——看起来像 UAC 问题，其实是配置文件坏了。改完先校验（Python `tomllib` / `json`）再重启应用。

---

## 一键切换：自定义网关 ↔ OpenAI 正常登录

`scripts/codex-mode.ps1`（macOS / Linux 用 `codex-mode.sh`）在两种模式间切换。它只动 `config.toml` 顶部的 4 个键（`model`、`model_provider`、`preferred_auth_method`、`model_catalog_json`），其余配置（providers、插件、MCP、项目信任等）原样保留：

```powershell
.\scripts\codex-mode.ps1 status            # 查看当前模式
.\scripts\codex-mode.ps1 openai            # 切到 OpenAI 登录模式（ChatGPT 账号 + 官方目录）
.\scripts\codex-mode.ps1 custom            # 切回自定义网关（恢复上次的选择器选择）
.\scripts\codex-mode.ps1 openai -Restart   # 切换并自动重启桌面版
```

要点：

- 配置只在启动时读取，切换后需**完全退出并重启应用**（`-Restart` 自动处理）。
- **首次切到 openai 模式**需先运行一次 `codex login` 用 ChatGPT 账号完成浏览器登录（脚本检测到 `auth.json` 没有 ChatGPT 令牌时会提醒）。
- 切到 openai 时，当前自定义设置（model / provider / catalog）会存入 `~/.codex/codex-mode-state.json`，切回 custom 时原样恢复——你在选择器里挑的模型不会丢。
- openai 模式下 `[model_providers.*]` 块留在配置里但不生效，随时可切回。

---

## 排障

### 桌面版模型下拉框不显示我的模型 / 上游新增了模型却看不到
根因：桌面版对自定义 provider 从不拉取 `/v1/models`（见上文 `model_catalog_json` 一节）。用 `model_catalog_json` + 同步脚本让选择器镜像网关列表。若只想锁定某一个模型，直接在 `config.toml` 里写死 `model` 和 `model_provider`——即使选择器不显示，配置依然生效。

### 启动卡在 "Finish Windows setup"，反复弹 UAC（`config_load`）
不是 UAC 的问题：`config.toml` 或其引用的文件（如 `model_catalog_json` 指向的 JSON）解析失败会让**整个配置加载失败**，安装向导在 `config_load` 步骤失败并重试，表现为 UAC 弹窗循环。先校验 TOML/JSON（注意 BOM 与必填字段），修复后再重启应用。

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
    ├── check-provider.ps1        # Windows 兼容性检查
    ├── check-provider.sh         # macOS / Linux 兼容性检查
    ├── sync-model-catalog.ps1    # 从网关同步模型目录（桌面版选择器用）
    ├── sync-model-catalog.sh     # 同上，macOS / Linux
    ├── model-entry-template.json # 完整 ModelInfo 模板条目（同步脚本依赖）
    ├── codex-mode.ps1            # 一键切换 自定义网关 ↔ OpenAI 登录模式
    └── codex-mode.sh             # 同上，macOS / Linux
```

## 许可证

MIT
