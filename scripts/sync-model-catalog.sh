#!/usr/bin/env bash
# Regenerate the Codex model-catalog JSON from the custom gateway's /v1/models.
#
# Codex desktop never fetches /v1/models from a custom provider, so newly added
# upstream models never appear in the picker. This script pulls the live model
# list and rewrites the catalog file referenced by `model_catalog_json` in
# ~/.codex/config.toml, making the picker mirror the gateway.
#
# Each entry is cloned from scripts/model-entry-template.json (a complete real
# ModelInfo entry). Do NOT hand-write minimal entries: codex requires every
# model to carry `base_instructions` OR `model_messages.instructions_template`,
# and a catalog that fails to parse makes the WHOLE config invalid — the
# desktop app then blocks on "Finish Windows setup (config_load)".
#
# Base URL and API key are read from the active [model_providers.*] block, so
# secrets never need to appear on the command line. Override with $1/$2.
#
# Usage: ./sync-model-catalog.sh [base_url] [api_key]
#        (default output: ~/.codex/gateway-model-catalog.json)
set -euo pipefail

CONFIG="${CODEX_HOME:-$HOME}/.codex/config.toml"
OUT="${CODEX_HOME:-$HOME}/.codex/gateway-model-catalog.json"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)/model-entry-template.json"
BASE_URL="${1:-}"
API_KEY="${2:-}"
TIMEOUT="${TIMEOUT_SEC:-30}"

[ -f "$CONFIG" ] || { echo "config.toml not found: $CONFIG" >&2; exit 1; }
[ -f "$TEMPLATE" ] || { echo "Template not found: $TEMPLATE (keep it next to this script)" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

provider_id=$(grep -m1 -E '^\s*model_provider\s*=' "$CONFIG" | sed -E 's/.*"([^"]+)".*/\1/')
[ -n "$provider_id" ] || { echo "No model_provider set in config.toml" >&2; exit 1; }

block=$(awk -v id="model_providers.$provider_id" '
  $0 == "[" id "]" { inblock=1; next }
  /^\[/ { inblock=0 }
  inblock { print }
' "$CONFIG")

[ -n "$block" ] || { echo "model_providers.$provider_id block not found" >&2; exit 1; }

if [ -z "$BASE_URL" ]; then
  BASE_URL=$(grep -m1 -E '^\s*base_url\s*=' <<<"$block" | sed -E 's/.*"([^"]+)".*/\1/')
  [ -n "$BASE_URL" ] || { echo "base_url not found in model_providers.$provider_id" >&2; exit 1; }
fi
if [ -z "$API_KEY" ]; then
  API_KEY=$(grep -m1 -E '^\s*experimental_bearer_token\s*=' <<<"$block" | sed -E 's/.*"([^"]+)".*/\1/')
  if [ -z "$API_KEY" ]; then
    env_name=$(grep -m1 -E '^\s*env_key\s*=' <<<"$block" | sed -E 's/.*"([^"]+)".*/\1/')
    [ -n "$env_name" ] && API_KEY="${!env_name:-}"
  fi
fi
[ -n "$API_KEY" ] || { echo "No API key: set experimental_bearer_token or env_key in the provider block." >&2; exit 1; }
BASE_URL="${BASE_URL%/}"

echo "=== Sync Codex model catalog from gateway ==="
echo "Gateway  : $BASE_URL"
echo "Catalog  : $OUT"
echo "Template : $TEMPLATE"

body=$(curl -sf -m "$TIMEOUT" -H "Authorization: Bearer $API_KEY" "$BASE_URL/models") \
  || { echo "GET $BASE_URL/models failed" >&2; exit 1; }

current_model=$(grep -m1 -E '^\s*model\s*=' "$CONFIG" | sed -E 's/.*"([^"]+)".*/\1/')

BASE_URL="$BASE_URL" OUT="$OUT" TEMPLATE="$TEMPLATE" \
  CURRENT_MODEL="$current_model" PROVIDER_ID="$provider_id" MODELS_JSON="$body" python3 - <<'PY'
import copy, json, os

ids = sorted({m["id"] for m in json.loads(os.environ["MODELS_JSON"])["data"]})
if not ids:
    raise SystemExit("Gateway returned no models.")

template = json.load(open(os.environ["TEMPLATE"], encoding="utf-8-sig"))
current = os.environ.get("CURRENT_MODEL", "")
provider = os.environ.get("PROVIDER_ID", "custom")

models = []
for mid in ids:
    entry = copy.deepcopy(template)
    entry.update({
        "slug": mid,
        "display_name": mid,
        "description": f"{mid} via {provider} gateway",
        "visibility": "list",
        "priority": 0 if mid == current else 5,
        "upgrade": None,
        "availability_nux": None,
    })
    models.append(entry)

# utf-8 without BOM: a BOM makes codex's serde_json reject the whole catalog.
with open(os.environ["OUT"], "w", encoding="utf-8", newline="\n") as f:
    json.dump({"models": models}, f, ensure_ascii=False)

print(f"Wrote {len(models)} models: {', '.join(ids)}")
PY

if ! grep -qE '^\s*model_catalog_json\s*=' "$CONFIG"; then
  echo
  echo "NOTE: config.toml has no model_catalog_json key. Add ABOVE the first [table]:"
  echo "  model_catalog_json = '$OUT'"
fi
echo
echo "Fully quit and relaunch the Codex desktop app to load the new catalog."
