FROM ubuntu:24.04

ARG UID
ARG GID

ENV LOCAL_UID=${UID}
ENV LOCAL_GID=${GID}

ENV DEBIAN_FRONTEND=noninteractive

ENV TZ=Europe/Kyiv

RUN apt-get update --fix-missing

RUN apt-get upgrade -y

RUN apt-get dist-upgrade -y

RUN apt-get install -y locales && localedef -i en_US -f UTF-8 en_US.UTF-8

# Generate Ukrainian locale
RUN localedef -i uk_UA -f UTF-8 uk_UA.UTF-8

ENV LANG=en_US.UTF-8  
ENV LANGUAGE=en_US:en  
ENV LC_ALL=en_US.UTF-8

RUN apt -y install \
    autoconf \
    autoconf-archive \
    automake \
    bat \
    bison \
    bsdmainutils \
    build-essential \
    ca-certificates \
    cargo \
    ccache \
    clang-18 \
    clangd \
    cmake \
    curl \
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
    iproute2 \
    iputils-ping \
    jq \
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
    lsb-release \
    lshw \
    mc \
    mold \
    neovim \
    net-tools \
    netcat-openbsd \
    ninja-build \
    npm \
    pciutils \
    pkg-config \
    redis-tools \
    ripgrep \
    rustc \
    software-properties-common \
    sudo \
    telnet \
    tmux \
    tzdata\
    unzip \
    valgrind \
    vim \
    zlib1g-dev

#RUN apt -y install \
#    gcc-14 \
#    g++-14 \

#RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100 \
#    --slave /usr/bin/g++ g++ /usr/bin/g++-14 \
#    --slave /usr/bin/gcov gcov /usr/bin/gcov-14

RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
RUN apt-get install -y nodejs

# Install GitHub Copilot CLI
RUN npm install -g @github/copilot

# Install OpenAI Codex CLI
RUN npm install -g @openai/codex

# Install Tree-sitter CLI
RUN npm install -g tree-sitter-cli

RUN add-apt-repository ppa:deadsnakes/ppa
RUN apt-get update --fix-missing
RUN apt-get upgrade -y

RUN apt -y install \
    python3.10 \
    python3.10-dev \
    python3.10-tk \
    python3.10-venv \
    python3.10-distutils

# Add memtier_benchmark
RUN curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list && \
    apt-get update --fix-missing && \
    apt-get install -y memtier-benchmark

# Build AFL++ from source with AFL_PERSISTENT_RECORD support
# RUN git clone --depth=1 --branch v4.34c https://github.com/AFLplusplus/AFLplusplus.git /opt/AFLplusplus && \
#     cd /opt/AFLplusplus && \
#     sed -i 's|// #define AFL_PERSISTENT_RECORD|#define AFL_PERSISTENT_RECORD|' include/config.h && \
#     make distrib && \
#     make install && \
#     cd / && rm -rf /opt/AFLplusplus

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

RUN usermod -aG sudo builder && echo "builder ALL=(ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/builder

# Add builder to docker group
RUN usermod -aG docker builder

# Configure Docker to run without sudo
RUN mkdir -p /etc/docker && \
    echo '{\n  "live-restore": true,\n  "group": "docker"\n}' > /etc/docker/daemon.json

# Debian/Ubuntu ship these under different binary names to avoid clashes.
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    ln -sf /usr/bin/batcat /usr/local/bin/bat

# Rust and Cargo come from the Ubuntu repository (rustc/cargo, installed above).
USER builder

RUN python3.10 -m venv /home/builder/.venv

# RUN git clone https://github.com/dragonflydb/df-afl.git /home/builder/df-afl

# Install Tree-sitter grammars for C++, Python, and Go.
RUN mkdir -p /home/builder/.tree-sitter/parsers && \
    git clone --depth=1 https://github.com/tree-sitter/tree-sitter-cpp /home/builder/.tree-sitter/parsers/tree-sitter-cpp && \
    git clone --depth=1 https://github.com/tree-sitter/tree-sitter-python /home/builder/.tree-sitter/parsers/tree-sitter-python && \
    git clone --depth=1 https://github.com/tree-sitter/tree-sitter-go /home/builder/.tree-sitter/parsers/tree-sitter-go && \
    mkdir -p /home/builder/.config/tree-sitter && \
    printf '{\n  "parser-directories": ["/home/builder/.tree-sitter/parsers"]\n}\n' > /home/builder/.config/tree-sitter/config.json

USER root

# Bumped by `update`/update.sh via --build-arg CACHE_BUST=<ts> to re-run only the
# steps below and refresh the CLIs, while every heavy layer above stays cached.
ARG CACHE_BUST=none
RUN npm update -g @github/copilot @openai/codex tree-sitter-cli

# npm globals live in a bind-mounted prefix (see run.sh) so anything installed
# from inside the container survives container recreation.
ENV NPM_CONFIG_PREFIX=/home/builder/.npm-global
ENV PATH=/home/builder/.npm-global/bin:$PATH

WORKDIR /home/builder
