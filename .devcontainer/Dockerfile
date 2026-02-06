# Ubuntu 24.04 (Noble) - Matches Oracle Cloud Ubuntu VM with psoland user
# This container provides an Ubuntu environment with both ubuntu and psoland users
FROM ubuntu:noble

# Install packages needed for bootstrap and SSH testing
RUN apt-get update && \
    apt-get install -y \
    systemd \
    systemd-sysv \
    sudo \
    curl \
    wget \
    ca-certificates \
    locales \
    lsb-release \
    openssh-server \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Generate locale (matches typical Ubuntu server)
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Ensure ubuntu user has proper shell and sudo (matches Oracle Cloud default)
RUN usermod -s /bin/bash ubuntu && \
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/ubuntu && \
    chmod 0440 /etc/sudoers.d/ubuntu

# Create psoland user for SSH access
RUN useradd -m -s /bin/bash -u 1001 psoland && \
    echo "psoland ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/psoland && \
    chmod 0440 /etc/sudoers.d/psoland

# Create necessary directories for systemd user services
RUN mkdir -p /run/user/1000 && \
    chown ubuntu:ubuntu /run/user/1000 && \
    chmod 700 /run/user/1000 && \
    mkdir -p /run/user/1001 && \
    chown psoland:psoland /run/user/1001 && \
    chmod 700 /run/user/1001

# Enable lingering for user services
RUN mkdir -p /var/lib/systemd/linger && \
    touch /var/lib/systemd/linger/ubuntu && \
    touch /var/lib/systemd/linger/psoland

# Set systemd as the entrypoint
STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
