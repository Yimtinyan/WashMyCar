$ErrorActionPreference = 'Stop'
$bridgeDir = $PSScriptRoot
$nodePath = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $nodePath) {
  $bundledNode = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node.exe'
  if (Test-Path -LiteralPath $bundledNode) { $nodePath = $bundledNode }
}
if (-not $nodePath) { throw 'Node.js was not found. Install Node.js or run through Codex.' }
$runtimeDir = Join-Path $bridgeDir '.runtime'
New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
$connectionPath = Join-Path $runtimeDir 'connection.json'
$running = $false
if (Test-Path -LiteralPath $connectionPath) {
  $connection = Get-Content -LiteralPath $connectionPath -Raw | ConvertFrom-Json
  try { $check = Invoke-RestMethod -Uri ($connection.url + '/healthz') -TimeoutSec 2; $running = $check.service -eq 'WashMyCar Local Figma Bridge' } catch { }
}
if (-not $running) {
  $serverPath = Join-Path $bridgeDir 'server.mjs'
  Start-Process -FilePath $nodePath -ArgumentList @('"' + $serverPath + '"') -WorkingDirectory $bridgeDir -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runtimeDir 'server.log') -RedirectStandardError (Join-Path $runtimeDir 'server.error.log') | Out-Null
  for ($attempt = 0; $attempt -lt 40; $attempt++) {
    Start-Sleep -Milliseconds 150
    try { $check = Invoke-RestMethod -Uri 'http://127.0.0.1:3847/healthz' -TimeoutSec 1; if ($check.ok -and (Test-Path -LiteralPath $connectionPath)) { $running = $true; break } } catch { }
  }
}
if (-not $running) { throw 'The local bridge did not start; see .runtime/server.error.log.' }
& $nodePath (Join-Path $bridgeDir 'cli.mjs') open
Write-Output 'Local Figma bridge is ready. Keep the Figma plugin open after pairing.'
