local anchor = require("document_comments.anchor")
local config = require("document_comments.config")
local model = require("document_comments.model")
local presentation = require("document_comments.presentation")
local root = require("document_comments.root")
local storage = require("document_comments.storage")

local M = {}

M.namespace = vim.api.nvim_create_namespace("document-comments")
M.sign_namespace = vim.api.nvim_create_namespace("document-comments-signs")
local buffers = {}

local function notify_error(message)
  vim.notify(message, vim.log.levels.ERROR, { title = "Document comments" })
end

local function normalize_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
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
  vim.api.nvim_set_hl(0, "DocumentCommentSignOpen", config.options.highlights.sign_open)
  vim.api.nvim_set_hl(0, "DocumentCommentSignProblem", config.options.highlights.sign_problem)
  vim.api.nvim_set_hl(0, "DocumentCommentSignResolved", config.options.highlights.sign_resolved)
end

function M.apply(bufnr, ctx, comments)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, M.namespace, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, M.sign_namespace, 0, -1)
  local state = buffers[bufnr] or { attached = false, marks = {} }
  state.marks = {}
  state.ctx = ctx
  local file = presentation.for_file(comments, ctx.source_path)
  if state.review_initialized and (state.problem_count or 0) == 0 and file.problem > 0 then
    vim.schedule(function()
      local current = buffers[bufnr]
      if vim.api.nvim_buf_is_valid(bufnr) and current and current.problem_count > 0 then
        vim.notify(
          ("%d document comment(s) need review — use <leader>av"):format(current.problem_count),
          vim.log.levels.WARN,
          { title = "Document comments" }
        )
      end
    end)
  end
  state.review_initialized = true
  state.problem_count = file.problem
  state.file = file
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
  local sign_highlights = {
    open = "DocumentCommentSignOpen",
    problem = "DocumentCommentSignProblem",
    resolved = "DocumentCommentSignResolved",
  }
  for _, sign in ipairs(presentation.sign_groups(file, vim.api.nvim_buf_line_count(bufnr), config.options.signs)) do
    vim.api.nvim_buf_set_extmark(bufnr, M.sign_namespace, sign.row, 0, {
      sign_text = sign.text,
      sign_hl_group = sign_highlights[sign.kind],
      number_hl_group = sign_highlights[sign.kind],
      priority = config.options.signs.priority,
    })
  end
  buffers[bufnr] = state
  vim.cmd.redrawstatus()
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
  bufnr = normalize_bufnr(bufnr)
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
  bufnr = normalize_bufnr(bufnr)
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
  bufnr = normalize_bufnr(bufnr)
  local state = buffers[bufnr]
  if not state then
    return {}
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, column = cursor[1] - 1, cursor[2]
  local containing = {}
  local on_line = {}
  local present = {}
  local function add(target, comment)
    if comment and not present[comment.id] then
      present[comment.id] = true
      table.insert(target, comment)
    end
  end
  for mark_id, comment_id in pairs(state.marks) do
    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, M.namespace, mark_id, { details = true })
    if #mark > 0 then
      local finish_row, finish_col = mark[3].end_row, mark[3].end_col
      local after_start = row > mark[1] or (row == mark[1] and column >= mark[2])
      local before_end = row < finish_row or (row == finish_row and column < finish_col)
      if after_start and before_end then
        add(containing, model.find(store, comment_id))
      elseif row >= mark[1] and row <= finish_row then
        add(on_line, model.find(store, comment_id))
      end
    end
  end
  if #containing > 0 then
    on_line = containing
  else
    for _, comment in ipairs(store.comments) do
      if
        comment.source.path == state.ctx.source_path
        and comment.anchor.state ~= "attached"
        and math.max(0, math.min(comment.anchor.current.position.start.line, vim.api.nvim_buf_line_count(bufnr) - 1))
          == row
      then
        add(on_line, comment)
      end
    end
  end
  table.sort(on_line, function(left, right)
    return left.id < right.id
  end)
  return on_line
end

function M.file_state(bufnr)
  local state = buffers[normalize_bufnr(bufnr)]
  return state and state.file or nil
end

function M.statusline(bufnr)
  return presentation.statusline(M.file_state(bufnr), config.options.statusline)
end

function M.attach(bufnr)
  bufnr = normalize_bufnr(bufnr)
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
