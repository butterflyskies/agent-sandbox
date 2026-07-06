# Kubernetes SSH Variant

The base `agent-sandbox` image does not include or run an SSH daemon. SSH support is provided by a separate image variant built from `Containerfile.sshd`.

## Build and Push

Build the base image, then the SSH variant:

```bash
just build
just build-sshd
```

By default, `build-sshd` uses `agent-sandbox:latest` as `BASE_IMAGE` and tags `agent-sandbox-sshd:latest`. To layer from a registry image:

```bash
BASE_IMAGE=ghcr.io/butterflyskies/agent-sandbox:latest just build-sshd
```

Push the SSH variant:

```bash
just push-sshd
```

With the default settings this pushes:

```text
ghcr.io/butterflyskies/agent-sandbox-sshd:latest
```

## Entrypoint

The SSH variant runs as root so `sshd` can accept SSH connections and start sessions as `agent`. This root runtime is isolated to the SSH image variant.

Invocation behavior:

```bash
podman run agent-sandbox-sshd:latest
# starts sshd in the foreground on port 2222

podman run agent-sandbox-sshd:latest shell
# delegates to the base agent entrypoint and runs zsh

podman run agent-sandbox-sshd:latest codex
# delegates to the base agent entrypoint and runs codex
```

The SSH daemon listens on container port `2222`. Kubernetes should expose Service port `22` and target the named container port `ssh`.

## SSH Keys

Host keys are generated at runtime under `/etc/ssh/hostkeys` only when missing. Mount a persistent volume at that path so the stable DNS name does not get a new host identity on each restart.

Authorized keys are read from:

```text
/etc/ssh/authorized_keys/agent
```

Mount this from a Kubernetes Secret or ExternalSecret. Do not store authorized keys in mutable `/home/agent/.ssh` state.

Password login and root SSH login are disabled.

## Argo CD Replacement Notes

The Argo CD app should point at the manifests replacing the old `itzpapalotl` workload. The new workload uses `/home/agent`, not `/home/butterfly`, and changes `volumeClaimTemplates`, which are immutable on an existing StatefulSet.

Since the old state can be deleted, replace the old workload before syncing the new one:

```bash
kubectl -n butterfly scale statefulset itzpapalotl --replicas=0
kubectl -n butterfly delete statefulset itzpapalotl
kubectl -n butterfly delete pvc home-butterfly-itzpapalotl-0
```

If you created an experimental host-key PVC during testing, delete that too before the final sync.

After Argo syncs:

```bash
kubectl -n butterfly get pod,pvc,svc
kubectl -n butterfly logs statefulset/itzpapalotl
kubectl -n butterfly exec -it itzpapalotl-0 -- id agent
```

Connect with:

```bash
ssh agent@itzi.svc.echoes
ssh agent@itzpapalotl.svc.echoes
```
