local config = require("document_comments.config")
local model = require("document_comments.model")
local presentation = require("document_comments.presentation")
local root = require("document_comments.root")
local select_ui = require("document_comments.ui.select")
local storage = require("document_comments.storage")

local M = {}
local state
local namespace = vim.api.nvim_create_namespace("document-comments-sidebar")
local preview_namespace = vim.api.nvim_create_namespace("document-comments-preview")
local filters = { "open", "resolved", "review", "new", "all" }
local window_options = { "winfixwidth", "wrap", "linebreak", "number", "relativenumber", "signcolumn", "foldcolumn" }

local function source_options(window)
  local result = {}
  for _, option in ipairs(window_options) do
    result[option] = vim.wo[window][option]
  end
  return result
end

local function clear_preview()
  if state and state.preview_buffer and vim.api.nvim_buf_is_valid(state.preview_buffer) then
    vim.api.nvim_buf_clear_namespace(state.preview_buffer, preview_namespace, 0, -1)
    state.preview_buffer = nil
  end
end

local function selected()
  if not state or not vim.api.nvim_win_is_valid(state.window) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(state.window)[1]
  for _, entry in ipairs(state.entries) do
    if row >= entry.first and row <= entry.last then
      return entry.comment
    end
  end
end

local function preview()
  clear_preview()
  local comment = selected()
  if not comment or comment.anchor.state ~= "attached" or not vim.api.nvim_win_is_valid(state.source_window) then
    return
  end
  local buffer = vim.api.nvim_win_get_buf(state.source_window)
  local ctx = root.for_buffer(buffer)
  if not ctx or ctx.store_path ~= state.ctx.store_path or ctx.source_path ~= comment.source.path then
    return
  end
  local extmarks = require("document_comments.extmarks")
  local position = extmarks.comment_position(buffer, comment)
  local line_count = vim.api.nvim_buf_line_count(buffer)
  if not position or position[1] >= line_count or position[3].end_row >= line_count then
    return
  end
  vim.api.nvim_buf_set_extmark(buffer, preview_namespace, position[1], position[2], {
    end_row = position[3].end_row,
    end_col = position[3].end_col,
    hl_group = "Search",
    priority = config.options.highlight_priority + 10,
    strict = false,
  })
  state.preview_buffer = buffer
end

local function matches(comment, fingerprints)
  if state.scope == "file" and comment.source.path ~= state.ctx.source_path then
    return false
  end
  if state.filter == "review" then
    return presentation.needs_review(comment)
  elseif state.filter == "new" then
    return model.is_pending(comment, fingerprints)
  end
  return state.filter == "all" or comment.status == state.filter
end

function M.refresh(ctx)
  if not state or not vim.api.nvim_win_is_valid(state.window) or not vim.api.nvim_buf_is_valid(state.buffer) then
    return
  end
  if ctx and ctx.store_path ~= state.ctx.store_path then
    return
  end
  -- Follow normal document windows in this project, never drafts, floats or the sidebar.
  local current_buffer = vim.api.nvim_get_current_buf()
  if ctx and vim.bo[current_buffer].buftype == "" and vim.bo[current_buffer].filetype == "markdown" then
    local current_ctx = root.for_buffer(current_buffer)
    if current_ctx and current_ctx.store_path == ctx.store_path then
      state.ctx = current_ctx
      state.source_window = vim.api.nvim_get_current_win()
      state.source_buffer = current_buffer
      state.source_options = source_options(state.source_window)
    end
  end
  local previous = selected()
  local store, err = storage.load(state.ctx)
  local comments, pending = {}, 0
  local fingerprints = store and model.exported_fingerprints(store) or {}
  for _, comment in ipairs(store and store.comments or {}) do
    if
      (state.scope == "project" or comment.source.path == state.ctx.source_path)
      and model.is_pending(comment, fingerprints)
    then
      pending = pending + 1
    end
    if matches(comment, fingerprints) then
      table.insert(comments, comment)
    end
  end
  table.sort(comments, function(left, right)
    if left.source.path ~= right.source.path then
      return left.source.path < right.source.path
    end
    local a, b = left.anchor.current.position.start, right.anchor.current.position.start
    if a.line ~= b.line then
      return a.line < b.line
    end
    if a.byte_column ~= b.byte_column then
      return a.byte_column < b.byte_column
    end
    return left.id < right.id
  end)
  local lines = {
    "Document annotations — " .. vim.fs.basename(state.ctx.root),
    ("%s · %s · %d shown · %d new/edited · ? help"):format(state.scope, state.filter, #comments, pending),
    "",
  }
  local entries = {}
  local formatter = state.scope == "project" and select_ui.project_formatter(comments) or select_ui.format_file
  for _, comment in ipairs(comments) do
    local entry = { comment = comment, first = #lines + 1 }
    table.insert(lines, formatter(comment))
    local exported = fingerprints[comment.id]
    local coverage = exported == model.feedback_fingerprint(comment) and "exported"
      or (exported and "edited since export" or "not exported")
    table.insert(lines, ("  @%s · %s · %s"):format(comment.id, model.kind_labels[model.kind(comment)], coverage))
    table.insert(lines, "  Selected text:")
    for _, line in ipairs(vim.split(comment.anchor.current.quote.exact, "\n", { plain = true })) do
      table.insert(lines, "  > " .. line)
    end
    table.insert(lines, "  Feedback:")
    local body = comment.body
    if vim.trim(body) == "" then
      body = model.kind(comment) == "delete" and "Remove this text." or "Looks good."
    end
    for _, line in ipairs(vim.split(body, "\n", { plain = true })) do
      table.insert(lines, "  " .. line)
    end
    table.insert(lines, "")
    entry.last = #lines
    table.insert(entries, entry)
  end
  if not store then
    table.insert(lines, "Store error: " .. err)
  elseif #comments == 0 then
    table.insert(lines, "No annotations match this filter.")
  end
  state.entries = entries
  vim.bo[state.buffer].modifiable = true
  vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
  vim.bo[state.buffer].modifiable = false
  vim.bo[state.buffer].modified = false
  vim.api.nvim_buf_clear_namespace(state.buffer, namespace, 0, -1)
  for _, entry in ipairs(entries) do
    vim.api.nvim_buf_set_extmark(state.buffer, namespace, entry.first - 1, 0, {
      line_hl_group = presentation.needs_review(entry.comment) and "DiagnosticWarn" or "Title",
    })
  end
  local row = entries[1] and entries[1].first or #lines
  for _, entry in ipairs(entries) do
    if previous and entry.comment.id == previous.id then
      row = entry.first
      break
    end
  end
  vim.api.nvim_win_set_cursor(state.window, { row, 0 })
  preview()
end

function M.set_filter(filter)
  if not state or not vim.list_contains(filters, filter) then
    return
  end
  state.filter = filter
  M.refresh()
end

function M.set_scope(scope)
  if not state or (scope ~= "file" and scope ~= "project") then
    return
  end
  state.scope = scope
  M.refresh()
end

local function navigate(direction)
  if not state or #state.entries == 0 then
    return
  end
  local row = vim.api.nvim_win_get_cursor(state.window)[1]
  local index = direction > 0 and 1 or #state.entries
  if direction > 0 then
    for i, entry in ipairs(state.entries) do
      if entry.first > row then
        index = i
        break
      end
    end
  else
    for i = #state.entries, 1, -1 do
      if state.entries[i].first < row then
        index = i
        break
      end
    end
  end
  vim.api.nvim_win_set_cursor(state.window, { state.entries[index].first, 0 })
  preview()
end

local function act(action)
  local comment = selected()
  if not comment or not vim.api.nvim_win_is_valid(state.source_window) then
    return
  end
  local panel_window = state.window
  local ctx = state.ctx
  vim.api.nvim_set_current_win(state.source_window)
  require("document_comments.commands").perform(action, comment, ctx, vim.api.nvim_get_current_buf(), function()
    if state and state.window == panel_window and vim.api.nvim_win_is_valid(panel_window) then
      vim.api.nvim_set_current_win(panel_window)
    end
  end)
end

local function export(mode)
  if not state or not vim.api.nvim_win_is_valid(state.source_window) then
    vim.notify("Open a source document window before exporting", vim.log.levels.WARN, { title = "Document comments" })
    return
  end
  local panel_window = state.window
  local scope = state.scope
  vim.api.nvim_set_current_win(state.source_window)
  require("document_comments.commands").export(mode .. " " .. scope)
  if vim.api.nvim_win_is_valid(panel_window) then
    vim.api.nvim_set_current_win(panel_window)
  end
end

function M.check_external_change()
  if not state or vim.api.nvim_get_current_buf() ~= state.buffer then
    return
  end
  local changed, err = storage.changed(state.ctx)
  if changed == nil then
    vim.notify(err, vim.log.levels.ERROR, { title = "Document comments" })
    return
  end
  if changed and not require("document_comments.ui.editor").has_draft(state.ctx.root) then
    storage.reload(state.ctx)
    M.refresh()
  end
end

function M.batches(ctx)
  local store, err = storage.load(ctx)
  if not store then
    vim.notify(err, vim.log.levels.ERROR, { title = "Document comments" })
    return
  end
  local batches = {}
  for index = #store.export_batches, 1, -1 do
    table.insert(batches, store.export_batches[index])
  end
  if #batches == 0 then
    vim.notify("No document comment export batches", vim.log.levels.INFO, { title = "Document comments" })
    return
  end
  vim.ui.select(batches, {
    prompt = "Export batches (exported is not sent or resolved)",
    format_item = function(batch)
      return ("%s · %s %s · %d annotations · %s"):format(
        batch.exported_at,
        batch.mode,
        batch.scope,
        #batch.comments,
        batch.id
      )
    end,
  }, function(batch)
    if not batch then
      return
    end
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[buffer].bufhidden = "wipe"
    vim.api.nvim_buf_set_name(buffer, "document-comments://batch/" .. batch.id .. "/" .. vim.uv.hrtime())
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(batch.markdown, "\n", { plain = true }))
    vim.bo[buffer].filetype = "markdown"
    vim.bo[buffer].modifiable = false
    vim.bo[buffer].modified = false
    local width = math.max(20, math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.85)))
    local height = math.max(4, math.min(vim.o.lines - 4, math.floor(vim.o.lines * 0.8)))
    local window = vim.api.nvim_open_win(buffer, true, {
      relative = "editor",
      style = "minimal",
      border = "rounded",
      title = " Export batch " .. batch.id .. " ",
      title_pos = "center",
      width = width,
      height = height,
      row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    })
    vim.wo[window].wrap = true
    vim.keymap.set("n", "q", function()
      vim.api.nvim_win_close(window, true)
    end, { buffer = buffer })
    vim.keymap.set("n", "<Esc>", function()
      vim.api.nvim_win_close(window, true)
    end, { buffer = buffer })
  end)
end

function M.help()
  if not state or not vim.api.nvim_win_is_valid(state.window) then
    return
  end
  if state.help_window and vim.api.nvim_win_is_valid(state.help_window) then
    vim.api.nvim_set_current_win(state.help_window)
    return
  end
  local lines = {
    "Navigation",
    "  j / k       Next / previous annotation",
    "  Arrow keys  Move within long notes",
    "  Enter       Jump to source",
    "",
    "Annotation actions",
    "  e           Edit note",
    "  r           Resolve / reopen",
    "  t           Change annotation type",
    "  a           Choose annotation for reattachment",
    "              Select replacement text, then <leader>aR",
    "  d           Permanently delete (with confirmation)",
    "  y           Copy stable ID",
    "  ] / [       Open references / backlinks",
    "",
    "Views and exports",
    "  f           Filter: open, resolved, review, new, all",
    "  p           Toggle file / project scope",
    "  x / X       Export new/edited / all open annotations",
    "  B           Browse export batches",
    "  q           Close sidebar",
    "",
    "Exported does not mean sent or resolved.",
    "? / q / Esc close this help popup.",
  }
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].filetype = "document_comments_help"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false
  vim.bo[buffer].modified = false
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.max(1, math.min(width, vim.o.columns - 4))
  local height = math.max(1, math.min(#lines, vim.o.lines - 4))
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = " Annotation sidebar help ",
    title_pos = "center",
    footer = " ? / q / Esc close ",
    footer_pos = "center",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  })
  state.help_window = window
  vim.wo[window].wrap = true
  vim.wo[window].linebreak = true
  for _, key in ipairs({ "?", "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_close(window, true)
      end
    end, { buffer = buffer, nowait = true, desc = "Close annotation help" })
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buffer,
    once = true,
    callback = function()
      if state and state.help_window == window then
        state.help_window = nil
      end
    end,
  })
end

function M.close()
  if not state then
    return
  end
  clear_preview()
  local window = state.window
  local source_buffer = state.source_buffer
  local options = state.source_options
  local help_window = state.help_window
  state = nil
  if help_window and vim.api.nvim_win_is_valid(help_window) then
    vim.api.nvim_win_close(help_window, true)
  end
  if vim.api.nvim_win_is_valid(window) then
    if #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(window)) == 1 then
      -- The source window may have been closed. Never try to close the last window.
      vim.api.nvim_win_set_buf(
        window,
        vim.api.nvim_buf_is_valid(source_buffer) and source_buffer or vim.api.nvim_create_buf(true, false)
      )
      for option, value in pairs(options) do
        vim.wo[window][option] = value
      end
    else
      vim.api.nvim_win_close(window, true)
    end
  end
end

function M.toggle()
  if state and vim.api.nvim_win_is_valid(state.window) then
    M.close()
    return
  end
  local ctx, err = root.for_buffer(0)
  if vim.bo.filetype ~= "markdown" or vim.bo.buftype ~= "" or not ctx then
    vim.notify(err or "Open the sidebar from a Markdown file", vim.log.levels.ERROR, { title = "Document comments" })
    return
  end
  local source_window = vim.api.nvim_get_current_win()
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].filetype = "document_comments"
  vim.bo[buffer].swapfile = false
  vim.cmd("botright vsplit")
  local window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(window, buffer)
  vim.api.nvim_win_set_width(window, config.options.sidebar.width)
  vim.wo[window].winfixwidth = true
  vim.wo[window].wrap = true
  vim.wo[window].linebreak = true
  vim.wo[window].number = false
  vim.wo[window].relativenumber = false
  vim.wo[window].signcolumn = "no"
  vim.wo[window].foldcolumn = "0"
  state = {
    ctx = ctx,
    buffer = buffer,
    window = window,
    source_window = source_window,
    source_buffer = vim.api.nvim_win_get_buf(source_window),
    source_options = source_options(source_window),
    filter = "open",
    scope = "file",
    entries = {},
  }
  local function map(key, callback, desc)
    vim.keymap.set("n", key, callback, { buffer = buffer, desc = desc, nowait = true })
  end
  map("q", M.close, "Close annotation sidebar")
  map("?", M.help, "Annotation sidebar help")
  map("j", function()
    navigate(1)
  end, "Next annotation")
  map("k", function()
    navigate(-1)
  end, "Previous annotation")
  for key, action in pairs({
    ["<CR>"] = "jump",
    e = "edit",
    r = "resolve",
    d = "delete",
    t = "type",
    a = "reattach",
    y = "copy",
    ["]"] = "references",
    ["["] = "backlinks",
  }) do
    map(key, function()
      act(action)
    end, "Annotation: " .. action)
  end
  map("f", function()
    vim.ui.select(filters, { prompt = "Annotation filter" }, M.set_filter)
  end, "Filter annotations")
  map("p", function()
    M.set_scope(state.scope == "file" and "project" or "file")
  end, "Toggle file/project scope")
  map("x", function()
    export("new")
  end, "Export new/edited annotations")
  map("X", function()
    export("all")
  end, "Export all open annotations")
  map("B", function()
    M.batches(state.ctx)
  end, "View export batches")
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buffer,
    callback = function()
      if state and state.buffer == buffer then
        preview()
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buffer,
    callback = M.check_external_change,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buffer,
    once = true,
    callback = function()
      if state and state.buffer == buffer then
        clear_preview()
        local help_window = state.help_window
        state = nil
        if help_window and vim.api.nvim_win_is_valid(help_window) then
          vim.api.nvim_win_close(help_window, true)
        end
      end
    end,
  })
  M.refresh()
end

return M
