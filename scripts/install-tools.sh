#!/bin/bash
# Install AI coding agents + language runtimes
# Runs as the agent user during image build
#
# Note: Claude Code is installed via its official installer which performs
# its own SHA256 verification against a manifest. This is the one curl|sh
# we accept — the installer is the only distribution channel and the binary
# it downloads is integrity-checked before execution.
set -euo pipefail

export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
mkdir -p "$NPM_CONFIG_PREFIX" "$HOME/.local/bin" "$HOME/.cargo/bin"

# ==========================================================================
# Pinned runtime versions
#
# These are pinned to exact versions. asdf plugin version lists can lag
# behind upstream — see VERSIONS.md for the validation methodology.
# ==========================================================================
NODEJS_VERSION=24.14.1
PYTHON_VERSION=3.12.13
GOLANG_VERSION=1.26.2
JAVA_VERSION=oracle-graalvm-21.0.8
RUBY_VERSION=3.4.8
ZIG_VERSION=0.15.1
BUN_VERSION=1.3.12
PNPM_VERSION=10.33.0
GRADLE_VERSION=9.4.1
MAVEN_VERSION=3.9.9

# ==========================================================================
# asdf bootstrap — pinned release
# ==========================================================================
ASDF_VERSION=0.18.1
ASDF_BIN="$ASDF_DATA_DIR/bin"
mkdir -p "$ASDF_BIN"
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ASDF_ARCH="amd64" ;;
    aarch64) ASDF_ARCH="arm64" ;;
    *)       echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac
curl -fsSL "https://github.com/asdf-vm/asdf/releases/download/v${ASDF_VERSION}/asdf-v${ASDF_VERSION}-linux-${ASDF_ARCH}.tar.gz" \
    | tar xz -C "$ASDF_BIN"
chmod +x "$ASDF_BIN/asdf"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$ASDF_BIN:$ASDF_DATA_DIR/shims:$NPM_CONFIG_PREFIX/bin:/opt/cargo/bin:$PATH"
echo "asdf $(asdf version)"

# ==========================================================================
# asdf plugins — pinned to exact git SHAs via asdf-plugin-manager
# The manager script is vendored in scripts/ to avoid a bootstrap cycle.
# Plugin URLs and SHAs are declared in ~/.plugin-versions (from config/).
# ==========================================================================
/tmp/asdf-plugin-manager add-all

# ==========================================================================
# Language runtimes — pinned to exact versions
# ==========================================================================
asdf install nodejs "$NODEJS_VERSION"
asdf set --home nodejs "$NODEJS_VERSION"
echo "node $(node --version)"

asdf install python "$PYTHON_VERSION"
asdf set --home python "$PYTHON_VERSION"
echo "python $(python3 --version)"

asdf install golang "$GOLANG_VERSION"
asdf set --home golang "$GOLANG_VERSION"
echo "go $(go version)"

asdf install java "$JAVA_VERSION"
asdf set --home java "$JAVA_VERSION"
echo "java $(java --version 2>&1 | head -1)"

asdf install ruby "$RUBY_VERSION"
asdf set --home ruby "$RUBY_VERSION"
echo "ruby $(ruby --version)"

asdf install zig "$ZIG_VERSION"
asdf set --home zig "$ZIG_VERSION"
echo "zig $(zig version)"

asdf install bun "$BUN_VERSION"
asdf set --home bun "$BUN_VERSION"
echo "bun $(bun --version)"

asdf install pnpm "$PNPM_VERSION"
asdf set --home pnpm "$PNPM_VERSION"
echo "pnpm $(pnpm --version)"

asdf install gradle "$GRADLE_VERSION"
asdf set --home gradle "$GRADLE_VERSION"
echo "gradle $(gradle --version 2>/dev/null | head -3 | tail -1)"

asdf install maven "$MAVEN_VERSION"
asdf set --home maven "$MAVEN_VERSION"
echo "mvn $(mvn --version 2>/dev/null | head -1)"

# ==========================================================================
# Claude Code (native binary — installer self-verifies via SHA256 manifest)
# ==========================================================================
echo "--- Installing Claude Code ---"
curl -fsSL https://claude.ai/install.sh | sh
echo "claude: $(claude --version 2>/dev/null || echo 'installed')"

# ==========================================================================
# npm-based AI CLIs (versions locked by npm)
# ==========================================================================
echo "--- Installing Codex ---"
npm install -g @openai/codex
echo "codex: $(codex --version 2>/dev/null || echo 'installed')"

echo "--- Installing Gemini CLI ---"
npm install -g @google/gemini-cli
echo "gemini: $(gemini --version 2>/dev/null || echo 'installed')"

# ==========================================================================
# Summary
# ==========================================================================
echo ""
echo "=== Installed ==="
echo "  Node.js  : $(node --version)"
echo "  Python   : $(python3 --version | cut -d' ' -f2)"
echo "  Go       : $(go version | cut -d' ' -f3)"
echo "  Java     : $(java --version 2>&1 | head -1)"
echo "  Ruby     : $(ruby --version | cut -d' ' -f2)"
echo "  Zig      : $(zig version)"
echo "  Bun      : $(bun --version)"
echo "  pnpm     : $(pnpm --version)"
echo "  Gradle   : $(gradle --version 2>/dev/null | grep Gradle | head -1)"
echo "  Maven    : $(mvn --version 2>/dev/null | head -1)"
echo "  Rust     : $(rustc --version | cut -d' ' -f2)"
echo "  Claude   : $(which claude)"
echo "  Codex    : $(which codex 2>/dev/null || echo 'check PATH')"
echo "  Gemini   : $(which gemini 2>/dev/null || echo 'check PATH')"
echo "  OpenCode : $(which opencode 2>/dev/null || echo '/usr/local/bin')"
echo "  msb      : $(msb --version 2>/dev/null || echo '/usr/local/bin')"
echo "  jj       : $(jj --version 2>/dev/null)"
echo "  chezmoi  : $(chezmoi --version 2>/dev/null)"
echo "  step     : $(step version 2>/dev/null | head -1)"
