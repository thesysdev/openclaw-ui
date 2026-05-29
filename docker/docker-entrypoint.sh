#!/usr/bin/env bash
set -euo pipefail

is_truthy() {
  case "${1:-}" in
    1 | true | TRUE | yes | YES | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_dirs() {
  mkdir -p \
    "${OPENCLAW_STATE_DIR}" \
    "${OPENCLAW_WORKSPACE_DIR}" \
    "$(dirname "${OPENCLAW_CONFIG_PATH}")" \
    /home/node/.config/openclaw
}

configure_gateway() {
  local batch_json

  batch_json="$(node -e '
    const bindMode = process.env.OPENCLAW_GATEWAY_BIND || "lan";
    const authMode = process.env.OPENCLAW_GATEWAY_AUTH_MODE || "token";
    const port = process.env.OPENCLAW_GATEWAY_HOST_PORT || "18789";
    const token = process.env.OPENCLAW_GATEWAY_TOKEN || "";
    const extra = (process.env.OPENCLAW_CONTROL_UI_EXTRA_ORIGINS || "")
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean);
    const ops = [
      { path: "gateway.mode", value: "local" },
      { path: "gateway.bind", value: bindMode },
      { path: "gateway.auth.mode", value: authMode },
      {
        path: "gateway.controlUi.allowedOrigins",
        value: [`http://localhost:${port}`, `http://127.0.0.1:${port}`, ...extra],
      },
    ];
    if (token) {
      ops.push({ path: "gateway.auth.token", value: token });
    }
    process.stdout.write(JSON.stringify(ops));
  ')"

  openclaw config set --batch-json "$batch_json" >/dev/null
}

apply_bootstrap_config() {
  local config_path="${OPENCLAW_BOOTSTRAP_CONFIG:-/etc/openclaw-os/openclaw-os.yaml}"
  local patch_file="/tmp/openclaw-bootstrap.patch.json"
  local keys_file="/tmp/openclaw-bootstrap-api-keys.tsv"

  if [ ! -f "$config_path" ]; then
    return 0
  fi

  python3 - "$config_path" "$patch_file" "$keys_file" <<'PY'
import json
import os
import sys
import yaml

config_path, patch_path, keys_path = sys.argv[1:4]

with open(config_path, "r", encoding="utf-8") as f:
    raw = yaml.safe_load(f) or {}

cfg = raw.get("openclaw", raw) or {}
patch = {}
keys = []

PLACEHOLDERS = {
    "",
    "change-me",
    "replace-me",
    "paste-your-key-here",
    "sk-...",
    "sk-ant-...",
    "your-api-key",
}


def useful(value):
    if value is None:
        return False
    if isinstance(value, str):
        return value.strip().lower() not in PLACEHOLDERS
    return True


def resolve(value):
    if not isinstance(value, str):
        return value
    value = value.strip()
    if value.startswith("${") and value.endswith("}"):
        return os.environ.get(value[2:-1], "")
    return value


def deep_merge(target, source):
    for key, value in source.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            deep_merge(target[key], value)
        else:
            target[key] = value


gateway = cfg.get("gateway") or {}
gateway_patch = {}
if useful(gateway.get("bind")):
    gateway_patch["bind"] = str(gateway["bind"])
if useful(gateway.get("authMode")):
    gateway_patch.setdefault("auth", {})["mode"] = str(gateway["authMode"])
if useful(gateway.get("authToken")):
    gateway_patch.setdefault("auth", {})["token"] = str(resolve(gateway["authToken"]))
if useful(gateway.get("allowedOrigins")):
    gateway_patch.setdefault("controlUi", {})["allowedOrigins"] = list(gateway["allowedOrigins"])
if gateway_patch:
    patch.setdefault("gateway", {})
    deep_merge(patch["gateway"], gateway_patch)

model = cfg.get("model") or {}
primary = model.get("primary")
fallbacks = model.get("fallbacks") or []
if useful(primary):
    primary = str(primary)
    model_patch = {"primary": primary}
    if fallbacks:
        model_patch["fallbacks"] = [str(item) for item in fallbacks if useful(item)]
    patch.setdefault("agents", {}).setdefault("defaults", {})["model"] = model_patch
    allowed_models = patch["agents"]["defaults"].setdefault("models", {})
    allowed_models.setdefault(primary, {})
    for fallback in model_patch.get("fallbacks", []):
        allowed_models.setdefault(fallback, {})
if useful(model.get("thinking")):
    patch.setdefault("agents", {}).setdefault("defaults", {})["thinkingDefault"] = str(model["thinking"])
if useful(model.get("workspace")):
    patch.setdefault("agents", {}).setdefault("defaults", {})["workspace"] = str(model["workspace"])

providers = cfg.get("providers") or {}
for provider_id, provider_cfg in providers.items():
    if not isinstance(provider_cfg, dict):
        continue
    clean = {}
    for key in ("baseUrl", "api", "auth", "contextWindow", "contextTokens", "maxTokens", "timeoutSeconds"):
        if useful(provider_cfg.get(key)):
            clean[key] = resolve(provider_cfg[key])
    if useful(provider_cfg.get("apiKey")):
        clean["apiKey"] = resolve(provider_cfg["apiKey"])
    models = provider_cfg.get("models")
    if isinstance(models, list):
        clean["models"] = {str(name): {} for name in models if useful(name)}
    elif isinstance(models, dict):
        clean["models"] = models
    if clean:
        patch.setdefault("models", {}).setdefault("providers", {})[str(provider_id)] = clean

api_keys = cfg.get("apiKeys") or cfg.get("api_keys") or {}
for provider_id, api_key in api_keys.items():
    api_key = resolve(api_key)
    if useful(api_key):
        provider_id = str(provider_id)
        profile_id = f"{provider_id}:docker"
        keys.append((provider_id, profile_id, str(api_key)))
        patch.setdefault("auth", {}).setdefault("profiles", {})[profile_id] = {
            "provider": provider_id,
            "mode": "api_key",
        }

for item in cfg.get("authProfiles") or []:
    if not isinstance(item, dict):
        continue
    provider_id = item.get("provider")
    api_key = resolve(item.get("apiKey"))
    if useful(provider_id) and useful(api_key):
        provider_id = str(provider_id)
        profile_id = str(item.get("profileId") or f"{provider_id}:docker")
        keys.append((provider_id, profile_id, str(api_key)))
        patch.setdefault("auth", {}).setdefault("profiles", {})[profile_id] = {
            "provider": provider_id,
            "mode": "api_key",
        }

with open(patch_path, "w", encoding="utf-8") as f:
    json.dump(patch, f)

with open(keys_path, "w", encoding="utf-8") as f:
    for provider_id, profile_id, api_key in keys:
        f.write(f"{provider_id}\t{profile_id}\t{api_key}\n")
PY

  if [ -s "$patch_file" ] && [ "$(node -e "const fs=require('node:fs'); const p=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(Object.keys(p).length ? 'yes' : 'no')" "$patch_file")" = "yes" ]; then
    openclaw config patch --stdin <"$patch_file" >/dev/null
  fi

  if [ -s "$keys_file" ]; then
    node - "$keys_file" "${OPENCLAW_STATE_DIR}/agents/main/agent/auth-profiles.json" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const [keysPath, storePath] = process.argv.slice(2);
let store = { version: 1, profiles: {} };
try {
  store = JSON.parse(fs.readFileSync(storePath, "utf8"));
  if (!store || typeof store !== "object") store = { version: 1, profiles: {} };
  if (!store.profiles || typeof store.profiles !== "object") store.profiles = {};
} catch {
  // First run.
}

for (const line of fs.readFileSync(keysPath, "utf8").split(/\r?\n/)) {
  if (!line.trim()) continue;
  const [provider, profileId, ...rest] = line.split("\t");
  const apiKey = rest.join("\t");
  if (!provider || !profileId || !apiKey) continue;
  store.profiles[profileId] = {
    type: "api_key",
    provider,
    key: apiKey,
  };
}

fs.mkdirSync(path.dirname(storePath), { recursive: true, mode: 0o700 });
fs.writeFileSync(storePath, `${JSON.stringify(store, null, 2)}\n`, { mode: 0o600 });
NODE
  fi
}

install_openclaw_os_plugin() {
  if ! is_truthy "${OPENCLAW_OS_AUTO_INSTALL:-1}"; then
    return 0
  fi

  local spec="${OPENCLAW_OS_PLUGIN_SPEC:-${OPENCLAW_OS_PLUGIN_PATH}}"
  local marker="${OPENCLAW_STATE_DIR}/.openclaw-os-plugin.spec"

  if [ -f "$marker" ] && [ "$(cat "$marker")" = "$spec" ]; then
    return 0
  fi

  echo "Installing OpenClaw OS plugin from ${spec}..."
  openclaw plugins install "$spec" --force
  printf '%s' "$spec" >"$marker"
}

start_gateway() {
  local bind_mode="${OPENCLAW_GATEWAY_BIND:-lan}"
  local port="${OPENCLAW_GATEWAY_PORT:-18789}"
  local auth_mode="${OPENCLAW_GATEWAY_AUTH_MODE:-token}"

  ensure_dirs
  configure_gateway
  apply_bootstrap_config
  install_openclaw_os_plugin

  exec openclaw gateway \
    --bind "$bind_mode" \
    --port "$port" \
    --auth "$auth_mode"
}

case "${1:-gateway}" in
  gateway)
    shift || true
    start_gateway "$@"
    ;;
  configure)
    ensure_dirs
    configure_gateway
    apply_bootstrap_config
    install_openclaw_os_plugin
    ;;
  cli)
    shift || true
    exec openclaw "$@"
    ;;
  openclaw)
    shift || true
    exec openclaw "$@"
    ;;
  *)
    exec openclaw "$@"
    ;;
esac
