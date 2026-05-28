FROM oven/bun:1.3.11 AS build

WORKDIR /app

ENV ELECTRON_SKIP_BINARY_DOWNLOAD=1

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates python3 make g++ node-gyp \
  && rm -rf /var/lib/apt/lists/*

COPY package.json bun.lock ./
COPY patches ./patches
COPY apps/desktop/package.json apps/desktop/package.json
COPY apps/marketing/package.json apps/marketing/package.json
COPY apps/server/package.json apps/server/package.json
COPY apps/web/package.json apps/web/package.json
COPY oxlint-plugin-t3code/package.json oxlint-plugin-t3code/package.json
COPY packages/client-runtime/package.json packages/client-runtime/package.json
COPY packages/contracts/package.json packages/contracts/package.json
COPY packages/effect-acp/package.json packages/effect-acp/package.json
COPY packages/effect-codex-app-server/package.json packages/effect-codex-app-server/package.json
COPY packages/shared/package.json packages/shared/package.json
COPY packages/ssh/package.json packages/ssh/package.json
COPY packages/tailscale/package.json packages/tailscale/package.json
COPY scripts/package.json scripts/package.json

RUN --mount=type=cache,target=/root/.bun/install/cache \
  bun install --frozen-lockfile

COPY . .
RUN --mount=type=cache,target=/app/.turbo \
  bun run --filter=@t3tools/web build
RUN --mount=type=cache,target=/app/.turbo \
  bun run --filter=t3 build

FROM oven/bun:1.3.11 AS runtime

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates gh git openssh-client \
  && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production
ENV HOME=/root
ENV T3CODE_HOME=/var/lib/t3code
ENV T3_WORKSPACE=/workspace
ENV CODEX_HOME=/var/lib/codex
ENV T3_HOST=0.0.0.0
ENV T3_PORT=3773

COPY --from=build /app /app

RUN --mount=type=cache,target=/root/.bun/install/cache \
  bun install --global @openai/codex \
  && mkdir -p /var/lib/t3code /var/lib/codex /workspace \
  && mkdir -p /root/.ssh \
  && ssh-keyscan github.com >> /root/.ssh/known_hosts \
  && chmod +x /app/apps/server/scripts/container-entrypoint.sh

EXPOSE 3773

ENTRYPOINT ["/app/apps/server/scripts/container-entrypoint.sh"]
CMD []
