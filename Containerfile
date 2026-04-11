# claude-sandbox — OCI image for running AI coding agents in microsandbox
#
# Design:
#   - Claude Code (native binary) is the default entrypoint
#   - Also ships: opencode, codex, gemini CLI
#   - zsh available via `podman run --entrypoint zsh`
#   - No credentials baked in — mount them at runtime
#   - Single non-root user (agent), no SSH daemon
#
# Usage:
#   podman build -t claude-sandbox -f Containerfile .
#   podman run -it --rm \
#     -v ~/dev:/home/agent/dev:Z \
#     -v ~/.claude:/home/agent/.claude:Z \
#     -v ~/.gitconfig.ai:/home/agent/.gitconfig:ro,Z \
#     -v ~/.config/gh:/home/agent/.config/gh:ro,Z \
#     -e ANTHROPIC_API_KEY \
#     claude-sandbox
#
# Shell instead of claude:
#   podman run -it --rm --entrypoint zsh claude-sandbox
#
# Different agent:
#   podman run -it --rm --entrypoint codex claude-sandbox

# =============================================================================
# Stage 1: cargo binary builder
# =============================================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    CARGO_HOME=/opt/cargo \
    RUSTUP_HOME=/opt/rustup

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential cmake pkg-config libssl-dev curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    # --- rust toolchain ---
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal \
    && . /opt/cargo/env \
    && rustup component add rust-analyzer clippy rustfmt \
    # --- cargo tools ---
    && cargo install --locked \
        just hyperfine tokei \
        bottom du-dust procs sd tealdeer bandwhich \
        cargo-watch cargo-edit cargo-outdated cargo-audit \
        jj-cli starship-jj atuin

# =============================================================================
# Stage 2: runtime image
# =============================================================================
FROM ubuntu:24.04

LABEL description="AI coding agent sandbox — polyglot dev environment with Claude Code" \
      org.opencontainers.image.source="https://github.com/butterflyskies/claude-sandbox"

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    XDG_CONFIG_HOME=/home/agent/.config \
    XDG_DATA_HOME=/home/agent/.local/share \
    XDG_CACHE_HOME=/home/agent/.cache \
    XDG_STATE_HOME=/home/agent/.local/state \
    CARGO_HOME=/opt/cargo \
    RUSTUP_HOME=/opt/rustup \
    ASDF_DATA_DIR=/home/agent/.asdf \
    EDITOR=nvim \
    VISUAL=nvim \
    PATH="/home/agent/.local/bin:/home/agent/.cargo/bin:/home/agent/.asdf/shims:/home/agent/.asdf/bin:/home/agent/.npm-global/bin:/opt/cargo/bin:${PATH}"

# ---------------------------------------------------------------------------
# System packages + third-party apt repos + locale + user — single layer
# ---------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        # core
        ca-certificates locales sudo man-db bash-completion coreutils \
        findutils grep sed gawk less file tree acl attr \
        tar gzip bzip2 xz-utils zip unzip zstd \
        # build toolchain + native extension deps
        build-essential cmake ninja-build meson autoconf automake libtool pkg-config \
        protobuf-compiler \
        libssl-dev libffi-dev zlib1g-dev libreadline-dev libsqlite3-dev \
        libncurses-dev libbz2-dev liblzma-dev libxml2-dev libxmlsec1-dev \
        tk-dev libgdbm-dev \
        # vcs
        git git-lfs git-crypt \
        # shell + editors
        zsh neovim nano \
        # network
        curl wget rsync dnsutils iputils-ping iproute2 \
        # debug
        strace htop procps lsof \
        # data / lint
        jq sqlite3 shellcheck \
        # modern cli (ubuntu repos)
        fzf ripgrep fd-find bat \
        # python (system)
        python3 python3-pip python3-venv \
        # gnupg
        gnupg \
    # --- symlink ubuntu-renamed binaries ---
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat \
    # --- third-party apt: GitHub CLI ---
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    # --- third-party apt: eza ---
    && curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
        | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
        > /etc/apt/sources.list.d/gierens.list \
    # --- third-party apt: step-cli ---
    && curl -fsSL https://packages.smallstep.com/keys/apt/repo-signing-key.gpg \
        -o /etc/apt/keyrings/smallstep.asc \
    && printf 'Types: deb\nURIs: https://packages.smallstep.com/stable/debian\nSuites: debs\nComponents: main\nSigned-By: /etc/apt/keyrings/smallstep.asc\n' \
        > /etc/apt/sources.list.d/smallstep.sources \
    && apt-get update && apt-get install -y gh eza step-cli \
    # --- locale ---
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen \
    # --- default editor ---
    && update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 100 \
    && update-alternatives --set editor /usr/bin/nvim \
    # --- standalone tools ---
    && curl -sS https://starship.rs/install.sh | sh -s -- -y \
    && curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | BIN_DIR=/usr/local/bin bash \
    && curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh \
    && sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin \
    # --- user setup ---
    && userdel -r ubuntu 2>/dev/null || true \
    && groupdel ubuntu 2>/dev/null || true \
    && groupadd -g 1000 agent \
    && useradd -m -u 1000 -g agent -s /bin/zsh agent \
    && usermod -aG sudo agent \
    && echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agent \
    && chmod 440 /etc/sudoers.d/agent \
    && mkdir -p \
        /home/agent/.local/bin \
        /home/agent/.local/share \
        /home/agent/.local/state/zsh \
        /home/agent/.cargo/bin \
        /home/agent/.config \
        /home/agent/.cache \
        /home/agent/.asdf \
        /home/agent/.npm-global \
        /home/agent/.claude \
        /home/agent/dev \
        /home/agent/projects \
    && chown -R agent:agent /home/agent \
    # --- cleanup ---
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Rust toolchain + cargo binaries from builder
# ---------------------------------------------------------------------------
COPY --from=builder /opt/rustup /opt/rustup
COPY --from=builder /opt/cargo /opt/cargo
RUN for bin in just hyperfine tokei btm dust procs sd tldr bandwhich \
               cargo-watch cargo-audit cargo cargo-clippy cargo-fmt \
               rustc rustup rust-analyzer rustfmt jj starship-jj atuin; do \
        [ -f "/opt/cargo/bin/$bin" ] && ln -sf "/opt/cargo/bin/$bin" "/usr/local/bin/$bin"; \
    done

# ---------------------------------------------------------------------------
# Shell + prompt configuration
# ---------------------------------------------------------------------------
COPY config/zshrc /home/agent/.zshrc
COPY config/interactive.zsh /home/agent/.zsh/interactive.zsh
COPY config/starship.toml /home/agent/.config/starship.toml
RUN chown -R agent:agent /home/agent/.zshrc /home/agent/.zsh /home/agent/.config/starship.toml

# ---------------------------------------------------------------------------
# AI coding agents + language runtimes (runs as agent user)
# ---------------------------------------------------------------------------
COPY scripts/install-tools.sh /tmp/install-tools.sh
RUN chmod +x /tmp/install-tools.sh \
    && su - agent -c /tmp/install-tools.sh \
    && rm /tmp/install-tools.sh

# ---------------------------------------------------------------------------
# Final security pass
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get upgrade -y \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------
USER agent
WORKDIR /home/agent

# Volume mount points (documented, not required):
#   /home/agent/dev          source repositories
#   /home/agent/projects     additional project dirs
#   /home/agent/.claude      Claude Code config + memory
#   /home/agent/.config/gh   GitHub CLI config
#   /home/agent/.gitconfig   git identity
#   /home/agent/.ssh         SSH keys

ENTRYPOINT ["claude"]
CMD []
