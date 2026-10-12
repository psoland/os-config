local model = require("document_comments.model")
local references = require("document_comments.references")
local storage = require("document_comments.storage")

local M = {}

local function code(text)
  if not text:find("`", 1, true) and not text:find("\n", 1, true) then
    return "`" .. text .. "`"
  end
  local longest = 0
  for run in text:gmatch("`+") do
    longest = math.max(longest, #run)
  end
  local fence = string.rep("`", math.max(3, longest + 1))
  -- A fenced block must start on its own line, not after a list-item label.
  return "\n\n" .. fence .. "text\n" .. text .. "\n" .. fence
end

local function quote_body(body)
  return "> " .. body:gsub("\n", "\n> ")
end

local function append_reference_context(lines, store, comment)
  local linked, issues = references.walk(store, comment)
  if #linked == 0 and #issues == 0 then
    return
  end
  table.insert(lines, "### Referenced comments (context only)")
  table.insert(lines, "")
  for _, item in ipairs(linked) do
    local target = item.comment
    table.insert(
      lines,
      ("#### @%s — %s:%d"):format(target.id, target.source.path, target.anchor.current.position.start.line + 1)
    )
    table.insert(lines, "")
    table.insert(lines, "- Referenced via: `" .. item.token .. "`")
    table.insert(lines, "- Reference depth: " .. item.depth)
    table.insert(lines, "- Status: " .. target.status)
    table.insert(lines, "- Type: " .. model.kind(target))
    table.insert(lines, "- Anchor: " .. target.anchor.state)
    table.insert(lines, "")
    table.insert(lines, quote_body(target.body))
    table.insert(lines, "")
  end
  if #issues > 0 then
    table.insert(lines, "#### Unresolved references")
    table.insert(lines, "")
    for _, issue in ipairs(issues) do
      table.insert(lines, ("- `%s` — %s"):format(issue.token, issue.state))
    end
    table.insert(lines, "")
  end
end

function M.render(store, comments, raw_hash, batch_id)
  local lines = {
    "# Document comments",
    "",
    "Generated: " .. model.now(),
    "Store revision: " .. store.store_revision,
    "Store SHA-256: " .. tostring(raw_hash or "unavailable"),
    "",
    "Apply actionable feedback to the referenced source documents; looks_good annotations require no edit.",
    "Do not edit `comments.json`, this export, or comment statuses. Exported does not mean sent or resolved.",
    "Report what was done for each comment ID.",
    "Referenced-comment sections are context only, not additional tasks unless they also have their own top-level section.",
    "",
  }
  if batch_id then
    table.insert(lines, 6, "Export batch: " .. batch_id)
  end
  for _, comment in ipairs(comments) do
    local current = comment.anchor.current
    table.insert(lines, ("## %s — %s:%d"):format(comment.id, comment.source.path, current.position.start.line + 1))
    table.insert(lines, "")
    table.insert(lines, "- Status: " .. comment.status)
    local kind = model.kind(comment)
    table.insert(lines, "- Type: " .. kind)
    if kind == "delete" then
      table.insert(lines, "- Instruction: Remove the selected text. Any comment below explains why.")
    elseif kind == "looks_good" then
      table.insert(
        lines,
        "- Instruction: Positive feedback; do not change this text solely because of this annotation."
      )
    end
    table.insert(lines, "- Anchor: " .. comment.anchor.state)
    table.insert(
      lines,
      ("- Position: line %d, byte column %d"):format(
        current.position.start.line + 1,
        current.position.start.byte_column
      )
    )
    table.insert(lines, "- Selected text: " .. code(current.quote.exact))
    if current.quote.prefix ~= "" then
      table.insert(lines, "- Prefix: " .. code(current.quote.prefix))
    end
    if current.quote.suffix ~= "" then
      table.insert(lines, "- Suffix: " .. code(current.quote.suffix))
    end
    if comment.anchor.original.quote.exact ~= current.quote.exact then
      table.insert(lines, "- Original selected text: " .. code(comment.anchor.original.quote.exact))
    end
    table.insert(lines, "")
    table.insert(lines, quote_body(comment.body))
    table.insert(lines, "")
    append_reference_context(lines, store, comment)
  end
  return table.concat(lines, "\n") .. "\n"
end

function M.write(ctx, scope, path, current, mode)
  mode = mode or "all"
  if mode ~= "new" and mode ~= "all" then
    return nil, "export mode must be new or all"
  end
  if scope ~= "project" and scope ~= "file" and scope ~= "current" then
    return nil, "export scope must be project, file, or current"
  end
  local store, err = storage.load(ctx)
  if not store then
    return nil, err
  end
  local comments = {}
  local fingerprints = model.exported_fingerprints(store)
  for _, comment in ipairs(store.comments) do
    local include = comment.status == "open"
    if scope == "file" then
      include = include and comment.source.path == ctx.source_path
    elseif scope == "current" then
      include = include and current and comment.id == current.id
    end
    if include and (mode == "all" or model.is_pending(comment, fingerprints)) then
      table.insert(comments, comment)
    end
  end
  table.sort(comments, function(left, right)
    if left.source.path ~= right.source.path then
      return left.source.path < right.source.path
    end
    local lp = left.anchor.current.position.start
    local rp = right.anchor.current.position.start
    if lp.line ~= rp.line then
      return lp.line < rp.line
    end
    if lp.byte_column ~= rp.byte_column then
      return lp.byte_column < rp.byte_column
    end
    return left.id < right.id
  end)
  if #comments == 0 then
    return nil,
      mode == "new" and "no new or edited open comments matched the export scope"
        or "no open comments matched the export scope"
  end
  local destination = path and path ~= "" and vim.fs.abspath(path) or ctx.export_path
  destination = vim.fs.abspath(destination)
  local real_destination = vim.uv.fs_realpath(destination)
  if destination == ctx.store_path or (real_destination and real_destination == vim.uv.fs_realpath(ctx.store_path)) then
    return nil, "the export cannot overwrite the comment store"
  end
  local changed, check_error = storage.changed(ctx)
  if changed == nil or changed then
    return nil, check_error or "conflict: the store changed in another process; reload before exporting"
  end
  local batch_id = "b_" .. model.new_id():sub(3)
  local markdown = M.render(store, comments, storage.raw_hash(ctx), batch_id)
  local batch = {
    id = batch_id,
    exported_at = model.now(),
    path = destination,
    store_revision = store.store_revision,
    scope = scope,
    mode = mode,
    comments = vim.deepcopy(comments),
    markdown = markdown,
  }
  local ok, write_error = storage.write_snapshot(destination, markdown)
  if not ok then
    return nil, write_error
  end
  local saved, save_error = storage.mutate(ctx, function(next_store)
    table.insert(next_store.export_batches, batch)
  end)
  if not saved then
    return nil,
      "export file was written, but its batch could not be recorded; export coverage was not advanced: " .. save_error
  end
  return destination, #comments, batch_id
end

return M
