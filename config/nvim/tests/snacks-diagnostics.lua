-- nvim --clean --headless -l config/nvim/tests/snacks-diagnostics.lua
local source = debug.getinfo(1, "S").source:sub(2)
local config_root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(source)))
vim.opt.runtimepath:prepend(config_root)

local passed = 0
local function test(name, callback)
  local ok, err = xpcall(callback, debug.traceback)
  if not ok then
    io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
    vim.cmd("cquit 1")
  end
  passed = passed + 1
  print("ok " .. name)
end

local snacks_path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "snacks.nvim")
assert(vim.uv.fs_stat(snacks_path), "These integration tests require the installed Snacks plugin")
vim.opt.runtimepath:append(snacks_path)
require("snacks")
local diagnostics = require("snacks.explorer.diagnostics")
local Tree = require("snacks.explorer.tree")
local fix = require("config.snacks-diagnostics")
local root = vim.fs.joinpath("/tmp/opencode", "snacks-diagnostics-test-" .. vim.uv.hrtime())
vim.fn.mkdir(vim.fs.joinpath(root, "nested"), "p")
local namespace = vim.api.nvim_create_namespace("snacks-diagnostics-tests")

local function buffer(path)
  local buf = vim.api.nvim_create_buf(false, true)
  if path then
    vim.api.nvim_buf_set_name(buf, path)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "text" })
  return buf
end

test("reproduce stale diagnostic buffer crash, then skip it without clearing caches", function()
  local live = buffer(vim.fs.joinpath(root, "shared.md"))
  local deleted = buffer()
  local shared = { { lnum = 0, col = 0, message = "Shared diagnostic", severity = vim.diagnostic.severity.ERROR } }
  vim.diagnostic.set(namespace, live, shared)
  vim.diagnostic.set(namespace, deleted, shared)
  vim.api.nvim_buf_delete(deleted, { force = true })
  assert(not vim.api.nvim_buf_is_valid(deleted))
  assert(vim.diagnostic.get(live)[1].bufnr == deleted)
  local ok, err = pcall(diagnostics.update, root)
  assert(not ok and err:match("Invalid buffer id"), "Expected the installed Snacks bug to reproduce")
  fix.setup()
  assert(diagnostics.update == fix.update)
  assert(type(diagnostics.update(root)) == "boolean")
  -- Skipping stale records must not erase a live buffer's diagnostic cache.
  assert(#vim.diagnostic.get(live) == 1)
  vim.api.nvim_buf_delete(live, { force = true })
end)

test("valid diagnostics still aggregate file, directory and project severities", function()
  local path = vim.fs.joinpath(root, "nested", "valid.md")
  local buf = buffer(path)
  vim.diagnostic.set(namespace, buf, {
    { lnum = 0, col = 0, message = "Warning", severity = vim.diagnostic.severity.WARN },
    { lnum = 0, col = 1, message = "Error", severity = vim.diagnostic.severity.ERROR },
  })
  assert(diagnostics.update(root))
  for _, node in ipairs({ Tree:find(path), Tree:find(vim.fs.dirname(path)), Tree:find(root) }) do
    assert(node.severity == vim.diagnostic.severity.ERROR)
  end
  assert(not diagnostics.update(root), "An unchanged diagnostic snapshot should not trigger another refresh")
  vim.diagnostic.reset(namespace, buf)
  assert(diagnostics.update(root))
  assert(Tree:find(path).severity == nil)
  assert(Tree:find(root).severity == nil)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("unnamed buffers do not contribute explorer diagnostics", function()
  local buf = buffer()
  vim.diagnostic.set(namespace, buf, { { lnum = 0, col = 0, message = "Scratch diagnostic" } })
  assert(not diagnostics.update(root))
  assert(Tree:find(root).severity == nil)
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("Snacks configuration installs the guard and preserves inherited options", function()
  _G.LazyVim = {
    pick = function()
      return function() end
    end,
  }
  local spec = require("plugins.snacks")[1]
  local opts = spec.opts(nil, {
    picker = { sources = { explorer = { diagnostics = true, follow_file = true } } },
    notifier = { enabled = true },
  })
  assert(opts.picker.sources.explorer.diagnostics)
  assert(opts.picker.sources.explorer.follow_file)
  assert(opts.picker.sources.explorer.hidden and opts.picker.sources.explorer.ignored)
  assert(opts.notifier.enabled)
  assert(opts.scroll.enabled == false)
  assert(opts.image.enabled)
  assert(diagnostics.update == fix.update)
end)

print(("snacks-diagnostics: %d tests passed"):format(passed))
vim.cmd("qa!")
