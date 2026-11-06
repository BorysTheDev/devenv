FROM ubuntu:24.04

ARG UID
ARG GID

ENV LOCAL_UID=${UID}
ENV LOCAL_GID=${GID}

ENV DEBIAN_FRONTEND=noninteractive

ENV TZ=Europe/Kyiv

RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get install -y \
    autoconf \
    autoconf-archive \
    automake \
    bat \
    bison \
    bsdmainutils \
    build-essential \
    cargo \
    ccache \
    clang-18 \
    clangd \
    cmake \
    docker-buildx \
    docker-compose-v2 \
    docker.io \
    fd-find \
    gdb \
    gh \
    git \
    golang-go \
    graphviz \
    htop \
    libboost-all-dev \
    libboost-fiber-dev \
    libevent-dev \
    liblzma-dev \
    libre2-dev \
    libssl-dev \
    libtool \
    libunwind-dev \
    libxml2-dev \
    libz-dev \
    libzstd-dev \
    lld-18 \
    llvm-18 \
    llvm-18-dev \
    locales \
    lsb-release \
    lshw \
    ltrace \
    mc \
    mold \
    neovim \
    net-tools \
    ninja-build \
    numactl \
    patchelf \
    pciutils \
    pipx \
    pkg-config \
    python3-dev \
    python3-venv \
    redis-tools \
    rsync \
    rustc \
    shellcheck \
    socat \
    sudo \
    telnet \
    tmux \
    tree \
    tzdata \
    unzip \
    valgrind \
    vim \
    wget \
    zip \
    zlib1g-dev && \
    localedef -i en_US -f UTF-8 en_US.UTF-8 && \
    localedef -i uk_UA -f UTF-8 uk_UA.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

# Baseline tools for Linux performance and network investigations. Services are
# not started during the build (the base image's policy-rc.d exits 101), and the
# preseeds answer the tshark (setuid dumpcap) and iperf3 (daemon) prompts.
RUN echo 'wireshark-common wireshark-common/install-setuid boolean false' | debconf-set-selections && \
    echo 'iperf3 iperf3/start_daemon boolean false' | debconf-set-selections && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        bubblewrap \
        ca-certificates \
        curl \
        dnsutils \
        ethtool \
        iperf3 \
        iproute2 \
        iputils-ping \
        jq \
        lsof \
        mtr-tiny \
        netcat-openbsd \
        openssl \
        procps \
        python3 \
        ripgrep \
        strace \
        sysstat \
        tcpdump \
        time \
        traceroute \
        tshark \
        util-linux && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Node.js comes from NodeSource: Copilot CLI needs Node 22+, Ubuntu ships 18.
# Its nodejs package bundles npm, so Ubuntu's npm is not installed.
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g @github/copilot @openai/codex tree-sitter-cli

# Dragonfly's formatting toolchain (see AGENTS.md "Code Style & Pre-commit Hooks").
# Ubuntu 24.04 marks its Python as externally managed (PEP 668), so these go through
# pipx. PIPX_HOME stays outside /home/builder because run.sh bind-mounts
# ~/.local/share, which would otherwise hide the venvs at runtime.
# Versions match .pre-commit-config.yaml so manual runs produce the same output as CI.
ENV PIPX_HOME=/opt/pipx
ENV PIPX_BIN_DIR=/usr/local/bin
RUN pipx install pre-commit && \
    pipx install clang-format==14.0.6 && \
    pipx install black==25.1.0 && \
    pipx install pyflakes==3.4.0

# Add memtier_benchmark
RUN curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list && \
    apt-get update && \
    apt-get install -y memtier-benchmark && \
    rm -rf /var/lib/apt/lists/*

# Go comes from the Ubuntu repository (golang-go, installed above); its
# binaries are already on PATH via /usr/bin, so only GOPATH needs wiring up.
ENV GOPATH=/home/builder/go
ENV PATH=$PATH:$GOPATH/bin

RUN existing_user=$(getent passwd $LOCAL_UID | cut -d: -f1) && \
    if [ -n "$existing_user" ]; then \
        echo "Removing existing user: $existing_user with UID $LOCAL_UID"; \
        deluser --remove-home "$existing_user"; \
    fi && \
    if [ -n "$LOCAL_GID" ]; then \
        if ! getent group $LOCAL_GID > /dev/null; then \
            addgroup --gid $LOCAL_GID g${LOCAL_GID}; \
        fi; \
        adduser --uid $LOCAL_UID --gid $LOCAL_GID --gecos "" --disabled-password --home /home/builder builder; \
    else \
        adduser --uid $LOCAL_UID --gecos "" --disabled-password --home /home/builder builder; \
    fi

# The docker group takes the host docker socket's GID (build.sh/update.sh pass
# DOCKER_GID), so the group run.sh adds with --group-add has a name: `groups`,
# run by /etc/bash.bashrc's sudo hint, errors on unnamed GIDs. The marker file
# turns that hint ("To run a command as administrator...") off.
ARG DOCKER_GID
RUN if [ -n "$DOCKER_GID" ] && ! getent group "$DOCKER_GID" > /dev/null; then \
        groupmod -g "$DOCKER_GID" docker; \
    fi && \
    usermod -aG sudo,docker builder && echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    touch /home/builder/.sudo_as_admin_successful && \
    chown builder: /home/builder/.sudo_as_admin_successful

# Debian/Ubuntu ship these under different binary names to avoid clashes.
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    ln -sf /usr/bin/batcat /usr/local/bin/bat

USER builder

RUN python3 -m venv /home/builder/.venv

# Dragonfly's Python test dependencies, so `pytest` works in a fresh container.
# The repo itself is bind-mounted at runtime and is not available here, so the
# list is fetched from the upstream default branch; Docker re-checks the URL on
# every build and only reinstalls when the file's content actually changes.
# Versions come only from that file, so version fixes belong in Dragonfly.
# To re-sync with a local checkout:
#   pip install -r ~/dragonfly/tests/dragonfly/requirements.txt
# Numeric owner: builder's group may be g<GID>, not "builder", and the legacy
# (non-BuildKit) builder fails on group names it can't resolve.
ADD --chown=${LOCAL_UID} \
    https://raw.githubusercontent.com/dragonflydb/dragonfly/main/tests/dragonfly/requirements.txt \
    /home/builder/.venv/df-requirements.txt
RUN /home/builder/.venv/bin/pip install --no-cache-dir -r /home/builder/.venv/df-requirements.txt

# Install Tree-sitter grammars for C++, Python, and Go.
# The config lives next to the parsers rather than in ~/.config, which run.sh
# bind-mounts from the host and would otherwise hide it at runtime.
RUN mkdir -p /home/builder/.tree-sitter/parsers && \
    git clone --depth=1 https://github.com/tree-sitter/tree-sitter-cpp /home/builder/.tree-sitter/parsers/tree-sitter-cpp && \
    git clone --depth=1 https://github.com/tree-sitter/tree-sitter-python /home/builder/.tree-sitter/parsers/tree-sitter-python && \
    git clone --depth=1 https://github.com/tree-sitter/tree-sitter-go /home/builder/.tree-sitter/parsers/tree-sitter-go && \
    printf '{\n  "parser-directories": ["/home/builder/.tree-sitter/parsers"]\n}\n' > /home/builder/.tree-sitter/config.json

ENV TREE_SITTER_DIR=/home/builder/.tree-sitter

USER root

# Full access by default for the AI CLIs: Codex's system config, and for Copilot
# run.sh seeds allow-all, autopilot and a trusted "/". COPILOT_ALLOW_ALL is not
# set: any value of it replaces allow-all with tools-only approval. Both are
# told that /tmp is RAM (run.sh mounts it as tmpfs); Copilot fully loads only
# instructions/*.instructions.md from COPILOT_CUSTOM_INSTRUCTIONS_DIRS.
ENV COPILOT_CUSTOM_INSTRUCTIONS_DIRS=/etc/copilot
RUN hint='/tmp is a RAM-backed tmpfs (check `df -hT /tmp`): faster than the disk-backed workspace, but size-limited and wiped when the container stops. Prefer it for scratch files, throwaway builds, test/benchmark output, perf data and packet captures; keep anything that must persist elsewhere.' && \
    mkdir -p /etc/codex /etc/copilot/instructions && \
    printf '%s\n' "$hint" > /etc/copilot/instructions/tmpfs.instructions.md && \
    printf 'approval_policy = "never"\nsandbox_mode = "danger-full-access"\ndeveloper_instructions = "%s"\n' "$hint" > /etc/codex/config.toml

# Bumped by `update`/update.sh via --build-arg CACHE_BUST=<ts> to re-run only the
# steps below and refresh the CLIs, while every heavy layer above stays cached.
ARG CACHE_BUST=none
RUN npm update -g @github/copilot @openai/codex tree-sitter-cli

# npm globals live in a bind-mounted prefix (see run.sh) so anything installed
# from inside the container survives container recreation.
ENV NPM_CONFIG_PREFIX=/home/builder/.npm-global

# The test virtualenv is on PATH so `python3 -m pytest` works straight away,
# which is what tests/dragonfly's documented commands assume.
ENV VIRTUAL_ENV=/home/builder/.venv
ENV PATH=/home/builder/.npm-global/bin:/home/builder/.venv/bin:$PATH

WORKDIR /home/builder
