# OpenClaw OS Docker

Docker image and Compose setup for running OpenClaw with OpenClaw OS registered as a gateway plugin. This is useful when the native installer is not a good fit, especially on Windows.

OpenClaw OS is served by the OpenClaw gateway at:

```text
http://localhost:18789/plugins/openclawos
```

## Quick Start

From this `docker/` directory:

```bash
./scripts/init-env.sh
docker compose up -d --build
```

Windows PowerShell:

```powershell
.\scripts\init-env.ps1
docker compose up -d --build
```

Wait until the gateway is healthy:

```bash
docker compose ps
```

The `openclaw-gateway` row should say `healthy`. First startup can take 20-60 seconds because the gateway installs/registers the OpenClaw OS plugin.

Then open:

- OpenClaw OS: `http://localhost:18789/plugins/openclawos`
- OpenClaw Control UI: `http://localhost:18789/`

Use the `OPENCLAW_GATEWAY_TOKEN` from `.env` when the UI asks for the gateway token.

If the browser says the page is empty or unavailable, the gateway is probably still starting or has crashed. Check:

```bash
docker compose ps
docker compose logs --tail=100 openclaw-gateway
```

## Configure Before Running

Edit `openclaw-os.yaml` before starting the container:

```yaml
model:
  primary: openai/gpt-5.5
  thinking: medium

apiKeys:
  openai: sk-your-key-here
```

You can also keep secrets in `.env` and reference them from YAML:

```env
OPENAI_API_KEY=sk-your-key-here
```

```yaml
apiKeys:
  openai: ${OPENAI_API_KEY}
```

The container applies `openclaw-os.yaml` on every start and stores API keys in OpenClaw's auth-profile store under `./data/openclaw`.

To print the token-authenticated OpenClaw OS URL:

```bash
./scripts/openclaw.sh os url
```

Windows PowerShell:

```powershell
.\scripts\openclaw.ps1 os url
```

## CLI Examples

```bash
# Check gateway health/status.
./scripts/openclaw.sh gateway probe

# Configure models, channels, plugins, and gateway settings.
./scripts/openclaw.sh configure

# Approve browser/device pairing requests.
./scripts/openclaw.sh devices list
./scripts/openclaw.sh devices approve <request-id>
```

Use the wrapper scripts for gateway/device commands instead of a host-installed `openclaw` binary. The wrapper always uses the OpenClaw CLI inside this image, so its gateway protocol matches the container. A host-installed OpenClaw CLI may be older than the Docker gateway and fail with `protocol mismatch`.

## Version Pins

Defaults are pinned in `.env.example`:

- `openclaw@2026.5.27`
- `@openuidev/openclaw-os-plugin@0.1.5`

Change `OPENCLAW_VERSION` or `OPENCLAW_OS_PLUGIN_VERSION`, then rebuild:

```bash
docker compose build --no-cache
docker compose up -d
```

## Persistence

Compose bind-mounts state into:

- `./data/openclaw` for OpenClaw config, workspace, sessions, and installed plugin state
- `./data/openclaw-auth-profile-secrets` for auth-profile secret material

Keep both directories private.
