# Python Template

Python + `uv` development shell template, with optional CUDA shell.

## Quick Start

```bash
nix flake init -t github:psoland/os-config#python
echo "use flake" > .envrc
direnv allow
```

Use CUDA shell:

```bash
echo "use flake .#cuda" > .envrc
direnv allow
```

## Available Shells

- `default` - Python + `uv` + lint/type tools
- `cuda` - Same as default, plus Linux-only runtime setup that preloads host `libcuda.so.1` for CUDA-enabled PyTorch wheels

## Included Tools

- `python312`
- `uv`
- `ruff`
- `ty`
- `just`
