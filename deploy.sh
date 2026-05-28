#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-latest}"
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/albindalbert/t3code}"
IMAGE_TAG="${IMAGE_TAG:-$TAG}"
IMAGE="${IMAGE_REPO}:${IMAGE_TAG}"
K8S_NAMESPACE="${K8S_NAMESPACE:-t3}"
NERDCTL_NAMESPACE="${NERDCTL_NAMESPACE:-k8s.io}"
NO_CACHE="${NO_CACHE:-0}"
TARGETARCH="${TARGETARCH:-amd64}"

case "${TARGETARCH}" in
    x86_64) TARGETARCH="amd64" ;;
    aarch64) TARGETARCH="arm64" ;;
    amd64|arm64) ;;
    *)
        echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2
        exit 1
        ;;
esac

TARGETPLATFORM="${TARGETPLATFORM:-linux/${TARGETARCH}}"

if ! pgrep -x buildkitd >/dev/null 2>&1; then
    sudo buildkitd >/dev/null 2>&1 &
    sleep 2
fi

build_args=(
    --platform "${TARGETPLATFORM}"
    --build-arg "TARGETARCH=${TARGETARCH}"
    -t "${IMAGE}"
    .
)

if [ "${NO_CACHE}" = "1" ]; then
    build_args=(--no-cache "${build_args[@]}")
fi

echo "Building ${IMAGE} for ${TARGETPLATFORM} in namespace ${NERDCTL_NAMESPACE}"
sudo nerdctl --namespace "${NERDCTL_NAMESPACE}" build "${build_args[@]}"

echo "Applying Kubernetes manifest in namespace ${K8S_NAMESPACE}"
kubectl apply -n "${K8S_NAMESPACE}" -f deploy/kubernetes/t3code-server.yaml

echo "Setting deploy/t3code image to ${IMAGE} in namespace ${K8S_NAMESPACE}"
kubectl set image deploy/t3code t3code="${IMAGE}" -n "${K8S_NAMESPACE}"

echo "Restarting deploy/t3code in namespace ${K8S_NAMESPACE}"
kubectl rollout restart deploy/t3code -n "${K8S_NAMESPACE}"

echo "Done."
