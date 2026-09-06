#!/usr/bin/env bash
# Check whether an OpenAI-compatible gateway works with Codex (Responses API).
# Usage: ./check-provider.sh <BASE_URL> <API_KEY> <MODEL_ID>
#   e.g. ./check-provider.sh "https://gateway.example.com/v1" "sk-xxxx" "gpt-5.6-sol"
set -uo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <BASE_URL> <API_KEY> <MODEL_ID>" >&2
  exit 2
fi

BASE_URL="${1%/}"
API_KEY="$2"
MODEL="$3"
TIMEOUT="${4:-30}"

echo "=== Codex provider compatibility check ==="
echo "Base URL : $BASE_URL"
echo "Model    : $MODEL"
echo

# 1) List models
echo "[1/2] GET /v1/models ..."
models_body="$(curl -sS --max-time "$TIMEOUT" \
  -H "Authorization: Bearer $API_KEY" \
  "$BASE_URL/models" 2>&1)"
models_status=$?
if [ $models_status -eq 0 ] && echo "$models_body" | grep -q '"id"'; then
  echo "  OK - models endpoint responded."
  if echo "$models_body" | grep -q "\"$MODEL\""; then
    echo "  Target model '$MODEL' is present."
  else
    echo "  WARNING: '$MODEL' not found in the model list."
  fi
else
  echo "  FAILED: $models_body"
fi

# 2) Responses API (the decisive test)
echo
echo "[2/2] POST /v1/responses ..."
resp_body="$(printf '{"model":"%s","input":"Reply with exactly: OK","stream":false}' "$MODEL")"
http_code="$(curl -sS --max-time "$TIMEOUT" -o /tmp/codex_resp.$$ -w '%{http_code}' \
  -X POST "$BASE_URL/responses" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "$resp_body" 2>/tmp/codex_err.$$)"
curl_status=$?
if [ $curl_status -eq 0 ] && [ "$http_code" = "200" ]; then
  echo "  OK - HTTP 200. Gateway is Responses-API compatible; Codex can use it."
else
  echo "  FAILED (HTTP ${http_code:-n/a}):"
  cat /tmp/codex_resp.$$ 2>/dev/null; cat /tmp/codex_err.$$ 2>/dev/null
  echo
  echo "  -> Likely only /v1/chat/completions is supported. Codex needs /v1/responses."
fi
rm -f /tmp/codex_resp.$$ /tmp/codex_err.$$

echo
echo "Done."
