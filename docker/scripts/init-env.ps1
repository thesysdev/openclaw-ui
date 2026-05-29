$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EnvFile = Join-Path $RootDir ".env"
$ExampleFile = Join-Path $RootDir ".env.example"

if (!(Test-Path $EnvFile)) {
  Copy-Item $ExampleFile $EnvFile
}

$envText = Get-Content $EnvFile -Raw
if ($envText -notmatch "(?m)^OPENCLAW_GATEWAY_TOKEN=.+") {
  $bytes = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  $token = -join ($bytes | ForEach-Object { $_.ToString("x2") })

  if ($envText -match "(?m)^OPENCLAW_GATEWAY_TOKEN=") {
    $envText = $envText -replace "(?m)^OPENCLAW_GATEWAY_TOKEN=.*$", "OPENCLAW_GATEWAY_TOKEN=$token"
  } else {
    $envText = $envText.TrimEnd() + "`nOPENCLAW_GATEWAY_TOKEN=$token`n"
  }
  Set-Content -Path $EnvFile -Value $envText -NoNewline
}

New-Item -ItemType Directory -Force -Path (Join-Path $RootDir "data/openclaw") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RootDir "data/openclaw-auth-profile-secrets") | Out-Null

Write-Host "Initialized $EnvFile"
Write-Host "Gateway token:"
(Select-String -Path $EnvFile -Pattern "^OPENCLAW_GATEWAY_TOKEN=(.*)$").Matches[0].Groups[1].Value
