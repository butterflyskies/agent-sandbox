# Persistence

agent-sandbox supports three persistence modes. Choose based on how much state you need to survive between runs and how portable it needs to be.

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

## Mode 2: External volume — full image home (`just init-home`)

Extracts the complete `/home/agent` directory from the image into a local path. Every tool, shell config, and PATH setup from the image lands in the volume.

```bash
just init-home               # Extracts to ./home
just init-home /data/myagent  # Custom path
```

The extraction uses a throwaway container:
```bash
# What init-home does under the hood:
podman run --rm -v ./home:/mnt --entrypoint sh agent-sandbox -c 'cp -a /home/agent/. /mnt/'
```

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

### PATH wiring

Tools installed via asdf (Node, Python, Go, etc.) are wired via `/etc/profile.d/agent-sandbox-paths.sh` in the image. This file adds asdf shims and tool paths to `PATH` for every shell session, regardless of whether you're using a volume or the built-in home. You don't need to replicate PATH setup in the volume.

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
| Full volume | `HOME_VOL=./home just claude` | Yes (`--rm` added) | `./home` directory | Delete files |
| Skeleton volume | `HOME_VOL=./home just claude` | Yes (`--rm` added) | `./home` directory | Delete files |

## Bringing your own home directory

Any existing directory works as `HOME_VOL`. If it was created outside `just init` / `just init-home`, the only requirement is that it's writable and mountable at `/home/agent`:

```bash
HOME_VOL=/mnt/nas/agent-home just claude
```

Files in the volume overlay the image's `/home/agent`. If a path exists in both, the volume wins.
