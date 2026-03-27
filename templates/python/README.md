# Python Template

Python + `uv` development shell template.

## Quick Start

```bash
nix flake init -t github:psoland/os-config#python
echo "use flake" > .envrc
direnv allow
```

## Included Tools

- `python312`
- `uv`
- `ruff`
- `ty`
- `just`
