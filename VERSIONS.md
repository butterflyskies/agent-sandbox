# Version pinning and update methodology

This document describes how tool versions are pinned in agent-sandbox and
how to validate and update them.

## Principles

1. **Pin everything.** Floating versions make builds non-reproducible and
   create invisible supply chain risk.
2. **Verify integrity.** Every binary downloaded at build time has a SHA256
   checksum verified before execution or installation.
3. **Pin the plugin, not just the runtime.** asdf plugin repositories are
   pinned to git SHAs via `asdf-plugin-manager`. A compromised plugin could
   serve a tampered runtime even if the version number looks correct.
4. **Validate against upstream, not just asdf.** asdf plugin version lists
   can lag behind upstream releases. Always cross-reference.

## Where versions are declared

| What | Where | Format |
|------|-------|--------|
| Cargo crate versions | `Containerfile` ARG block | `ARG CRATE_VERSION=X.Y.Z` |
| Standalone tool versions + SHA256 | `Containerfile` ARG block | `ARG TOOL_VERSION=X.Y.Z` / `ARG TOOL_SHA256=...` |
| asdf runtime versions | `scripts/install-tools.sh` top block | `RUNTIME_VERSION=X.Y.Z` |
| asdf plugin git SHAs | `config/plugin-versions` | `name  url  sha` (tab-separated) |
| asdf-plugin-manager | `scripts/asdf-plugin-manager` | Vendored script (v1.5.0) |
| asdf itself | `scripts/install-tools.sh` | `ASDF_VERSION=X.Y.Z` |

## How to validate versions

### 1. Check upstream latest stable releases

```bash
# Node.js — use active LTS, not current
curl -fsSL https://nodejs.org/dist/index.json \
  | jq -r '[.[] | select(.lts != false)] | .[0] | "\(.version) (LTS: \(.lts))"'

# Python
curl -fsSL https://endoflife.date/api/python.json \
  | jq -r '.[:4] | .[] | "\(.cycle): \(.latest) (EOL: \(.eol))"'

# Go
curl -fsSL 'https://go.dev/dl/?mode=json' | jq -r '.[0].version'

# Ruby
curl -fsSL https://endoflife.date/api/ruby.json \
  | jq -r '.[:3] | .[] | "\(.cycle): \(.latest) (EOL: \(.eol))"'

# Java (GraalVM) — use LTS line (21), not latest feature release
curl -fsSL https://endoflife.date/api/oracle-jdk.json \
  | jq -r '.[:5] | .[] | "\(.cycle): \(.latest) (EOL: \(.eol))"'

# Zig
curl -fsSL https://api.github.com/repos/ziglang/zig/releases \
  | jq -r '[.[] | select(.prerelease == false)] | .[0].tag_name'

# Bun
curl -fsSL https://api.github.com/repos/oven-sh/bun/releases/latest | jq -r '.tag_name'

# pnpm
curl -fsSL https://api.github.com/repos/pnpm/pnpm/releases/latest | jq -r '.tag_name'

# Gradle — stable only, no RCs
curl -fsSL https://services.gradle.org/versions/current | jq -r '.version'

# Maven — 3.9.x line (4.x is pre-release)
curl -fsSL https://endoflife.date/api/maven/3.9.json | jq -r '.latest'
```

### 2. Check what asdf can actually deliver

asdf plugin version lists may lag behind upstream. Always verify:

```bash
asdf list all <runtime> | grep '^X\.Y\.' | tail -5
```

If asdf is behind, either:
- Pin to what asdf has and note the gap
- Update the plugin SHA in `config/plugin-versions` (the newer plugin may
  know about newer versions)

To update a plugin SHA:
```bash
git ls-remote <plugin-repo-url> HEAD | cut -f1
```

### 3. Check cargo crate versions

```bash
for crate in just hyperfine tokei bottom du-dust procs sd tealdeer \
             bandwhich cargo-watch cargo-edit cargo-outdated cargo-audit \
             jj-cli starship-jj atuin; do
  ver=$(curl -fsSL "https://crates.io/api/v1/crates/$crate" \
    | jq -r '.crate.max_stable_version // .crate.max_version')
  echo "$crate=$ver"
done
```

### 4. Check standalone tool versions and compute checksums

For each tool, download the new version and compute its SHA256:

```bash
# uv
VER=X.Y.Z
curl -fsSL "https://github.com/astral-sh/uv/releases/download/${VER}/uv-x86_64-unknown-linux-gnu.tar.gz" | sha256sum

# chezmoi
VER=X.Y.Z
curl -fsSL "https://github.com/twpayne/chezmoi/releases/download/v${VER}/chezmoi-linux-amd64" | sha256sum

# zoxide
VER=X.Y.Z
curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/v${VER}/zoxide-${VER}-x86_64-unknown-linux-musl.tar.gz" | sha256sum

# opencode
VER=X.Y.Z
curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${VER}/opencode-linux-x64.tar.gz" | sha256sum

# microsandbox
VER=X.Y.Z
curl -fsSL "https://github.com/superradcompany/microsandbox/releases/download/v${VER}/microsandbox-linux-x86_64.tar.gz" | sha256sum

# rustup-init (rarely changes, but check after toolchain updates)
curl -fsSL https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init.sha256
```

Some tools publish their own checksums (uv, chezmoi, microsandbox, rustup).
Others don't (zoxide, opencode) — compute from the download and pin.

### 5. Check asdf itself

```bash
curl -fsSL https://api.github.com/repos/asdf-vm/asdf/releases/latest | jq -r '.tag_name'
```

## Update procedure

1. Run the validation commands above. Note any version bumps.
2. Update the `ARG` values in `Containerfile` (versions + SHA256s).
3. Update `scripts/install-tools.sh` runtime version variables.
4. If asdf plugins need updating, update SHAs in `config/plugin-versions`:
   ```bash
   git ls-remote <plugin-url> HEAD | cut -f1
   ```
5. Rebuild: `just build`
6. Smoke test: `just shell`
7. Commit with a message listing what changed.

## Known gaps

- **Ruby**: asdf-ruby plugin may lag 1-2 patch versions behind
  rubygems.org. The plugin must compile Ruby from source, so new releases
  take time to be verified.
- **Maven**: asdf-maven plugin historically lags upstream by several patch
  versions. If you need the absolute latest, consider updating the plugin
  SHA first.
- **Claude Code**: Version floats — the installer always fetches latest.
  The binary itself is SHA256-verified by the installer against a manifest,
  but we cannot pin the version without hardcoding the GCS bucket URL.
- **Codex, Gemini CLI**: npm packages installed at latest. Pin with
  `npm install -g @openai/codex@X.Y.Z` if reproducibility is required.
- **apt packages**: Versions come from Ubuntu 24.04 repos + third-party
  repos (gh, eza, step-cli). Pinning apt packages to exact versions is
  possible but brittle across repo updates.

## EOL policy

Prefer **active LTS** versions over latest/current:
- Node.js: active LTS line (even major numbers — currently 24)
- Java: LTS releases (currently 21, next is 25)
- Python: any supported 3.x (3.12+ recommended)
- Go: current + previous (1.26.x and 1.25.x both supported)
- Ruby: current + previous (3.4.x and 3.3.x both supported)

Avoid versions in **maintenance-only** or **EOL** status. The endoflife.date
API is useful for checking: `curl -fsSL https://endoflife.date/api/<tool>.json`
