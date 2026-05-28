# Kubernetes Deployment

This repo now has a Codex-first container path for the headless server mode exposed by `t3 serve`.

The image:

- builds the web client and server from this monorepo
- installs the `codex` CLI into the runtime image
- starts `t3 serve`
- binds to `0.0.0.0:3773`
- stores server state under `/var/lib/t3code`
- stores Codex auth/home state under `/var/lib/codex`
- uses `/workspace` as the default provider working directory

## Build The Image

```bash
./deploy/build-and-push.sh
```

This builds on your laptop with Docker Buildx and pushes to GHCR. The default target is
`linux/amd64`, matching the pinned `sietch-tabr` deployment node.

Supported environment variables:

```text
IMAGE_REPO=ghcr.io/albindalbert/t3code
IMAGE_TAG=latest
TARGETARCH=arm64|amd64
TARGETPLATFORM=linux/arm64|linux/amd64
NO_CACHE=1
PUSH=0
CACHE_REF=ghcr.io/albindalbert/t3code:buildcache-amd64
BUILDER_NAME=t3code-builder
```

Examples:

```bash
./deploy/build-and-push.sh
IMAGE_TAG=dev ./deploy/build-and-push.sh dev
TARGETARCH=amd64 IMAGE_TAG=amd64 ./deploy/build-and-push.sh amd64
```

The script uses a registry-backed BuildKit cache so dependency installs and build layers can survive
between machines and between Docker builder resets:

```text
ghcr.io/albindalbert/t3code:buildcache-amd64
```

Make sure you are logged into GHCR before pushing:

```bash
echo "$GITHUB_TOKEN" | docker login ghcr.io -u AlbinDalbert --password-stdin
```

Use a GitHub personal access token, not your GitHub account password. The token needs package write
access for `ghcr.io/albindalbert/t3code`.

The build script requires the Docker Buildx plugin. On Arch-based systems:

```bash
sudo pacman -S docker-buildx
```

On Debian/Ubuntu Docker CE installs:

```bash
sudo apt install docker-buildx-plugin
```

## Roll Out On Kubernetes

Run this on the control plane, or anywhere with a working `kubectl` context:

```bash
./deploy/rollout.sh
```

Before the first rollout, create the GHCR pull secret used by the deployment:

```bash
export GITHUB_TOKEN=your_github_pat
./deploy/create-ghcr-pull-secret.sh
```

That script creates or updates the `ghcr-pull` secret in namespace `t3`. The deployment manifest
references that secret through `imagePullSecrets`, so the node can pull a private image from GHCR.

Default behavior:

- applies `deploy/kubernetes/t3code-server.yaml`
- sets `deploy/t3code` container `t3code` to `ghcr.io/albindalbert/t3code:latest`
- waits for the rollout to finish
- relies on `imagePullPolicy: Always` so a refreshed `latest` tag is pulled

Supported environment variables:

```text
IMAGE_REPO=ghcr.io/albindalbert/t3code
IMAGE_TAG=latest
K8S_NAMESPACE=t3
MANIFEST=deploy/kubernetes/t3code-server.yaml
DEPLOYMENT=t3code
CONTAINER=t3code
```

Example:

```bash
IMAGE_TAG=dev ./deploy/rollout.sh dev
```

If the deployment gets into a bad rollout state and you want to kill the app pods and recreate the
deployment cleanly while keeping the PVCs, use:

```bash
RESET=1 ./deploy/rollout.sh
```

## One Command From A Laptop

The root script keeps the fast local path as the default:

```bash
./deploy.sh
```

That builds and pushes, then prints the exact control-plane rollout command. If your laptop already
has `kubectl` pointed at the cluster, you can make it do both:

```bash
ROLLOUT=1 ./deploy.sh
```

## Run It Locally

```bash
docker run --rm -p 3773:3773 \
  -v t3code-state:/var/lib/t3code \
  -v t3code-codex-home:/var/lib/codex \
  -v /path/to/projects:/workspace \
  ghcr.io/albindalbert/t3code:latest
```

On startup the container runs the equivalent of:

```bash
CODEX_HOME=/var/lib/codex t3 serve --host 0.0.0.0 --port 3773 --base-dir /var/lib/t3code /workspace
```

The server prints the pairing URL and token to stdout. Treat those like credentials.

## Kubernetes

Apply the bundled manifest:

```bash
kubectl apply -n t3 -f deploy/kubernetes/t3code-server.yaml
```

The manifest creates:

- one `Deployment`
- one `ClusterIP` `Service`
- one Traefik `Ingress` for `t3.lan`
- one PVC for T3 state
- one PVC for the working directory / projects
- one PVC for the Codex home/auth state

The deployment uses `strategy: Recreate` instead of a rolling update. That matches this workload:
single replica, one pinned node, and `ReadWriteOnce` PVCs. It avoids overlapping ReplicaSets during
updates and makes failures easier to interpret.

The PVCs request the `local-path` storage class, and the pod is pinned to the Kubernetes node whose
hostname label is `sietch-tabr`. The deploy script builds `linux/amd64` by default for that node. If
the node is offline or `NotReady`, the deployment is expected to remain pending until it comes back.

### Access Pattern

This is shaped for a home cluster with internal DNS and Traefik:

- Traefik exposes `http://t3.lan`
- there is no extra ingress auth layer
- T3 Code still uses its own pairing/session model
- WebSocket traffic flows through the same ingress path

## Workspace And Persistence

`/var/lib/t3code` stores:

- the SQLite state database
- auth/session material
- attachments
- logs

`/workspace` is the default server cwd used for provider sessions. Mount the repos you want T3 Code
to operate on there, or override `T3_WORKSPACE`.

`/var/lib/codex` stores the Codex CLI home and login state because the image sets:

```text
CODEX_HOME=/var/lib/codex
```

That PVC is what makes a one-time `codex login` persist across pod restarts.

## Codex Bootstrap

This image is deliberately Codex-first. It installs the `codex` CLI during the image build and
mounts a persistent Codex home into the pod.

After the pod is up, log into Codex once:

```bash
kubectl exec -n t3 -it deploy/t3code -- codex login
```

That writes auth state into the `t3code-codex-home` PVC.

If you later add Claude or OpenCode, you will need to extend the image and decide how you want
their home/auth state persisted. This setup does not try to solve multi-provider persistence.

## Image Distribution

The manifest assumes you publish from your fork to:

```text
ghcr.io/albindalbert/t3code:latest
```

That matches your usual pattern of building locally with the final GHCR image name and letting the
cluster use the local image when present.

## Health Checks

The Kubernetes manifest probes:

```text
/.well-known/t3/environment
```

That route is unauthenticated and returns a server descriptor, which makes it suitable for both
readiness and liveness checks.
