local anchor = require("document_comments.anchor")
local config = require("document_comments.config")
local exporter = require("document_comments.export")
local model = require("document_comments.model")
local presentation = require("document_comments.presentation")
local range = require("document_comments.range")
local references = require("document_comments.references")
local root = require("document_comments.root")
local storage = require("document_comments.storage")
local select_ui = require("document_comments.ui.select")

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

test("export contains durable identity and records a batch without resolving comments", function()
  storage._reset()
  local project = tempdir()
  local ctx = context(project)
  assert(storage.mutate(ctx, function(store)
    table.insert(store.comments, sample_comment("Presiser dette."))
  end))
  local before = vim.deepcopy(assert(storage.load(ctx)).comments)
  local path, count, batch_id = exporter.write(ctx, "project")
  eq(1, count)
  local output = read(path)
  assert(output:match("c_[0-9a-f]+"))
  assert(output:match("doc%.md"))
  assert(output:match("Anchor: attached"))
  assert(output:match("Presiser dette"))
  local after = assert(storage.load(ctx))
  eq(before, after.comments)
  eq(1, #after.export_batches)
  eq(batch_id, after.export_batches[1].id)
  eq(before, after.export_batches[1].comments)
  eq(output, after.export_batches[1].markdown)
end)

test("comment references resolve prefixes, backlinks, cycles, and completion", function()
  local first = sample_comment("See @c_bbbb1111 and @c_dead")
  first.id = "c_aaaa1111"
  local second = sample_comment("Back to @c_aaaa")
  second.id = "c_bbbb1111"
  local third = sample_comment("Another B")
  third.id = "c_bbbb2222"
  local store = { comments = { first, second, third } }

  eq({ "@c_bbbb1111", "@c_dead" }, references.tokens(first.body))
  eq(second.id, references.resolve(store, "@c_bbbb1111").comment.id)
  eq(first.id, references.resolve(store, "@c_aaaa").comment.id)
  eq("ambiguous", references.resolve(store, "@c_bbbb").state)
  eq("missing", references.resolve(store, "@c_dead").state)
  eq(second.id, references.backlinks(store, first.id)[1].id)

  local linked, issues = references.walk(store, first)
  eq(1, #linked)
  eq(second.id, linked[1].comment.id)
  eq(1, #issues)
  eq("@c_dead", issues[1].token)

  local completions = references.completions(store, first.id)
  eq(2, #completions)
  eq("@c_bbbb1111", completions[1].word)
  eq(1, #references.warnings(store, "Unknown @c_dead", first.id))
  eq(1, #references.warnings(store, "Self @c_aaaa", first.id))

  local editor = require("document_comments.ui.editor")
  local completion_buffer, completion_window = editor.open({
    id = "completion-test",
    root = "/tmp",
    completions = references.completions(store),
    save = function()
      return true
    end,
  })
  vim.api.nvim_buf_set_lines(completion_buffer, 0, -1, false, { "See @" })
  vim.api.nvim_win_set_cursor(completion_window, { 1, 5 })
  eq(4, editor.complete(1, ""))
  eq(3, #editor.complete(0, "@c_"))
  vim.cmd.stopinsert()
  vim.api.nvim_win_close(completion_window, true)
end)

test("export includes resolved referenced comments without following cycles forever", function()
  local primary = sample_comment("Use the decision from @c_bbbb1111 and @c_dead")
  primary.id = "c_aaaa1111"
  local context_comment = sample_comment("This points back to @c_aaaa1111")
  context_comment.id = "c_bbbb1111"
  context_comment.status = "resolved"
  context_comment.resolved_at = model.now()
  local store = model.new_store()
  store.comments = { primary, context_comment }
  local output = exporter.render(store, { primary }, "hash")
  assert(output:match("Referenced comments %(context only%)"))
  assert(output:match("@c_bbbb1111"))
  assert(output:match("Status: resolved"))
  assert(output:match("@c_dead` — missing"))
end)

test("presentation aggregates signs, statusline counts, and review candidates", function()
  local attached = sample_comment("Attached")
  local changed = sample_comment("Changed")
  changed.id = "c_changed"
  changed.anchor.current.quote.exact = "rewritten"
  changed.anchor.current.position.start.line = 2
  changed.anchor.current.position["end"].line = 2
  local orphaned = sample_comment("Orphaned")
  orphaned.id = "c_orphaned"
  orphaned.anchor.state = "orphaned"
  orphaned.anchor.current.position.start.line = 2
  orphaned.anchor.current.position["end"].line = 2
  local resolved = sample_comment("Resolved")
  resolved.id = "c_resolved"
  resolved.status = "resolved"
  resolved.resolved_at = model.now()
  resolved.anchor.current.position.start.line = 20
  resolved.anchor.current.position["end"].line = 20

  local file = presentation.for_file({ attached, changed, orphaned, resolved }, "doc.md")
  eq(3, file.open)
  eq(1, file.resolved)
  eq(2, file.problem)
  eq(2, #file.review)
  eq("C 3 !2", presentation.statusline(file, { enabled = true, icon = "C" }))

  local signs = presentation.sign_groups(file, 5, {
    enabled = true,
    show_resolved = true,
    open = "●",
    problem = "!",
    resolved = "○",
  })
  eq(3, #signs)
  eq({ row = 0, count = 1, kind = "open", text = "●" }, signs[1])
  eq({ row = 2, count = 2, kind = "problem", text = "2" }, signs[2])
  eq({ row = 4, count = 1, kind = "resolved", text = "○" }, signs[3])
end)

test("comment list formatting is concise and scope-aware", function()
  local open = sample_comment("Hva betyr dette?")
  open.source.path = "produkter/enterprise_ai/enterprise_ai_backup.md"
  open.anchor.current.position.start.line = 38
  open.anchor.current.position["end"].line = 38
  eq("● L39  Hva betyr dette?", select_ui.format_file(open))

  local orphaned = vim.deepcopy(open)
  orphaned.id = "c_orphaned_format"
  orphaned.anchor.state = "orphaned"
  eq("! L39  [orphaned] Hva betyr dette?", select_ui.format_file(orphaned))

  local resolved = vim.deepcopy(open)
  resolved.id = "c_resolved_format"
  resolved.status = "resolved"
  resolved.resolved_at = model.now()
  eq("○ L39  Hva betyr dette?", select_ui.format_file(resolved))

  local project_format = select_ui.project_formatter({ open, orphaned, resolved })
  eq("● enterprise_ai_backup.md:39  Hva betyr dette?", project_format(open))

  local collision = vim.deepcopy(open)
  collision.id = "c_collision"
  collision.source.path = "arkiv/enterprise_ai_backup.md"
  project_format = select_ui.project_formatter({ open, collision })
  assert(project_format(open):match("produkter/enterprise_ai/enterprise_ai_backup%.md:39"))
  assert(project_format(collision):match("arkiv/enterprise_ai_backup%.md:39"))
end)

test("setup registers commands", function()
  require("document_comments").setup()
  assert(vim.fn.exists(":DocumentCommentsAdd") == 2)
  assert(vim.fn.exists(":DocumentCommentsExport") == 2)
  assert(vim.fn.exists(":DocumentCommentsReview") == 2)
  assert(vim.fn.exists(":DocumentCommentsListProject") == 2)
  assert(vim.fn.exists(":DocumentCommentsSidebar") == 2)
  assert(vim.fn.exists(":DocumentCommentsBatches") == 2)
end)

test("file and project lists use separate scopes", function()
  storage._reset()
  local project = tempdir()
  vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p", 448)
  local document = vim.fs.joinpath(project, "scope.md")
  write(document, "scope text")
  write(vim.fs.joinpath(project, "other.md"), "other text")
  vim.cmd.edit(vim.fn.fnameescape(document))
  vim.bo.filetype = "markdown"
  local ctx = assert(root.for_buffer(0))
  local current_id
  local other_id
  assert(storage.mutate(ctx, function(store)
    local position = { start = { line = 0, byte_column = 0 }, ["end"] = { line = 0, byte_column = 5 } }
    local current = model.new_comment(
      "scope.md",
      position,
      { exact = "scope", prefix = "", suffix = " text" },
      model.hash("scope text"),
      "Current file"
    )
    local other = model.new_comment(
      "other.md",
      position,
      { exact = "other", prefix = "", suffix = " text" },
      model.hash("other text"),
      "Other file"
    )
    current.body = "Current file; see @" .. other.id
    other.body = "Other file; back to @" .. current.id
    current_id = current.id
    other_id = other.id
    table.insert(store.comments, current)
    table.insert(store.comments, other)
  end))
  require("document_comments.extmarks").refresh(0)

  local captured = {}
  local original_select = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    table.insert(captured, { items = items, opts = opts })
    callback(nil)
  end
  require("document_comments.commands").list("open", "file")
  require("document_comments.commands").list("open", "project")
  vim.ui.select = original_select

  eq(1, #captured[1].items)
  assert(captured[1].opts.prompt:match("scope%.md"))
  assert(captured[1].opts.format_item(captured[1].items[1]):match("● L1  Current file"))
  eq(2, #captured[2].items)
  assert(captured[2].opts.prompt:match("project"))
  assert(captured[2].opts.format_item(captured[2].items[1]):match("%.md:1"))

  local saw_references = false
  local saw_backlinks = false
  vim.ui.select = function(items, _, callback)
    if type(items[1]) == "table" then
      callback(items[1])
      return
    end
    saw_references = vim.list_contains(items, "Open referenced comment…")
    for _, item in ipairs(items) do
      saw_backlinks = saw_backlinks or item:match("^Show backlinks") ~= nil
    end
    callback("Copy comment ID")
  end
  require("document_comments.commands").list("open", "file")
  vim.ui.select = original_select
  assert(saw_references and saw_backlinks)
  eq(current_id, vim.fn.getreg('"'))

  vim.ui.select = function(items, _, callback)
    if type(items[1]) == "table" then
      callback(items[1])
    else
      callback("Open referenced comment…")
    end
  end
  require("document_comments.commands").list("open", "file")
  vim.ui.select = original_select
  eq(other_id, model.find(assert(storage.load(ctx)), other_id).id)
  assert(vim.api.nvim_buf_get_name(0):match("other%.md$"))
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
  eq(1, #vim.api.nvim_buf_get_extmarks(source_buffer, extmarks.sign_namespace, 0, -1, {}))
  assert(require("document_comments").statusline(source_buffer):match("1"))

  -- Edit and resolve work from elsewhere on the same line, not only inside the range.
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  eq(1, #extmarks.comments_at_cursor(source_buffer, store))
  require("document_comments.commands").edit()
  draft_buffer = vim.api.nvim_get_current_buf()
  assert(draft_buffer ~= source_buffer)
  vim.api.nvim_buf_set_lines(draft_buffer, 0, -1, false, { "Updated from the same line." })
  vim.cmd.stopinsert()
  vim.cmd.write()
  store = assert(storage.load(ctx))
  eq("Updated from the same line.", store.comments[1].body)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  require("document_comments.commands").resolve()
  store = assert(storage.load(ctx))
  eq("resolved", store.comments[1].status)
  require("document_comments.commands").resolve()
  store = assert(storage.load(ctx))
  eq("open", store.comments[1].status)

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
  eq("open", store.comments[1].status)
  local signs = vim.api.nvim_buf_get_extmarks(source_buffer, extmarks.sign_namespace, 0, -1, { details = true })
  eq("!", vim.trim(signs[1][4].sign_text))
  assert(require("document_comments").statusline(source_buffer):match("!1"))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  eq(store.comments[1].id, extmarks.comments_at_cursor(source_buffer, store)[1].id)

  storage._reset()
  store = assert(storage.load(ctx))
  eq("orphaned", store.comments[1].anchor.state)

  local original_select = vim.ui.select
  local saw_action_menu = false
  local saw_confirmation = false
  vim.ui.select = function(items, _, callback)
    if type(items[1]) == "table" then
      callback(items[1])
    elseif vim.list_contains(items, "Delete comment") then
      saw_action_menu = true
      callback("Delete comment")
    else
      saw_confirmation = true
      callback("Delete")
    end
  end
  require("document_comments.commands").list("open", "file")
  vim.ui.select = original_select
  assert(saw_action_menu and saw_confirmation)
  store = assert(storage.load(ctx))
  eq(0, #store.comments)
end)

test("v1 stores migrate in memory and persist v2 only on a successful write", function()
  storage._reset()
  local ctx = context(tempdir())
  local legacy = model.new_store()
  legacy.schema_version = 1
  legacy.export_batches = nil
  local comment = sample_comment("Legacy feedback")
  comment.kind = nil
  comment.status = "resolved"
  comment.resolved_at = model.now()
  legacy.comments = { comment }
  local raw = vim.json.encode(legacy)
  write(ctx.store_path, raw)
  local loaded = assert(storage.load(ctx))
  eq(2, loaded.schema_version)
  eq("comment", loaded.comments[1].kind)
  eq("resolved", loaded.comments[1].status)
  eq({}, loaded.export_batches)
  eq(raw, read(ctx.store_path))
  local saved = assert(storage.mutate(ctx, function(store)
    store.comments[1].body = "Updated legacy feedback"
  end))
  storage._reset()
  eq(saved, assert(storage.load(ctx)))
  eq(2, vim.json.decode(read(ctx.store_path)).schema_version)
end)

test("typed annotations permit empty notes but comments and invalid kinds are rejected", function()
  local store = model.new_store()
  local comment = sample_comment()
  comment.body = ""
  store.comments = { comment }
  assert(not model.validate(store))
  for _, kind in ipairs({ "delete", "looks_good" }) do
    comment.kind = kind
    assert(model.validate(store))
  end
  comment.kind = "unknown"
  local valid, err = model.validate(store)
  assert(not valid and err:match("invalid annotation kind"))
  comment.kind = "comment"
  comment.body = "Valid comment"
  assert(model.validate(store))
  store.export_batches = "invalid"
  assert(not model.validate(store))
end)

test("exports use adaptive fences and explicit delete/positive-feedback instructions", function()
  local comment = sample_comment("Review this Markdown")
  comment.anchor.current.quote.exact = "```lua\nprint('hello')\n```\n````"
  comment.anchor.original.quote.exact = comment.anchor.current.quote.exact
  local deletion = sample_comment()
  deletion.kind, deletion.body = "delete", ""
  local approval = sample_comment()
  approval.kind, approval.body = "looks_good", ""
  local store = model.new_store()
  store.comments = { comment, deletion, approval }
  local output = exporter.render(store, store.comments, "hash")
  assert(output:find("`````text\n" .. comment.anchor.current.quote.exact .. "\n`````", 1, true))
  assert(output:find("- Type: delete", 1, true))
  assert(output:find("Remove the selected text", 1, true))
  assert(output:find("- Type: looks_good", 1, true))
  assert(output:find("do not change this text solely", 1, true))
end)

test("incremental exports survive restart, preserve versions, and ignore anchor movement", function()
  storage._reset()
  local ctx = context(tempdir())
  local first = sample_comment("Original feedback")
  local second = sample_comment("Other file feedback")
  second.source.path = "other.md"
  assert(storage.mutate(ctx, function(store)
    store.comments = { first, second }
  end))
  local _, count = exporter.write(ctx, "project", nil, nil, "new")
  eq(2, count)
  local previous_export = read(ctx.export_path)
  local previous_revision = assert(storage.load(ctx)).store_revision
  local path, err = exporter.write(ctx, "project", nil, nil, "new")
  assert(not path and err:match("no new or edited"))
  eq(previous_export, read(ctx.export_path))
  eq(previous_revision, assert(storage.load(ctx)).store_revision)

  assert(storage.mutate(ctx, function(store)
    local target = model.find(store, first.id)
    target.anchor.current.position.start.line = 3
    target.anchor.current.position["end"].line = 3
    target.anchor.current.document_hash = model.hash("moved document")
    target.anchor.current.quote.prefix = "Moved context"
    target.updated_at = "2026-10-12T00:01:00Z"
  end))
  storage._reset()
  local loaded = assert(storage.load(ctx))
  assert(not model.is_pending(model.find(loaded, first.id), model.exported_fingerprints(loaded)))
  assert(storage.mutate(ctx, function(store)
    model.find(store, first.id).body = "Edited feedback"
  end))
  path, count = exporter.write(ctx, "file", nil, nil, "new")
  assert(path)
  eq(1, count)
  loaded = assert(storage.load(ctx))
  eq(2, #loaded.export_batches)
  eq("Original feedback", loaded.export_batches[1].comments[1].body)
  eq("Edited feedback", loaded.export_batches[2].comments[1].body)
  eq("open", model.find(loaded, first.id).status)
  assert(read(path):find(first.id, 1, true))
  assert(not read(path):find(second.id, 1, true))

  assert(storage.mutate(ctx, function(store)
    model.find(store, second.id).body = "Other file edited"
  end))
  local current = model.find(assert(storage.load(ctx)), first.id)
  path, err = exporter.write(ctx, "current", nil, current, "new")
  assert(not path and err:match("no new or edited"))
  _, count = exporter.write(ctx, "project", nil, nil, "new")
  eq(1, count)
  _, count = exporter.write(ctx, "project", nil, nil, "all")
  eq(2, count)
  storage._reset()
  loaded = assert(storage.load(ctx))
  eq(4, #loaded.export_batches)
  eq("all", loaded.export_batches[4].mode)
  assert(not model.is_pending(loaded.comments[1], model.exported_fingerprints(loaded)))
end)

test("kind, selected text, and anchor safety changes are new feedback but resolved notes are excluded", function()
  storage._reset()
  local ctx = context(tempdir())
  local comment = sample_comment()
  assert(storage.mutate(ctx, function(store)
    store.comments = { comment }
  end))
  assert(exporter.write(ctx, "project", nil, nil, "new"))
  for _, change in ipairs({
    function(target)
      target.kind = "delete"
    end,
    function(target)
      target.anchor.current.quote.exact = "new selection"
    end,
    function(target)
      target.anchor.state = "orphaned"
    end,
  }) do
    assert(storage.mutate(ctx, function(store)
      change(store.comments[1])
    end))
    local loaded = assert(storage.load(ctx))
    assert(model.is_pending(loaded.comments[1], model.exported_fingerprints(loaded)))
    local _, count = exporter.write(ctx, "project", nil, nil, "new")
    eq(1, count)
  end
  assert(storage.mutate(ctx, function(store)
    store.comments[1].body = "Edited but resolved"
    store.comments[1].status = "resolved"
    store.comments[1].resolved_at = model.now()
  end))
  assert(not exporter.write(ctx, "project", nil, nil, "new"))
  assert(not exporter.write(ctx, "project", nil, nil, "all"))
end)

test("export failures never mark feedback exported and cannot overwrite the store", function()
  storage._reset()
  local ctx = context(tempdir())
  assert(storage.mutate(ctx, function(store)
    store.comments = { sample_comment() }
  end))
  local before = read(ctx.store_path)
  local path, err = exporter.write(ctx, "project", ctx.store_path, nil, "new")
  assert(not path and err:match("cannot overwrite"))
  eq(before, read(ctx.store_path))
  path, err = exporter.write(ctx, "project", ctx.storage_dir, nil, "new")
  assert(not path)
  eq(before, read(ctx.store_path))
  eq(0, #assert(storage.load(ctx)).export_batches)
  local original_io = storage.io
  storage.io = vim.tbl_extend("force", {}, original_io, {
    fs_rename = function(from, to)
      if to == ctx.store_path then
        return nil, "injected batch-record failure"
      end
      return original_io.fs_rename(from, to)
    end,
  })
  path, err = exporter.write(ctx, "project", nil, nil, "new")
  storage.io = original_io
  assert(not path and err:match("batch could not be recorded"))
  eq(before, read(ctx.store_path))
  assert(read(ctx.export_path):match("Export batch: b_"))
  local loaded = assert(storage.load(ctx))
  eq(0, #loaded.export_batches)
  assert(model.is_pending(loaded.comments[1], model.exported_fingerprints(loaded)))
  assert(exporter.write(ctx, "project", nil, nil, "new"))

  write(ctx.store_path, read(ctx.store_path) .. " ")
  local export_before = read(ctx.export_path)
  path, err = exporter.write(ctx, "project", nil, nil, "all")
  assert(not path and err:match("conflict"))
  eq(export_before, read(ctx.export_path))
end)

test("visual shortcuts create typed annotations without changing the source or normal delete mapping", function()
  storage._reset()
  local project = tempdir()
  vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p", 448)
  local document = vim.fs.joinpath(project, "typed.md")
  write(document, "alpha beta")
  vim.cmd.edit(vim.fn.fnameescape(document))
  vim.bo.filetype = "markdown"
  local buffer = vim.api.nvim_get_current_buf()
  local ctx = assert(root.for_buffer(buffer))
  eq("", vim.fn.maparg("<leader>d", "x"))
  eq("", vim.fn.maparg("<leader>g", "x"))
  for _, item in ipairs({ { "<leader>ad", "delete" }, { "<leader>ag", "looks_good" } }) do
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    local mapping = vim.fn.maparg(item[1], "x", false, true)
    assert(mapping.buffer == 1 and type(mapping.callback) == "function")
    mapping.callback()
    eq(buffer, vim.api.nvim_get_current_buf())
    local loaded = assert(storage.load(ctx))
    eq(item[2], loaded.comments[#loaded.comments].kind)
    eq("", loaded.comments[#loaded.comments].body)
    eq("alpha", loaded.comments[#loaded.comments].anchor.current.quote.exact)
    assert(not vim.bo[buffer].modified)
    eq("alpha beta", read(document))
  end
  eq("Delete document comment", vim.fn.maparg("<leader>ad", "n", false, true).desc)
  eq("Add delete annotation", vim.fn.maparg("<leader>ad", "x", false, true).desc)
  local original_select = vim.ui.select
  vim.ui.select = function(items, _, callback)
    callback(items[1])
  end
  require("document_comments.commands").edit()
  vim.ui.select = original_select
  local draft = vim.api.nvim_get_current_buf()
  if draft ~= buffer then
    vim.cmd.stopinsert()
    vim.cmd.write()
  end
  local saved
  local draft_buffer, draft_window = require("document_comments.ui.editor").open({
    id = "empty-typed-test",
    root = ctx.root,
    allow_empty = true,
    save = function(body)
      saved = body
      return true
    end,
  })
  vim.cmd.stopinsert()
  vim.cmd.write()
  eq("", saved)
  assert(not vim.api.nvim_win_is_valid(draft_window))
  assert(not vim.api.nvim_buf_is_valid(draft_buffer))
end)

test("export commands default to incremental and accept explicit all with scope and path", function()
  storage._reset()
  local project = tempdir()
  vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p", 448)
  local document = vim.fs.joinpath(project, "commands.md")
  write(document, "æ😊 suffix")
  vim.cmd.edit(vim.fn.fnameescape(document))
  vim.bo.filetype = "markdown"
  local ctx = assert(root.for_buffer(0))
  assert(storage.mutate(ctx, function(store)
    local comment = sample_comment()
    comment.source.path = "commands.md"
    store.comments = { comment }
  end))
  local commands = require("document_comments.commands")
  commands.export("")
  eq("new", assert(storage.load(ctx)).export_batches[1].mode)
  commands.export("project")
  eq(1, #assert(storage.load(ctx)).export_batches)
  local custom = vim.fs.joinpath(project, "custom export.md")
  commands.export("all file " .. custom)
  eq(custom, assert(storage.load(ctx)).export_batches[2].path)
  assert(read(custom):match("Type: comment"))
  eq("open", assert(storage.load(ctx)).comments[1].status)
end)

test("sidebar previews selections, filters scopes, refreshes actions, and keeps manual resolution", function()
  storage._reset()
  local sidebar = require("document_comments.ui.sidebar")
  sidebar.close()
  local project = tempdir()
  vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p", 448)
  local document = vim.fs.joinpath(project, "doc.md")
  write(document, "æ😊 suffix")
  write(vim.fs.joinpath(project, "other.md"), "æ😊 suffix")
  vim.cmd.edit(vim.fn.fnameescape(document))
  vim.bo.filetype = "markdown"
  local source_window, source_buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local ctx = assert(root.for_buffer(source_buffer))
  local open = sample_comment("Visible feedback")
  local resolved = sample_comment("Resolved feedback")
  resolved.status, resolved.resolved_at = "resolved", model.now()
  local detached = sample_comment("Detached feedback")
  detached.source.path, detached.anchor.state = "other.md", "orphaned"
  detached.anchor.current.quote.exact = "absent quote"
  assert(storage.mutate(ctx, function(store)
    store.comments = { open, resolved, detached }
  end))
  require("document_comments.extmarks").refresh(source_buffer)
  sidebar.toggle()
  local panel_window, panel_buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local function panel_text()
    return table.concat(vim.api.nvim_buf_get_lines(panel_buffer, 0, -1, false), "\n")
  end
  assert(panel_window ~= source_window)
  assert(panel_text():find("Visible feedback", 1, true))
  assert(not panel_text():find("Resolved feedback", 1, true))
  assert(panel_text():find("not exported", 1, true))
  local preview_ns = vim.api.nvim_create_namespace("document-comments-preview")
  eq(1, #vim.api.nvim_buf_get_extmarks(source_buffer, preview_ns, 0, -1, {}))
  sidebar.set_filter("resolved")
  assert(panel_text():find("Resolved feedback", 1, true))
  assert(not panel_text():find("Visible feedback", 1, true))
  sidebar.set_filter("all")
  sidebar.set_scope("project")
  assert(panel_text():find("Detached feedback", 1, true))
  sidebar.set_filter("review")
  assert(panel_text():find("Detached feedback", 1, true))
  assert(not panel_text():find("Visible feedback", 1, true))
  sidebar.set_scope("file")
  sidebar.set_filter("new")
  assert(panel_text():find("Visible feedback", 1, true))
  assert(exporter.write(ctx, "file", nil, nil, "new"))
  assert(panel_text():find("No annotations match", 1, true))
  sidebar.set_filter("open")
  assert(panel_text():find("exported", 1, true))
  assert(storage.mutate(ctx, function(store)
    model.find(store, open.id).body = "Edited in place"
  end))
  assert(panel_text():find("Edited in place", 1, true))
  assert(panel_text():find("edited since export", 1, true))
  vim.api.nvim_set_current_win(panel_window)
  vim.fn.maparg("r", "n", false, true).callback()
  eq("resolved", model.find(assert(storage.load(ctx)), open.id).status)
  assert(not panel_text():find("Edited in place", 1, true))
  sidebar.set_filter("resolved")
  assert(panel_text():find("Edited in place", 1, true))
  vim.api.nvim_set_current_win(panel_window)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(panel_buffer, 0, -1, false)) do
    if line:find("Edited in place", 1, true) then
      vim.api.nvim_win_set_cursor(panel_window, { row, 0 })
      break
    end
  end
  vim.fn.maparg("r", "n", false, true).callback()
  eq("open", model.find(assert(storage.load(ctx)), open.id).status)
  sidebar.close()
  assert(not vim.api.nvim_win_is_valid(panel_window))
  eq(0, #vim.api.nvim_buf_get_extmarks(source_buffer, preview_ns, 0, -1, {}))
end)

test("sidebar window switches preserve unsaved extmark movement and undo", function()
  storage._reset()
  local sidebar = require("document_comments.ui.sidebar")
  sidebar.close()
  local project = tempdir()
  vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p", 448)
  local document = vim.fs.joinpath(project, "live.md")
  write(document, "alpha beta")
  vim.cmd.edit(vim.fn.fnameescape(document))
  vim.bo.filetype = "markdown"
  local source_window, buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local ctx = assert(root.for_buffer(buffer))
  local comment = model.new_comment("live.md", {
    start = { line = 0, byte_column = 6 },
    ["end"] = { line = 0, byte_column = 10 },
  }, { exact = "beta", prefix = "alpha ", suffix = "" }, model.hash("alpha beta"), "Keep tracking beta")
  assert(storage.mutate(ctx, function(store)
    store.comments = { comment }
  end))
  local extmarks = require("document_comments.extmarks")
  extmarks.refresh(buffer)
  vim.api.nvim_buf_set_text(buffer, 0, 0, 0, 0, { "new " })
  eq(10, extmarks.comment_position(buffer, comment)[2])
  sidebar.toggle()
  local panel_window = vim.api.nvim_get_current_win()
  eq(10, extmarks.comment_position(buffer, comment)[2])
  vim.api.nvim_set_current_win(source_window)
  eq(10, extmarks.comment_position(buffer, comment)[2])
  vim.cmd.undo()
  eq(6, extmarks.comment_position(buffer, comment)[2])
  vim.cmd.redo()
  eq(10, extmarks.comment_position(buffer, comment)[2])
  vim.cmd.write()
  eq(10, assert(storage.load(ctx)).comments[1].anchor.current.position.start.byte_column)
  vim.api.nvim_set_current_win(panel_window)
  sidebar.close()
end)

test("sidebar batch history shows the exact original export after edits and deletion", function()
  storage._reset()
  local ctx = context(tempdir())
  local comment = sample_comment("Original batch body")
  assert(storage.mutate(ctx, function(store)
    store.comments = { comment }
  end))
  assert(exporter.write(ctx, "project", nil, nil, "new"))
  local original = assert(storage.load(ctx)).export_batches[1].markdown
  assert(storage.mutate(ctx, function(store)
    store.comments = {}
  end))
  storage._reset()
  local original_select = vim.ui.select
  vim.ui.select = function(items, opts, callback)
    eq(1, #items)
    assert(opts.format_item(items[1]):match("1 annotations"))
    callback(items[1])
  end
  require("document_comments.ui.sidebar").batches(ctx)
  vim.ui.select = original_select
  local buffer = vim.api.nvim_get_current_buf()
  eq(original, table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n"))
  assert(not vim.bo[buffer].modifiable)
  vim.fn.maparg("q", "n", false, true).callback()
end)

test("typed source annotations have distinct highlights and single-annotation signs", function()
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "æ😊 suffix", "æ😊 suffix", "æ😊 suffix" })
  vim.bo[buffer].modified = false
  local ctx = context(tempdir())
  local comments = {}
  for row, kind in ipairs({ "comment", "delete", "looks_good" }) do
    local comment = sample_comment(kind == "comment" and "Note" or "")
    comment.kind = kind
    comment.anchor.current.position.start.line = row - 1
    comment.anchor.current.position["end"].line = row - 1
    table.insert(comments, comment)
  end
  local extmarks = require("document_comments.extmarks")
  extmarks.apply(buffer, ctx, comments)
  local marks = vim.api.nvim_buf_get_extmarks(buffer, extmarks.namespace, 0, -1, { details = true })
  eq("DocumentCommentOpen", marks[1][4].hl_group)
  eq("DocumentCommentDelete", marks[2][4].hl_group)
  eq("DocumentCommentLooksGood", marks[3][4].hl_group)
  local signs = vim.api.nvim_buf_get_extmarks(buffer, extmarks.sign_namespace, 0, -1, { details = true })
  eq("●", vim.trim(signs[1][4].sign_text))
  eq("−", vim.trim(signs[2][4].sign_text))
  eq("✓", vim.trim(signs[3][4].sign_text))
end)

test("sidebar type conversion requires a comment body and editing returns to the panel", function()
  storage._reset()
  local sidebar = require("document_comments.ui.sidebar")
  sidebar.close()
  local project = tempdir()
  vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p", 448)
  local document = vim.fs.joinpath(project, "convert.md")
  write(document, "æ😊 suffix")
  vim.cmd.edit(vim.fn.fnameescape(document))
  vim.bo.filetype = "markdown"
  local ctx = assert(root.for_buffer(0))
  local annotation = sample_comment()
  annotation.kind, annotation.body, annotation.source.path = "looks_good", "", "convert.md"
  assert(storage.mutate(ctx, function(store)
    store.comments = { annotation }
  end))
  require("document_comments.extmarks").refresh(0)
  sidebar.toggle()
  local panel_window, panel_buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local original_select = vim.ui.select
  vim.ui.select = function(_, _, callback)
    callback("comment")
  end
  vim.fn.maparg("t", "n", false, true).callback()
  vim.ui.select = original_select
  local draft = vim.api.nvim_get_current_buf()
  assert(draft ~= panel_buffer)
  eq("looks_good", assert(storage.load(ctx)).comments[1].kind)
  vim.api.nvim_buf_set_lines(draft, 0, -1, false, { "Please clarify this." })
  vim.cmd.stopinsert()
  vim.cmd.write()
  assert(vim.wait(1000, function()
    return vim.api.nvim_get_current_win() == panel_window
  end))
  local saved = assert(storage.load(ctx)).comments[1]
  eq("comment", saved.kind)
  eq("Please clarify this.", saved.body)
  local text = table.concat(vim.api.nvim_buf_get_lines(panel_buffer, 0, -1, false), "\n")
  assert(text:find("Please clarify this.", 1, true))
  sidebar.close()
end)

test("sidebar reattachment targets only the selected annotation and permanent deletion confirms", function()
  storage._reset()
  local sidebar = require("document_comments.ui.sidebar")
  sidebar.close()
  local project = tempdir()
  vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p", 448)
  local document = vim.fs.joinpath(project, "reattach.md")
  write(document, "alpha beta gamma")
  vim.cmd.edit(vim.fn.fnameescape(document))
  vim.bo.filetype = "markdown"
  local ctx = assert(root.for_buffer(0))
  local first, second = sample_comment("First detached"), sample_comment("Second detached")
  for _, comment in ipairs({ first, second }) do
    comment.source.path = "reattach.md"
    comment.anchor.current.quote.exact = "absent"
    comment.anchor.state = "orphaned"
  end
  assert(storage.mutate(ctx, function(store)
    store.comments = { first, second }
  end))
  require("document_comments.extmarks").refresh(0)
  sidebar.toggle()
  local panel_window, panel_buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  for row, line in ipairs(vim.api.nvim_buf_get_lines(panel_buffer, 0, -1, false)) do
    if line:find("Second detached", 1, true) then
      vim.api.nvim_win_set_cursor(panel_window, { row, 0 })
      break
    end
  end
  vim.fn.maparg("a", "n", false, true).callback()
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { 1, 9 })
  require("document_comments.commands").reattach()
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  local saved = assert(storage.load(ctx))
  eq("orphaned", model.find(saved, first.id).anchor.state)
  eq("attached", model.find(saved, second.id).anchor.state)
  eq("beta", model.find(saved, second.id).anchor.current.quote.exact)
  vim.api.nvim_set_current_win(panel_window)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(panel_buffer, 0, -1, false)) do
    if line:find("Second detached", 1, true) then
      vim.api.nvim_win_set_cursor(panel_window, { row, 0 })
      break
    end
  end
  local original_select = vim.ui.select
  local saw_confirmation = false
  vim.ui.select = function(items, opts, callback)
    eq({ "Cancel", "Delete" }, items)
    assert(opts.prompt:find(second.id, 1, true))
    saw_confirmation = true
    callback("Delete")
  end
  vim.fn.maparg("d", "n", false, true).callback()
  vim.ui.select = original_select
  assert(saw_confirmation)
  assert(not model.find(assert(storage.load(ctx)), second.id))
  assert(model.find(assert(storage.load(ctx)), first.id))
  assert(vim.api.nvim_win_is_valid(panel_window))
  sidebar.close()
end)

test("sidebar external-store reload preserves drafts and shows corrupt-store errors", function()
  storage._reset()
  local sidebar = require("document_comments.ui.sidebar")
  sidebar.close()
  local project = tempdir()
  vim.fn.mkdir(vim.fs.joinpath(project, ".git"), "p", 448)
  local document = vim.fs.joinpath(project, "external.md")
  write(document, "æ😊 suffix")
  vim.cmd.edit(vim.fn.fnameescape(document))
  vim.bo.filetype = "markdown"
  local ctx = assert(root.for_buffer(0))
  local annotation = sample_comment("Initial feedback")
  annotation.source.path = "external.md"
  assert(storage.mutate(ctx, function(store)
    store.comments = { annotation }
  end))
  require("document_comments.extmarks").refresh(0)
  sidebar.toggle()
  local panel_window, panel_buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local updated = vim.deepcopy(assert(storage.load(ctx)))
  updated.comments[1].body = "External edit"
  write(ctx.store_path, vim.json.encode(updated))
  sidebar.check_external_change()
  eq("External edit", assert(storage.load(ctx)).comments[1].body)
  local text = table.concat(vim.api.nvim_buf_get_lines(panel_buffer, 0, -1, false), "\n")
  assert(text:find("External edit", 1, true))
  local draft_buffer, draft_window = require("document_comments.ui.editor").open({
    id = "external-sidebar-draft",
    root = ctx.root,
    body = "Unsaved draft",
    save = function()
      return true
    end,
  })
  updated.comments[1].body = "Another external edit"
  write(ctx.store_path, vim.json.encode(updated))
  vim.cmd.stopinsert()
  vim.api.nvim_set_current_win(panel_window)
  sidebar.check_external_change()
  eq("External edit", assert(storage.load(ctx)).comments[1].body)
  eq({ "Unsaved draft" }, vim.api.nvim_buf_get_lines(draft_buffer, 0, -1, false))
  vim.api.nvim_win_close(draft_window, true)
  sidebar.check_external_change()
  eq("Another external edit", assert(storage.load(ctx)).comments[1].body)
  write(ctx.store_path, "invalid json")
  sidebar.check_external_change()
  text = table.concat(vim.api.nvim_buf_get_lines(panel_buffer, 0, -1, false), "\n")
  assert(text:find("Store error:", 1, true))
  assert(text:find("invalid JSON", 1, true))
  sidebar.close()
end)

test("sidebar can close safely after its source window has been closed", function()
  storage._reset()
  local sidebar = require("document_comments.ui.sidebar")
  sidebar.close()
  local project = tempdir()
  local document = vim.fs.joinpath(project, "last-window.md")
  write(document, "A saved document")
  vim.cmd.edit(vim.fn.fnameescape(document))
  vim.bo.filetype = "markdown"
  vim.wo.number = true
  local source_window, source_buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  sidebar.toggle()
  local panel_window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_close(source_window, true)
  sidebar.close()
  assert(vim.api.nvim_win_is_valid(panel_window))
  eq(source_buffer, vim.api.nvim_win_get_buf(panel_window))
  assert(vim.wo[panel_window].number)
end)

test("Visual Ex command accepts annotation types and export command completion offers valid scopes", function()
  storage._reset()
  local project = tempdir()
  local document = vim.fs.joinpath(project, "ex-command.md")
  write(document, "alpha beta")
  vim.cmd.edit(vim.fn.fnameescape(document))
  vim.bo.filetype = "markdown"
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { 1, 4 })
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  vim.cmd("'<,'>DocumentCommentsAdd delete")
  local ctx = assert(root.for_buffer(0))
  local stored = assert(storage.load(ctx))
  eq(1, #stored.comments)
  eq("delete", stored.comments[1].kind)
  eq("alpha", stored.comments[1].anchor.current.quote.exact)
  eq({ "project", "file", "current" }, vim.fn.getcompletion("DocumentCommentsExport new ", "cmdline"))
end)

print(("document-comments: %d tests passed"):format(passed))
vim.cmd("qa!")
