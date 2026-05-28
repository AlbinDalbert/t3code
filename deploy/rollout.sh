#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-${IMAGE_TAG:-latest}}"
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/albindalbert/t3code}"
IMAGE_TAG="${IMAGE_TAG:-$TAG}"
IMAGE="${IMAGE_REPO}:${IMAGE_TAG}"
K8S_NAMESPACE="${K8S_NAMESPACE:-t3}"
MANIFEST="${MANIFEST:-deploy/kubernetes/t3code-server.yaml}"
DEPLOYMENT="${DEPLOYMENT:-t3code}"
CONTAINER="${CONTAINER:-t3code}"
APP_LABEL="${APP_LABEL:-t3code}"
RESET="${RESET:-0}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required to roll out ${IMAGE}" >&2
  exit 1
fi

if [ "${RESET}" = "1" ]; then
  echo "Deleting deployment/${DEPLOYMENT} in namespace ${K8S_NAMESPACE}"
  kubectl delete "deploy/${DEPLOYMENT}" -n "${K8S_NAMESPACE}" --ignore-not-found=true

  echo "Waiting for old pods with app=${APP_LABEL} to terminate"
  kubectl wait \
    --for=delete pod \
    -l "app=${APP_LABEL}" \
    -n "${K8S_NAMESPACE}" \
    --timeout=180s \
    || true
fi

echo "Applying ${MANIFEST} in namespace ${K8S_NAMESPACE}"
kubectl apply -n "${K8S_NAMESPACE}" -f "${MANIFEST}"

echo "Setting deploy/${DEPLOYMENT} ${CONTAINER} image to ${IMAGE}"
kubectl set image "deploy/${DEPLOYMENT}" "${CONTAINER}=${IMAGE}" -n "${K8S_NAMESPACE}"

echo "Waiting for deploy/${DEPLOYMENT} rollout"
kubectl rollout status "deploy/${DEPLOYMENT}" -n "${K8S_NAMESPACE}"

echo "Rolled out ${IMAGE}"
