# Dev Container Dockerfile for Nix Configuration Development
# This provides a full development environment with Nix, Git, and dev tools
# The workspace is mounted from the host, so all changes persist

FROM ubuntu:24.04

# Avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    xz-utils \
    sudo \
    git \
    ca-certificates \
    zsh \
    vim \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create user 'psoland' with sudo privileges
# UID 1000 is common and helps with file permissions when mounting volumes
RUN useradd -m -s /bin/zsh -u 1000 psoland && \
    echo "psoland ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Nix in multi-user mode
RUN curl -L https://nixos.org/nix/install > /tmp/install-nix.sh && \
    sh /tmp/install-nix.sh --daemon --yes && \
    rm /tmp/install-nix.sh

# Configure Nix to enable flakes and the nix command
RUN mkdir -p /etc/nix && \
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf && \
    echo "keep-outputs = true" >> /etc/nix/nix.conf && \
    echo "keep-derivations = true" >> /etc/nix/nix.conf

# Set up Nix environment
ENV PATH="/nix/var/nix/profiles/default/bin:${PATH}"

# Create workspace directory
RUN mkdir -p /workspace && chown psoland:psoland /workspace

# Switch to user
USER psoland
WORKDIR /workspace

# Set up zsh for the user (will use Nix-managed zsh config later)
RUN echo 'if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then' >> ~/.zshrc && \
    echo '  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' >> ~/.zshrc && \
    echo 'fi' >> ~/.zshrc

# Default command
CMD ["/bin/zsh"]
