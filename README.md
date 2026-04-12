# claude-sandbox

OCI container image for running AI coding agents — primarily [Claude Code](https://docs.anthropic.com/en/docs/claude-code), but also ships OpenAI Codex, Google Gemini CLI, and OpenCode.

Designed for use with [microsandbox](https://github.com/nicholasgasior/microsandbox) or plain `podman run`, with volume mounts for source repos and credentials injected at runtime.

## Quick start

```bash
podman build -t claude-sandbox -f Containerfile .

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
| **Runtimes** | Node.js 22, Python 3.12, Go, Java (GraalVM 21), Ruby, Zig, Bun (via asdf) |
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

Local rebuilds benefit from cargo cache mounts automatically (`--mount=type=cache` in the Containerfile).

For CI or cross-machine cache sharing, use registry-backed caching:

```bash
podman build \
  --layers \
  --cache-from=ghcr.io/butterflyskies/claude-sandbox-cache \
  --cache-to=ghcr.io/butterflyskies/claude-sandbox-cache \
  -t claude-sandbox -f Containerfile .
```

## Limitations and security considerations

**This is a hasty first pass. Use at your own risk.**

- **Nothing is pinned.** No tool versions, no image digests, no git refs. Builds are not reproducible — running the same Containerfile a week apart may produce meaningfully different images. Pinning is planned but not yet implemented.

- **`curl | sh` is used extensively.** The following tools are installed by piping remote scripts into a shell at build time, with no integrity verification beyond TLS:
  - `rustup` (sh.rustup.rs)
  - `uv` (astral.sh/uv/install.sh)
  - `chezmoi` (get.chezmoi.io)
  - `claude` (claude.ai/install.sh)
  - `opencode` (opencode.ai/install)

  This is an inherent supply-chain risk. Each of these scripts could be compromised or changed between builds. A hardened version would download pinned releases, verify checksums, and avoid shell-pipe installation entirely.

- **asdf plugin sources are not pinned.** Plugin repositories are cloned from GitHub at build time with no ref or SHA lock. The `asdf install <tool> latest:N` pattern also means patch versions float between builds.

- **`apt-get upgrade` at the end introduces drift.** The final security-patch layer is good practice but means the image content depends on when it was built.

- **The image is large.** Multi-stage build keeps the Rust compilation artifacts out, but the runtime image still includes a full build toolchain (gcc, cmake, etc.), multiple language runtimes, and ~15 cargo binaries. Expect 2-4 GB.

- **No seccomp/AppArmor profiles are provided.** The image runs as a non-root user (`agent`, uid 1000) with passwordless sudo. Restrict capabilities at the container runtime level as appropriate for your threat model.

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at your option.
