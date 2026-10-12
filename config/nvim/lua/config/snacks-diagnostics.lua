local M = {}

-- Local compatibility fix for snacks.explorer.diagnostics.update: Neovim can
-- retain diagnostic objects whose bufnr was changed to a subsequently wiped
-- buffer (for example, when a producer reuses diagnostic tables). Do not reset
-- diagnostic caches: the stale object may belong to a still-valid buffer's cache.
-- Keep this guard until upstream checks buffer validity before reading its name.
function M.update(cwd)
  local Tree = require("snacks.explorer.tree")
  local node = Tree:find(cwd)
  local snapshot = Tree:snapshot(node, { "severity" })
  Tree:walk(node, function(n)
    n.severity = nil
  end, { all = true })

  local function add(path, diag)
    local n = Tree:find(path)
    local severity = tonumber(diag.severity) or vim.diagnostic.severity.INFO
    n.severity = math.min(n.severity or severity, severity)
  end

  for _, diag in ipairs(vim.diagnostic.get()) do
    if diag.bufnr and vim.api.nvim_buf_is_valid(diag.bufnr) then
      local path = vim.api.nvim_buf_get_name(diag.bufnr)
      if path ~= "" then
        path = vim.fs.normalize(path)
        add(path, diag)
        add(cwd, diag)
        for dir in Snacks.picker.util.parents(path, cwd) do
          add(dir, diag)
        end
      end
    end
  end

  return Tree:changed(node, snapshot)
end

function M.setup()
  require("snacks.explorer.diagnostics").update = M.update
end

return M
