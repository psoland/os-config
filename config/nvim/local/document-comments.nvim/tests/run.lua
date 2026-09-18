local anchor = require("document_comments.anchor")
local config = require("document_comments.config")
local exporter = require("document_comments.export")
local model = require("document_comments.model")
local range = require("document_comments.range")
local root = require("document_comments.root")
local storage = require("document_comments.storage")

config.setup()

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

local function eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(
      (message or "values differ") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual)
    )
  end
end

local function tempdir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p", 448)
  return path
end

local function write(path, data)
  vim.fn.mkdir(vim.fs.dirname(path), "p", 448)
  assert(vim.fn.writefile({ data }, path, "b") == 0)
end

local function read(path)
  return table.concat(vim.fn.readfile(path, "b"), "\n")
end

local function context(project)
  local directory = vim.fs.joinpath(project, ".document-comments")
  return {
    root = project,
    source_path = "doc.md",
    document_path = vim.fs.joinpath(project, "doc.md"),
    storage_dir = directory,
    store_path = vim.fs.joinpath(directory, "comments.json"),
    export_path = vim.fs.joinpath(directory, "export.md"),
  }
end

local function sample_comment(body)
  return model.new_comment(
    "doc.md",
    { start = { line = 0, byte_column = 0 }, ["end"] = { line = 0, byte_column = 6 } },
    { exact = "æ😊", prefix = "", suffix = " suffix" },
    model.hash("æ😊 suffix"),
    body or "Kommentar"
  )
end

test("root detection, git file, symlink, and plain directory", function()
  local outer = tempdir()
  local repo = vim.fs.joinpath(outer, "repo")
  vim.fn.mkdir(vim.fs.joinpath(repo, ".git"), "p", 448)
  local nested = vim.fs.joinpath(repo, "nested")
  vim.fn.mkdir(nested, "p", 448)
  local document = vim.fs.joinpath(nested, "doc.md")
  write(document, "hello")
  local ctx = assert(root.for_path(document))
  eq(vim.uv.fs_realpath(repo), ctx.root)
  eq("nested/doc.md", ctx.source_path)

  local worktree = vim.fs.joinpath(outer, "worktree")
  vim.fn.mkdir(worktree, "p", 448)
  write(vim.fs.joinpath(worktree, ".git"), "gitdir: elsewhere")
  local workdoc = vim.fs.joinpath(worktree, "work.md")
  write(workdoc, "work")
  eq(vim.uv.fs_realpath(worktree), assert(root.for_path(workdoc)).root)

  local link = vim.fs.joinpath(outer, "linked.md")
  assert(vim.uv.fs_symlink(document, link))
  eq(ctx.document_path, assert(root.for_path(link)).document_path)

  local plain = vim.fs.joinpath(outer, "plain", "single.md")
  write(plain, "plain")
  eq(vim.uv.fs_realpath(vim.fs.dirname(plain)), assert(root.for_path(plain)).root)
end)

test("deterministic Unicode storage survives reload", function()
  storage._reset()
  local project = tempdir()
  local ctx = context(project)
  write(ctx.document_path, "æ😊 suffix")
  local saved = assert(storage.mutate(ctx, function(store)
    table.insert(store.comments, sample_comment("Norsk æøå og emoji 😊"))
  end))
  eq(1, saved.store_revision)
  local first_raw = read(ctx.store_path)
  storage._reset()
  local loaded = assert(storage.load(ctx))
  eq(saved, loaded)
  eq("Norsk æøå og emoji 😊", loaded.comments[1].body)
  eq(first_raw, vim.json.encode(loaded, { indent = "  ", sort_keys = true }) .. "\n")
end)

test("invalid JSON and newer schema block writes", function()
  storage._reset()
  local project = tempdir()
  local ctx = context(project)
  write(ctx.store_path, "not json")
  local loaded, err = storage.load(ctx)
  assert(not loaded and err:match("invalid JSON"))
  local updated, update_err = storage.mutate(ctx, function() end)
  assert(not updated and update_err:match("invalid JSON"))

  storage._reset()
  write(
    ctx.store_path,
    vim.json.encode({ schema_version = 99, store_revision = 0, updated_at = model.now(), comments = {} })
  )
  loaded, err = storage.load(ctx)
  assert(not loaded and err:match("newer than supported"))
end)

test("write conflict and fsync failure preserve disk data", function()
  storage._reset()
  local project = tempdir()
  local ctx = context(project)
  assert(storage.mutate(ctx, function(store)
    table.insert(store.comments, sample_comment())
  end))
  local valid_raw = read(ctx.store_path)
  write(ctx.store_path, valid_raw .. " ")
  local updated, err = storage.mutate(ctx, function(store)
    store.comments[1].body = "conflicting"
  end)
  assert(not updated and err:match("conflict"))
  eq(valid_raw .. " ", read(ctx.store_path))

  storage._reset()
  local failure_project = tempdir()
  local failure_ctx = context(failure_project)
  assert(storage.mutate(failure_ctx, function(store)
    table.insert(store.comments, sample_comment())
  end))
  local before = read(failure_ctx.store_path)
  local real_io = storage.io
  storage.io = vim.tbl_extend("force", {}, real_io, {
    fs_fsync = function()
      return nil, "injected fsync failure"
    end,
  })
  updated, err = storage.mutate(failure_ctx, function(store)
    store.comments[1].body = "must not persist"
  end)
  assert(not updated and err:match("fsync failure"))
  eq(before, read(failure_ctx.store_path))
  storage.io = real_io

  for operation, replacement in pairs({
    fs_write = function()
      return nil, "injected write failure"
    end,
    fs_rename = function()
      return nil, "injected rename failure"
    end,
  }) do
    storage._reset()
    local operation_project = tempdir()
    local operation_ctx = context(operation_project)
    assert(storage.mutate(operation_ctx, function(store)
      table.insert(store.comments, sample_comment())
    end))
    local original = read(operation_ctx.store_path)
    local operation_io = storage.io
    storage.io = vim.tbl_extend("force", {}, operation_io, { [operation] = replacement })
    updated, err = storage.mutate(operation_ctx, function(store)
      store.comments[1].body = "must also not persist"
    end)
    assert(not updated and err:match("injected"))
    eq(original, read(operation_ctx.store_path))
    storage.io = operation_io
  end

  for _, failure in ipairs({ "open", "close" }) do
    storage._reset()
    local operation_project = tempdir()
    local operation_ctx = context(operation_project)
    assert(storage.mutate(operation_ctx, function(store)
      table.insert(store.comments, sample_comment())
    end))
    local original = read(operation_ctx.store_path)
    local operation_io = storage.io
    local temporary_fd
    storage.io = vim.tbl_extend("force", {}, operation_io, {
      fs_open = function(path, flags, mode)
        if failure == "open" and flags == "wx" then
          return nil, "injected open failure"
        end
        local fd, open_error = operation_io.fs_open(path, flags, mode)
        if flags == "wx" then
          temporary_fd = fd
        end
        return fd, open_error
      end,
      fs_close = function(fd)
        if failure == "close" and fd == temporary_fd then
          temporary_fd = nil
          operation_io.fs_close(fd)
          return nil, "injected close failure"
        end
        return operation_io.fs_close(fd)
      end,
    })
    updated, err = storage.mutate(operation_ctx, function(store)
      store.comments[1].body = "must still not persist"
    end)
    assert(not updated and err:match("injected"))
    eq(original, read(operation_ctx.store_path))
    storage.io = operation_io
  end
end)

test("conservative exact reanchoring", function()
  local comment = sample_comment()
  comment.anchor.current.quote = { exact = "target", prefix = "before ", suffix = " after" }
  comment.anchor.current.position = { start = { line = 0, byte_column = 0 }, ["end"] = { line = 0, byte_column = 6 } }
  eq("attached", anchor.reanchor(comment, { "moved before target after end" }))
  eq(13, comment.anchor.current.position.start.byte_column)

  local ambiguous = vim.deepcopy(comment)
  ambiguous.anchor.current.quote = { exact = "same", prefix = "", suffix = "" }
  ambiguous.anchor.current.position = { start = { line = 9, byte_column = 0 }, ["end"] = { line = 9, byte_column = 4 } }
  eq("ambiguous", anchor.reanchor(ambiguous, { "same and same" }))

  local contextual = vim.deepcopy(comment)
  contextual.anchor.current.quote = { exact = "same", prefix = "red ", suffix = " end" }
  contextual.anchor.current.position =
    { start = { line = 9, byte_column = 0 }, ["end"] = { line = 9, byte_column = 4 } }
  eq("attached", anchor.reanchor(contextual, { "blue same end red same end" }))
  eq(18, contextual.anchor.current.position.start.byte_column)

  local orphaned = vim.deepcopy(comment)
  orphaned.anchor.current.quote.exact = "gone"
  eq("orphaned", anchor.reanchor(orphaned, { "nothing here" }))
end)

test("Visual range preserves UTF-8, tabs, direction, and multiple lines", function()
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buffer)
  vim.bo[buffer].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "start\tæøå", "emoji 😊 finish" })
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { 2, 9 })
  local forward = assert(range.from_visual(buffer))
  eq("æøå\nemoji 😊", forward.exact)
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)

  vim.api.nvim_win_set_cursor(0, { 2, 9 })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  local backward = assert(range.from_visual(buffer))
  eq(forward.exact, backward.exact)
  eq(forward.position, backward.position)
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
end)

test("extmark gravity follows edits and permits overlap", function()
  local extmarks = require("document_comments.extmarks")
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "alpha beta gamma" })
  local opts = {
    end_row = 0,
    end_col = 10,
    right_gravity = false,
    end_right_gravity = true,
    invalidate = false,
    undo_restore = true,
  }
  local first = vim.api.nvim_buf_set_extmark(buffer, extmarks.namespace, 0, 6, opts)
  vim.api.nvim_buf_set_extmark(buffer, extmarks.namespace, 0, 7, vim.tbl_extend("force", {}, opts, { end_col = 9 }))
  vim.api.nvim_buf_set_text(buffer, 0, 0, 0, 0, { "new " })
  local mark = vim.api.nvim_buf_get_extmark_by_id(buffer, extmarks.namespace, first, { details = true })
  eq(10, mark[2])
  eq(14, mark[3].end_col)
end)

test("export contains durable identity and does not mutate store", function()
  storage._reset()
  local project = tempdir()
  local ctx = context(project)
  assert(storage.mutate(ctx, function(store)
    table.insert(store.comments, sample_comment("Presiser dette."))
  end))
  local before = read(ctx.store_path)
  local path, count = exporter.write(ctx, "project")
  eq(1, count)
  local output = read(path)
  assert(output:match("c_[0-9a-f]+"))
  assert(output:match("doc%.md"))
  assert(output:match("Anchor: attached"))
  assert(output:match("Presiser dette"))
  eq(before, read(ctx.store_path))
end)

test("setup registers commands", function()
  require("document_comments").setup()
  assert(vim.fn.exists(":DocumentCommentsAdd") == 2)
  assert(vim.fn.exists(":DocumentCommentsExport") == 2)
end)

test("confirmed comment survives writes and collapsed extmark becomes orphaned", function()
  storage._reset()
  local project = tempdir()
  vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p", 448)
  local document = vim.fs.joinpath(project, "flow.md")
  write(document, "start alpha beta")
  vim.cmd.edit(vim.fn.fnameescape(document))
  vim.bo.filetype = "markdown"
  local source_buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { 1, 10 })
  require("document_comments.commands").add()

  local draft_buffer = vim.api.nvim_get_current_buf()
  assert(draft_buffer ~= source_buffer)
  assert(not vim.b[draft_buffer].document_comments_attached)
  vim.api.nvim_buf_set_lines(draft_buffer, 0, -1, false, { "Explain this selection." })
  vim.cmd.stopinsert()
  vim.cmd.write()

  assert(vim.api.nvim_get_current_buf() == source_buffer)
  local ctx = assert(root.for_buffer(source_buffer))
  local store = assert(storage.load(ctx))
  eq(1, #store.comments)
  eq("alpha", store.comments[1].anchor.current.quote.exact)
  local extmarks = require("document_comments.extmarks")
  eq(1, #vim.api.nvim_buf_get_extmarks(source_buffer, extmarks.namespace, 0, -1, {}))

  vim.api.nvim_buf_set_text(source_buffer, 0, 0, 0, 0, { "new " })
  vim.cmd.write()
  store = assert(storage.load(ctx))
  eq(10, store.comments[1].anchor.current.position.start.byte_column)
  eq("alpha", store.comments[1].anchor.original.quote.exact)

  vim.api.nvim_buf_set_text(source_buffer, 0, 10, 0, 15, { "omega" })
  vim.cmd.write()
  store = assert(storage.load(ctx))
  eq("omega", store.comments[1].anchor.current.quote.exact)
  eq("alpha", store.comments[1].anchor.original.quote.exact)

  vim.cmd.undo()
  vim.cmd.write()
  store = assert(storage.load(ctx))
  eq("alpha", store.comments[1].anchor.current.quote.exact)
  vim.cmd.redo()
  vim.cmd.write()
  store = assert(storage.load(ctx))
  eq("omega", store.comments[1].anchor.current.quote.exact)

  vim.api.nvim_buf_set_text(source_buffer, 0, 10, 0, 15, { "" })
  vim.cmd.write()
  store = assert(storage.load(ctx))
  eq("orphaned", store.comments[1].anchor.state)
  eq("omega", store.comments[1].anchor.current.quote.exact)

  storage._reset()
  store = assert(storage.load(ctx))
  eq("orphaned", store.comments[1].anchor.state)
end)

print(("document-comments: %d tests passed"):format(passed))
vim.cmd("qa!")
