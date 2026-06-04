-- Formatting configuration
-- prettier is provided via Nix (modules/nvim.nix home.packages) so we do NOT
-- import LazyVim's prettier extra (which would add a Mason ensure_installed).
-- require_cwd = false lets prettier format standalone files without a project config.
return {
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      for _, ft in ipairs({
        "css",
        "graphql",
        "html",
        "javascript",
        "javascriptreact",
        "json",
        "jsonc",
        "less",
        "markdown",
        "scss",
        "typescript",
        "typescriptreact",
        "vue",
        "yaml",
      }) do
        opts.formatters_by_ft[ft] = { "prettier" }
      end

      opts.formatters = opts.formatters or {}
      opts.formatters.prettier = opts.formatters.prettier or {}
      opts.formatters.prettier.require_cwd = false
    end,
  },
}
