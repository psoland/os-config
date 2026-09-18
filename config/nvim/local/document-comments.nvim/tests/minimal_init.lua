local source = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(source)))
vim.opt.runtimepath:prepend(plugin_root)
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.g.mapleader = " "
