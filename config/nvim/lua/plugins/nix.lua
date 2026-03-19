-- Nix language configuration
-- nil_ls, statix, and nixpkgs-fmt are provided via Nix (programs.neovim.extraPackages)
-- so we tell Mason not to install them
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.nil_ls = opts.servers.nil_ls or {}
      -- mason = false tells LazyVim's LSP setup not to install nil_ls via Mason
      -- since it is provided by Nix via programs.neovim.extraPackages
      opts.servers.nil_ls.mason = false
    end,
  },
}
