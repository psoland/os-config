-- Mojo language configuration
-- mojo-lsp-server is provided by Modular's toolchain via pixi/conda,
-- not available in Mason, so we tell Mason not to try to install it
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.mojo = opts.servers.mojo or {}
      -- mason = false tells LazyVim's LSP setup not to install mojo-lsp-server via Mason
      -- it is provided by the Mojo toolchain (pixi/conda from conda.modular.com)
      opts.servers.mojo.mason = false
      opts.servers.mojo.cmd = { "mojo-lsp-server", "-I", "." }

      -- Format on save for .mojo files via LSP
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.mojo",
        callback = function()
          local clients = vim.lsp.get_clients({ bufnr = 0, name = "mojo" })
          if #clients > 0 and clients[1].supports_method("textDocument/formatting") then
            vim.lsp.buf.format({ async = false })
          end
        end,
      })
    end,
  },
}
