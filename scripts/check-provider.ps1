<#
.SYNOPSIS
  Check whether an OpenAI-compatible gateway works with Codex (Responses API).
.DESCRIPTION
  Tests GET /v1/models and POST /v1/responses. Codex forces wire_api="responses",
  so /v1/responses returning HTTP 200 is the key signal.
.EXAMPLE
  .\check-provider.ps1 -BaseUrl "https://gateway.example.com/v1" -ApiKey "sk-xxxx" -Model "gpt-5.6-sol"
#>
param(
  [Parameter(Mandatory = $true)][string]$BaseUrl,
  [Parameter(Mandatory = $true)][string]$ApiKey,
  [Parameter(Mandatory = $true)][string]$Model,
  [int]$TimeoutSec = 30
)

$ErrorActionPreference = "Stop"
if ($BaseUrl.EndsWith("/")) { $BaseUrl = $BaseUrl.TrimEnd("/") }
$headers = @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json" }

Write-Host "=== Codex provider compatibility check ===" -ForegroundColor Cyan
Write-Host "Base URL : $BaseUrl"
Write-Host "Model    : $Model"
Write-Host ""

# 1) List models
Write-Host "[1/2] GET /v1/models ..." -ForegroundColor Yellow
try {
  $r = Invoke-RestMethod -Uri "$BaseUrl/models" -Headers $headers -TimeoutSec $TimeoutSec
  $ids = @($r.data | ForEach-Object { $_.id })
  Write-Host "  OK - $($ids.Count) model(s) available." -ForegroundColor Green
  if ($ids -contains $Model) {
    Write-Host "  Target model '$Model' is present." -ForegroundColor Green
  } else {
    Write-Host "  WARNING: '$Model' NOT in list. Available: $($ids -join ', ')" -ForegroundColor DarkYellow
  }
} catch {
  Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
}

# 2) Responses API (the decisive test)
Write-Host ""
Write-Host "[2/2] POST /v1/responses ..." -ForegroundColor Yellow
$body = @{ model = $Model; input = "Reply with exactly: OK"; stream = $false } | ConvertTo-Json
try {
  $resp = Invoke-WebRequest -Uri "$BaseUrl/responses" -Method Post -Headers $headers -Body $body -TimeoutSec $TimeoutSec -UseBasicParsing
  if ($resp.StatusCode -eq 200) {
    Write-Host "  OK - HTTP 200. Gateway is Responses-API compatible; Codex can use it." -ForegroundColor Green
  } else {
    Write-Host "  Unexpected status: $($resp.StatusCode)" -ForegroundColor DarkYellow
  }
} catch {
  $code = $_.Exception.Response.StatusCode.value__
  Write-Host "  FAILED (HTTP $code): $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "  -> Likely only /v1/chat/completions is supported. Codex needs /v1/responses." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
