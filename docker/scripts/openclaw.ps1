$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

docker compose `
  --project-directory $RootDir `
  -f (Join-Path $RootDir "docker-compose.yml") `
  run --rm openclaw-cli @args
