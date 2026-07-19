-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.del("n", "<leader><tab><tab>")

vim.keymap.set("n", "<leader>uB", function()
  if vim.b.completion == false then
    vim.b.completion = nil
  else
    vim.b.completion = false
  end
  require("blink.cmp").hide()
  vim.notify("Completion " .. (vim.b.completion == false and "disabled" or "enabled") .. " for this buffer")
end, { desc = "Toggle Blink Completion" })
