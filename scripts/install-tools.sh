#!/bin/bash
# Install AI coding agents + language runtimes
# Runs as the agent user during image build
set -euo pipefail

export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
mkdir -p "$NPM_CONFIG_PREFIX" "$HOME/.local/bin" "$HOME/.cargo/bin"

# ==========================================================================
# asdf bootstrap
# ==========================================================================
ASDF_BIN="$ASDF_DATA_DIR/bin"
mkdir -p "$ASDF_BIN"
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ASDF_ARCH="amd64" ;;
    aarch64) ASDF_ARCH="arm64" ;;
    *)       echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac
ASDF_URL=$(curl -fsSL https://api.github.com/repos/asdf-vm/asdf/releases/latest \
    | jq -r ".assets[] | select(.name | test(\"linux-${ASDF_ARCH}\\\\.tar\\\\.gz$\")) | .browser_download_url" \
    | head -1)
curl -fsSL "$ASDF_URL" | tar xz -C "$ASDF_BIN"
chmod +x "$ASDF_BIN/asdf"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$ASDF_BIN:$ASDF_DATA_DIR/shims:$NPM_CONFIG_PREFIX/bin:/opt/cargo/bin:$PATH"
echo "asdf $(asdf version)"

# ==========================================================================
# asdf plugins (add all upfront, installs below)
# ==========================================================================
for plugin in nodejs python java golang ruby zig bun pnpm gradle maven; do
    asdf plugin add "$plugin" 2>/dev/null || true
done

# ==========================================================================
# Node.js (required for npm-based AI CLIs)
# ==========================================================================
asdf install nodejs latest:22
asdf set --home nodejs latest:22
echo "node $(node --version)"

# ==========================================================================
# Python
# ==========================================================================
asdf install python latest:3.12
asdf set --home python latest:3.12
echo "python $(python3 --version)"

# ==========================================================================
# Go
# ==========================================================================
asdf install golang latest
asdf set --home golang latest
echo "go $(go version)"

# ==========================================================================
# Java (GraalVM)
# ==========================================================================
asdf install java latest:oracle-graalvm-21
asdf set --home java latest:oracle-graalvm-21
echo "java $(java --version 2>&1 | head -1)"

# ==========================================================================
# Ruby
# ==========================================================================
asdf install ruby latest:3
asdf set --home ruby latest:3
echo "ruby $(ruby --version)"

# ==========================================================================
# Zig
# ==========================================================================
asdf install zig latest
asdf set --home zig latest
echo "zig $(zig version)"

# ==========================================================================
# Bun
# ==========================================================================
asdf install bun latest
asdf set --home bun latest
echo "bun $(bun --version)"

# ==========================================================================
# pnpm
# ==========================================================================
asdf install pnpm latest
asdf set --home pnpm latest
echo "pnpm $(pnpm --version)"

# ==========================================================================
# Gradle
# ==========================================================================
asdf install gradle latest
asdf set --home gradle latest
echo "gradle $(gradle --version 2>/dev/null | head -3 | tail -1)"

# ==========================================================================
# Maven
# ==========================================================================
asdf install maven latest
asdf set --home maven latest
echo "mvn $(mvn --version 2>/dev/null | head -1)"

# ==========================================================================
# Claude Code (native binary)
# ==========================================================================
echo "--- Installing Claude Code ---"
curl -fsSL https://claude.ai/install.sh | sh
echo "claude: $(claude --version 2>/dev/null || echo 'installed')"

# ==========================================================================
# OpenAI Codex
# ==========================================================================
echo "--- Installing Codex ---"
npm install -g @openai/codex
echo "codex: $(codex --version 2>/dev/null || echo 'installed')"

# ==========================================================================
# Google Gemini CLI
# ==========================================================================
echo "--- Installing Gemini CLI ---"
npm install -g @google/gemini-cli
echo "gemini: $(gemini --version 2>/dev/null || echo 'installed')"

# ==========================================================================
# OpenCode
# ==========================================================================
echo "--- Installing OpenCode ---"
curl -fsSL https://opencode.ai/install | bash
echo "opencode: $(opencode version 2>/dev/null || echo 'installed')"

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
echo "  OpenCode : $(which opencode 2>/dev/null || echo 'check PATH')"
echo "  jj       : $(jj --version 2>/dev/null || echo 'in /usr/local/bin')"
echo "  chezmoi  : $(chezmoi --version 2>/dev/null || echo 'in /usr/local/bin')"
echo "  step     : $(step version 2>/dev/null | head -1)"
