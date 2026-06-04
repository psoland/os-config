vim.g.lazyvim_ts_lsp = "vtsls"

return {
  { import = "lazyvim.plugins.extras.lang.typescript" },
  { import = "lazyvim.plugins.extras.linting.eslint" },
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
