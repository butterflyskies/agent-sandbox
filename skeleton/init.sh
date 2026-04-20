#!/bin/bash
# Initialize a persistent home directory for the agent-sandbox agent.
#
# NOTE: For a fully populated home with all build-time tools and configs,
# prefer the image-extraction method:
#
#   just init-home [target-dir]
#
# That command copies /home/agent directly out of the image (including asdf,
# cargo binaries, zsh config, etc.) into a local directory. Use this script
# instead when you want a lightweight skeleton without pulling the full image,
# or when you plan to supply your own tooling.
#
# This creates a minimal directory structure that gets mounted as /home/agent.
# Populate the files described below before running the container.
#
# Usage: ./skeleton/init.sh [target-dir]
#   Default target: ./home (relative to repo root)
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TARGET="${1:-${ROOT_DIR}/home}"

if [[ -d "$TARGET" && "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
    echo "Directory $TARGET already exists and is not empty."
    echo "Remove it or choose a different path."
    exit 1
fi

echo "Initializing agent home at $TARGET ..."

mkdir -p \
    "$TARGET/.local/bin" \
    "$TARGET/.local/share" \
    "$TARGET/.local/state/zsh" \
    "$TARGET/.cargo/bin" \
    "$TARGET/.config/gh" \
    "$TARGET/.cache" \
    "$TARGET/.asdf" \
    "$TARGET/.npm-global" \
    "$TARGET/.claude" \
    "$TARGET/.ssh" \
    "$TARGET/dev" \
    "$TARGET/projects"

# Placeholder files with guidance
cat > "$TARGET/.gitconfig" << 'GITCONFIG'
# Git identity for the agent.
# Fill in before running the container.
#
# [user]
#     name = Your Name
#     email = your@email.com
# [credential]
#     helper = !/usr/bin/gh auth git-credential
GITCONFIG

cat > "$TARGET/.config/gh/README" << 'GHREADME'
# GitHub CLI config
#
# To populate, either:
#   1. Copy your existing gh config into this directory:
#      cp ~/.config/gh/hosts.yml .config/gh/hosts.yml
#
#   2. Or run gh auth login inside the container:
#      podman run -it --rm -v $PWD:/home/agent/.config/gh:Z \
#        --entrypoint gh agent-sandbox auth login
GHREADME

cat > "$TARGET/.claude/README" << 'CLAUDEREADME'
# Claude Code configuration
#
# This directory persists Claude Code's settings, memory, and session
# state across container runs. Claude Code will populate it on first
# launch.
#
# You can pre-populate:
#   settings.json   — model preferences, permissions, hooks
#   CLAUDE.md       — project/global instructions
CLAUDEREADME

cat > "$TARGET/.ssh/README" << 'SSHREADME'
# SSH keys
#
# Place your SSH keys here if the agent needs git+ssh access.
# Make sure permissions are correct:
#   chmod 700 .ssh/
#   chmod 600 .ssh/id_*
#   chmod 644 .ssh/*.pub
#
# Or use gh CLI for HTTPS auth instead (no SSH keys needed).
SSHREADME

cat > "$TARGET/dev/README" << 'DEVREADME'
# Source repositories
#
# Clone repos here before running the container, or clone from inside:
#   git clone https://github.com/org/repo.git
#
# This directory is mounted at /home/agent/dev inside the container.
DEVREADME

chmod 700 "$TARGET/.ssh"

echo ""
echo "Done. Skeleton created at $TARGET"
echo ""
echo "Before running the container, populate:"
echo "  $TARGET/.gitconfig          — git identity"
echo "  $TARGET/.config/gh/         — gh auth (hosts.yml)"
echo "  $TARGET/.ssh/               — SSH keys (optional)"
echo "  $TARGET/dev/                — source repos to work on"
echo ""
echo "Note: this skeleton does not include build-time tools (asdf, cargo"
echo "binaries, zsh config, etc.). For a fully populated home directory, run:"
echo "  just init-home $TARGET"
echo ""
echo "Then run:"
echo "  just claude"
