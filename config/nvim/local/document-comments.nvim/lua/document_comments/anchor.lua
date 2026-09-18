local model = require("document_comments.model")

local M = {}

local function line_offsets(lines)
  local offsets = {}
  local offset = 0
  for index, line in ipairs(lines) do
    offsets[index] = offset
    offset = offset + #line
    if index < #lines then
      offset = offset + 1
    end
  end
  return offsets
end

function M.position_to_offset(lines, position)
  local row = position.line + 1
  if row < 1 or row > #lines then
    return nil
  end
  if position.byte_column < 0 or position.byte_column > #lines[row] then
    return nil
  end
  local offsets = line_offsets(lines)
  return offsets[row] + position.byte_column
end

function M.offset_to_position(lines, offset)
  if offset < 0 then
    return nil
  end
  local offsets = line_offsets(lines)
  for row = #lines, 1, -1 do
    if offset >= offsets[row] then
      local column = offset - offsets[row]
      if column <= #lines[row] then
        return { line = row - 1, byte_column = column }
      end
    end
  end
end

function M.text_at(lines, position)
  local start_offset = M.position_to_offset(lines, position.start)
  local end_offset = M.position_to_offset(lines, position["end"])
  if not start_offset or not end_offset or end_offset < start_offset then
    return nil
  end
  return model.canonical_text(lines):sub(start_offset + 1, end_offset)
end

local function candidate(text, lines, start_offset, exact)
  local end_offset = start_offset + #exact
  return {
    start_offset = start_offset,
    end_offset = end_offset,
    position = {
      start = M.offset_to_position(lines, start_offset),
      ["end"] = M.offset_to_position(lines, end_offset),
    },
  }
end

function M.find_candidates(lines, exact)
  if exact == "" then
    return {}
  end
  local text = model.canonical_text(lines)
  local candidates = {}
  local from = 1
  while from <= #text do
    local found = text:find(exact, from, true)
    if not found then
      break
    end
    local item = candidate(text, lines, found - 1, exact)
    if item.position.start and item.position["end"] then
      table.insert(candidates, item)
    end
    from = found + 1
  end
  return candidates
end

local function context_matches(text, item, quote)
  local prefix = quote.prefix or ""
  local suffix = quote.suffix or ""
  local before = text:sub(math.max(1, item.start_offset - #prefix + 1), item.start_offset)
  local after = text:sub(item.end_offset + 1, item.end_offset + #suffix)
  return (prefix == "" or before == prefix) and (suffix == "" or after == suffix)
end

local function attach(comment, lines, item, document_hash)
  comment.anchor.current = {
    document_hash = document_hash,
    position = item.position,
    quote = model.quote(model.canonical_text(lines), item.start_offset, item.end_offset),
  }
  comment.anchor.state = "attached"
end

function M.reanchor(comment, lines)
  local text = model.canonical_text(lines)
  local hash = model.hash(text)
  local current = comment.anchor.current
  local exact = current.quote.exact
  if M.text_at(lines, current.position) == exact then
    local start_offset = M.position_to_offset(lines, current.position.start)
    attach(comment, lines, candidate(text, lines, start_offset, exact), hash)
    return "attached"
  end

  local candidates = M.find_candidates(lines, exact)
  if #candidates == 1 then
    attach(comment, lines, candidates[1], hash)
    return "attached"
  end
  if #candidates > 1 then
    local matching = {}
    for _, item in ipairs(candidates) do
      if context_matches(text, item, current.quote) then
        table.insert(matching, item)
      end
    end
    if #matching == 1 then
      attach(comment, lines, matching[1], hash)
      return "attached"
    end
    comment.anchor.state = "ambiguous"
    return "ambiguous"
  end
  comment.anchor.state = "orphaned"
  return "orphaned"
end

return M
