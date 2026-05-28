#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-${IMAGE_TAG:-latest}}"
ROLLOUT="${ROLLOUT:-0}"

"$(dirname "$0")/deploy/build-and-push.sh" "${TAG}"

if [ "${ROLLOUT}" = "1" ]; then
  "$(dirname "$0")/deploy/rollout.sh" "${TAG}"
else
  IMAGE_REPO="${IMAGE_REPO:-ghcr.io/albindalbert/t3code}"
  echo
  echo "Image is pushed. To deploy it from the control plane, run:"
  echo "  IMAGE_REPO=${IMAGE_REPO} ./deploy/rollout.sh ${TAG}"
  echo
  echo "If your laptop kubectl context points at the cluster, run this instead:"
  echo "  ROLLOUT=1 ./deploy.sh ${TAG}"
fi
