-- Nix language configuration
-- nil_ls, statix, and nixpkgs-fmt are provided via Nix (programs.neovim.extraPackages)
-- so we tell Mason not to install them
return {
  {
    "williamboman/mason-lspconfig.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      -- Remove nil_ls from ensure_installed since it's provided via Nix
      opts.ensure_installed = vim.tbl_filter(function(name)
        return name ~= "nil_ls"
      end, opts.ensure_installed)
    end,
  },
}
