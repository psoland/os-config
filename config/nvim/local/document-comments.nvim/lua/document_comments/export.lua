local model = require("document_comments.model")
local references = require("document_comments.references")
local storage = require("document_comments.storage")

local M = {}

local function code(text)
  if not text:find("`", 1, true) and not text:find("\n", 1, true) then
    return "`" .. text .. "`"
  end
  return "```text\n" .. text .. "\n```"
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

function M.render(store, comments, raw_hash)
  local lines = {
    "# Document comments",
    "",
    "Generated: " .. model.now(),
    "Store revision: " .. store.store_revision,
    "Store SHA-256: " .. tostring(raw_hash or "unavailable"),
    "",
    "Edit the referenced source documents. Do not edit `comments.json`, this export, or comment statuses.",
    "Report what was done for each comment ID.",
    "Referenced-comment sections are context only, not additional tasks unless they also have their own top-level section.",
    "",
  }
  for _, comment in ipairs(comments) do
    local current = comment.anchor.current
    table.insert(lines, ("## %s — %s:%d"):format(comment.id, comment.source.path, current.position.start.line + 1))
    table.insert(lines, "")
    table.insert(lines, "- Status: " .. comment.status)
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

function M.write(ctx, scope, path, current)
  local store, err = storage.load(ctx)
  if not store then
    return nil, err
  end
  local comments = {}
  for _, comment in ipairs(store.comments) do
    local include = comment.status == "open"
    if scope == "file" then
      include = include and comment.source.path == ctx.source_path
    elseif scope == "current" then
      include = include and current and comment.id == current.id
    end
    if include then
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
    return nil, "no open comments matched the export scope"
  end
  local destination = path and path ~= "" and vim.fs.abspath(path) or ctx.export_path
  local ok, write_error = storage.write_snapshot(destination, M.render(store, comments, storage.raw_hash(ctx)))
  if not ok then
    return nil, write_error
  end
  return destination, #comments
end

return M
