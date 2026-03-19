-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Use OSC 52 clipboard provider for remote/SSH/tmux compatibility.
-- This ensures yanks reach the system clipboard through tmux and over SSH
-- without needing xclip/xsel on the remote machine.
vim.g.clipboard = {
  name = "OSC 52",
  copy = {
    ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
    ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
  },
  paste = {
    ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
    ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
  },
}

-- Force clipboard=unnamedplus even over SSH.
-- LazyVim disables this when $SSH_TTY is set, but our OSC 52 provider
-- handles clipboard correctly through SSH + tmux.
vim.opt.clipboard = "unnamedplus"
