local M = {}

local defaults = {
  context_chars = 128,
  storage_dir = ".document-comments",
  root = nil,
  highlight_priority = 180,
  highlights = {
    open = { link = "Visual" },
    resolved = { link = "Comment" },
  },
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  opts = opts or {}
  vim.validate({
    context_chars = { opts.context_chars, "number", true },
    storage_dir = { opts.storage_dir, "string", true },
    root = { opts.root, "function", true },
    highlight_priority = { opts.highlight_priority, "number", true },
    highlights = { opts.highlights, "table", true },
  })
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  if M.options.context_chars < 0 or M.options.context_chars > 128 or M.options.context_chars % 1 ~= 0 then
    error("document-comments: context_chars must be an integer between 0 and 128")
  end
  if M.options.storage_dir == "" or M.options.storage_dir:find("[/\\]") then
    error("document-comments: storage_dir must be a directory name")
  end
  return M.options
end

return M
