return {
  {
    name = "merman.nvim",
    dir = vim.fn.stdpath("config") .. "/local/merman.nvim",
    main = "merman",
    ft = { "markdown", "mermaid" },
    cmd = "MermaidPreview",
    init = function()
      vim.filetype.add({ extension = { mmd = "mermaid", mermaid = "mermaid" } })
      -- Snacks marks its own query as "extends", so a file override alone
      -- would still append its Mermaid pattern. Install an explicit query.
      local query = vim.api.nvim_get_runtime_file("queries/markdown/images.scm", false)[1]
      vim.treesitter.query.set("markdown", "images", table.concat(vim.fn.readfile(query), "\n"))
    end,
    opts = {},
    keys = {
      {
        "<leader>cm",
        "<cmd>MermaidPreview<cr>",
        ft = { "markdown", "mermaid" },
        desc = "Mermaid Preview",
      },
    },
  },
}
