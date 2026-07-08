-- Nix language configuration
-- nil_ls, statix, and nixfmt are provided by Nix/Home Manager so Mason does not
-- need to install nil_ls, and Conform should use the same formatter as `nix fmt`.
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.nil_ls = opts.servers.nil_ls or {}
      -- mason = false tells LazyVim's LSP setup not to install nil_ls via Mason
      -- since it is provided by Nix via Home Manager.
      opts.servers.nil_ls.mason = false
    end,
  },
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.nix = { "nixfmt", lsp_format = "never" }
    end,
  },
}
