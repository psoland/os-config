# Ubuntu 24.04 (Noble) - Matches Oracle Cloud Ubuntu VM
# This container provides a clean Ubuntu environment to test the bootstrap script
FROM ubuntu:noble

# Install only the absolute minimum needed for a fresh Ubuntu VM
# This mirrors what you'd have on a fresh cloud VM
RUN apt-get update && \
    apt-get install -y \
    systemd \
    systemd-sysv \
    sudo \
    curl \
    wget \
    ca-certificates \
    locales \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Generate locale (matches typical Ubuntu server)
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create user 'psoland' to match your actual server setup
# UID 1000 is typical for first non-root user on Ubuntu
RUN useradd -m -s /bin/bash -u 1000 psoland && \
    echo "psoland ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/psoland && \
    chmod 0440 /etc/sudoers.d/psoland

# Create necessary directories for systemd user services
RUN mkdir -p /run/user/1000 && \
    chown psoland:psoland /run/user/1000 && \
    chmod 700 /run/user/1000

# Enable lingering for user services (like syncthing)
RUN mkdir -p /var/lib/systemd/linger && \
    touch /var/lib/systemd/linger/psoland

# Set XDG_RUNTIME_DIR for user services
ENV XDG_RUNTIME_DIR=/run/user/1000

# Set systemd as the entrypoint
STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
