# UID mapping

The image runs as `agent`, uid 1000, gid 1000. How that maps to your host depends on the runtime.

## Summary

| Runtime | Default UID behavior | File ownership on volumes |
|---------|---------------------|--------------------------|
| Podman (rootless) | Host UID mapped to uid 1000 inside container | Files owned by your host user |
| Docker | No user namespace remapping | Files owned by uid 1000 on host |
| microsandbox | microVM has its own user space | Volumes owned by uid 1000 inside VM |

## Podman

Rootless Podman uses user namespaces. When your host UID is 1000, it maps directly to `agent` inside the container — no mismatch, no permission issues.

If your host UID is not 1000 (e.g., uid 1001), Podman maps it to uid 1000 inside the container via the subordinate UID range in `/etc/subuid`. Files written to a volume from inside the container will appear on the host as owned by your actual UID, not uid 1000.

The `just` recipes use `-v ... :z` (lowercase z) which applies SELinux relabeling on Fedora/RHEL. This is necessary for the container to read volumes on SELinux-enabled hosts.

If you see permission errors on a volume mount:
```bash
# Check your subordinate UID range
cat /etc/subuid | grep $(whoami)

# Verify the container sees the right UID
podman run --rm agent-sandbox id
```

## Docker

Docker does not remap UIDs by default. Files created inside the container on a bind-mounted volume will be owned by uid 1000 on the host, regardless of who is running the `docker` command.

If you're running Docker as a non-root user (via the `docker` group), uid 1000 on the container maps to uid 1000 on the host — which may or may not be your user.

To run as a specific UID:
```bash
docker run -it --rm --user $(id -u):$(id -g) agent-sandbox
```

Note: running as a non-1000 UID will break paths that are hardcoded to `/home/agent` inside the image. Only use this if you understand the implications.

## microsandbox

microsandbox runs inside a microVM. The VM has its own kernel, user space, and uid namespace — separate from the host entirely. The `agent` user (uid 1000) inside the VM does not correspond to any host UID.

Files on volumes mounted into the VM (`-v host-path:/home/agent`) will be owned by uid 1000 from the VM's perspective. On the host, they'll appear owned by whatever UID the msb daemon uses when writing files.

The `--user` flag is available in msb but typically not needed — the default `agent` user is set in the image's entrypoint.

## When UID mapping matters

- **Bind mounts with host files:** If you mount `~/.gitconfig` read-only into the container, the file must be readable by uid 1000. With rootless Podman this is automatic; with Docker you may need to `chmod o+r` the file.
- **Shared volumes between host and container:** Files written by the container will be owned by uid 1000 on Docker hosts. Run `chown -R $(id -u):$(id -g) ./home` after init if needed.
- **CI environments:** Many CI runners use uid != 1000. With Podman this usually works via user namespace mapping. With Docker, the files in volumes may end up owned by uid 1000 which the CI runner cannot write to without explicit `chown` steps.
- **`just init-home`:** Runs a throwaway container to copy files. On Docker hosts, the extracted `home/` directory will be owned by uid 1000. On rootless Podman hosts, files will be owned by your UID.
