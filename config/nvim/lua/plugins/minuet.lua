if true then
  return {}
end

specs = {
  {
    "milanglacier/minuet-ai.nvim",
    config = function()
      require("minuet").setup({
        -- Your configuration options here
      })
    end,
  },
  -- optional, if you are using virtual-text frontend, nvim-cmp is not
  -- required.
  { "hrsh7th/nvim-cmp" },
  -- optional, if you are using virtual-text frontend, blink is not required.
  { "Saghen/blink.cmp" },
}
