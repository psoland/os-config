local M = {}

local group
local prompting_reload = {}

local function notify_error(message)
  vim.notify(message, vim.log.levels.ERROR, { title = "Document comments" })
end

local function map_buffer(bufnr)
  local commands = require("document_comments.commands")
  local mappings = {
    { "x", "<leader>aa", commands.add, "Add document comment" },
    {
      "n",
      "<leader>al",
      function()
        commands.list("open")
      end,
      "List document comments",
    },
    { "n", "<leader>ae", commands.edit, "Edit document comment" },
    { "n", "<leader>ar", commands.resolve, "Resolve/reopen document comment" },
    { "n", "<leader>an", commands.next, "Next document comment" },
    { "n", "<leader>ap", commands.prev, "Previous document comment" },
    { "x", "<leader>aR", commands.reattach, "Reattach document comment" },
    {
      "n",
      "<leader>ax",
      function()
        commands.export("project")
      end,
      "Export document comments",
    },
    { "n", "<leader>ad", commands.delete, "Delete document comment" },
  }
  for _, mapping in ipairs(mappings) do
    vim.keymap.set(mapping[1], mapping[2], mapping[3], { buffer = bufnr, desc = mapping[4] })
  end
end

local function check_external_change(bufnr)
  local editor = require("document_comments.ui.editor")
  local extmarks = require("document_comments.extmarks")
  local root = require("document_comments.root")
  local storage = require("document_comments.storage")
  local ctx = root.for_buffer(bufnr)
  if not ctx then
    return
  end
  local changed, err = storage.changed(ctx)
  if changed == nil then
    notify_error(tostring(err))
    return
  end
  if not changed then
    return
  end
  if not editor.has_draft(ctx.root) then
    local reloaded, reload_error = storage.reload(ctx)
    if not reloaded then
      notify_error(reload_error)
      return
    end
    extmarks.refresh(bufnr)
    return
  end
  if prompting_reload[ctx.root] then
    return
  end
  prompting_reload[ctx.root] = true
  vim.ui.select({ "Keep draft", "Reload store" }, {
    prompt = "The document comment store changed in another process",
  }, function(choice)
    prompting_reload[ctx.root] = nil
    if choice == "Reload store" then
      local reloaded, reload_error = storage.reload(ctx)
      if not reloaded then
        notify_error(reload_error)
      else
        extmarks.refresh(bufnr)
      end
    end
  end)
end

local function attach_buffer(bufnr)
  if vim.bo[bufnr].buftype ~= "" or vim.api.nvim_buf_get_name(bufnr):match("^document%-comment://") then
    return
  end
  if vim.b[bufnr].document_comments_attached then
    return
  end
  vim.b[bufnr].document_comments_attached = true
  map_buffer(bufnr)
  require("document_comments.extmarks").attach(bufnr)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    buffer = bufnr,
    callback = function()
      require("document_comments.extmarks").sync_on_write(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    buffer = bufnr,
    callback = function()
      check_external_change(bufnr)
      require("document_comments.extmarks").refresh(bufnr, { quiet = true })
    end,
  })
end

function M.setup(opts)
  require("document_comments.config").setup(opts)
  require("document_comments.extmarks").setup_highlights()
  require("document_comments.commands").register()
  group = vim.api.nvim_create_augroup("document-comments", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "markdown",
    callback = function(event)
      attach_buffer(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if vim.bo[bufnr].filetype == "markdown" then
        check_external_change(bufnr)
      end
    end,
  })
  if vim.bo.filetype == "markdown" then
    attach_buffer(vim.api.nvim_get_current_buf())
  end
  local ok, which_key = pcall(require, "which-key")
  if ok then
    which_key.add({ { "<leader>a", group = "annotations" } })
  end
end

return M
