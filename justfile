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

# Initialize a persistent home directory
init:
    ./skeleton/init.sh

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
