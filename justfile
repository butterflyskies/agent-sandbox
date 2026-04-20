# agent-sandbox — AI coding agent sandbox
# Usage: just <recipe> [args...]
#
# Named targets (msb-*, docker-*) are sugar — all env var escape hatches still work:
#   CONTAINER_RUNTIME, IMAGE, IMAGE_TAG, REGISTRY, HOME_VOL,
#   MSB_CPUS, MSB_MEMORY, MSB_NAME, MSB_NETWORK_POLICY

set shell := ["bash", "-euo", "pipefail", "-c"]

image    := env("IMAGE", "agent-sandbox")
tag      := env("IMAGE_TAG", "latest")
runtime  := env("CONTAINER_RUNTIME", "podman")
registry := env("REGISTRY", "ghcr.io/butterflyskies")

# List available recipes
default:
    @just --list

# Build the OCI image (local dev — tags as :latest or $IMAGE_TAG)
build:
    #!/bin/bash
    set -euo pipefail
    BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    GIT_SHA=$(git rev-parse HEAD)
    if [[ -n "$(git status --porcelain)" ]]; then
        GIT_SHA="${GIT_SHA}-dirty"
    fi
    IMAGE_VERSION="{{tag}}"
    {{runtime}} build \
        --tag {{image}}:{{tag}} \
        --build-arg IMAGE_VERSION="${IMAGE_VERSION}" \
        --build-arg BUILD_DATE="${BUILD_DATE}" \
        --build-arg GIT_SHA="${GIT_SHA}" \
        --file Containerfile \
        --layers .

# Tag and push to registry
push:
    {{runtime}} tag {{image}}:{{tag}} {{registry}}/{{image}}:{{tag}}
    {{runtime}} push {{registry}}/{{image}}:{{tag}}

# Build with CalVer labels, tag :latest and :YYYYMMDD, push both to registry
release:
    #!/bin/bash
    set -euo pipefail
    DATE_TAG=$(date -u +%Y%m%d)
    BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    GIT_SHA=$(git rev-parse HEAD)
    if [[ -n "$(git status --porcelain)" ]]; then
        GIT_SHA="${GIT_SHA}-dirty"
    fi
    IMAGE_VERSION="${DATE_TAG}"
    echo "Building {{image}} — version=${IMAGE_VERSION} sha=${GIT_SHA}"
    {{runtime}} build \
        --tag {{image}}:${DATE_TAG} \
        --build-arg IMAGE_VERSION="${IMAGE_VERSION}" \
        --build-arg BUILD_DATE="${BUILD_DATE}" \
        --build-arg GIT_SHA="${GIT_SHA}" \
        --file Containerfile \
        --layers .
    {{runtime}} tag {{image}}:${DATE_TAG} {{image}}:latest
    {{runtime}} tag {{image}}:${DATE_TAG} {{registry}}/{{image}}:${DATE_TAG}
    {{runtime}} tag {{image}}:${DATE_TAG} {{registry}}/{{image}}:latest
    {{runtime}} push {{registry}}/{{image}}:${DATE_TAG}
    {{runtime}} push {{registry}}/{{image}}:latest
    echo ""
    echo "Pushed:"
    echo "  {{registry}}/{{image}}:${DATE_TAG}"
    echo "  {{registry}}/{{image}}:latest"

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

# Run Claude Code in the sandbox (uses $CONTAINER_RUNTIME, default: podman)
claude *args:
    #!/bin/bash
    set -euo pipefail
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec claude {{args}}

# Run OpenAI Codex in the sandbox (uses $CONTAINER_RUNTIME, default: podman)
codex *args:
    #!/bin/bash
    set -euo pipefail
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec codex {{args}}

# Drop into an interactive zsh shell (uses $CONTAINER_RUNTIME, default: podman)
shell:
    #!/bin/bash
    set -euo pipefail
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec zsh

# Run Claude Code via microsandbox (public-only network)
msb-claude *args:
    #!/bin/bash
    set -euo pipefail
    export CONTAINER_RUNTIME=msb
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec claude {{args}}

# Run Claude Code via microsandbox — allow-all network + no DNS-rebind protection
msb-claude-open *args:
    #!/bin/bash
    set -euo pipefail
    export CONTAINER_RUNTIME=msb
    export MSB_NETWORK_POLICY=allow-all
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec claude {{args}}

# Run Claude Code via microsandbox — no network access
msb-claude-offline *args:
    #!/bin/bash
    set -euo pipefail
    export CONTAINER_RUNTIME=msb
    export MSB_NETWORK_POLICY=none
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec claude {{args}}

# Run OpenAI Codex via microsandbox
msb-codex *args:
    #!/bin/bash
    set -euo pipefail
    export CONTAINER_RUNTIME=msb
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec codex {{args}}

# Drop into an interactive zsh shell via microsandbox
msb-shell:
    #!/bin/bash
    set -euo pipefail
    export CONTAINER_RUNTIME=msb
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec zsh

# Drop into an interactive zsh shell via microsandbox — allow-all network
msb-shell-open:
    #!/bin/bash
    set -euo pipefail
    export CONTAINER_RUNTIME=msb
    export MSB_NETWORK_POLICY=allow-all
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec zsh

# Show microsandbox sandbox status
msb-status:
    msb list

# Stop the named microsandbox sandbox
msb-stop:
    msb stop "${MSB_NAME:-agent-sandbox}"

# Destroy the named microsandbox sandbox (irreversible — use to reset state)
msb-reset:
    msb rm "${MSB_NAME:-agent-sandbox}"

# Exec a command in the running microsandbox sandbox
msb-exec *args:
    msb exec "${MSB_NAME:-agent-sandbox}" {{args}}

# Run Claude Code via docker
docker-claude *args:
    #!/bin/bash
    set -euo pipefail
    export CONTAINER_RUNTIME=docker
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec claude {{args}}

# Run OpenAI Codex via docker
docker-codex *args:
    #!/bin/bash
    set -euo pipefail
    export CONTAINER_RUNTIME=docker
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec codex {{args}}

# Drop into an interactive zsh shell via docker
docker-shell:
    #!/bin/bash
    set -euo pipefail
    export CONTAINER_RUNTIME=docker
    export ROOT_DIR="{{justfile_directory()}}"
    source run/common.sh
    sandbox_exec zsh
