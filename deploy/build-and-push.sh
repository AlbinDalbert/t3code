#!/usr/bin/env bash
set -euo pipefail

USE_KANIKO=0
POSITIONAL=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --kaniko)
      USE_KANIKO=1
      shift
      ;;
    --help | -h)
      cat <<'EOF'
Usage: deploy/build-and-push.sh [--kaniko] [tag]

Build and push the deployable T3 Code image.

Options:
  --kaniko  Run the build as a Kubernetes Kaniko Job instead of docker buildx.

Environment:
  IMAGE_REPO                    Image repository. Default: ghcr.io/albindalbert/t3code
  IMAGE_TAG                     Image tag. Default: positional tag or latest
  TARGETARCH                    amd64 or arm64. Default: amd64
  K8S_NAMESPACE                 Kubernetes namespace for --kaniko. Default: t3
  KANIKO_CONTEXT                Kaniko context path. Default: /workspace/t3code
  KANIKO_DOCKERFILE             Kaniko Dockerfile path. Default: /workspace/t3code/deploy/Dockerfile.kaniko
  KANIKO_WORKSPACE_PVC          PVC mounted at /workspace for --kaniko. Default: t3code-workspace
  KANIKO_DOCKER_CONFIG_SECRET   dockerconfigjson secret for GHCR auth. Default: ghcr-pull
  KANIKO_NODE_SELECTOR          Optional nodeSelector as key=value. Default: kubernetes.io/hostname=sietch-tabr
  KANIKO_TIMEOUT_SECONDS        Wait timeout for --kaniko. Default: 3600
EOF
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        POSITIONAL+=("$1")
        shift
      done
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

TAG="${POSITIONAL[0]:-${IMAGE_TAG:-latest}}"
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

sanitize_k8s_name() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9.-]+/-/g; s/^[^a-z0-9]+//; s/[^a-z0-9]+$//; s/-+/-/g' \
    | cut -c 1-45
}

run_kaniko_build() {
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl is required to build and push ${IMAGE} with Kaniko" >&2
    exit 1
  fi

  local namespace="${K8S_NAMESPACE:-t3}"
  local context="${KANIKO_CONTEXT:-/workspace/t3code}"
  local dockerfile="${KANIKO_DOCKERFILE:-${context}/deploy/Dockerfile.kaniko}"
  local workspace_pvc="${KANIKO_WORKSPACE_PVC:-t3code-workspace}"
  local docker_config_secret="${KANIKO_DOCKER_CONFIG_SECRET:-ghcr-pull}"
  local kaniko_image="${KANIKO_IMAGE:-gcr.io/kaniko-project/executor:v1.24.0-debug}"
  local timeout_seconds="${KANIKO_TIMEOUT_SECONDS:-3600}"
  local cache_repo="${KANIKO_CACHE_REPO:-${IMAGE_REPO}/cache}"
  local node_selector="${KANIKO_NODE_SELECTOR:-kubernetes.io/hostname=sietch-tabr}"
  local node_selector_key="${node_selector%%=*}"
  local node_selector_value="${node_selector#*=}"
  local tag_name
  local job_name
  local deadline
  local status
  local failed
  local succeeded

  tag_name="$(sanitize_k8s_name "${IMAGE_TAG}")"
  if [ -z "${tag_name}" ]; then
    tag_name="latest"
  fi
  job_name="t3code-kaniko-${tag_name}-$(date +%s)"
  deadline=$((SECONDS + timeout_seconds))

  echo "Building ${IMAGE} with Kaniko job/${job_name} in namespace ${namespace}"
  echo "Using context dir://${context}"
  echo "Using Dockerfile ${dockerfile}"
  echo "Using registry build cache ${cache_repo}"

  kubectl delete "job/${job_name}" -n "${namespace}" --ignore-not-found=true >/dev/null

  kubectl apply -n "${namespace}" -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app: t3code-kaniko-build
        job-name: ${job_name}
    spec:
      restartPolicy: Never
      enableServiceLinks: false
      nodeSelector:
        ${node_selector_key}: ${node_selector_value}
      containers:
        - name: kaniko
          image: ${kaniko_image}
          args:
            - --context=dir://${context}
            - --dockerfile=${dockerfile}
            - --destination=${IMAGE}
            - --cache=true
            - --cache-repo=${cache_repo}
            - --snapshot-mode=redo
          volumeMounts:
            - name: workspace
              mountPath: /workspace
            - name: docker-config
              mountPath: /kaniko/.docker
              readOnly: true
      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: ${workspace_pvc}
        - name: docker-config
          secret:
            secretName: ${docker_config_secret}
            items:
              - key: .dockerconfigjson
                path: config.json
EOF

  kubectl logs -n "${namespace}" -f "job/${job_name}" &
  local logs_pid=$!

  while true; do
    succeeded="$(kubectl get "job/${job_name}" -n "${namespace}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
    failed="$(kubectl get "job/${job_name}" -n "${namespace}" -o jsonpath='{.status.failed}' 2>/dev/null || true)"

    if [ "${succeeded:-0}" != "0" ] && [ -n "${succeeded}" ]; then
      wait "${logs_pid}" || true
      echo "Built and pushed ${IMAGE}"
      return 0
    fi

    if [ "${failed:-0}" != "0" ] && [ -n "${failed}" ]; then
      wait "${logs_pid}" || true
      echo "Kaniko build job/${job_name} failed" >&2
      kubectl describe "job/${job_name}" -n "${namespace}" >&2 || true
      return 1
    fi

    if [ "${SECONDS}" -ge "${deadline}" ]; then
      kill "${logs_pid}" >/dev/null 2>&1 || true
      status="$(kubectl get "job/${job_name}" -n "${namespace}" -o jsonpath='{.status.conditions[*].type}' 2>/dev/null || true)"
      echo "Timed out waiting for Kaniko job/${job_name}; status: ${status}" >&2
      return 1
    fi

    sleep 5
  done
}

if [ "${USE_KANIKO}" = "1" ]; then
  run_kaniko_build
  exit 0
fi

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
