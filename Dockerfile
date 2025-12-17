# Dockerfile for testing Nix configuration in Ubuntu environment
# This creates a containerized environment where you can safely test
# your Nix flake and home-manager configurations without affecting your host system.

FROM ubuntu:24.04

# Install system dependencies required for Nix and development
RUN apt-get update && apt-get install -y \
    curl \
    xz-utils \
    sudo \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create user 'psoland' with sudo privileges
RUN useradd -m -s /bin/bash psoland && \
    echo "psoland ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Nix in multi-user mode
# This is the recommended installation method
RUN curl -L https://nixos.org/nix/install > /tmp/install-nix.sh && \
    sh /tmp/install-nix.sh --daemon --yes && \
    rm /tmp/install-nix.sh

# Configure Nix to enable flakes and the nix command
RUN mkdir -p /etc/nix && \
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

# Set up the Nix environment for non-interactive shells
ENV PATH="/nix/var/nix/profiles/default/bin:${PATH}"

# Copy the entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Copy the entire repository to the user's home directory
COPY --chown=psoland:psoland . /home/psoland/os-config

# Switch to the psoland user
USER psoland
WORKDIR /home/psoland/os-config

# Use the entrypoint script to start Nix daemon
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Default command opens a bash shell
# From here, you can run commands like:
#   nix flake check
#   nix build .#homeConfigurations.psoland.activationPackage
#   home-manager switch --flake .#psoland
CMD ["/bin/bash"]
