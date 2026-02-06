# Ubuntu 24.04 test environment matching Oracle Cloud
FROM ubuntu:24.04

# Minimal packages needed for Nix installation
RUN apt-get update && apt-get install -y \
    curl \
    git \
    sudo \
    xz-utils \
    locales \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Create psoland user (matching Oracle Cloud setup)
RUN useradd -m -s /bin/bash -u 1000 psoland \
    && echo "psoland ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/psoland \
    && chmod 0440 /etc/sudoers.d/psoland

USER psoland
WORKDIR /home/psoland

# Copy the config for testing
COPY --chown=psoland:psoland . /home/psoland/os-config

CMD ["/bin/bash"]
