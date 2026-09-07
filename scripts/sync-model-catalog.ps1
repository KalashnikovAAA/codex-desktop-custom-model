<#
.SYNOPSIS
  Regenerate the Codex model-catalog JSON from the custom gateway's /v1/models.
.DESCRIPTION
  Codex desktop never fetches /v1/models from a custom provider, so newly added
  upstream models never appear in the picker. This script pulls the live model
  list and rewrites the catalog file referenced by `model_catalog_json` in
  ~/.codex/config.toml, making the picker mirror the gateway.

  Each entry is cloned from scripts/model-entry-template.json (a complete real
  ModelInfo entry). Do NOT hand-write minimal entries: codex requires every
  model to carry `base_instructions` OR `model_messages.instructions_template`,
  and a catalog that fails to parse makes the WHOLE config invalid — the
  desktop app then blocks on "Finish Windows setup (config_load)".

  Base URL and API key are read from the active [model_providers.*] block in
  %USERPROFILE%\.codex\config.toml, so secrets never appear on the command
  line. Override with -BaseUrl / -ApiKey if needed.

  After running: fully quit and relaunch the Codex desktop app (config and
  catalog are only loaded at startup).
.EXAMPLE
  .\sync-model-catalog.ps1
  .\sync-model-catalog.ps1 -OutputPath "$env:USERPROFILE\.codex\gateway-model-catalog.json"
#>
param(
  [string]$BaseUrl,
  [string]$ApiKey,
  [string]$OutputPath = "$env:USERPROFILE\.codex\gateway-model-catalog.json",
  [string]$TemplatePath = "$PSScriptRoot\model-entry-template.json",
  [int]$TimeoutSec = 30
)

$ErrorActionPreference = "Stop"
$configPath = Join-Path $env:USERPROFILE ".codex\config.toml"
if (-not (Test-Path $configPath)) { throw "config.toml not found: $configPath" }
if (-not (Test-Path $TemplatePath)) { throw "Template not found: $TemplatePath (keep it next to this script)" }
$config = Get-Content $configPath -Raw

# Resolve the active provider block unless the caller supplied credentials.
if (-not $BaseUrl -or -not $ApiKey) {
  $providerId = [regex]::Match($config, '(?m)^\s*model_provider\s*=\s*"([^"]+)"').Groups[1].Value
  if (-not $providerId) { throw "No `model_provider` set in config.toml; nothing to sync from." }
  $block = [regex]::Match($config, "(?ms)^\[model_providers\.$([regex]::Escape($providerId))\]\s*(.*?)(?=^\[|\z)").Groups[1].Value
  if (-not $block) { throw "model_providers.$providerId block not found in config.toml" }
  if (-not $BaseUrl) {
    $BaseUrl = [regex]::Match($block, '(?m)^\s*base_url\s*=\s*"([^"]+)"').Groups[1].Value
    if (-not $BaseUrl) { throw "base_url not found in model_providers.$providerId" }
  }
  if (-not $ApiKey) {
    $ApiKey = [regex]::Match($block, "(?m)^\s*experimental_bearer_token\s*=\s*`"([^`"]+)`"").Groups[1].Value
    if (-not $ApiKey) {
      $envName = [regex]::Match($block, '(?m)^\s*env_key\s*=\s*"([^"]+)"').Groups[1].Value
      if ($envName) { $ApiKey = [Environment]::GetEnvironmentVariable($envName) }
    }
  }
}
if (-not $ApiKey) { throw "No API key: set experimental_bearer_token or env_key in the provider block." }
$BaseUrl = $BaseUrl.TrimEnd('/')

Write-Host "=== Sync Codex model catalog from gateway ===" -ForegroundColor Cyan
Write-Host "Gateway  : $BaseUrl"
Write-Host "Catalog  : $OutputPath"
Write-Host "Template : $TemplatePath"
Write-Host ""

$r = Invoke-RestMethod -Uri "$BaseUrl/models" -Headers @{ Authorization = "Bearer $ApiKey" } -TimeoutSec $TimeoutSec
$ids = @($r.data | ForEach-Object { $_.id } | Sort-Object -Unique)
if ($ids.Count -eq 0) { throw "Gateway returned no models." }

$template = Get-Content $TemplatePath -Raw | ConvertFrom-Json
$currentModel = [regex]::Match($config, '(?m)^\s*model\s*=\s*"([^"]+)"').Groups[1].Value

$models = foreach ($id in $ids) {
  # Deep clone via JSON round-trip so shared references never bleed between entries.
  $entry = ConvertTo-Json $template -Depth 20 | ConvertFrom-Json
  $entry.slug = $id
  $entry.display_name = $id
  $entry.description = "$id via $providerId gateway"
  $entry.visibility = "list"
  $entry.priority = if ($id -eq $currentModel) { 0 } else { 5 }
  $entry.upgrade = $null
  $entry.availability_nux = $null
  $entry
}

$json = @{ models = $models } | ConvertTo-Json -Depth 20
# Write UTF-8 WITHOUT BOM: Windows PowerShell 5.1's `Set-Content -Encoding UTF8`
# prepends a BOM, which makes codex's serde_json reject the catalog and breaks
# config loading entirely (the desktop app then fails startup with `config_load`).
[System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.UTF8Encoding]::new($false))

# Self-check: what we wrote must parse back.
$null = Get-Content $OutputPath -Raw | ConvertFrom-Json
Write-Host "Wrote $($ids.Count) models: $($ids -join ', ')" -ForegroundColor Green

if ($config -notmatch '(?m)^\s*model_catalog_json\s*=') {
  Write-Host ""
  Write-Host "NOTE: config.toml has no model_catalog_json key. Add this line ABOVE the first [table]:" -ForegroundColor Yellow
  Write-Host "  model_catalog_json = '$OutputPath'"
}
Write-Host ""
Write-Host "Fully quit and relaunch the Codex desktop app to load the new catalog." -ForegroundColor Cyan
