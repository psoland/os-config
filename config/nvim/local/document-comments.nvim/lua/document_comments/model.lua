local config = require("document_comments.config")

local M = { schema_version = 1 }

local statuses = { open = true, resolved = true }
local anchor_states = { attached = true, ambiguous = true, orphaned = true }

local function is_integer(value)
  return type(value) == "number" and value >= 0 and value % 1 == 0
end

local function is_null(value)
  return value == nil or value == vim.NIL
end

local function valid_position(value)
  return type(value) == "table" and is_integer(value.line) and is_integer(value.byte_column)
end

local function valid_quote(value)
  return type(value) == "table"
    and type(value.exact) == "string"
    and value.exact ~= ""
    and type(value.prefix) == "string"
    and type(value.suffix) == "string"
    and vim.fn.strchars(value.prefix) <= 128
    and vim.fn.strchars(value.suffix) <= 128
end

local function valid_hash(value)
  return type(value) == "string" and value:match("^[0-9a-f]+$") ~= nil and #value == 64
end

local function valid_timestamp(value)
  return type(value) == "string" and value:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil
end

local function valid_snapshot(value)
  if
    not (
      type(value) == "table"
      and valid_hash(value.document_hash)
      and type(value.position) == "table"
      and valid_position(value.position.start)
      and valid_position(value.position["end"])
      and valid_quote(value.quote)
    )
  then
    return false
  end
  local start = value.position.start
  local finish = value.position["end"]
  return finish.line > start.line or (finish.line == start.line and finish.byte_column > start.byte_column)
end

local function valid_relative_path(path)
  return type(path) == "string"
    and path ~= ""
    and not path:match("^[/\\]")
    and not path:match("^%a:[/\\]")
    and not path:match("^%.%.[/\\]")
    and not path:match("[/\\]%.%.[/\\]")
    and not path:match("[/\\]%.%.$")
    and not path:find("\\")
end

function M.now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function M.hash(text)
  return vim.fn.sha256(text)
end

function M.canonical_text(lines)
  return table.concat(lines, "\n")
end

function M.document_text(bufnr)
  return M.canonical_text(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
end

function M.document_hash(bufnr)
  return M.hash(M.document_text(bufnr))
end

function M.new_id()
  local seed =
    table.concat({ tostring(vim.uv.hrtime()), tostring(vim.uv.os_getpid()), tostring(math.random()), M.now() }, ":")
  return "c_" .. M.hash(seed):sub(1, 20)
end

function M.new_store()
  return {
    comments = {},
    schema_version = M.schema_version,
    store_revision = 0,
    updated_at = M.now(),
  }
end

local function context_part(text, start_byte, end_byte, limit)
  local prefix = text:sub(1, start_byte)
  local suffix = text:sub(end_byte + 1)
  local prefix_chars = vim.fn.strchars(prefix)
  if prefix_chars > limit then
    prefix = vim.fn.strcharpart(prefix, prefix_chars - limit, limit)
  end
  suffix = vim.fn.strcharpart(suffix, 0, limit)
  return prefix, suffix
end

function M.quote(text, start_byte, end_byte)
  local prefix, suffix = context_part(text, start_byte, end_byte, config.options.context_chars)
  return {
    exact = text:sub(start_byte + 1, end_byte),
    prefix = prefix,
    suffix = suffix,
  }
end

function M.new_comment(source_path, position, quote, document_hash, body)
  local timestamp = M.now()
  local snapshot = {
    document_hash = document_hash,
    position = vim.deepcopy(position),
    quote = vim.deepcopy(quote),
  }
  return {
    anchor = {
      current = vim.deepcopy(snapshot),
      original = vim.deepcopy(snapshot),
      state = "attached",
    },
    body = body,
    created_at = timestamp,
    id = M.new_id(),
    resolved_at = vim.NIL,
    source = { path = source_path },
    status = "open",
    updated_at = timestamp,
  }
end

function M.validate(store)
  if type(store) ~= "table" then
    return nil, "store root must be an object"
  end
  if store.schema_version ~= M.schema_version then
    if type(store.schema_version) == "number" and store.schema_version > M.schema_version then
      return nil,
        ("schema version %s is newer than supported version %d; store is read-only"):format(
          tostring(store.schema_version),
          M.schema_version
        )
    end
    return nil, ("unsupported schema version %s"):format(tostring(store.schema_version))
  end
  if
    not is_integer(store.store_revision)
    or not valid_timestamp(store.updated_at)
    or type(store.comments) ~= "table"
    or not vim.islist(store.comments)
  then
    return nil, "store metadata is invalid"
  end
  local ids = {}
  for index, comment in ipairs(store.comments) do
    local prefix = "comment " .. index
    if type(comment) ~= "table" or type(comment.id) ~= "string" or comment.id == "" then
      return nil, prefix .. " has an invalid id"
    end
    if ids[comment.id] then
      return nil, "duplicate comment id " .. comment.id
    end
    ids[comment.id] = true
    if not statuses[comment.status] then
      return nil, prefix .. " has an invalid status"
    end
    if
      type(comment.anchor) ~= "table"
      or not anchor_states[comment.anchor.state]
      or not valid_snapshot(comment.anchor.original)
      or not valid_snapshot(comment.anchor.current)
    then
      return nil, prefix .. " has an invalid anchor"
    end
    if type(comment.source) ~= "table" or not valid_relative_path(comment.source.path) then
      return nil, prefix .. " has an invalid source path"
    end
    if type(comment.body) ~= "string" or vim.trim(comment.body) == "" then
      return nil, prefix .. " has an empty body"
    end
    if not valid_timestamp(comment.created_at) or not valid_timestamp(comment.updated_at) then
      return nil, prefix .. " has invalid timestamps"
    end
    if comment.status == "resolved" and (is_null(comment.resolved_at) or not valid_timestamp(comment.resolved_at)) then
      return nil, prefix .. " is resolved without a valid resolved_at"
    end
    if comment.status == "open" and not is_null(comment.resolved_at) then
      return nil, prefix .. " is open with resolved_at"
    end
  end
  return true
end

function M.find(store, id)
  for index, comment in ipairs(store.comments) do
    if comment.id == id then
      return comment, index
    end
  end
end

return M
