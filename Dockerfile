FROM golang:1.25-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    # --- networking / lesson tooling ---
    iproute2 \
    iputils-ping \
    tcpdump \
    tshark \
    netcat-openbsd \
    python3 \
    # --- editors / dev quality-of-life ---
    neovim \
    vim \
    git \
    ripgrep \
    fd-find \
    fzf \
    tmux \
    htop \
    tree \
    jq \
    bat \
    curl \
    less \
    ca-certificates \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Debian ships these under non-standard names; add the conventional aliases.
RUN ln -sf "$(command -v fdfind)" /usr/local/bin/fd && \
    ln -sf "$(command -v batcat)" /usr/local/bin/bat

WORKDIR /workspace

ENV CGO_ENABLED=0
ENV GOFLAGS=-buildvcs=false

CMD ["/bin/bash"]
