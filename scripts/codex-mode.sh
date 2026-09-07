#!/usr/bin/env bash
# Toggle the Codex desktop app between custom-gateway mode and OpenAI login mode.
#
# Switches the four mode-defining top-level keys in ~/.codex/config.toml:
#   custom : model, model_provider, preferred_auth_method="apikey",
#            model_catalog_json (gateway catalog for the picker)
#   openai : none of the above (bundled catalog, ChatGPT-login auth)
#
# custom -> openai captures the current settings to ~/.codex/codex-mode-state.json
# and 'custom' restores them, so picker choices survive a round trip.
#
# Config loads at startup only: fully quit and relaunch the app afterwards.
# First switch to openai mode needs a one-time `codex login` if auth.json
# has no ChatGPT tokens (the script will tell you).
#
# Usage: ./codex-mode.sh status|custom|openai [--restart]
set -euo pipefail

# Resolve the .codex dir: CODEX_HOME > $HOME/.codex > $USERPROFILE/.codex
# (the last one matters under Git Bash / CI where HOME may be redirected)
if [ -n "${CODEX_HOME:-}" ]; then
  CODEX_DIR="$CODEX_HOME"
elif [ -f "${HOME:-/nonexistent}/.codex/config.toml" ]; then
  CODEX_DIR="$HOME/.codex"
else
  CODEX_DIR="${USERPROFILE:-$HOME}/.codex"
fi
CONFIG="$CODEX_DIR/config.toml"
STATE="$CODEX_DIR/codex-mode-state.json"
MODE="${1:-status}"
RESTART="${2:-}"

[ -f "$CONFIG" ] || { echo "config.toml not found: $CONFIG" >&2; exit 1; }
PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || { echo "python3 (or python) is required" >&2; exit 1; }

run_python() { "$PY" - "$CONFIG" "$STATE" "$MODE" <<'PY'
import json, re, sys

config_path, state_path, mode = sys.argv[1:4]
text = open(config_path, encoding="utf-8").read()

def head_tail(text):
    m = re.search(r"(?m)^\s*\[", text)
    cut = m.start() if m else len(text)
    return text[:cut], text[cut:]

def key(head, name):
    m = re.search(rf"(?m)^\s*{name}\s*=\s*(.+)$", head)
    return m.group(1).strip().strip("\"'") if m else None

def strip_mode_keys(head):
    for k in ("model_provider", "model_catalog_json", "preferred_auth_method", "model"):
        head = re.sub(rf"(?m)^\s*{k}\s*=.*\n?", "", head)
    return head

def write(head, tail):
    # utf-8 without BOM (a BOM invalidates the whole config for codex)
    with open(config_path, "w", encoding="utf-8", newline="\n") as f:
        f.write((head.rstrip("\n") + "\n\n" if head.strip() else "") + tail)

head, tail = head_tail(text)
is_custom = key(head, "model_provider") is not None

if mode == "status":
    if is_custom:
        print("Current mode : CUSTOM gateway")
        print(f"  model    : {key(head,'model')}")
        print(f"  provider : {key(head,'model_provider')}")
        print(f"  catalog  : {key(head,'model_catalog_json')}")
    else:
        print("Current mode : OPENAI (ChatGPT login / bundled catalog)")
    sys.exit(0)

if mode == "custom":
    if is_custom:
        print("Already in custom mode."); sys.exit(0)
    import os
    try:
        state = json.load(open(state_path, encoding="utf-8"))
    except FileNotFoundError:
        state = {}
    m = re.search(r"(?m)^\[model_providers\.([^\]]+)\]", text)
    provider = state.get("provider") or (m.group(1) if m else None)
    model = state.get("model")
    catalog = state.get("catalog") or os.path.join(os.path.dirname(config_path), "gateway-model-catalog.json")
    if not provider or not model:
        sys.exit("No saved custom settings found. Run once in custom mode first (or pre-create codex-mode-state.json).")
    head = strip_mode_keys(head)
    head = (f'model = "{model}"\nmodel_provider = "{provider}"\n'
            f'preferred_auth_method = "apikey"\nmodel_catalog_json = \'{catalog}\'\n') + head
    write(head, tail)
    print(f"Switched to CUSTOM mode: model={model} provider={provider}")

elif mode == "openai":
    if not is_custom:
        print("Already in openai mode."); sys.exit(0)
    import os
    state = {"provider": key(head, "model_provider"),
             "model": key(head, "model"),
             "catalog": key(head, "model_catalog_json")}
    with open(state_path, "w", encoding="utf-8") as f:
        json.dump(state, f)
    write(strip_mode_keys(head), tail)
    print("Switched to OPENAI mode (ChatGPT login, bundled catalog).")
    auth = os.path.join(os.path.dirname(config_path), "auth.json")
    has_tokens = False
    try:
        has_tokens = "tokens" in json.load(open(auth, encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    if not has_tokens:
        print("\nOne-time setup needed: no ChatGPT login found. Run:")
        print("  codex login      # choose ChatGPT sign-in, complete browser OAuth")
else:
    sys.exit(f"Unknown mode: {mode} (use status|custom|openai)")
PY
}

run_python

if [ "$RESTART" = "--restart" ]; then
  echo "Restarting the Codex desktop app..."
  pkill -f "Codex.*ChatGPT|ChatGPT.*Codex" 2>/dev/null || true
  sleep 2
  codex app >/dev/null 2>&1 || echo "  launch the app manually"
elif [ "$MODE" != "status" ]; then
  echo
  echo "Config loads at startup only - fully quit and relaunch the app."
fi
