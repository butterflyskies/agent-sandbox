# shellcheck shell=sh
# /etc/profile.d/agent-sandbox-paths.sh
# Ensure build-time tools are in PATH even when /home/agent is externally mounted

# Cargo/Rust toolchain
case ":${PATH}:" in
    *:/opt/cargo/bin:*) ;;
    *)
        if [ -d /opt/cargo/bin ]; then
            export PATH="/opt/cargo/bin:$PATH"
            export CARGO_HOME="${CARGO_HOME:-/opt/cargo}"
            export RUSTUP_HOME="${RUSTUP_HOME:-/opt/rustup}"
        fi
        ;;
esac

# asdf — only if user's home doesn't have its own asdf
if [ ! -d "${HOME}/.asdf/bin" ] && [ -d /opt/cargo/bin/asdf ]; then
    export ASDF_DATA_DIR="${ASDF_DATA_DIR:-${HOME}/.asdf}"
fi
