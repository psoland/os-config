local anchor = require("document_comments.anchor")
local config = require("document_comments.config")
local model = require("document_comments.model")
local root = require("document_comments.root")
local storage = require("document_comments.storage")

local M = {}

M.namespace = vim.api.nvim_create_namespace("document-comments")
local buffers = {}

local function notify_error(message)
  vim.notify(message, vim.log.levels.ERROR, { title = "Document comments" })
end

local function same_position(left, right)
  return left.start.line == right.start.line
    and left.start.byte_column == right.start.byte_column
    and left["end"].line == right["end"].line
    and left["end"].byte_column == right["end"].byte_column
end

local function valid_position(bufnr, position)
  local count = vim.api.nvim_buf_line_count(bufnr)
  if
    position.start.line < 0
    or position["end"].line < position.start.line
    or position["end"].line >= count
    or position.start.line >= count
  then
    return false
  end
  local start_line = vim.api.nvim_buf_get_lines(bufnr, position.start.line, position.start.line + 1, false)[1]
  local end_line = vim.api.nvim_buf_get_lines(bufnr, position["end"].line, position["end"].line + 1, false)[1]
  return position.start.byte_column <= #start_line and position["end"].byte_column <= #end_line
end

function M.setup_highlights()
  vim.api.nvim_set_hl(0, "DocumentCommentOpen", config.options.highlights.open)
  vim.api.nvim_set_hl(0, "DocumentCommentResolved", config.options.highlights.resolved)
end

function M.apply(bufnr, ctx, comments)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
  local state = buffers[bufnr] or { attached = false, marks = {} }
  state.marks = {}
  state.ctx = ctx
  for _, comment in ipairs(comments) do
    local position = comment.anchor.current.position
    if
      comment.source.path == ctx.source_path
      and comment.anchor.state == "attached"
      and valid_position(bufnr, position)
    then
      local id = vim.api.nvim_buf_set_extmark(bufnr, M.namespace, position.start.line, position.start.byte_column, {
        end_row = position["end"].line,
        end_col = position["end"].byte_column,
        hl_group = comment.status == "open" and "DocumentCommentOpen" or "DocumentCommentResolved",
        priority = config.options.highlight_priority,
        right_gravity = false,
        end_right_gravity = true,
        invalidate = false,
        undo_restore = true,
      })
      state.marks[id] = comment.id
    end
  end
  buffers[bufnr] = state
end

local function reanchor_store(bufnr, ctx, store)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local changed = false
  local next_comments = {}
  for _, comment in ipairs(store.comments) do
    if comment.source.path == ctx.source_path then
      local copy = vim.deepcopy(comment)
      local before = vim.json.encode(copy.anchor, { sort_keys = true })
      anchor.reanchor(copy, lines)
      if vim.json.encode(copy.anchor, { sort_keys = true }) ~= before then
        changed = true
        copy.updated_at = model.now()
      end
      next_comments[copy.id] = copy
    end
  end
  if not changed then
    return store
  end
  local updated, err = storage.mutate(ctx, function(next_store)
    for index, comment in ipairs(next_store.comments) do
      if next_comments[comment.id] then
        next_store.comments[index] = next_comments[comment.id]
      end
    end
  end)
  if not updated then
    notify_error(err)
    return store
  end
  return updated
end

function M.refresh(bufnr, opts)
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "markdown" then
    return
  end
  local ctx, ctx_error = root.for_buffer(bufnr)
  if not ctx then
    if not opts.quiet then
      notify_error(ctx_error)
    end
    return
  end
  local store, load_error = storage.load(ctx)
  if not store then
    notify_error(load_error)
    return
  end
  if not vim.bo[bufnr].modified then
    store = reanchor_store(bufnr, ctx, store)
  end
  M.apply(bufnr, ctx, store.comments)
end

function M.sync_on_write(bufnr)
  local state = buffers[bufnr]
  if not state or not state.ctx then
    M.refresh(bufnr)
    return
  end
  local ctx = state.ctx
  local store, load_error = storage.load(ctx)
  if not store then
    notify_error(load_error)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = model.canonical_text(lines)
  local hash = model.hash(text)
  local changes = {}
  for mark_id, comment_id in pairs(state.marks) do
    local position = vim.api.nvim_buf_get_extmark_by_id(bufnr, M.namespace, mark_id, { details = true })
    if #position > 0 then
      local details = position[3]
      local next_position = {
        start = { line = position[1], byte_column = position[2] },
        ["end"] = { line = details.end_row, byte_column = details.end_col },
      }
      local comment = model.find(store, comment_id)
      if comment then
        local copy = vim.deepcopy(comment)
        if
          next_position.start.line == next_position["end"].line
          and next_position.start.byte_column == next_position["end"].byte_column
        then
          copy.anchor.state = "orphaned"
        else
          local start_offset = anchor.position_to_offset(lines, next_position.start)
          local end_offset = anchor.position_to_offset(lines, next_position["end"])
          copy.anchor.current = {
            document_hash = hash,
            position = next_position,
            quote = model.quote(text, start_offset, end_offset),
          }
          copy.anchor.state = "attached"
        end
        if
          copy.anchor.state ~= comment.anchor.state
          or not same_position(copy.anchor.current.position, comment.anchor.current.position)
          or copy.anchor.current.document_hash ~= comment.anchor.current.document_hash
          or copy.anchor.current.quote.exact ~= comment.anchor.current.quote.exact
          or copy.anchor.current.quote.prefix ~= comment.anchor.current.quote.prefix
          or copy.anchor.current.quote.suffix ~= comment.anchor.current.quote.suffix
        then
          copy.updated_at = model.now()
          changes[copy.id] = copy
        end
      end
    end
  end
  if next(changes) then
    local updated, err = storage.mutate(ctx, function(next_store)
      for index, comment in ipairs(next_store.comments) do
        if changes[comment.id] then
          next_store.comments[index] = changes[comment.id]
        end
      end
    end)
    if not updated then
      notify_error(err)
      return
    end
    store = updated
  end
  M.apply(bufnr, ctx, store.comments)
end

function M.comments_at_cursor(bufnr, store)
  bufnr = bufnr or 0
  local state = buffers[bufnr]
  if not state then
    return {}
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, column = cursor[1] - 1, cursor[2]
  local found = {}
  for mark_id, comment_id in pairs(state.marks) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, M.namespace, mark_id, { details = true })
    if #mark > 0 then
      local finish_row, finish_col = mark[3].end_row, mark[3].end_col
      local after_start = row > mark[1] or (row == mark[1] and column >= mark[2])
      local before_end = row < finish_row or (row == finish_row and column < finish_col)
      if after_start and before_end then
        local comment = model.find(store, comment_id)
        if comment then
          table.insert(found, comment)
        end
      end
    end
  end
  table.sort(found, function(left, right)
    return left.id < right.id
  end)
  return found
end

function M.attach(bufnr)
  local state = buffers[bufnr] or { marks = {} }
  if not state.attached then
    vim.api.nvim_buf_attach(bufnr, false, {
      on_reload = function(_, buffer)
        vim.schedule(function()
          M.refresh(buffer)
        end)
      end,
      on_detach = function(_, buffer)
        buffers[buffer] = nil
      end,
    })
    state.attached = true
    buffers[bufnr] = state
  end
  M.refresh(bufnr, { quiet = true })
end

return M
