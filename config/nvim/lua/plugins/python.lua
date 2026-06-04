-- Python LSP overrides
-- The lang.python extra is enabled in lazyvim.json; the LSP choice (ty + ruff)
-- is set in lua/config/options.lua. Here we only tell LazyVim not to install
-- ruff/ty via Mason, since they are provided by Nix (modules/nvim.nix).
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}

      opts.servers.ruff = opts.servers.ruff or {}
      opts.servers.ruff.mason = false

      opts.servers.ty = opts.servers.ty or {}
      opts.servers.ty.mason = false
    end,
  },
}
