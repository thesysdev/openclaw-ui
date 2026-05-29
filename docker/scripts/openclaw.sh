#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec docker compose \
  --project-directory "${ROOT_DIR}" \
  -f "${ROOT_DIR}/docker-compose.yml" \
  run --rm openclaw-cli "$@"
