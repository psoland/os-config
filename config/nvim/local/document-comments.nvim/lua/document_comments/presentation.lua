local M = {}

function M.needs_review(comment)
  return comment.status == "open"
    and (
      comment.anchor.state ~= "attached" or comment.anchor.current.quote.exact ~= comment.anchor.original.quote.exact
    )
end

function M.for_file(comments, source_path)
  local result = {
    comments = {},
    open = 0,
    resolved = 0,
    problem = 0,
    review = {},
  }
  for _, comment in ipairs(comments) do
    if comment.source.path == source_path then
      table.insert(result.comments, comment)
      if comment.status == "open" then
        result.open = result.open + 1
      else
        result.resolved = result.resolved + 1
      end
      if M.needs_review(comment) then
        result.problem = result.problem + 1
        table.insert(result.review, comment)
      end
    end
  end
  table.sort(result.review, function(left, right)
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
  return result
end

local severity = { resolved = 1, open = 2, problem = 3 }

function M.sign_groups(file, line_count, opts)
  if not opts.enabled or line_count < 1 then
    return {}
  end
  local groups = {}
  for _, comment in ipairs(file.comments) do
    if comment.status == "open" or opts.show_resolved then
      local row = math.max(0, math.min(comment.anchor.current.position.start.line, line_count - 1))
      local kind
      if M.needs_review(comment) then
        kind = "problem"
      elseif comment.status == "open" then
        kind = "open"
      else
        kind = "resolved"
      end
      local group = groups[row]
      if not group then
        group = { row = row, count = 0, kind = kind }
        groups[row] = group
      end
      group.count = group.count + 1
      if severity[kind] > severity[group.kind] then
        group.kind = kind
      end
    end
  end
  local result = {}
  for _, group in pairs(groups) do
    if group.count == 1 then
      group.text = opts[group.kind]
    elseif group.count < 10 then
      group.text = tostring(group.count)
    else
      group.text = "+"
    end
    table.insert(result, group)
  end
  table.sort(result, function(left, right)
    return left.row < right.row
  end)
  return result
end

function M.statusline(file, opts)
  if not opts.enabled or not file then
    return ""
  end
  local icon = opts.icon ~= "" and opts.icon or "Comments"
  if file.open > 0 then
    local text = icon .. " " .. file.open
    if file.problem > 0 then
      text = text .. " !" .. file.problem
    end
    return text
  end
  if file.resolved > 0 then
    return icon .. " ✓" .. file.resolved
  end
  return ""
end

return M
