# agent-sandbox

OCI image for running AI coding agents — Claude Code, Codex, Gemini CLI, OpenCode, and [pi-agent-rust](https://github.com/Dicklesworthstone/pi_agent_rust) — inside a hardened, reproducible environment with three runtime options: rootless Podman, [microsandbox](https://github.com/microsandbox/microsandbox) microVMs, or Docker.

## Quick start

No `init` needed. Persistence is automatic out of the box.

**Podman (preferred default — rootless, hardened):**
```bash
just build && just claude
```

**microsandbox (microVM isolation, secret scoping, network policy):**
```bash
just build && just msb-claude
```

**Docker:**
```bash
just build && just docker-claude
```

## Running

### microsandbox

microsandbox provides hardware-level VM isolation with millisecond boot times. API keys are scoped to their provider endpoints. Network is `public-only` by default (blocks private/loopback ranges).

| Target | Network | Use case |
|--------|---------|----------|
| `just msb-claude` | public-only | Default — safe for most work |
| `just msb-claude-open` | allow-all | Agents that need local services |
| `just msb-claude-offline` | none | Air-gapped code review |
| `just msb-codex` | public-only | OpenAI Codex |
| `just msb-pi` | public-only | pi-agent-rust |
| `just msb-pi-open` | allow-all | pi-agent-rust with local services |
| `just msb-pi-offline` | none | pi-agent-rust air-gapped |
| `just msb-shell` | public-only | Interactive shell |
| `just msb-shell-open` | allow-all | Shell with local network access |

Lifecycle:
```bash
just msb-status          # List running sandboxes
just msb-stop            # Stop the named sandbox
just msb-reset           # Destroy it (irreversible)
just msb-exec -- <cmd>   # Run a command in the running sandbox
```

See [docs/network-policy.md](docs/network-policy.md) for details on network policies.

### Podman

```bash
just claude              # Claude Code
just codex               # OpenAI Codex
just pi                  # pi-agent-rust
just shell               # Interactive zsh
```

Runs with `--cap-drop=ALL --read-only --security-opt=no-new-privileges` automatically.

The image runs as `agent` UID/GID 1000 by default. The Podman recipes also use `--userns=keep-id:uid=1000,gid=1000 --user agent`, which maps your invoking host user to `agent` inside the container while preserving the image's `USER agent` behavior. Bind-mounted files should be owned by you on the host. Disable or replace the user namespace mapping with `PODMAN_USERNS=...`; for example, `PODMAN_USERNS= just claude`.

### Docker

```bash
just docker-claude       # Claude Code
just docker-codex        # OpenAI Codex
just docker-pi           # pi-agent-rust
just docker-shell        # Interactive zsh
```

Same hardening as Podman, minus SELinux labels and Podman user namespace mapping. Docker does not remap UIDs by default, so files created through bind mounts may appear as UID/GID 1000 on the host unless your host account also uses 1000.

For a Docker-local image whose `agent` UID/GID matches the invoking user:

```bash
just docker-build-user
just docker-claude
```

`just docker-build-user` overwrites the local `IMAGE:IMAGE_TAG` tag, defaulting to `agent-sandbox:latest`, so the Docker recipes use the rebuilt image automatically.

### Env var overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `CONTAINER_RUNTIME` | `podman` | Runtime: `podman`, `docker`, or `msb` |
| `IMAGE` | `agent-sandbox` | Image name |
| `IMAGE_TAG` | `latest` | Image tag |
| `REGISTRY` | `ghcr.io/butterflyskies` | Registry for push/pull |
| `HOME_VOL` | `./home` | External home directory (optional) |
| `PODMAN_USERNS` | `keep-id:uid=1000,gid=1000` | Podman `--userns` value; empty disables |
| `MSB_CPUS` | host/2 | CPU count for msb |
| `MSB_MEMORY` | host/2 | Memory for msb |
| `MSB_NAME` | `agent-sandbox` | Named sandbox for msb |
| `MSB_NETWORK_POLICY` | `public-only` | msb network: `public-only`, `allow-all`, `none` |

Example:

```bash
MSB_NAME=my-project just msb-claude
HOME_VOL=/data/agent-home just claude
PODMAN_USERNS= just claude
IMAGE_TAG=20250418 just docker-claude
```

## Entrypoint

The image uses `/usr/local/bin/agent-entrypoint`, a small zsh dispatcher:

| Invocation | Behavior |
|------------|----------|
| `podman run agent-sandbox` | Runs `claude` |
| `podman run agent-sandbox --version` | Runs `claude --version` |
| `podman run agent-sandbox shell` | Runs `zsh` |
| `podman run agent-sandbox shell -lc 'echo ok'` | Runs `zsh -lc 'echo ok'` |
| `podman run agent-sandbox codex` | Runs `codex` |
| `podman run agent-sandbox zsh` | Runs `zsh` |

## Persistence

Three modes — choose based on your workflow. See [docs/persistence.md](docs/persistence.md) for details.

### 1. Built-in (default — no setup required)

**microsandbox:** The named sandbox (`--name agent-sandbox`) keeps `/home/agent` alive across `msb exec` calls. No volume needed. Files persist until `just msb-reset`.

**Podman/Docker without `HOME_VOL`:** Container is not run with `--rm`, so it persists after exit. Re-attach with `podman start -ai <id>` or just run again.

### 2. External volume — full image home (`just init-home`)

Extracts the complete `/home/agent` from the image into a local directory. All tools, configs, and shell setup included.

```bash
just init-home           # Extracts to ./home (errors if non-empty)
just init-home /data/my-home   # Custom path
```

Then edit identity files:
```bash
vi home/.gitconfig
cp ~/.config/gh/hosts.yml home/.config/gh/
```

Run with the volume:
```bash
HOME_VOL=./home just claude
```

### 3. Skeleton volume (`just init`)

Creates a minimal directory structure — no tool copies from the image, just the folders. Lighter weight; bring your own dotfiles.

```bash
just init                # Creates ./home with the skeleton layout
```

When to use each:

| Mode | Persistence | Setup | Best for |
|------|-------------|-------|---------|
| Built-in (msb) | Until `msb-reset` | None | Daily use with microsandbox |
| Built-in (container) | Until container removed | None | Quick one-off sessions |
| `init-home` | Volume-backed | One `init-home` | Portable home, custom dotfiles layer |
| `init` (skeleton) | Volume-backed | Manual setup | Minimal, BYO everything |

## Security

### microsandbox

**Secret scoping** — API keys are bound to their provider's domain. A key leaking from one agent cannot be used against another provider:

| Key | Allowed host |
|-----|-------------|
| `ANTHROPIC_API_KEY` | `api.anthropic.com` |
| `OPENAI_API_KEY` | `api.openai.com` |
| `GEMINI_API_KEY` | `generativelanguage.googleapis.com` |
| `GOOGLE_API_KEY` | `*.googleapis.com` |

Violations are blocked and logged (`--on-secret-violation block-and-log`).

**Network policies** — default `public-only` blocks private ranges (RFC 1918), loopback, and link-local. Use `msb-claude-open` for local service access or `msb-claude-offline` for no network. See [docs/network-policy.md](docs/network-policy.md).

**Resource auto-scaling** — msb allocates host/2 CPUs and host/2 memory automatically. Override with `MSB_CPUS` / `MSB_MEMORY`.

### Podman / Docker hardening

All `just` recipes apply these flags automatically:

| Flag | Effect |
|------|--------|
| `--cap-drop=ALL` | Drop all Linux capabilities |
| `--security-opt=no-new-privileges` | Prevent setuid/setgid escalation |
| `--read-only` | Immutable root filesystem |
| `--tmpfs /tmp,/var/tmp,/run` | Writable scratch space only |

The container process runs as the non-root `agent` user. In the default image, `agent` is UID/GID 1000. Rootless Podman recipes additionally pass `--userns=keep-id:uid=1000,gid=1000 --user agent` so that bind-mounted files are written as your host user while the process remains `agent`/1000 inside the container.

See [docs/uid-mapping.md](docs/uid-mapping.md) for notes on UID mapping with bind mounts.

## What's in the box

| Category | Contents |
|----------|----------|
| **AI agents** | Claude Code (native), Codex, Gemini CLI, OpenCode, pi-agent-rust |
| **Sandbox** | microsandbox (`msb`) CLI + runtime |
| **Runtimes** | Node.js 24 LTS, Python 3.12, Go, Java (GraalVM 21), Ruby, Zig, Bun (via asdf) |
| **Build tools** | Rust (stable) + cargo tools, Gradle, Maven, pnpm, uv, cmake, ninja, meson |
| **VCS** | git, git-lfs, git-crypt, jj (Jujutsu), gh CLI |
| **Cloud** | Google Cloud CLI (`gcloud`), AWS CLI v2 (`aws`), Azure CLI (`az`) |
| **Shell** | zsh + zinit + starship + fzf-tab + atuin + zoxide + direnv |
| **Editors** | neovim (default), nano |
| **CLI** | ripgrep, fd, bat, eza, fzf, jq, just, hyperfine, tokei, bottom, dust, chezmoi, step-cli |

## Building & versioning

```bash
just build                          # Local build, tags :latest (or $IMAGE_TAG)
just docker-build-user              # Docker-local rebuild with agent UID/GID matching you
just release                        # CalVer build: tags :latest + :YYYYMMDD, pushes both
just push                           # Push current tag to $REGISTRY
REGISTRY=ghcr.io/myorg just release # Push to a custom registry
```

OCI labels stamped at build: `org.opencontainers.image.version`, `org.opencontainers.image.revision`, `org.opencontainers.image.created`.

Local rebuilds benefit from cargo cache mounts (`--mount=type=cache`) and Podman layer cache (`--layers`) automatically.

## Supply chain security

All tool installations use **pinned versions with SHA256 checksum verification** where possible.

| Tool | Install method | Pinned | Integrity check |
|------|---------------|--------|-----------------|
| Rust toolchain | Direct binary download | rustup-init SHA256 | sha256sum verify |
| Cargo crates (15) | `cargo install --locked @version` | Exact versions | cargo lockfile |
| uv | GitHub release tarball | Version + SHA256 | sha256sum verify |
| chezmoi | GitHub release binary | Version + SHA256 | sha256sum verify |
| zoxide | GitHub release tarball | Version + SHA256 | sha256sum verify |
| opencode | GitHub release tarball | Version + SHA256 | sha256sum verify |
| pi-agent-rust | GitHub release tarball | Version + SHA256 | sha256sum verify |
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
- **Third-party apt signing keys are fetched at build time** over TLS without pinning.
- **`apt-get upgrade` introduces drift.** Image content depends on build date.
- **The image is large.** Expect 3–5 GB with the full build toolchain, cloud CLIs, and multiple runtimes.
- **No seccomp/AppArmor profiles are provided.** The image runs as `agent` (uid 1000) with passwordless sudo. Restrict capabilities at the container runtime level (the justfile does this automatically).

## Updating versions

All pinned versions live in `Containerfile` ARG declarations and `scripts/install-tools.sh`. See [VERSIONS.md](VERSIONS.md) for the full validation methodology and update procedure.

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
