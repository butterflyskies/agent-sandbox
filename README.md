# claude-sandbox

OCI container image for running AI coding agents — primarily [Claude Code](https://docs.anthropic.com/en/docs/claude-code), but also ships OpenAI Codex, Google Gemini CLI, OpenCode, and [microsandbox](https://github.com/microsandbox/microsandbox).

Designed for use with microsandbox or plain `podman run`, with volume mounts for source repos and credentials injected at runtime.

## Quick start

```bash
./build.sh

podman run -it --rm \
  -v ~/dev:/home/agent/dev:Z \
  -v ~/.claude:/home/agent/.claude:Z \
  -v ~/.gitconfig:/home/agent/.gitconfig:ro,Z \
  -v ~/.config/gh:/home/agent/.config/gh:ro,Z \
  -e ANTHROPIC_API_KEY \
  claude-sandbox
```

Shell instead of Claude:
```bash
podman run -it --rm --entrypoint zsh claude-sandbox
```

Different agent:
```bash
podman run -it --rm --entrypoint codex -e OPENAI_API_KEY claude-sandbox
podman run -it --rm --entrypoint gemini -e GEMINI_API_KEY claude-sandbox
podman run -it --rm --entrypoint opencode claude-sandbox
```

## What's in the box

| Category | Contents |
|----------|----------|
| **AI agents** | Claude Code (native), Codex, Gemini CLI, OpenCode |
| **Sandbox** | microsandbox (`msb`) CLI |
| **Runtimes** | Node.js 24 LTS, Python 3.12, Go, Java (GraalVM 21), Ruby, Zig, Bun (via asdf) |
| **Build tools** | Rust (stable) + cargo tools, Gradle, Maven, pnpm, uv, cmake, ninja, meson |
| **VCS** | git, git-lfs, git-crypt, jj (Jujutsu), gh CLI |
| **Shell** | zsh + zinit + starship + fzf-tab + atuin + zoxide + direnv |
| **Editors** | neovim (default), nano |
| **CLI** | ripgrep, fd, bat, eza, fzf, jq, just, hyperfine, tokei, bottom, dust, chezmoi, step-cli |

## Volume mounts

No credentials or identity are baked into the image. Mount what you need:

| Mount point | Purpose |
|-------------|---------|
| `/home/agent/dev` | Source repositories |
| `/home/agent/projects` | Additional project directories |
| `/home/agent/.claude` | Claude Code config and memory |
| `/home/agent/.config/gh` | GitHub CLI authentication |
| `/home/agent/.gitconfig` | Git identity and signing config |
| `/home/agent/.ssh` | SSH keys (if needed) |

The `agent` user's home is `/home/agent`. If you want state to persist across runs, mount the entire home directory or specific subdirectories onto a persistent volume.

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
| Claude Code | Official installer script | Floating (latest) | Installer verifies binary SHA256 from manifest |
| Codex, Gemini | npm install -g | Floating (latest) | npm registry signatures |
| gh, eza, step-cli | apt with signed repos | Distro package version | GPG-signed apt repos |
| asdf runtimes | asdf install latest:N | Major.minor pinned | Plugin-specific verification |

### Remaining risks

- **Claude Code's installer script itself is not pinned.** The binary it downloads is SHA256-verified, but the script that does the downloading is fetched fresh each build. A compromised script could bypass its own verification.

- **npm packages (Codex, Gemini) float to latest.** npm registry signatures provide some protection, but versions are not locked.

- **asdf plugin repos are not pinned to SHAs.** Plugins are cloned from GitHub with no ref lock. The `latest:N` pattern means patch versions float.

- **Third-party apt repo signing keys are fetched at build time.** The gh, eza, and step-cli apt repos are GPG-signed, but the signing keys themselves are downloaded over TLS without pinning.

- **`apt-get upgrade` introduces drift.** The final security-patch layer means image content depends on build date.

- **The image is large.** Multi-stage build keeps Rust compilation artifacts out, but expect 2-4 GB with the full build toolchain and multiple runtimes.

- **No seccomp/AppArmor profiles are provided.** The image runs as a non-root user (`agent`, uid 1000) with passwordless sudo. Restrict capabilities at the container runtime level.

## Updating versions

All pinned versions are at the top of the Containerfile as `ARG` declarations. To bump:

1. Update the version ARG
2. Download the new artifact and compute `sha256sum`
3. Update the corresponding SHA256 ARG
4. Rebuild

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
