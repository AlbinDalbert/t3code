#!/usr/bin/env sh
set -eu

HOST="${T3_HOST:-0.0.0.0}"
PORT="${T3_PORT:-3773}"
BASE_DIR="${T3CODE_HOME:-/var/lib/t3code}"
WORKSPACE="${T3_WORKSPACE:-/workspace}"
CODEX_HOME_DIR="${CODEX_HOME:-/var/lib/codex}"

mkdir -p "${BASE_DIR}" "${WORKSPACE}" "${CODEX_HOME_DIR}"

cd /app

exec env CODEX_HOME="${CODEX_HOME_DIR}" bun apps/server/dist/bin.mjs serve \
  --host "${HOST}" \
  --port "${PORT}" \
  --base-dir "${BASE_DIR}" \
  "$@" \
  "${WORKSPACE}"
