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
| `model_catalog_json` | Optional: absolute path to a custom model-catalog JSON that replaces the bundled catalog at startup (see dedicated section) |

### Custom request shaping

You can add headers and query params, but **you cannot inject arbitrary JSON into the request body**:

```toml
[model_providers.custom111.http_headers]
X-Custom-Header = "value"

[model_providers.custom111.query_params]
api-version = "2026-01-01"
```

---

## Show all gateway models in the desktop picker (`model_catalog_json`)

**Why newly added upstream models never appear:** the Codex desktop app **never calls `/v1/models` on a custom provider** (verifiable in logs: the gateway only ever receives `/v1/responses` requests). The picker is fed by the app-server's `model/list`, which only reads the local cache `~/.codex/models_cache.json` — and in API-key mode (no ChatGPT login) no online catalog refresh ever happens. So the picker forever shows the bundled catalog plus the single `model` hard-coded in config.

**Fix:** the top-level config key `model_catalog_json` (supported since codex 0.124, verified on 0.151) — point it at a JSON file that is loaded at startup and **replaces the bundled catalog**, so the picker mirrors your gateway:

```toml
# at the TOP of config.toml, above the first [table]
model_catalog_json = 'C:\Users\<you>\.codex\gateway-model-catalog.json'
```

Generate/refresh the catalog with the bundled script (it reads the provider's base_url and key from config.toml automatically):

```powershell
.\scripts\sync-model-catalog.ps1   # Windows
./scripts/sync-model-catalog.sh    # macOS / Linux
```

The script fetches `/v1/models`, clones each model ID from a **complete template entry** (`scripts/model-entry-template.json`), and writes BOM-free UTF-8 JSON. When upstream adds models: re-run the script → fully quit and relaunch the desktop app.

### Three catalog JSON pitfalls (any one makes the WHOLE config invalid)

1. **Every entry needs `base_instructions` OR `model_messages.instructions_template`.** Hand-written minimal entries fail with `model ... is missing both base_instructions and model_messages.instructions_template` — always clone from the template.
2. **No UTF-8 BOM.** Windows PowerShell 5.1's `Set-Content -Encoding UTF8` writes a BOM, which codex's serde_json rejects. Write with `[IO.File]::WriteAllText($p, $json, [Text.UTF8Encoding]::new($false))`.
3. **A catalog that fails to parse invalidates the entire config.** The desktop app then blocks on "Finish Windows setup · config_load" and retries in a loop, surfacing as repeated UAC prompts — it looks like a UAC problem, but the config file is broken. Validate (Python `tomllib` / `json`) before restarting.

---

## One-command toggle: custom gateway ↔ OpenAI login

`scripts/codex-mode.ps1` (macOS / Linux: `codex-mode.sh`) switches between the two modes. It only touches the four top-level keys in `config.toml` (`model`, `model_provider`, `preferred_auth_method`, `model_catalog_json`); everything else (providers, plugins, MCP servers, project trust...) is preserved:

```powershell
.\scripts\codex-mode.ps1 status            # show current mode
.\scripts\codex-mode.ps1 openai            # switch to OpenAI login mode (ChatGPT account + bundled catalog)
.\scripts\codex-mode.ps1 custom            # switch back to the custom gateway (restores last picker choice)
.\scripts\codex-mode.ps1 openai -Restart   # switch and auto-restart the desktop app
```

Notes:

- Config is read at startup only — **fully quit and relaunch the app** after switching (`-Restart` handles it).
- **First switch to openai mode** requires a one-time `codex login` (ChatGPT account, browser OAuth); the script reminds you when `auth.json` has no ChatGPT tokens.
- Switching to openai saves the current custom settings (model / provider / catalog) to `~/.codex/codex-mode-state.json` and `custom` restores them verbatim — picker choices are never lost.
- In openai mode the `[model_providers.*]` blocks stay in the file but are inert; switch back anytime.

---

## Troubleshooting

### Desktop picker doesn't show my model / new upstream models are invisible
Root cause: the desktop never fetches `/v1/models` from a custom provider (see the `model_catalog_json` section above). Use `model_catalog_json` + the sync script to mirror the gateway in the picker. If you only want one specific model, hard-coding `model` + `model_provider` in `config.toml` still works even when the picker hides it.

### App stuck on "Finish Windows setup", UAC prompt loop (`config_load`)
Not a UAC problem: a `config.toml` parse failure — or a file it references (e.g. the `model_catalog_json` JSON) — invalidates the whole config. The setup wizard fails at `config_load` and retries, which surfaces as a UAC prompt loop. Validate your TOML/JSON (watch for BOM and required fields), fix, then restart.

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
    ├── check-provider.ps1        # Windows compatibility check
    ├── check-provider.sh         # macOS / Linux compatibility check
    ├── sync-model-catalog.ps1    # sync model catalog from gateway (desktop picker)
    ├── sync-model-catalog.sh     # same, macOS / Linux
    ├── model-entry-template.json # complete ModelInfo template entry (used by sync)
    ├── codex-mode.ps1            # toggle custom gateway ↔ OpenAI login mode
    └── codex-mode.sh             # same, macOS / Linux
```

## License

MIT
