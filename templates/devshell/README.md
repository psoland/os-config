# Development Shell Template

This is a Nix flake template for creating development shells.

## Quick Start

1. Initialize this template in your project:
   ```bash
   nix flake init -t github:psoland/os-config#devshell
   ```

2. Edit `flake.nix` to add your project's dependencies

3. Create `.envrc` for automatic environment loading:
   ```bash
   echo "use flake" > .envrc
   direnv allow
   ```

4. Enter the development shell:
   ```bash
   nix develop
   ```

## Available Shells

This template includes several pre-configured shells:

- `default` - Basic shell with common tools
- `node` - Node.js development
- `python` - Python development with virtualenv
- `go` - Go development
- `fullstack` - Example full-stack setup

Use a specific shell:
```bash
nix develop .#node
nix develop .#python
nix develop .#go
```

## Customization

### Adding Dependencies

Edit the `buildInputs` list in `flake.nix`:

```nix
buildInputs = with pkgs; [
  nodejs_20
  python312
  # Add more packages...
];
```

### Environment Variables

```nix
devShells.default = pkgs.mkShell {
  DATABASE_URL = "postgres://localhost/mydb";
  
  # Or in shellHook for dynamic values
  shellHook = ''
    export API_KEY="$(cat .api-key)"
  '';
};
```

### Shell Hook

The `shellHook` runs when entering the shell:

```nix
shellHook = ''
  echo "Welcome to the dev environment!"
  
  # Install dependencies
  npm install
  
  # Start services
  docker-compose up -d
'';
```

## Tips

### Finding Packages

Search for packages at https://search.nixos.org/packages

Or use the CLI:
```bash
nix search nixpkgs nodejs
```

### Updating Dependencies

```bash
nix flake update
```

### Checking the Flake

```bash
nix flake check
```

## Integration with IDEs

### VS Code
Install the "Nix Environment Selector" extension to automatically use the Nix environment.

### JetBrains IDEs
Configure the Nix SDK in Project Structure settings.

## Troubleshooting

### direnv not loading
```bash
direnv allow
```

### Package not found
Make sure you're using nixpkgs unstable for latest packages:
```nix
nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
```

### Unfree package error
Add to flake.nix:
```nix
pkgs = import nixpkgs {
  inherit system;
  config.allowUnfree = true;
};
```
