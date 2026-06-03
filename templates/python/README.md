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

- `default` - Python + `uv` + lint/type tools, with Linux runtime libraries for native PyPI wheels
- `cuda` - Same as default, plus Linux-only runtime setup (Ubuntu-friendly paths) that preloads host `libcuda.so.1` for CUDA-enabled PyTorch wheels

## Included Tools

- `python312`
- `uv`
- `ruff`
- `ty`
- `just`

## Native Wheels on Linux

The Linux shells expose Nix runtime libraries so packages installed with `uv` from PyPI, such as `numpy` and `torch`, can load native extensions that need libraries like `libstdc++.so.6` and `libz.so.1`.

This is intentionally scoped to the dev shell instead of setting a global `LD_LIBRARY_PATH`.
