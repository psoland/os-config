# os-config justfile
# Inspired by ironicbadger/nix-config

default: switch

user := "psoland"
host := "oracle-vm"
config := user + "@" + host

# Build the home-manager configuration without switching
build:
    nix build .#homeConfigurations.{{config}}.activationPackage

# Build and activate the configuration
switch:
    home-manager switch --flake .#{{config}}

# Show what would change without applying
dry-run:
    home-manager build --flake .#{{config}}

# Validate the flake
check:
    nix flake check

# Update all flake inputs
update:
    nix flake update

# Update a specific input
update-input input:
    nix flake update {{input}}

# Format nix files
fmt:
    nixpkgs-fmt .

# Garbage collect old generations
gc:
    nix-collect-garbage -d
    nix-store --gc

# Enter dev shell for working on this config
dev:
    nix develop

# Docker: build test image
docker-build:
    docker build -t os-config-test -f docker/Dockerfile .

# Docker: run interactive test container
docker-run:
    docker run -it --rm os-config-test

# Docker: test full bootstrap in container
docker-test:
    docker run -it --rm os-config-test bash -c '\
        cd ~/os-config && \
        ./bootstrap.sh && \
        exec zsh'
