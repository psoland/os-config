# Python CUDA Template

Python + `uv` development shell template for GPU-enabled PyTorch on non-NixOS Linux.

This template exports `LD_LIBRARY_PATH` with Nix-provided `libstdc++.so.6` so `import torch` works with CUDA wheels.

## Quick Start

```bash
nix flake init -t github:psoland/os-config#python-cuda
echo "use flake" > .envrc
direnv allow
```

## Verify

```bash
uv sync
uv run python -c "import torch; print(torch.__version__); print(torch.version.cuda); print(torch.cuda.is_available())"
```
