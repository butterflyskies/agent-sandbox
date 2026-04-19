#!/bin/bash
# Install AI coding agents + language runtimes
# Runs as the agent user during image build
set -euo pipefail

export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
mkdir -p "$NPM_CONFIG_PREFIX" "$HOME/.local/bin"

# ==========================================================================
# Pinned runtime versions (see VERSIONS.md for validation methodology)
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

CODEX_VERSION=0.120.0
GEMINI_CLI_VERSION=0.37.1

# ==========================================================================
# asdf bootstrap — pinned release, SHA256-verified
# ==========================================================================
ASDF_VERSION=0.18.1
ASDF_SHA256=56141dc99eab75c140dcdd85cf73f3b82fed2485a8dccd4f11a4dc5cbcb6ea5c
ASDF_BIN="$ASDF_DATA_DIR/bin"
mkdir -p "$ASDF_BIN"
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ASDF_ARCH="amd64" ;;
    aarch64) ASDF_ARCH="arm64" ;;
    *)       echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac
curl -fsSL -o /tmp/asdf.tar.gz \
    "https://github.com/asdf-vm/asdf/releases/download/v${ASDF_VERSION}/asdf-v${ASDF_VERSION}-linux-${ASDF_ARCH}.tar.gz"
echo "${ASDF_SHA256}  /tmp/asdf.tar.gz" | sha256sum -c -
tar xzf /tmp/asdf.tar.gz -C "$ASDF_BIN"
rm /tmp/asdf.tar.gz
chmod +x "$ASDF_BIN/asdf"
export PATH="$HOME/.local/bin:$ASDF_BIN:$ASDF_DATA_DIR/shims:$NPM_CONFIG_PREFIX/bin:/opt/cargo/bin:$PATH"
echo "asdf $(asdf version)"

# ==========================================================================
# asdf plugins — pinned to exact git SHAs via asdf-plugin-manager
# The manager script is vendored in scripts/ to avoid a bootstrap cycle.
# Plugin URLs and SHAs are declared in ~/.plugin-versions (from config/).
# ==========================================================================
export ASDF_PLUGIN_MANAGER_PLUGIN_VERSIONS_FILENAME="$HOME/.plugin-versions"
[[ -f "$ASDF_PLUGIN_MANAGER_PLUGIN_VERSIONS_FILENAME" ]] || {
    echo "plugin-versions not found at $ASDF_PLUGIN_MANAGER_PLUGIN_VERSIONS_FILENAME" >&2
    exit 1
}
/tmp/asdf-plugin-manager add-all

# ==========================================================================
# Language runtimes — pinned to exact versions
# ==========================================================================
asdf install nodejs "$NODEJS_VERSION"
asdf set --home nodejs "$NODEJS_VERSION"
NODE_VER="$(node --version)"
echo "node $NODE_VER"

asdf install python "$PYTHON_VERSION"
asdf set --home python "$PYTHON_VERSION"
PYTHON_VER="$(python3 --version)"
echo "python $PYTHON_VER"

asdf install golang "$GOLANG_VERSION"
asdf set --home golang "$GOLANG_VERSION"
GO_VER="$(go version)"
echo "$GO_VER"

asdf install java "$JAVA_VERSION"
asdf set --home java "$JAVA_VERSION"
JAVA_VER="$(java --version 2>&1 | head -1)"
echo "java $JAVA_VER"

asdf install ruby "$RUBY_VERSION"
asdf set --home ruby "$RUBY_VERSION"
RUBY_VER="$(ruby --version)"
echo "$RUBY_VER"

asdf install zig "$ZIG_VERSION"
asdf set --home zig "$ZIG_VERSION"
ZIG_VER="$(zig version)"
echo "zig $ZIG_VER"

asdf install bun "$BUN_VERSION"
asdf set --home bun "$BUN_VERSION"
BUN_VER="$(bun --version)"
echo "bun $BUN_VER"

asdf install pnpm "$PNPM_VERSION"
asdf set --home pnpm "$PNPM_VERSION"
PNPM_VER="$(pnpm --version)"
echo "pnpm $PNPM_VER"

asdf install gradle "$GRADLE_VERSION"
asdf set --home gradle "$GRADLE_VERSION"
GRADLE_VER="$(gradle --version 2>/dev/null | grep Gradle | head -1 || echo "$GRADLE_VERSION")"
echo "gradle $GRADLE_VER"

asdf install maven "$MAVEN_VERSION"
asdf set --home maven "$MAVEN_VERSION"
MAVEN_VER="$(mvn --version 2>/dev/null | head -1 || echo "$MAVEN_VERSION")"
echo "maven $MAVEN_VER"

# ==========================================================================
# Claude Code (vendored installer — self-verifies binary via SHA256 manifest)
# ==========================================================================
echo "--- Installing Claude Code ---"
bash /tmp/scripts/claude-install.sh
CLAUDE_PATH="$(which claude 2>/dev/null || echo '/home/agent/.local/bin/claude')"
echo "claude: $CLAUDE_PATH"

# ==========================================================================
# npm-based AI CLIs — pinned versions
# ==========================================================================
echo "--- Installing Codex ---"
npm install -g "@openai/codex@${CODEX_VERSION}"
echo "codex: $(which codex 2>/dev/null || echo 'installed')"

echo "--- Installing Gemini CLI ---"
npm install -g "@google/gemini-cli@${GEMINI_CLI_VERSION}"
echo "gemini: $(which gemini 2>/dev/null || echo 'installed')"

# ==========================================================================
# Summary
# ==========================================================================
echo ""
echo "=== Installed ==="
echo "  Node.js  : $NODE_VER"
echo "  Python   : $PYTHON_VER"
echo "  Go       : $GO_VER"
echo "  Java     : $JAVA_VER"
echo "  Ruby     : $RUBY_VER"
echo "  Zig      : $ZIG_VER"
echo "  Bun      : $BUN_VER"
echo "  pnpm     : $PNPM_VER"
echo "  Gradle   : $GRADLE_VER"
echo "  Maven    : $MAVEN_VER"
echo "  Rust     : $(rustc --version 2>/dev/null || echo 'in /usr/local/bin')"
echo "  Claude   : $CLAUDE_PATH"
echo "  Codex    : $(which codex 2>/dev/null || echo 'check PATH')"
echo "  Gemini   : $(which gemini 2>/dev/null || echo 'check PATH')"
echo "  OpenCode : $(which opencode 2>/dev/null || echo '/usr/local/bin')"
echo "  msb      : $(msb --version 2>/dev/null || echo '/usr/local/bin')"
echo "  jj       : $(jj --version 2>/dev/null || echo '/usr/local/bin')"
echo "  chezmoi  : $(chezmoi --version 2>/dev/null || echo '/usr/local/bin')"
echo "  step     : $(step version 2>/dev/null | head -1 || echo 'installed')"
echo "  gcloud   : $(gcloud --version 2>/dev/null | head -1 || echo 'installed')"
echo "  aws      : $(aws --version 2>/dev/null || echo 'installed')"
echo "  az       : $(az --version 2>/dev/null | head -1 || echo 'installed')"
