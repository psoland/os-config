-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.del("n", "<leader><tab><tab>")

vim.keymap.del("n", "<leader>ub")
Snacks.toggle.option("background", { off = "light", on = "dark", name = "Dark Background" }):map("<leader>uB")

Snacks.toggle({
  id = "blink_completion",
  name = "Blink Completion",
  get = function()
    return vim.b.completion ~= false
  end,
  set = function(enabled)
    if enabled then
      vim.b.completion = nil
    else
      vim.b.completion = false
    end
    require("blink.cmp").hide()
  end,
}):map("<leader>ub")
