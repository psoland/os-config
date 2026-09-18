local editor = require("document_comments.ui.editor")
local exporter = require("document_comments.export")
local extmarks = require("document_comments.extmarks")
local model = require("document_comments.model")
local range = require("document_comments.range")
local root = require("document_comments.root")
local select_ui = require("document_comments.ui.select")
local storage = require("document_comments.storage")

local M = {}
local registered = false

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Document comments" })
end

local function context(bufnr, require_saved)
  bufnr = bufnr or 0
  if vim.bo[bufnr].filetype ~= "markdown" then
    return nil, "document comments are only supported in Markdown buffers"
  end
  if vim.bo[bufnr].buftype ~= "" then
    return nil, "document comments require a normal file buffer"
  end
  if require_saved and vim.bo[bufnr].modified then
    return nil, "save the document before creating or reattaching a comment"
  end
  return root.for_buffer(bufnr)
end

local function refresh(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    extmarks.refresh(bufnr)
  end
end

local function current_comments(bufnr)
  local ctx, ctx_error = context(bufnr)
  if not ctx then
    return nil, ctx_error
  end
  local store, load_error = storage.load(ctx)
  if not store then
    return nil, load_error
  end
  local comments = extmarks.comments_at_cursor(bufnr, store)
  local present = {}
  for _, comment in ipairs(comments) do
    present[comment.id] = true
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  for _, comment in ipairs(store.comments) do
    local position = comment.anchor.current.position.start
    if
      not present[comment.id]
      and comment.source.path == ctx.source_path
      and comment.anchor.state ~= "attached"
      and position.line == cursor[1] - 1
      and position.byte_column == cursor[2]
    then
      table.insert(comments, comment)
    end
  end
  return comments, ctx, store
end

local function choose_current(prompt, callback)
  local comments, ctx_or_error, store = current_comments(0)
  if not comments then
    notify(ctx_or_error, vim.log.levels.ERROR)
    return
  end
  if #comments == 0 then
    notify("No document comment under the cursor")
    return
  end
  select_ui.comment(comments, prompt, function(comment)
    if comment then
      callback(comment, ctx_or_error, store)
    end
  end)
end

local function jump(ctx, comment)
  local path = vim.fs.joinpath(ctx.root, comment.source.path)
  if not vim.uv.fs_stat(path) then
    notify("Source file no longer exists: " .. path, vim.log.levels.WARN)
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
  local position = comment.anchor.current.position.start
  local row = math.min(position.line, vim.api.nvim_buf_line_count(0) - 1)
  local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
  vim.api.nvim_win_set_cursor(0, { row + 1, math.min(position.byte_column, #line) })
  vim.cmd.normal({ "zv", bang = true })
  if comment.anchor.state ~= "attached" then
    notify(
      ("%s is %s; showing only its last known position"):format(comment.id, comment.anchor.state),
      vim.log.levels.WARN
    )
  end
end

function M.add(allow_inactive)
  local source_buffer = vim.api.nvim_get_current_buf()
  local ctx, ctx_error = context(source_buffer, true)
  if not ctx then
    notify(ctx_error, vim.log.levels.ERROR)
    return
  end
  local selection, selection_error = range.from_visual(source_buffer, allow_inactive)
  if not selection then
    notify(selection_error, vim.log.levels.ERROR)
    return
  end
  local draft_id = "new-" .. model.new_id()
  editor.open({
    id = draft_id,
    root = ctx.root,
    title = " New document comment ",
    save = function(body)
      local comment =
        model.new_comment(ctx.source_path, selection.position, selection.quote, selection.document_hash, body)
      local updated, err = storage.mutate(ctx, function(store)
        table.insert(store.comments, comment)
      end)
      if not updated then
        return nil, err
      end
      refresh(source_buffer)
      return true
    end,
  })
end

function M.list(filter)
  filter = filter == "" and "open" or filter
  if filter ~= "open" and filter ~= "resolved" and filter ~= "all" then
    notify("List filter must be open, resolved, or all", vim.log.levels.ERROR)
    return
  end
  local ctx, ctx_error = context(0)
  if not ctx then
    notify(ctx_error, vim.log.levels.ERROR)
    return
  end
  local store, load_error = storage.load(ctx)
  if not store then
    notify(load_error, vim.log.levels.ERROR)
    return
  end
  local comments = vim
    .iter(store.comments)
    :filter(function(comment)
      return filter == "all" or comment.status == filter
    end)
    :totable()
  table.sort(comments, function(left, right)
    local lf = select_ui.format(left)
    local rf = select_ui.format(right)
    return lf < rf
  end)
  select_ui.comment(comments, "Document comments (" .. filter .. ")", function(comment)
    if comment then
      jump(ctx, comment)
    end
  end, true)
end

function M.edit()
  local source_buffer = vim.api.nvim_get_current_buf()
  choose_current("Edit document comment", function(comment, ctx)
    editor.open({
      id = comment.id,
      body = comment.body,
      root = ctx.root,
      title = " Edit " .. comment.id .. " ",
      save = function(body)
        local updated, err = storage.mutate(ctx, function(store)
          local target = model.find(store, comment.id)
          assert(target, "comment no longer exists")
          target.body = body
          target.updated_at = model.now()
        end)
        if not updated then
          return nil, err
        end
        refresh(source_buffer)
        return true
      end,
    })
  end)
end

function M.resolve()
  local source_buffer = vim.api.nvim_get_current_buf()
  choose_current("Resolve or reopen document comment", function(comment, ctx)
    local updated, err = storage.mutate(ctx, function(store)
      local target = model.find(store, comment.id)
      assert(target, "comment no longer exists")
      if target.status == "open" then
        target.status = "resolved"
        target.resolved_at = model.now()
      else
        target.status = "open"
        target.resolved_at = vim.NIL
      end
      target.updated_at = model.now()
    end)
    if not updated then
      notify(err, vim.log.levels.ERROR)
      return
    end
    refresh(source_buffer)
    notify(comment.status == "open" and "Comment resolved" or "Comment reopened")
  end)
end

function M.delete()
  local source_buffer = vim.api.nvim_get_current_buf()
  choose_current("Delete document comment", function(comment, ctx)
    vim.ui.select({ "Cancel", "Delete" }, { prompt = "Permanently delete " .. comment.id .. "?" }, function(choice)
      if choice ~= "Delete" then
        return
      end
      local updated, err = storage.mutate(ctx, function(store)
        local _, index = model.find(store, comment.id)
        assert(index, "comment no longer exists")
        table.remove(store.comments, index)
      end)
      if not updated then
        notify(err, vim.log.levels.ERROR)
        return
      end
      refresh(source_buffer)
      notify("Comment deleted")
    end)
  end)
end

local function navigate(direction)
  local ctx, ctx_error = context(0)
  if not ctx then
    notify(ctx_error, vim.log.levels.ERROR)
    return
  end
  local store, load_error = storage.load(ctx)
  if not store then
    notify(load_error, vim.log.levels.ERROR)
    return
  end
  local comments = vim
    .iter(store.comments)
    :filter(function(comment)
      return comment.source.path == ctx.source_path and comment.status == "open" and comment.anchor.state == "attached"
    end)
    :totable()
  table.sort(comments, function(left, right)
    local lp, rp = left.anchor.current.position.start, right.anchor.current.position.start
    return lp.line == rp.line and lp.byte_column < rp.byte_column or lp.line < rp.line
  end)
  if #comments == 0 then
    notify("No attached open comments in this file")
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line, cursor_column = cursor[1] - 1, cursor[2]
  local chosen
  if direction > 0 then
    for _, comment in ipairs(comments) do
      local position = comment.anchor.current.position.start
      if position.line > cursor_line or (position.line == cursor_line and position.byte_column > cursor_column) then
        chosen = comment
        break
      end
    end
    chosen = chosen or comments[1]
  else
    for index = #comments, 1, -1 do
      local comment = comments[index]
      local position = comment.anchor.current.position.start
      if position.line < cursor_line or (position.line == cursor_line and position.byte_column < cursor_column) then
        chosen = comment
        break
      end
    end
    chosen = chosen or comments[#comments]
  end
  jump(ctx, chosen)
end

function M.next()
  navigate(1)
end

function M.prev()
  navigate(-1)
end

function M.reattach(allow_inactive)
  local source_buffer = vim.api.nvim_get_current_buf()
  local ctx, ctx_error = context(source_buffer, true)
  if not ctx then
    notify(ctx_error, vim.log.levels.ERROR)
    return
  end
  local selection, selection_error = range.from_visual(source_buffer, allow_inactive)
  if not selection then
    notify(selection_error, vim.log.levels.ERROR)
    return
  end
  local store, load_error = storage.load(ctx)
  if not store then
    notify(load_error, vim.log.levels.ERROR)
    return
  end
  local comments = vim
    .iter(store.comments)
    :filter(function(comment)
      return comment.anchor.state == "ambiguous" or comment.anchor.state == "orphaned"
    end)
    :totable()
  select_ui.comment(comments, "Reattach document comment", function(comment)
    if not comment then
      return
    end
    local updated, err = storage.mutate(ctx, function(next_store)
      local target = model.find(next_store, comment.id)
      assert(target, "comment no longer exists")
      target.anchor.current = {
        document_hash = selection.document_hash,
        position = vim.deepcopy(selection.position),
        quote = vim.deepcopy(selection.quote),
      }
      target.anchor.state = "attached"
      target.source.path = ctx.source_path
      target.updated_at = model.now()
    end)
    if not updated then
      notify(err, vim.log.levels.ERROR)
      return
    end
    refresh(source_buffer)
    notify("Comment reattached")
  end)
end

function M.export(args)
  local ctx, ctx_error = context(0)
  if not ctx then
    notify(ctx_error, vim.log.levels.ERROR)
    return
  end
  local scope, path = args:match("^(%S+)%s*(.*)$")
  scope = scope or "project"
  path = path ~= "" and path or nil
  if scope ~= "project" and scope ~= "file" and scope ~= "current" then
    notify("Export scope must be project, file, or current", vim.log.levels.ERROR)
    return
  end
  local function write(current)
    local destination, count_or_error = exporter.write(ctx, scope, path, current)
    if not destination then
      notify(count_or_error, vim.log.levels.ERROR)
      return
    end
    notify(("Exported %d comment(s) to %s"):format(count_or_error, destination))
  end
  if scope == "current" then
    choose_current("Export document comment", function(comment)
      write(comment)
    end)
  else
    write()
  end
end

function M.reload()
  local ctx, ctx_error = context(0)
  if not ctx then
    notify(ctx_error, vim.log.levels.ERROR)
    return
  end
  if editor.has_draft(ctx.root) then
    notify("Cannot reload while a comment draft is open", vim.log.levels.ERROR)
    return
  end
  local store, err = storage.reload(ctx)
  if not store then
    notify(err, vim.log.levels.ERROR)
    return
  end
  extmarks.refresh(0)
  notify(("Reloaded store revision %d"):format(store.store_revision))
end

function M.store_path()
  local ctx, ctx_error = context(0)
  if not ctx then
    notify(ctx_error, vim.log.levels.ERROR)
    return
  end
  local store, err = storage.load(ctx)
  if not store then
    notify(err, vim.log.levels.ERROR)
    return
  end
  notify(("Root: %s\nStore: %s\nLoaded revision: %d"):format(ctx.root, ctx.store_path, store.store_revision))
end

function M.register()
  if registered then
    return
  end
  registered = true
  vim.api.nvim_create_user_command("DocumentCommentsAdd", function(opts)
    if opts.range == 0 then
      notify("DocumentCommentsAdd must be started from Visual mode", vim.log.levels.ERROR)
      return
    end
    M.add(true)
  end, { desc = "Add comment from Visual selection", range = true })
  vim.api.nvim_create_user_command("DocumentCommentsList", function(opts)
    M.list(opts.args)
  end, {
    desc = "List document comments",
    nargs = "?",
    complete = function()
      return { "open", "resolved", "all" }
    end,
  })
  vim.api.nvim_create_user_command("DocumentCommentsEdit", M.edit, { desc = "Edit comment under cursor" })
  vim.api.nvim_create_user_command("DocumentCommentsResolve", M.resolve, { desc = "Resolve or reopen comment" })
  vim.api.nvim_create_user_command("DocumentCommentsDelete", M.delete, { desc = "Delete comment under cursor" })
  vim.api.nvim_create_user_command("DocumentCommentsNext", M.next, { desc = "Next open comment" })
  vim.api.nvim_create_user_command("DocumentCommentsPrev", M.prev, { desc = "Previous open comment" })
  vim.api.nvim_create_user_command("DocumentCommentsReattach", function(opts)
    if opts.range == 0 then
      notify("DocumentCommentsReattach must be started from Visual mode", vim.log.levels.ERROR)
      return
    end
    M.reattach(true)
  end, {
    desc = "Reattach comment to Visual selection",
    range = true,
  })
  vim.api.nvim_create_user_command("DocumentCommentsExport", function(opts)
    M.export(opts.args)
  end, {
    desc = "Export open document comments",
    nargs = "*",
    complete = function(_, line)
      if not line:match("DocumentCommentsExport%s+%S+%s+") then
        return { "project", "file", "current" }
      end
      return {}
    end,
  })
  vim.api.nvim_create_user_command("DocumentCommentsReload", M.reload, { desc = "Reload document comment store" })
  vim.api.nvim_create_user_command(
    "DocumentCommentsStorePath",
    M.store_path,
    { desc = "Show document comment store path" }
  )
end

return M
