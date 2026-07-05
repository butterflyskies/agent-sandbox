# UID Mapping

The default image runs as the non-root user `agent`, UID 1000 and GID 1000. How that maps to your host depends on the runtime.

## Summary

| Runtime | Default UID behavior | File ownership on volumes |
|---------|---------------------|--------------------------|
| Podman (rootless, preferred) | `--userns=keep-id:uid=1000,gid=1000` maps your host user to `agent` inside the container | Files should be owned by your host user |
| Docker | No user namespace remapping by default | Files owned by UID/GID 1000 on host unless you rebuild or override |
| microsandbox | microVM has its own user space | Volumes owned by UID/GID 1000 inside VM |

## Podman

Rootless Podman is the preferred local container path. The `just` recipes pass:

```bash
--userns=keep-id:uid=1000,gid=1000
```

That asks Podman to keep the invoking host user mapped to UID/GID 1000 inside the container. The container process still runs as `agent`/1000, but files written through bind mounts should appear on the host as owned by the invoking user and group.

This is explicit because rootless Podman user namespaces are powerful but not magic. Without a keep-id mapping, bind-mounted ownership can still be confusing, especially when your host UID is not 1000.

The `just` recipes use `-v ... :z` (lowercase z) which applies SELinux relabeling on Fedora/RHEL. This is necessary for the container to read volumes on SELinux-enabled hosts.

If the keep-id mapping causes trouble on a specific machine, disable or replace it with `PODMAN_USERNS`:

```bash
PODMAN_USERNS= just claude
PODMAN_USERNS=auto just claude
```

If you see permission errors on a volume mount:

```bash
# Check your subordinate UID range
cat /etc/subuid | grep $(whoami)

# Verify the container runs as agent/1000 inside
podman run --rm --userns=keep-id:uid=1000,gid=1000 agent-sandbox id
```

## Docker

Docker does not remap UIDs by default. Files created inside the container on a bind-mounted volume may appear as UID/GID 1000 on the host unless the host user is also UID/GID 1000.

The default Docker recipes keep the image behavior the same as Podman: the container runs as `agent`/1000. For a Docker-local compatibility image whose `agent` user matches your host UID/GID, run:

```bash
just docker-build-user
just docker-claude
```

That rebuilds the image with `AGENT_UID="$(id -u)"` and `AGENT_GID="$(id -g)"`, overwriting the local `IMAGE:IMAGE_TAG` tag so the Docker recipes use it automatically. It is a convenience path for Docker users, not the default published-image contract.

For one-off Docker runs without rebuilding, the best-effort option is:

```bash
docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -e HOME=/home/agent \
  agent-sandbox
```

The caveat is that a non-1000 numeric user may not match `/etc/passwd` entries in the image, and it can interact badly with `/home/agent` ownership. Rebuilding with `just docker-build-user` is usually cleaner for Docker if UID/GID 1000 does not match your host account.

## microsandbox

microsandbox runs inside a microVM. The VM has its own kernel, user space, and UID namespace, separate from the host. The `agent` user (UID/GID 1000 by default) inside the VM does not correspond directly to any host UID.

Files on volumes mounted into the VM (`-v host-path:/home/agent`) will be owned by UID/GID 1000 from the VM's perspective. On the host, they appear according to how the msb runtime writes them.

The `--user` flag is available in msb but typically not needed — the default `agent` user is set in the image's entrypoint.

## When UID mapping matters

- **Bind mounts with host files:** If you mount `~/.gitconfig` read-only into the container, it must be readable by the mapped container user. The Podman keep-id mapping is designed to make this natural.
- **Shared volumes between host and container:** Files written by the container should be owned by your user with the default Podman recipes. With default Docker, they may be owned by UID/GID 1000.
- **CI environments:** Many CI runners use UID/GID values other than 1000. Podman can use the keep-id mapping; Docker often needs explicit `chown`, `--user`, or a rebuilt image.
- **`just init-home`:** Runs a throwaway container to copy files. On Docker hosts, the extracted `home/` directory may be owned by UID/GID 1000 unless you use a UID/GID-compatible image.
