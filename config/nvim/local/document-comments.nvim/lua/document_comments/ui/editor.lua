local M = {}

local namespace = vim.api.nvim_create_namespace("document-comments-editor")
local drafts = {}

local function body_lines(body)
  if not body or body == "" then
    return { "" }
  end
  return vim.split(body, "\n", { plain = true })
end

function M.open(opts)
  vim.validate({
    id = { opts.id, "string" },
    body = { opts.body, "string", true },
    root = { opts.root, "string" },
    title = { opts.title, "string", true },
    save = { opts.save, "function" },
  })
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].buftype = "acwrite"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "markdown"
  vim.api.nvim_buf_set_name(buffer, "document-comment://" .. opts.id)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, body_lines(opts.body))
  vim.api.nvim_buf_set_extmark(buffer, namespace, math.max(0, vim.api.nvim_buf_line_count(buffer) - 1), 0, {
    virt_lines = { { { "  :w save  ·  :q cancel (unconfirmed drafts are not crash-recovered)", "Comment" } } },
    virt_lines_above = false,
  })
  vim.bo[buffer].modified = false

  local width = math.min(math.max(52, math.floor(vim.o.columns * 0.62)), math.max(20, vim.o.columns - 4))
  local height = math.min(math.max(8, math.floor(vim.o.lines * 0.35)), math.max(4, vim.o.lines - 4))
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = opts.title or " Document comment ",
    title_pos = "center",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
  })
  vim.wo[window].wrap = true
  vim.wo[window].linebreak = true
  drafts[buffer] = { root = opts.root, window = window }

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buffer,
    callback = function()
      local body = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
      if vim.trim(body) == "" then
        vim.notify("A document comment cannot be empty", vim.log.levels.ERROR, { title = "Document comments" })
        return
      end
      local ok, err = opts.save(body)
      if not ok then
        vim.notify(err or "Could not save document comment", vim.log.levels.ERROR, { title = "Document comments" })
        return
      end
      vim.bo[buffer].modified = false
      drafts[buffer] = nil
      if vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_close(window, true)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buffer,
    once = true,
    callback = function()
      drafts[buffer] = nil
    end,
  })
  vim.cmd("startinsert")
  return buffer, window
end

function M.has_draft(root)
  for buffer, draft in pairs(drafts) do
    if draft.root == root and vim.api.nvim_buf_is_valid(buffer) then
      return true
    end
  end
  return false
end

return M
