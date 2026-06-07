FROM golang:1.22-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    iproute2 \
    iputils-ping \
    tcpdump \
    tshark \
    netcat-openbsd \
    python3 \
    curl \
    vim \
    less \
    sudo \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

ENV CGO_ENABLED=0
ENV GOFLAGS=-buildvcs=false

CMD ["/bin/bash"]
