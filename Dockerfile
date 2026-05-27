FROM oven/bun:1.3.11 AS build

WORKDIR /app

COPY . .

RUN bun install .
RUN bun run --filter=@t3tools/web build
RUN bun run --filter=t3 build

FROM oven/bun:1.3.11 AS runtime

WORKDIR /app

ENV NODE_ENV=production
ENV HOME=/root
ENV T3CODE_HOME=/var/lib/t3code
ENV T3_WORKSPACE=/workspace
ENV CODEX_HOME=/var/lib/codex
ENV T3_HOST=0.0.0.0
ENV T3_PORT=3773

COPY --from=build /app /app

RUN npm install --global @openai/codex \
  && mkdir -p /var/lib/t3code /var/lib/codex /workspace \
  && chmod +x /app/apps/server/scripts/container-entrypoint.sh

EXPOSE 3773

ENTRYPOINT ["/app/apps/server/scripts/container-entrypoint.sh"]
CMD []
