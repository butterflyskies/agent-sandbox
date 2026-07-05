# shellcheck shell=sh
# /etc/profile.d/agent-sandbox-paths.sh
# Ensure build-time tools are in PATH even when /home/agent is externally mounted

path_prepend() {
    case ":${PATH}:" in
        *:"$1":*) ;;
        *) [ -d "$1" ] && export PATH="$1:$PATH" ;;
    esac
}

export CARGO_HOME="${CARGO_HOME:-/opt/cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-/opt/rustup}"
export ASDF_DATA_DIR="${ASDF_DATA_DIR:-${HOME}/.asdf}"
export NPM_CONFIG_PREFIX="${NPM_CONFIG_PREFIX:-${HOME}/.npm-global}"

path_prepend /opt/cargo/bin
path_prepend "${NPM_CONFIG_PREFIX}/bin"
path_prepend "${ASDF_DATA_DIR}/bin"
path_prepend "${ASDF_DATA_DIR}/shims"
