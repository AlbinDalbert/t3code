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
sudo nerdctl --namespace k8s.io build -t ghcr.io/albindalbert/t3code:latest .
```

## Local Deploy Script

This repo now includes a `deploy.sh` patterned after your `hermes` flow:

```bash
./deploy.sh
```

Default behavior:

- builds with `nerdctl` in namespace `k8s.io`
- builds the image for `linux/amd64` by default, matching the pinned `sietch-tabr` node
- tags the image as `ghcr.io/albindalbert/t3code:latest`
- applies `deploy/kubernetes/t3code-server.yaml`
- sets the `deploy/t3code` container image to the exact built tag
- restarts `deploy/t3code`

The script deploys to the `t3` namespace by default and assumes the target Kubernetes namespace
already exists.

Supported environment variables:

```text
IMAGE_REPO=ghcr.io/albindalbert/t3code
IMAGE_TAG=latest
K8S_NAMESPACE=t3
NERDCTL_NAMESPACE=k8s.io
NO_CACHE=1
TARGETARCH=amd64|arm64
TARGETPLATFORM=linux/amd64|linux/arm64
```

Example:

```bash
IMAGE_TAG=dev ./deploy.sh dev
```

If you intentionally want an ARM image for local Pi testing instead of the `sietch-tabr` deployment
target, override the architecture:

```bash
TARGETARCH=arm64 IMAGE_TAG=pi ./deploy.sh pi
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
