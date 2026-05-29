ARG NODE_IMAGE=node:24-bookworm-slim

FROM ${NODE_IMAGE}

ARG OPENCLAW_VERSION=2026.5.27
ARG OPENCLAW_OS_PLUGIN_VERSION=0.1.5

LABEL org.opencontainers.image.title="OpenClaw with OpenClaw OS" \
  org.opencontainers.image.description="OpenClaw gateway image with the OpenClaw OS workspace plugin pre-cached" \
  org.opencontainers.image.source="https://github.com/thesysdev/openclaw-os" \
  org.opencontainers.image.documentation="https://www.openui.com/openclaw-os" \
  org.opencontainers.image.licenses="MIT"

ENV NODE_ENV=production \
  HOME=/home/node \
  OPENCLAW_HOME=/home/node \
  OPENCLAW_STATE_DIR=/home/node/.openclaw \
  OPENCLAW_CONFIG_DIR=/home/node/.openclaw \
  OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json \
  OPENCLAW_WORKSPACE_DIR=/home/node/.openclaw/workspace \
  OPENCLAW_OS_PLUGIN_PATH=/opt/openclaw-os-plugin/node_modules/@openuidev/openclaw-os-plugin \
  NPM_CONFIG_AUDIT=false \
  NPM_CONFIG_FUND=false

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    hostname \
    lsof \
    openssl \
    procps \
    python3 \
    python3-yaml \
    tini \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g "openclaw@${OPENCLAW_VERSION}" \
  && npm install --prefix /opt/openclaw-os-plugin --omit=dev "@openuidev/openclaw-os-plugin@${OPENCLAW_OS_PLUGIN_VERSION}" \
  && npm cache clean --force \
  && chown -R node:node /opt/openclaw-os-plugin

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh \
  && install -d -m 0755 -o node -g node /home/node/.npm \
  && install -d -m 0755 -o node -g node /home/node/.config \
  && install -d -m 0700 -o node -g node \
    /home/node/.openclaw \
    /home/node/.openclaw/workspace \
    /home/node/.config/openclaw

USER node
WORKDIR /home/node

EXPOSE 18789 18790 3978

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["tini", "-s", "--", "docker-entrypoint.sh"]
CMD ["gateway"]
