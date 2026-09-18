return {
  {
    name = "document-comments.nvim",
    dir = vim.fn.stdpath("config") .. "/local/document-comments.nvim",
    main = "document_comments",
    ft = "markdown",
    opts = {},
  },
  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, 1, {
        function()
          return require("document_comments").statusline()
        end,
        cond = function()
          return vim.bo.filetype == "markdown"
        end,
      })
    end,
  },
}
