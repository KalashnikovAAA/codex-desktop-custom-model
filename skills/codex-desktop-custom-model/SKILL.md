---
name: codex-desktop-custom-model
description: Configure the OpenAI Codex desktop app (ChatGPT desktop client), CLI, or IDE extension to use a custom OpenAI-compatible model gateway via ~/.codex/config.toml. Use when the user wants to change the Codex/ChatGPT desktop model, point it at a custom base_url or third-party API, switch the LLM endpoint, add a model_provider, or troubleshoot custom-model setup on Codex.
---

# Codex Desktop Custom Model

Point the OpenAI Codex desktop app (and its CLI / IDE extension, which share one config) at any OpenAI-compatible gateway.

## Config location (user-level only)

- Windows: `%USERPROFILE%\.codex\config.toml`
- macOS / Linux: `~/.codex/config.toml`

Provider keys (`model_provider`, `model_providers`, `openai_base_url`, `profile`, `notify`, `otel`) in a **project-level** `.codex/config.toml` are **ignored**. Always edit the user-level file.

## Workflow

Copy this checklist and track progress:

```
- [ ] 1. Verify gateway supports the Responses API
- [ ] 2. Back up config.toml
- [ ] 3. Add provider block + select it
- [ ] 4. Supply the API key (env var or inline)
- [ ] 5. Restart the app (config is not hot-reloaded)
```

### 1. Verify compatibility (required)

Codex forces `wire_api = "responses"` — the gateway must serve `/v1/responses`, not just `/v1/chat/completions`. Run the check script from the repo's `scripts/` dir:

```powershell
# Windows
.\check-provider.ps1 -BaseUrl "https://GATEWAY/v1" -ApiKey "sk-xxxx" -Model "MODEL-ID"
```
```bash
# macOS / Linux
./check-provider.sh "https://GATEWAY/v1" "sk-xxxx" "MODEL-ID"
```

Or manually confirm `/v1/models` lists the model and `POST /v1/responses` returns HTTP 200.

### 2. Back up first

```powershell
Copy-Item "$env:USERPROFILE\.codex\config.toml" "$env:USERPROFILE\.codex\config.toml.bak" -Force
```

### 3. Edit config.toml

Place at the **top** of the file. `base_url` must end with `/v1`:

```toml
model = "MODEL-ID"
model_provider = "custom"
preferred_auth_method = "apikey"
model_reasoning_effort = "low"   # optional: low|medium|high

[model_providers.custom]
name = "Custom Gateway"
base_url = "https://GATEWAY/v1"
wire_api = "responses"
env_key = "CUSTOM_GATEWAY_KEY"   # env var NAME, not the secret
```

> TOML gotcha: keep top-level scalar keys (`model`, `model_reasoning_effort`, etc.) **above** the first `[table]` header. Any key placed after a `[model_providers.*]` header becomes part of that table and breaks parsing.

Optional request shaping (headers / query params only — arbitrary body JSON is NOT supported):

```toml
[model_providers.custom.http_headers]
X-Custom-Header = "value"

[model_providers.custom.query_params]
api-version = "2026-01-01"
```

### 4. Supply the API key

Preferred — environment variable (matches `env_key`):

```powershell
[Environment]::SetEnvironmentVariable("CUSTOM_GATEWAY_KEY", "sk-xxxx", "User")   # Windows
```
```bash
export CUSTOM_GATEWAY_KEY="sk-xxxx"                                              # macOS / Linux
```

Alternative — inline (plaintext; trusted single-user machine only, never commit):

```toml
[model_providers.custom]
base_url = "https://GATEWAY/v1"
wire_api = "responses"
experimental_bearer_token = "sk-xxxx"
```

### 5. Restart

Fully quit and relaunch the desktop app. On Windows, launching the desktop app from a terminal that already exported the env var ensures it inherits the key.

## Troubleshooting

- **Desktop picker hides the model** but CLI `/model` lists it → known display bug; hard-code `model` + `model_provider` in config.toml, it still takes effect.
- **400 / tool-calling fails** → gateway lacks `/v1/responses`; switch gateway or add a Responses-compatible proxy.
- **Custom provider ignored** → likely signed in with ChatGPT subscription; set `preferred_auth_method = "apikey"`, sign out in-app, restart.
- **App won't self-update** → if installed from Microsoft Store (MSIX), `WindowsApps\` is write-protected; update via Store → Library, or `winget upgrade`. Unrelated to proxy/network.

## Security

- Never write real keys or private endpoints into a repo. Use `env_key` + environment variables.
- Treat `~/.codex/auth.json` as a secret file; do not hand-edit or commit it.
