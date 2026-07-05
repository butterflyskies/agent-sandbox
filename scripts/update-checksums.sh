#!/usr/bin/env bash
set -euo pipefail

# Re-computes SHA256 checksums for all version-pinned tools in the Containerfile.
# Downloads each artifact, hashes it, and updates the corresponding *_SHA256 ARG.
#
# Usage:
#   ./scripts/update-checksums.sh           # update all checksums
#   ./scripts/update-checksums.sh uv msb    # update only specific tools

CONTAINERFILE="${CONTAINERFILE:-Containerfile}"

if [[ ! -f "$CONTAINERFILE" ]]; then
    echo "Error: $CONTAINERFILE not found" >&2
    exit 1
fi

get_arg() {
    grep -P "^ARG ${1}=" "$CONTAINERFILE" | sed "s/^ARG ${1}=//"
}

download_and_hash() {
    local url="$1"
    local tmp
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' RETURN
    if ! curl -fsSL -o "$tmp" "$url"; then
        echo "FAILED (download error)" >&2
        return 1
    fi
    sha256sum "$tmp" | cut -d' ' -f1
}

update_checksum() {
    local name="$1"
    local url="$2"
    local sha_arg="${name}_SHA256"
    local old_sha
    old_sha=$(get_arg "$sha_arg")

    printf "%-20s " "$name"
    local new_sha
    if ! new_sha=$(download_and_hash "$url"); then
        return 1
    fi

    if [[ "$old_sha" == "$new_sha" ]]; then
        echo "$new_sha (unchanged)"
    else
        sed -i "s/^ARG ${sha_arg}=.*/ARG ${sha_arg}=${new_sha}/" "$CONTAINERFILE"
        echo "$new_sha (updated from ${old_sha:0:12}...)"
    fi
}

declare -A TOOLS

UV_VERSION=$(get_arg UV_VERSION)
TOOLS[UV]="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz"

CHEZMOI_VERSION=$(get_arg CHEZMOI_VERSION)
TOOLS[CHEZMOI]="https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi-linux-amd64"

ZOXIDE_VERSION=$(get_arg ZOXIDE_VERSION)
TOOLS[ZOXIDE]="https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz"

OPENCODE_VERSION=$(get_arg OPENCODE_VERSION)
TOOLS[OPENCODE]="https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz"

PI_AGENT_VERSION=$(get_arg PI_AGENT_VERSION)
TOOLS[PI_AGENT]="https://github.com/Dicklesworthstone/pi_agent_rust/releases/download/v${PI_AGENT_VERSION}/pi-${PI_AGENT_VERSION}-linux_amd64.tar.gz"

MSB_VERSION=$(get_arg MSB_VERSION)
TOOLS[MSB]="https://github.com/superradcompany/microsandbox/releases/download/v${MSB_VERSION}/microsandbox-linux-x86_64.tar.gz"

AWSCLI_VERSION=$(get_arg AWSCLI_VERSION)
TOOLS[AWSCLI]="https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip"

RUSTUP_VERSION=$(get_arg RUSTUP_VERSION)
TOOLS[RUSTUP]="https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init"

filter=("$@")

echo "Updating checksums in $CONTAINERFILE"
echo "---"

for name in RUSTUP UV CHEZMOI ZOXIDE OPENCODE PI_AGENT MSB AWSCLI; do
    if [[ ${#filter[@]} -gt 0 ]]; then
        match=false
        for f in "${filter[@]}"; do
            f_norm="${f//-/_}"
            if [[ "${name,,}" == "${f_norm,,}" ]]; then
                match=true
                break
            fi
        done
        $match || continue
    fi
    update_checksum "$name" "${TOOLS[$name]}" || true
done

echo "---"
echo "Done."
