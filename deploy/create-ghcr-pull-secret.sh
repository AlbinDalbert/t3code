#!/usr/bin/env bash
set -euo pipefail

K8S_NAMESPACE="${K8S_NAMESPACE:-t3}"
SECRET_NAME="${SECRET_NAME:-ghcr-pull}"
GHCR_SERVER="${GHCR_SERVER:-ghcr.io}"
GHCR_USERNAME="${GHCR_USERNAME:-AlbinDalbert}"
GHCR_TOKEN="${GHCR_TOKEN:-${GITHUB_TOKEN:-}}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required to create ${SECRET_NAME}" >&2
  exit 1
fi

if [ -z "${GHCR_TOKEN}" ]; then
  echo "Set GHCR_TOKEN or GITHUB_TOKEN before running this script." >&2
  exit 1
fi

kubectl create secret docker-registry "${SECRET_NAME}" \
  -n "${K8S_NAMESPACE}" \
  --docker-server="${GHCR_SERVER}" \
  --docker-username="${GHCR_USERNAME}" \
  --docker-password="${GHCR_TOKEN}" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Updated secret ${SECRET_NAME} in namespace ${K8S_NAMESPACE}"
