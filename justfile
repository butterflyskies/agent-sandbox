# agent-sandbox — AI coding agent sandbox
# Usage: just <recipe> [args...]

set shell := ["bash", "-euo", "pipefail", "-c"]

image    := env("IMAGE", "agent-sandbox")
tag      := env("IMAGE_TAG", "latest")
runtime  := env("CONTAINER_RUNTIME", "podman")
registry := env("REGISTRY", "ghcr.io/butterflyskies")

# List available recipes
default:
    @just --list

# Build the OCI image
build:
    {{runtime}} build --tag {{image}}:{{tag}} --file Containerfile --layers .

# Tag and push to registry
push:
    {{runtime}} tag {{image}}:{{tag}} {{registry}}/{{image}}:{{tag}}
    {{runtime}} push {{registry}}/{{image}}:{{tag}}

# Build and push
release: build push

# Initialize a persistent home directory (skeleton only — see init-home for full copy)
init:
    ./skeleton/init.sh

# Extract the full built-in home directory from the image into a local directory
# Usage: just init-home [target]   (default target: ./home)
init-home target="./home":
    #!/bin/bash
    set -euo pipefail
    TARGET="{{target}}"
    if [[ -d "$TARGET" && "$(ls -A "$TARGET" 2>/dev/null)" ]]; then
        echo "Error: $TARGET already exists and is not empty." >&2
        echo "Remove it or choose a different path." >&2
        exit 1
    fi
    mkdir -p "$TARGET"
    echo "Extracting /home/agent from {{image}}:{{tag}} into $TARGET ..."
    if [[ "{{runtime}}" == "msb" ]]; then
        msb run --volume "$TARGET:/mnt" --entrypoint sh "{{image}}:{{tag}}" -c 'cp -a /home/agent/. /mnt/'
    else
        {{runtime}} run --rm -v "$TARGET:/mnt" --entrypoint sh "{{image}}:{{tag}}" -c 'cp -a /home/agent/. /mnt/'
    fi
    echo ""
    echo "Done. Full home directory extracted to $TARGET"
    echo ""
    echo "Next steps:"
    echo "  Edit $TARGET/.gitconfig        — set git identity"
    echo "  Copy ~/.config/gh/hosts.yml    — gh authentication"
    echo "  Copy SSH keys to $TARGET/.ssh/ — (optional)"
    echo "  Then run: just claude"

# Run Claude Code in the sandbox
claude *args:
    #!/bin/bash
    set -euo pipefail
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec claude {{args}}

# Run OpenAI Codex in the sandbox
codex *args:
    #!/bin/bash
    set -euo pipefail
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec codex {{args}}

# Drop into an interactive zsh shell
shell:
    #!/bin/bash
    set -euo pipefail
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec zsh
