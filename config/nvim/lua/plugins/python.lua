vim.g.lazyvim_python_lsp = "ty"
vim.g.lazyvim_python_ruff = "ruff"

return {
  { import = "lazyvim.plugins.extras.lang.python" },
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
