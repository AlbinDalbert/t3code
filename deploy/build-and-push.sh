#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-${IMAGE_TAG:-latest}}"
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/albindalbert/t3code}"
IMAGE_TAG="${IMAGE_TAG:-$TAG}"
IMAGE="${IMAGE_REPO}:${IMAGE_TAG}"
TARGETARCH="${TARGETARCH:-amd64}"
NO_CACHE="${NO_CACHE:-0}"
PUSH="${PUSH:-1}"
BUILDER_NAME="${BUILDER_NAME:-t3code-builder}"

case "${TARGETARCH}" in
  x86_64) TARGETARCH="amd64" ;;
  aarch64) TARGETARCH="arm64" ;;
  amd64 | arm64) ;;
  *)
    echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2
    exit 1
    ;;
esac

TARGETPLATFORM="${TARGETPLATFORM:-linux/${TARGETARCH}}"
CACHE_REF="${CACHE_REF:-${IMAGE_REPO}:buildcache-${TARGETARCH}}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to build and push ${IMAGE}" >&2
  exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
  cat >&2 <<'EOF'
docker buildx is required for this script.

Install the Docker Buildx plugin, then run this again. On Arch-based systems:

  sudo pacman -S docker-buildx

On Debian/Ubuntu Docker CE installs, the package is usually:

  sudo apt install docker-buildx-plugin

EOF
  exit 1
fi

echo "Building ${IMAGE} for ${TARGETPLATFORM}"
echo "Using registry build cache ${CACHE_REF}"

if ! docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
  docker buildx create --name "${BUILDER_NAME}" --driver docker-container >/dev/null
fi

docker buildx use "${BUILDER_NAME}"
docker buildx inspect --bootstrap >/dev/null

build_args=(
  --platform "${TARGETPLATFORM}"
  --build-arg "TARGETARCH=${TARGETARCH}"
  --cache-from "type=registry,ref=${CACHE_REF}"
  --cache-to "type=registry,ref=${CACHE_REF},mode=max"
  -t "${IMAGE}"
)

if [ "${NO_CACHE}" = "1" ]; then
  build_args=(--no-cache "${build_args[@]}")
fi

if [ "${PUSH}" = "1" ]; then
  build_args=("${build_args[@]}" --push)
else
  build_args=("${build_args[@]}" --load)
fi

docker buildx build "${build_args[@]}" .

echo "Built ${IMAGE}"
if [ "${PUSH}" = "1" ]; then
  echo "Pushed ${IMAGE}"
fi
