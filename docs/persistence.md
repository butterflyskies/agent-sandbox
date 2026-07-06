# Persistence

agent-sandbox supports three persistence modes. Choose based on how much state you need to survive between runs and how portable it needs to be.

The image carries a staged home template at `/opt/agent-home-template`. That template includes the default dotfiles, asdf runtimes under `.asdf`, npm globals under `.npm-global`, and other writable home state. Cargo-installed tools live under `/opt/cargo`.

## Mode 1: Built-in (no setup)

No volume flag, no `init`. State lives inside the sandbox or container.

### microsandbox

The default sandbox name is `agent-sandbox` (`--name agent-sandbox`). microsandbox keeps `/home/agent` alive inside the microVM across invocations as long as you don't reset it.

```
just msb-claude          # Run, do work, exit
just msb-claude          # Resume — /home/agent still has your work
just msb-reset           # Wipe state (irreversible)
```

To run multiple isolated projects simultaneously, use different sandbox names:

```bash
MSB_NAME=project-a just msb-claude
MSB_NAME=project-b just msb-claude
```

Each sandbox has its own independent `/home/agent`.

### Podman / Docker

Without `HOME_VOL`, the container is started without `--rm`. It persists after exit. You can re-attach or just run `just claude` again — a new container starts from the same image, so in-container state from the previous run is gone.

For session-to-session persistence without a volume, use a named container:
```bash
podman start -ai <container-id>
```

The justfile doesn't manage named containers — that's a manual workflow.

## Mode 2: External volume — image home template (`just init-home`)

Extracts `/opt/agent-home-template` from the image into a local path. This includes the image's default shell config, `.tool-versions`, asdf runtimes, npm globals, Claude launcher files, and other home-level setup. Replacing `/home/agent` with a volume no longer hides those staged tools because the entrypoint can seed them from the template.

```bash
just init-home               # Extracts to ./home
just init-home /data/myagent  # Custom path
```

The extraction uses a throwaway container:

```bash
# What init-home does under the hood:
podman run --rm -v ./home:/mnt agent-sandbox sh -lc 'cp -a /opt/agent-home-template/. /mnt/'
```

The image defaults to `agent` UID/GID 1000. The Podman recipes use `--userns=keep-id:uid=1000,gid=1000 --user agent`, so files copied into a bind mount should appear on the host as your invoking user while the container still runs as `agent`. Set `PODMAN_USERNS=` to disable that mapping if a specific host requires it.

Docker does not remap UIDs by default. If your host user is not UID/GID 1000, files extracted by Docker may appear on the host as UID/GID 1000. For Docker-local compatibility, run `just docker-build-user` before `just docker-claude` to rebuild the `agent` user with your host UID/GID.

After extraction, customize identity:
```bash
vi home/.gitconfig           # Set name/email
cp ~/.config/gh/hosts.yml home/.config/gh/   # gh auth
cp ~/.ssh/id_ed25519 home/.ssh/              # SSH keys (optional)
```

Then run with the volume:
```bash
HOME_VOL=./home just claude
HOME_VOL=./home just msb-claude
```

When `HOME_VOL` points to an existing directory, the justfile mounts it at `/home/agent`. The container is run with `--rm` so the container itself is ephemeral — all state lives in the volume.

### Automatic first-start seeding

The entrypoint seeds `$HOME` from `/opt/agent-home-template` on startup. It uses `rsync --ignore-existing`, so missing default files and missing tool-version directories are copied into an empty or partial mounted home, while files you already created in the volume win. If the home directory is not writable, the bootstrap is skipped.

The home-level `$HOME/.tool-versions` file is image-owned and is refreshed from the template on startup. That keeps asdf pinned to versions actually installed by the current image after upgrades. Put project-specific `.tool-versions` files in project directories when you need per-repo overrides, or disable the bootstrap if you fully manage the home yourself.

Disable this behavior with:

```bash
AGENT_HOME_BOOTSTRAP=0 just claude
```

### PATH wiring

Tools installed via asdf (Node, Python, Go, etc.) are wired through `$HOME/.asdf`; npm globals are under `$HOME/.npm-global`; cargo tools are under `/opt/cargo`. `/etc/profile.d/agent-sandbox-paths.sh` adds these paths for login shells, and the image `PATH` includes them for direct entrypoint commands. With a writable mounted home, agents can still run `asdf install ...` or `npm install -g ...` and have those additions persist in the volume.

## Mode 3: Skeleton volume (`just init`)

Creates only the directory structure — no files copied from the image. Lighter weight; bring your own dotfiles.

```bash
just init
```

Creates:
```
home/
├── .gitconfig
├── .config/gh/
├── .claude/
├── .ssh/
├── .local/bin/
├── .cargo/bin/
├── .asdf/
├── .npm-global/
├── .cache/
├── dev/
└── projects/
```

Use this when you want to manage your dotfiles with chezmoi, symlinks, or your own setup script rather than carrying the image's defaults.

## Summary

| Mode | Command | Container ephemeral? | State location | Reset how |
|------|---------|---------------------|---------------|-----------|
| Built-in (msb) | `just msb-claude` | No (microVM persists) | Inside microVM | `just msb-reset` |
| Built-in (container) | `just claude` | No (unless `--rm` added) | Inside container | Remove container |
| Template volume | `HOME_VOL=./home just claude` | Yes (`--rm` added) | `./home` directory | Delete files |
| Skeleton volume | `HOME_VOL=./home just claude` | Yes (`--rm` added) | `./home` directory | Delete files |

## Bringing your own home directory

Any existing directory works as `HOME_VOL`. If it was created outside `just init` / `just init-home`, the only requirement is that it's writable and mountable at `/home/agent`:

```bash
HOME_VOL=/mnt/nas/agent-home just claude
```

Files in the volume overlay the image's `/home/agent`. If a path exists in both, the volume wins. Missing files are seeded from `/opt/agent-home-template` unless `AGENT_HOME_BOOTSTRAP=0` is set.
