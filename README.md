# Codex Desktop · Custom Model & API URL

Use any OpenAI-compatible model gateway with the **OpenAI Codex desktop app** (a.k.a. the ChatGPT desktop client that bundles Codex) — plus the CLI and IDE extension, which all share one config file.

[中文文档 →](README.zh-CN.md)

> ⚠️ **Security first**: never commit your real API key or private endpoint to a public repo. Use environment variables for keys. The examples below use placeholders.

---

## How it works

The Codex desktop app, Codex CLI, and the Codex IDE extension all read the **same user-level config file**:

| OS | Path |
|----|------|
| Windows | `%USERPROFILE%\.codex\config.toml` |
| macOS / Linux | `~/.codex/config.toml` |

To point Codex at your own gateway you add a `model_providers` entry and select it with `model_provider`.

**Important:** the provider definition **must** live in the *user-level* config. Project-level `.codex/config.toml` is ignored for `model_provider`, `model_providers`, `openai_base_url`, `profile`, `notify`, and `otel`.

---

## Quick start

### 1. Verify your gateway is compatible

Codex requires the **Responses API** (`/v1/responses`), not just `/v1/chat/completions`. Run the bundled check script:

```powershell
# Windows PowerShell
.\scripts\check-provider.ps1 -BaseUrl "https://YOUR-GATEWAY/v1" -ApiKey "sk-xxxx" -Model "YOUR-MODEL-ID"
```

```bash
# macOS / Linux
./scripts/check-provider.sh "https://YOUR-GATEWAY/v1" "sk-xxxx" "YOUR-MODEL-ID"
```

The script tests `/v1/models` and `/v1/responses`. If `/v1/responses` returns 200, you're good.

### 2. Edit `config.toml`

Add the following to the **top** of your user-level `config.toml`:

```toml
model = "YOUR-MODEL-ID"
model_provider = "custom111"
preferred_auth_method = "apikey"

[model_providers.custom111]
name = "Custom Gateway"
base_url = "https://YOUR-GATEWAY/v1"   # must end with /v1
wire_api = "responses"
env_key = "CUSTOM_GATEWAY_KEY"          # name of the env var holding your key
```

Set the key as an environment variable (recommended over hard-coding):

```powershell
# Windows (persistent, user scope)
[Environment]::SetEnvironmentVariable("CUSTOM_GATEWAY_KEY", "sk-xxxx", "User")
```

```bash
# macOS / Linux
export CUSTOM_GATEWAY_KEY="sk-xxxx"
```

> **Alternative (inline key):** if you can't manage env vars, you may use
> `experimental_bearer_token = "sk-xxxx"` inside the `[model_providers.*]` block
> instead of `env_key`. This is simpler but stores the key in plaintext — only do
> this on a trusted, single-user machine, and keep the file out of any repo.

### 3. Restart the app

Fully quit and relaunch the Codex desktop app (config is **not** hot-reloaded).

---

## Config field reference

| Field | Meaning |
|-------|---------|
| `model` | Model ID as exposed by your gateway (e.g. `gpt-5.6-sol`, `claude-sonnet-5`) |
| `model_provider` | ID that points to your `[model_providers.*]` block |
| `preferred_auth_method` | Set to `"apikey"` to force API-key auth instead of ChatGPT login |
| `base_url` | Gateway URL, **must end with `/v1`** |
| `wire_api` | Only `"responses"` is currently supported |
| `env_key` | **Name** of the environment variable that holds the key (not the key itself) |
| `experimental_bearer_token` | Inline API key (alternative to `env_key`; plaintext, use with care) |
| `http_headers` | Optional extra request headers |
| `query_params` | Optional extra query-string params |
| `model_reasoning_effort` | Optional: `low` / `medium` / `high` |

### Custom request shaping

You can add headers and query params, but **you cannot inject arbitrary JSON into the request body**:

```toml
[model_providers.custom111.http_headers]
X-Custom-Header = "value"

[model_providers.custom111.query_params]
api-version = "2026-01-01"
```

---

## Troubleshooting

### Desktop model picker doesn't show my model
A known client display issue: the model catalog may load but the desktop selector filters out custom models. If the CLI works (`codex` → `/model` lists it) but the desktop picker doesn't, **hard-code `model` and `model_provider` in `config.toml`** — the setting still takes effect even when the picker hides it.

### Requests fail with 400 / tool-calling breaks
Your gateway likely only supports `/v1/chat/completions`, not `/v1/responses`. Codex forces the Responses API. Either switch to a gateway that supports it, or run a translation proxy in front.

### Auth conflicts (ChatGPT login vs API key)
If you're signed in with a ChatGPT subscription, the custom provider may be ignored. Set `preferred_auth_method = "apikey"` and sign out of the ChatGPT account in the app, then restart.

### Can't update the app itself
If Codex was installed from the **Microsoft Store (MSIX)**, the install dir under `WindowsApps\` is write-protected, so in-app self-update fails. Update via **Microsoft Store → Library → Get updates**, or `winget upgrade`. This is unrelated to your proxy/network.

---

## Repo layout

```
codex-desktop-custom-model/
├── README.md            # this file (English)
├── README.zh-CN.md      # Chinese
├── skills/
│   └── codex-desktop-custom-model/
│       └── SKILL.md     # importable Qoder / AI-assistant skill
└── scripts/
    ├── check-provider.ps1   # Windows compatibility check
    └── check-provider.sh    # macOS / Linux compatibility check
```

## License

MIT
