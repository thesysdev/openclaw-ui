#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [ ! -f "${ENV_FILE}" ]; then
  cp "${ROOT_DIR}/.env.example" "${ENV_FILE}"
fi

if ! grep -q '^OPENCLAW_GATEWAY_TOKEN=.\+' "${ENV_FILE}"; then
  token="$(openssl rand -hex 32)"
  tmp_file="$(mktemp)"
  awk -v token="${token}" '
    BEGIN { replaced = 0 }
    /^OPENCLAW_GATEWAY_TOKEN=/ {
      print "OPENCLAW_GATEWAY_TOKEN=" token
      replaced = 1
      next
    }
    { print }
    END {
      if (!replaced) {
        print "OPENCLAW_GATEWAY_TOKEN=" token
      }
    }
  ' "${ENV_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${ENV_FILE}"
fi

mkdir -p "${ROOT_DIR}/data/openclaw" "${ROOT_DIR}/data/openclaw-auth-profile-secrets"

echo "Initialized ${ENV_FILE}"
echo "Gateway token:"
grep '^OPENCLAW_GATEWAY_TOKEN=' "${ENV_FILE}" | sed 's/^OPENCLAW_GATEWAY_TOKEN=//'
