-- TypeScript LSP overrides
-- The lang.typescript and linting.eslint extras are enabled in lazyvim.json.
-- vtsls is already LazyVim's default TS LSP, so no vim.g switch is needed.
-- Here we only tell LazyVim not to install vtsls/eslint via Mason, since they
-- are provided by Nix (modules/home/programs/nvim.nix).
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}

      opts.servers.vtsls = opts.servers.vtsls or {}
      opts.servers.vtsls.mason = false

      opts.servers.eslint = opts.servers.eslint or {}
      opts.servers.eslint.mason = false
    end,
  },
}
