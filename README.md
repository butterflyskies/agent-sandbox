# agent-sandbox

OCI container image for running AI coding agents — primarily [Claude Code](https://docs.anthropic.com/en/docs/claude-code), but also ships OpenAI Codex, Google Gemini CLI, OpenCode, and [microsandbox](https://github.com/microsandbox/microsandbox).

Designed for use with microsandbox, Podman, or Docker, with volume mounts for source repos and credentials injected at runtime.

## Quick start

```bash
# Build the image
./build.sh

# Initialize a persistent home directory
./skeleton/init.sh

# Populate your identity (edit these before first run)
vi home/.gitconfig
cp ~/.config/gh/hosts.yml home/.config/gh/

# Run Claude Code
./run/claude.sh
```

## Building

```bash
# Local build (uses Podman layer cache automatically)
./build.sh

# With Docker instead
docker build -t agent-sandbox -f Containerfile .

# With registry cache for CI
REGISTRY=ghcr.io/yourorg/yourrepo ./build.sh
```

## Running

### With the run scripts (recommended)

The `run/` scripts mount `./home/` as a persistent volume and apply hardening flags by default (`--cap-drop=ALL`, `--read-only`, `--security-opt=no-new-privileges`). They auto-detect and forward any set API keys.

```bash
./run/claude.sh              # Claude Code (default)
./run/claude.sh --help       # Pass args to claude
./run/codex.sh               # OpenAI Codex
./run/shell.sh               # Interactive zsh shell
./run/msb-claude.sh          # Claude Code inside microsandbox microVM
```

Override the container runtime, home volume, or image:

```bash
CONTAINER_RUNTIME=docker ./run/claude.sh            # Use Docker instead of Podman
HOME_VOL=/path/to/my/home ./run/claude.sh           # Custom home volume
IMAGE=ghcr.io/org/agent-sandbox:latest ./run/claude.sh  # Custom image
```

### With Podman

```bash
podman run -it --rm \
  -v ~/dev:/home/agent/dev:Z \
  -v ~/.claude:/home/agent/.claude:Z \
  -v ~/.gitconfig:/home/agent/.gitconfig:ro,Z \
  -v ~/.config/gh:/home/agent/.config/gh:ro,Z \
  -e ANTHROPIC_API_KEY \
  agent-sandbox
```

Shell instead of Claude:

```bash
podman run -it --rm --entrypoint zsh agent-sandbox
```

Different agent:

```bash
podman run -it --rm --entrypoint codex -e OPENAI_API_KEY agent-sandbox
podman run -it --rm --entrypoint gemini -e GEMINI_API_KEY agent-sandbox
podman run -it --rm --entrypoint opencode agent-sandbox
```

### With Docker

```bash
docker run -it --rm \
  -v ~/dev:/home/agent/dev \
  -v ~/.claude:/home/agent/.claude \
  -v ~/.gitconfig:/home/agent/.gitconfig:ro \
  -v ~/.config/gh:/home/agent/.config/gh:ro \
  -e ANTHROPIC_API_KEY \
  agent-sandbox
```

Note: Docker doesn't need the `:Z` SELinux relabel suffix that Podman requires on Fedora/RHEL. If you're on macOS with OrbStack or Docker Desktop, volume mounts work as-is.

Shell:

```bash
docker run -it --rm --entrypoint zsh agent-sandbox
```

### With Docker Compose

```yaml
# compose.yml
services:
  claude:
    image: agent-sandbox
    stdin_open: true
    tty: true
    environment:
      - ANTHROPIC_API_KEY
    volumes:
      - ./home:/home/agent
```

```bash
docker compose run --rm claude
```

### With microsandbox

[Microsandbox](https://github.com/microsandbox/microsandbox) provides hardware-level VM isolation with millisecond boot times. The `msb` CLI is included in the image, and it can also be used from the host to run the image itself.

From the host (requires msb installed and KVM enabled):

```bash
# One-off run
msb run agent-sandbox -- claude

# Named persistent sandbox
msb create --name my-agent agent-sandbox
msb exec my-agent -- claude
msb exec my-agent -- zsh
msb stop my-agent

# Install as a system command
msb install --name claude agent-sandbox
claude  # launches a microVM every time
```

From inside the container, agents can create their own nested sandboxes using the msb CLI or the [microsandbox MCP server](https://github.com/superradcompany/microsandbox-mcp):

```bash
# Add the MCP server to Claude Code
claude mcp add --transport stdio microsandbox -- npx -y microsandbox-mcp
```

## What's in the box

| Category | Contents |
|----------|----------|
| **AI agents** | Claude Code (native), Codex, Gemini CLI, OpenCode |
| **Sandbox** | microsandbox (`msb`) CLI + runtime |
| **Runtimes** | Node.js 24 LTS, Python 3.12, Go, Java (GraalVM 21), Ruby, Zig, Bun (via asdf) |
| **Build tools** | Rust (stable) + cargo tools, Gradle, Maven, pnpm, uv, cmake, ninja, meson |
| **VCS** | git, git-lfs, git-crypt, jj (Jujutsu), gh CLI |
| **Cloud** | Google Cloud CLI (`gcloud`), AWS CLI v2 (`aws`), Azure CLI (`az`) |
| **Shell** | zsh + zinit + starship + fzf-tab + atuin + zoxide + direnv |
| **Editors** | neovim (default), nano |
| **CLI** | ripgrep, fd, bat, eza, fzf, jq, just, hyperfine, tokei, bottom, dust, chezmoi, step-cli |

## Persistent home directory

The `skeleton/init.sh` script creates a directory structure for mounting as `/home/agent`:

```
home/
├── .gitconfig          # Git identity (edit before first run)
├── .config/gh/         # GitHub CLI auth (copy hosts.yml here)
├── .claude/            # Claude Code config, memory, sessions
├── .ssh/               # SSH keys (optional, for git+ssh)
├── .local/bin/         # User-installed binaries
├── .cargo/bin/         # User-installed cargo binaries
├── .asdf/              # Language runtime versions
├── .npm-global/        # npm global packages
├── .cache/             # Build/tool caches
├── dev/                # Source repositories
└── projects/           # Additional project directories
```

The container works fine without a persistent home — everything is self-contained in the image. A persistent volume just means your shell history, tool configs, cloned repos, and installed runtimes survive across runs.

## Build caching

Local rebuilds benefit from cargo cache mounts automatically (`--mount=type=cache` in the Containerfile) and Podman's layer cache (`--layers`).

For CI or cross-machine cache sharing, use registry-backed caching:

```bash
REGISTRY=ghcr.io/yourorg/yourrepo ./build.sh
```

Set `REGISTRY` to your own OCI registry. Requires `write:packages` scope (or equivalent) for push. The build script falls back to local-only caching if the registry push fails.

## Supply chain security

All tool installations use **pinned versions with SHA256 checksum verification** where possible. Version pins and checksums are declared as `ARG` values at the top of the Containerfile for easy auditing and updates.

| Tool | Install method | Pinned | Integrity check |
|------|---------------|--------|-----------------|
| Rust toolchain | Direct binary download | rustup-init SHA256 | sha256sum verify |
| Cargo crates (15) | `cargo install --locked @version` | Exact versions | cargo lockfile |
| uv | GitHub release tarball | Version + SHA256 | sha256sum verify |
| chezmoi | GitHub release binary | Version + SHA256 | sha256sum verify |
| zoxide | GitHub release tarball | Version + SHA256 | sha256sum verify |
| opencode | GitHub release tarball | Version + SHA256 | sha256sum verify |
| microsandbox | GitHub release tarball | Version + SHA256 | sha256sum verify |
| Claude Code | Vendored installer script | Script snapshotted at build | Installer verifies binary SHA256 from manifest |
| Codex, Gemini | npm install -g | Floating (latest) | npm registry signatures |
| gh, eza, step-cli | apt with signed repos | Distro package version | GPG-signed apt repos |
| gcloud, az | apt with signed repos | Distro package version | GPG-signed apt repos |
| AWS CLI v2 | Direct zip download | Floating (latest) | Amazon TLS |
| asdf plugins | asdf-plugin-manager | Git SHA pinned | Exact commit checkout |
| asdf runtimes | asdf install | Exact versions | Plugin-specific verification |

### Remaining risks

- **npm packages (Codex, Gemini) float to latest.** npm registry signatures provide some protection, but versions are not locked.

- **AWS CLI v2 is not checksum-verified.** Amazon distributes it as a zip with no published checksums. TLS is the only protection.

- **Third-party apt repo signing keys are fetched at build time.** The gh, eza, step-cli, gcloud, and Azure CLI apt repos are GPG-signed, but the signing keys themselves are downloaded over TLS without pinning.

- **`apt-get upgrade` introduces drift.** The final security-patch layer means image content depends on build date.

- **The image is large.** Multi-stage build keeps Rust compilation artifacts out, but expect 3-5 GB with the full build toolchain, cloud CLIs, and multiple runtimes.

- **No seccomp/AppArmor profiles are provided.** The image runs as a non-root user (`agent`, uid 1000) with passwordless sudo. Restrict capabilities at the container runtime level.

## Runtime hardening

The image ships with `sudo` available — useful for ad-hoc package installs during development. In rootless Podman, `root` inside the container maps to your unprivileged UID on the host, so it's not real root. Microsandbox provides similar isolation via hardware-level VM boundaries.

For tighter lockdown, apply these at runtime:

```bash
podman run -it --rm \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --read-only --tmpfs /tmp \
  -v ./home:/home/agent:Z \
  -e ANTHROPIC_API_KEY \
  agent-sandbox
```

```bash
docker run -it --rm \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --read-only --tmpfs /tmp \
  -v ./home:/home/agent \
  -e ANTHROPIC_API_KEY \
  agent-sandbox
```

| Flag | Effect |
|------|--------|
| `--cap-drop=ALL` | Drop all Linux capabilities (coding agents don't need any) |
| `--security-opt=no-new-privileges` | Prevent setuid/setgid escalation |
| `--read-only --tmpfs /tmp` | Immutable root filesystem, writable /tmp only |
| `-v ... :ro` | Mount config volumes read-only where possible |

With `--read-only`, the agent can only write to explicitly mounted volumes and `/tmp`. This limits blast radius if the agent or any tool is compromised — it can't modify its own toolchain, install backdoors, or tamper with binaries.

## Updating versions

All pinned versions are at the top of the Containerfile as `ARG` declarations, and runtime versions are at the top of `scripts/install-tools.sh`. See [VERSIONS.md](VERSIONS.md) for the full validation methodology and update procedure.

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
