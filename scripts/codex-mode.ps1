<#
.SYNOPSIS
  Toggle the Codex desktop app between custom-gateway mode and OpenAI login mode.
.DESCRIPTION
  Switches the four mode-defining top-level keys in ~/.codex/config.toml:

    custom mode : model, model_provider, preferred_auth_method = "apikey",
                  model_catalog_json (gateway catalog for the picker)
    openai mode : none of the above (bundled catalog, ChatGPT-login auth)

  Everything else (providers, plugins, MCP servers, projects...) is untouched.
  When switching custom -> openai the current custom settings are captured to
  ~/.codex/codex-mode-state.json and restored on the way back, so picker
  choices made inside a mode survive a round trip.

  IMPORTANT:
  - Config is read at startup only. Use -Restart to also restart the app, or
    fully quit and relaunch it yourself.
  - First switch to openai mode requires a one-time `codex login` (ChatGPT
    account) if auth.json has no ChatGPT tokens. The script will tell you.

  Only top-level keys are touched: edits are applied strictly before the
  first [table] header, and config.toml is rewritten as UTF-8 without BOM.
.EXAMPLE
  .\codex-mode.ps1 status
  .\codex-mode.ps1 openai -Restart
  .\codex-mode.ps1 custom -Restart
#>
param(
  [Parameter(Position = 0)][ValidateSet("status", "custom", "openai")][string]$Mode = "status",
  [switch]$Restart,
  [string]$Model,          # custom mode: override model (default: last used)
  [string]$Provider,       # custom mode: override provider id (default: last used)
  [string]$CatalogPath     # custom mode: override catalog path (default: last used)
)
$ErrorActionPreference = "Stop"

$codexDir = Join-Path $env:USERPROFILE ".codex"
$configPath = Join-Path $codexDir "config.toml"
$statePath = Join-Path $codexDir "codex-mode-state.json"
if (-not (Test-Path $configPath)) { throw "config.toml not found: $configPath" }

function Read-HeadTail {
  # Split config.toml into (top-level head, rest) at the first [table] header.
  $lines = [System.IO.File]::ReadAllLines($configPath)
  $cut = ($lines | Select-String -Pattern '^\s*\[' | Select-Object -First 1).LineNumber
  if (-not $cut) { $cut = $lines.Count + 1 }
  $head = ($lines[0..([Math]::Min($cut - 2, $lines.Count - 1))] -join "`n")
  $tail = if ($cut -le $lines.Count) { ($lines[($cut - 1)..($lines.Count - 1)] -join "`n") } else { "" }
  return @($head, $tail)
}

function Get-HeadKey([string]$head, [string]$key) {
  # Right-hand side with surrounding quotes (single or double) stripped.
  [regex]::Match($head, ("(?m)^\s*$key\s*=\s*(.+)$")).Groups[1].Value.Trim().Trim([char[]]@('"', "'"))
}

function Remove-ModeKeys([string]$head) {
  foreach ($k in "model_provider", "model_catalog_json", "preferred_auth_method", "model") {
    $head = [regex]::Replace($head, "(?m)^\s*$k\s*=.*(\r?\n|$)", "")
  }
  $head
}

function Write-Config([string]$head, [string]$tail) {
  $text = if ($tail) { "$head`n$tail" } else { $head }
  [System.IO.File]::WriteAllText($configPath, $text.TrimStart("`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Test-ChatGptAuth {
  (Test-Path (Join-Path $codexDir "auth.json")) -and
    (Get-Content (Join-Path $codexDir "auth.json") -Raw | ConvertFrom-Json).PSObject.Properties.Name -contains "tokens"
}

function Restart-App {
  Write-Host "Restarting the Codex desktop app..." -ForegroundColor Cyan
  taskkill /IM ChatGPT.exe /F 2>$null | Out-Null
  Start-Sleep -Seconds 3
  $codexBin = Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin" -Filter codex.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($codexBin) { Start-Process $codexBin.FullName -ArgumentList "app" } else { Write-Host "  codex.exe not found - launch the app manually." -ForegroundColor Yellow }
}

$head, $tail = Read-HeadTail
$isCustom = [bool](Get-HeadKey $head "model_provider")

switch ($Mode) {
  "status" {
    if ($isCustom) {
      Write-Host "Current mode : CUSTOM gateway" -ForegroundColor Green
      Write-Host ("  model      : " + (Get-HeadKey $head "model"))
      Write-Host ("  provider   : " + (Get-HeadKey $head "model_provider"))
      Write-Host ("  catalog    : " + (Get-HeadKey $head "model_catalog_json"))
    } else {
      Write-Host "Current mode : OPENAI (ChatGPT login / bundled catalog)" -ForegroundColor Green
    }
    return
  }

  "custom" {
    if ($isCustom) { Write-Host "Already in custom mode."; if ($Restart) { Restart-App }; return }
    $state = if (Test-Path $statePath) { Get-Content $statePath -Raw | ConvertFrom-Json } else { $null }
    $provider = if ($Provider) { $Provider } elseif ($state) { $state.provider } else { "" }
    $model = if ($Model) { $Model } elseif ($state) { $state.model } else { "" }
    $catalog = if ($CatalogPath) { $CatalogPath } elseif ($state) { $state.catalog } else { "" }
    if (-not $provider) {
      # Fall back to the first [model_providers.*] block in the file.
      $provider = [regex]::Match((Get-Content $configPath -Raw), '(?m)^\[model_providers\.([^\]]+)\]').Groups[1].Value
    }
    if (-not $provider -or -not $model) { throw "No saved custom settings and no -Provider/-Model given. Run once with explicit parameters." }
    if (-not $catalog) { $catalog = Join-Path $codexDir "gateway-model-catalog.json" }

    $head = Remove-ModeKeys $head
    # TOML literal strings (single quotes) need no backslash escaping.
    $head = "model = `"$model`"`nmodel_provider = `"$provider`"`npreferred_auth_method = `"apikey`"`nmodel_catalog_json = '$catalog'`n$head"
    Write-Config $head $tail
    Write-Host "Switched to CUSTOM mode: model=$model provider=$provider" -ForegroundColor Green
    Write-Host "  (preferred_auth_method=apikey, model_catalog_json restored)"
  }

  "openai" {
    if (-not $isCustom) { Write-Host "Already in openai mode."; if ($Restart) { Restart-App }; return }
    # Capture current custom settings so 'custom' can restore them verbatim.
    # (TOML literal strings carry unescaped backslashes - keep the value as-is.)
    @{ provider = Get-HeadKey $head "model_provider"
       model    = Get-HeadKey $head "model"
       catalog  = Get-HeadKey $head "model_catalog_json"
    } | ConvertTo-Json | Set-Content -Path $statePath -Encoding ASCII

    $head = Remove-ModeKeys $head
    Write-Config $head $tail
    Write-Host "Switched to OPENAI mode (ChatGPT login, bundled catalog)." -ForegroundColor Green
    if (-not (Test-ChatGptAuth)) {
      Write-Host ""
      Write-Host "One-time setup needed: no ChatGPT login found. Run:" -ForegroundColor Yellow
      Write-Host "  codex login      # choose ChatGPT sign-in, complete browser OAuth" -ForegroundColor Yellow
    }
  }
}

if ($Restart) { Restart-App } else {
  Write-Host ""
  Write-Host "Config loads at startup only - fully quit and relaunch the app (or rerun with -Restart)." -ForegroundColor Cyan
}
