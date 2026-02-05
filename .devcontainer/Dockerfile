FROM ubuntu:noble

# Install systemd and essential tools (minimum needed for Determinate Systems Nix installer)
RUN apt-get update && \
    apt-get install -y \
    systemd \
    sudo \
    curl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set systemd as the entrypoint
STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
