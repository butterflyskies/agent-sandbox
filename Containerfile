# agent-sandbox — OCI image for running AI coding agents in microsandbox
#
# Design:
#   - Claude Code (native binary) is the default entrypoint
#   - Also ships: opencode, codex, gemini CLI, microsandbox
#   - zsh available via `podman run --entrypoint zsh`
#   - No credentials baked in — mount them at runtime
#   - Single non-root user (agent), no SSH daemon
#   - All tool downloads are pinned to specific versions with SHA256 verification
#
# Build:
#   just build
#
# Run:
#   just claude

# =============================================================================
# Pinned versions — update these together when bumping (see VERSIONS.md)
# =============================================================================

# Builder-stage: Rust toolchain
ARG RUSTUP_SHA256=4acc9acc76d5079515b46346a485974457b5a79893cfb01112423c89aeb5aa10

# Builder-stage: cargo crate versions
ARG JUST_VERSION=1.49.0
ARG HYPERFINE_VERSION=1.20.0
ARG TOKEI_VERSION=14.0.0
ARG BOTTOM_VERSION=0.12.3
ARG DU_DUST_VERSION=1.2.4
ARG PROCS_VERSION=0.14.11
ARG SD_VERSION=1.0.0
ARG TEALDEER_VERSION=1.8.1
ARG BANDWHICH_VERSION=0.23.1
ARG CARGO_WATCH_VERSION=8.5.3
ARG CARGO_EDIT_VERSION=0.13.9
ARG CARGO_OUTDATED_VERSION=0.18.0
ARG CARGO_AUDIT_VERSION=0.22.1
ARG JJ_CLI_VERSION=0.40.0
ARG STARSHIP_JJ_VERSION=0.7.0
ARG ATUIN_VERSION=18.13.6

# Runtime-stage: standalone tool versions + checksums (linux x86_64)
ARG UV_VERSION=0.11.6
ARG UV_SHA256=0c6bab77a67a445dc849ed5e8ee8d3cb333b6e2eba863643ce1e228075f27943
ARG CHEZMOI_VERSION=2.70.1
ARG CHEZMOI_SHA256=3f51b236fa337abd1c48b4d893182553aabe2ddb4eff07737c4950d7bea5ed61
ARG ZOXIDE_VERSION=0.9.9
ARG ZOXIDE_SHA256=4ff057d3c4d957946937274c2b8be7af2a9bbae7f90a1b5e9baaa7cb65a20caa
ARG OPENCODE_VERSION=1.4.3
ARG OPENCODE_SHA256=34d503ebb029853293be6fd4d441bbb2dbb03919bfa4525e88b1ca55d68f3e17
ARG MSB_VERSION=0.3.12
ARG MSB_SHA256=bd0eb76a91e4a0dcdd7c16a3525f35435727422a43c4470f31d3aec1c6b56902
ARG AWSCLI_VERSION=2.34.29
ARG AWSCLI_SHA256=8812e303cb4618ec495d39b94e4f338cf37d274007ca89faf587a0bc4792cd0e

# =============================================================================
# Stage 1: cargo binary builder
# =============================================================================
FROM ubuntu:24.04 AS builder

ARG RUSTUP_SHA256
ARG JUST_VERSION HYPERFINE_VERSION TOKEI_VERSION BOTTOM_VERSION DU_DUST_VERSION
ARG PROCS_VERSION SD_VERSION TEALDEER_VERSION BANDWHICH_VERSION
ARG CARGO_WATCH_VERSION CARGO_EDIT_VERSION CARGO_OUTDATED_VERSION CARGO_AUDIT_VERSION
ARG JJ_CLI_VERSION STARSHIP_JJ_VERSION ATUIN_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    CARGO_HOME=/opt/cargo \
    RUSTUP_HOME=/opt/rustup

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential cmake pkg-config libssl-dev curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    # --- rustup: download, verify, execute (no curl|sh) ---
    && curl --proto '=https' --tlsv1.2 -sSf \
        -o /tmp/rustup-init \
        https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init \
    && echo "${RUSTUP_SHA256}  /tmp/rustup-init" | sha256sum -c - \
    && chmod +x /tmp/rustup-init \
    && /tmp/rustup-init -y --default-toolchain stable --profile minimal \
    && rm /tmp/rustup-init \
    && . /opt/cargo/env \
    && rustup component add rust-analyzer clippy rustfmt

# Cargo tools — pinned versions, cache mounts for incremental rebuilds
RUN --mount=type=cache,target=/opt/cargo/registry,sharing=locked \
    --mount=type=cache,target=/opt/cargo/git,sharing=locked \
    --mount=type=cache,target=/tmp/cargo-build,sharing=locked \
    . /opt/cargo/env \
    && CARGO_TARGET_DIR=/tmp/cargo-build cargo install --locked \
        just@${JUST_VERSION} \
        hyperfine@${HYPERFINE_VERSION} \
        tokei@${TOKEI_VERSION} \
        bottom@${BOTTOM_VERSION} \
        du-dust@${DU_DUST_VERSION} \
        procs@${PROCS_VERSION} \
        sd@${SD_VERSION} \
        tealdeer@${TEALDEER_VERSION} \
        bandwhich@${BANDWHICH_VERSION} \
        cargo-watch@${CARGO_WATCH_VERSION} \
        cargo-edit@${CARGO_EDIT_VERSION} \
        cargo-outdated@${CARGO_OUTDATED_VERSION} \
        cargo-audit@${CARGO_AUDIT_VERSION} \
        jj-cli@${JJ_CLI_VERSION} \
        starship-jj@${STARSHIP_JJ_VERSION} \
        atuin@${ATUIN_VERSION}

# =============================================================================
# Stage 2: runtime image
# =============================================================================
FROM ubuntu:24.04

ARG UV_VERSION UV_SHA256
ARG CHEZMOI_VERSION CHEZMOI_SHA256
ARG ZOXIDE_VERSION ZOXIDE_SHA256
ARG OPENCODE_VERSION OPENCODE_SHA256
ARG MSB_VERSION MSB_SHA256
ARG AWSCLI_VERSION AWSCLI_SHA256

ARG IMAGE_VERSION=dev
ARG BUILD_DATE=unknown
ARG GIT_SHA=unknown

LABEL org.opencontainers.image.title="agent-sandbox" \
      org.opencontainers.image.description="AI coding agent sandbox — polyglot dev environment with Claude Code" \
      org.opencontainers.image.source="https://github.com/butterflyskies/agent-sandbox" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${GIT_SHA}"

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
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    EDITOR=nvim \
    VISUAL=nvim \
    PATH="/home/agent/.local/bin:/home/agent/.asdf/shims:/home/agent/.asdf/bin:/home/agent/.npm-global/bin:/opt/cargo/bin:${PATH}"

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
        tk-dev libgdbm-dev libyaml-dev \
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
    && update-ca-certificates \
    # --- symlink ubuntu-renamed binaries ---
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat \
    # --- third-party apt: GitHub CLI ---
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    # --- third-party apt: eza (key pinned to commit) ---
    && curl -fsSL https://raw.githubusercontent.com/eza-community/eza/1cff499fb218f2a133aafa01824ddab090f4389e/deb.asc \
        -o /tmp/eza.asc \
    && gpg --dearmor < /tmp/eza.asc > /etc/apt/keyrings/gierens.gpg \
    && rm /tmp/eza.asc \
    && echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] https://deb.gierens.de stable main" \
        > /etc/apt/sources.list.d/gierens.list \
    # --- third-party apt: step-cli ---
    && curl -fsSL https://packages.smallstep.com/keys/apt/repo-signing-key.gpg \
        -o /etc/apt/keyrings/smallstep.asc \
    && printf 'Types: deb\nURIs: https://packages.smallstep.com/stable/debian\nSuites: debs\nComponents: main\nSigned-By: /etc/apt/keyrings/smallstep.asc\n' \
        > /etc/apt/sources.list.d/smallstep.sources \
    # --- third-party apt: Google Cloud CLI ---
    && curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        > /etc/apt/sources.list.d/google-cloud-sdk.list \
    # --- third-party apt: Azure CLI ---
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ noble main" \
        > /etc/apt/sources.list.d/azure-cli.list \
    && apt-get update && apt-get install -y gh eza step-cli google-cloud-cli azure-cli \
    # --- AWS CLI v2: pinned version, SHA256-verified ---
    && curl -fsSL -o /tmp/awscliv2.zip \
        "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip" \
    && echo "${AWSCLI_SHA256}  /tmp/awscliv2.zip" | sha256sum -c - \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip \
    # --- locale ---
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen \
    # --- default editor ---
    && update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 100 \
    && update-alternatives --set editor /usr/bin/nvim \
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
        /home/agent/.config \
        /home/agent/.cache \
        /home/agent/.asdf \
        /home/agent/.npm-global \
        /home/agent/.claude \
        /home/agent/dev \
        /home/agent/projects \
    && chown -R agent:agent /home/agent \
    # --- unprivileged ping ---
    && echo 'net.ipv4.ping_group_range = 0 2147483647' > /etc/sysctl.d/99-ping.conf \
    # --- cleanup ---
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Standalone tools — pinned versions, SHA256-verified, no curl|sh
# ---------------------------------------------------------------------------
RUN set -eux \
    # --- uv (Python package manager) ---
    && curl -fsSL -o /tmp/uv.tar.gz \
        "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" \
    && echo "${UV_SHA256}  /tmp/uv.tar.gz" | sha256sum -c - \
    && tar xzf /tmp/uv.tar.gz -C /tmp \
    && install -m 755 /tmp/uv-x86_64-unknown-linux-gnu/uv /usr/local/bin/uv \
    && install -m 755 /tmp/uv-x86_64-unknown-linux-gnu/uvx /usr/local/bin/uvx \
    && rm -rf /tmp/uv.tar.gz /tmp/uv-x86_64-unknown-linux-gnu \
    # --- chezmoi ---
    && curl -fsSL -o /usr/local/bin/chezmoi \
        "https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi-linux-amd64" \
    && echo "${CHEZMOI_SHA256}  /usr/local/bin/chezmoi" | sha256sum -c - \
    && chmod +x /usr/local/bin/chezmoi \
    # --- zoxide ---
    && curl -fsSL -o /tmp/zoxide.tar.gz \
        "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && echo "${ZOXIDE_SHA256}  /tmp/zoxide.tar.gz" | sha256sum -c - \
    && tar xzf /tmp/zoxide.tar.gz -C /usr/local/bin zoxide \
    && rm /tmp/zoxide.tar.gz \
    # --- opencode ---
    && curl -fsSL -o /tmp/opencode.tar.gz \
        "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
    && echo "${OPENCODE_SHA256}  /tmp/opencode.tar.gz" | sha256sum -c - \
    && tar xzf /tmp/opencode.tar.gz -C /usr/local/bin opencode \
    && chmod +x /usr/local/bin/opencode \
    && rm /tmp/opencode.tar.gz \
    # --- microsandbox (binary + libkrunfw runtime lib) ---
    && curl -fsSL -o /tmp/msb.tar.gz \
        "https://github.com/superradcompany/microsandbox/releases/download/v${MSB_VERSION}/microsandbox-linux-x86_64.tar.gz" \
    && echo "${MSB_SHA256}  /tmp/msb.tar.gz" | sha256sum -c - \
    && tar xzf /tmp/msb.tar.gz -C /tmp msb libkrunfw.so.5.2.1 \
    && install -m 755 /tmp/msb /usr/local/bin/msb \
    && install -m 755 /tmp/libkrunfw.so.5.2.1 /usr/local/lib/ \
    && ln -sf libkrunfw.so.5.2.1 /usr/local/lib/libkrunfw.so.5 \
    && ln -sf libkrunfw.so.5 /usr/local/lib/libkrunfw.so \
    && ldconfig \
    && rm /tmp/msb /tmp/libkrunfw.so.5.2.1 /tmp/msb.tar.gz

# ---------------------------------------------------------------------------
# Rust toolchain + cargo binaries from builder
# ---------------------------------------------------------------------------
COPY --from=builder /opt/rustup /opt/rustup
COPY --from=builder /opt/cargo /opt/cargo
# Symlink all cargo-installed binaries + rustup toolchain binaries into PATH
RUN for bin in /opt/cargo/bin/*; do \
        ln -sf "$bin" "/usr/local/bin/$(basename "$bin")"; \
    done \
    && TOOLCHAIN_BIN="$(find /opt/rustup/toolchains -maxdepth 2 -name bin -type d | head -1)" \
    && if [ -n "$TOOLCHAIN_BIN" ]; then \
        for bin in cargo-clippy cargo-fmt rust-analyzer rustfmt; do \
            [ -f "$TOOLCHAIN_BIN/$bin" ] && ln -sf "$TOOLCHAIN_BIN/$bin" "/usr/local/bin/$bin"; \
        done; \
    fi

# ---------------------------------------------------------------------------
# Shell + prompt configuration
# ---------------------------------------------------------------------------
COPY config/ /tmp/config/
RUN cp /tmp/config/zshrc /home/agent/.zshrc \
    && mkdir -p /home/agent/.zsh \
    && cp /tmp/config/interactive.zsh /home/agent/.zsh/interactive.zsh \
    && cp /tmp/config/starship.toml /home/agent/.config/starship.toml \
    && cp /tmp/config/plugin-versions /home/agent/.plugin-versions \
    && chown -R agent:agent /home/agent/.zshrc /home/agent/.zsh /home/agent/.config/starship.toml /home/agent/.plugin-versions \
    && rm -rf /tmp/config

# ---------------------------------------------------------------------------
# AI coding agents + language runtimes (runs as agent user)
# Claude Code installer is vendored in scripts/claude-install.sh — it
# verifies the binary SHA256 from a manifest before execution. The script
# itself is snapshotted at build time; Claude Code self-updates at runtime.
# ---------------------------------------------------------------------------
COPY scripts/ /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh /tmp/scripts/asdf-plugin-manager \
    && cp /tmp/scripts/asdf-plugin-manager /tmp/asdf-plugin-manager \
    && su - agent -c "bash /tmp/scripts/install-tools.sh" \
    && rm -rf /tmp/scripts /tmp/asdf-plugin-manager

# ---------------------------------------------------------------------------
# Final security pass
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get upgrade -y \
    && apt-get clean

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
