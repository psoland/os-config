local M = {}

local function key(token)
  return token:gsub("^@", "")
end

function M.tokens(body)
  local tokens = {}
  local seen = {}
  for token in body:gmatch("@c_[0-9a-f]+") do
    if not seen[token] then
      seen[token] = true
      table.insert(tokens, token)
    end
  end
  return tokens
end

function M.resolve(store, token)
  local prefix = key(token)
  local matches = {}
  for _, comment in ipairs(store.comments) do
    if comment.id == prefix then
      return { token = token, state = "exact", comment = comment }
    end
    if comment.id:sub(1, #prefix) == prefix then
      table.insert(matches, comment)
    end
  end
  if #matches == 1 then
    return { token = token, state = "unique-prefix", comment = matches[1] }
  end
  if #matches > 1 then
    return { token = token, state = "ambiguous", matches = matches }
  end
  return { token = token, state = "missing" }
end

function M.inspect(store, body)
  local results = {}
  for _, token in ipairs(M.tokens(body)) do
    table.insert(results, M.resolve(store, token))
  end
  return results
end

function M.targets(store, body)
  local targets = {}
  local issues = {}
  local seen = {}
  for _, result in ipairs(M.inspect(store, body)) do
    if result.comment then
      if not seen[result.comment.id] then
        seen[result.comment.id] = true
        table.insert(targets, result.comment)
      end
    else
      table.insert(issues, result)
    end
  end
  return targets, issues
end

function M.backlinks(store, target_id)
  local backlinks = {}
  for _, comment in ipairs(store.comments) do
    if comment.id ~= target_id then
      for _, result in ipairs(M.inspect(store, comment.body)) do
        if result.comment and result.comment.id == target_id then
          table.insert(backlinks, comment)
          break
        end
      end
    end
  end
  return backlinks
end

local function summary(body)
  local text = body:gsub("%s+", " ")
  if vim.fn.strchars(text) > 36 then
    return vim.fn.strcharpart(text, 0, 35) .. "…"
  end
  return text
end

function M.completions(store, exclude_id)
  local items = {}
  for _, comment in ipairs(store.comments) do
    if comment.id ~= exclude_id then
      table.insert(items, {
        word = "@" .. comment.id,
        abbr = "@" .. comment.id,
        menu = ("  %s:%d  %s"):format(
          vim.fs.basename(comment.source.path),
          comment.anchor.current.position.start.line + 1,
          summary(comment.body)
        ),
        dup = 0,
      })
    end
  end
  table.sort(items, function(left, right)
    return left.word < right.word
  end)
  return items
end

function M.warnings(store, body, self_id)
  local warnings = {}
  for _, result in ipairs(M.inspect(store, body)) do
    if result.state == "missing" then
      table.insert(warnings, result.token .. " does not match a comment")
    elseif result.state == "ambiguous" then
      table.insert(warnings, result.token .. " matches more than one comment")
    elseif self_id and result.comment.id == self_id then
      table.insert(warnings, result.token .. " refers to the comment itself")
    end
  end
  return warnings
end

function M.walk(store, comment)
  local linked = {}
  local issues = {}
  local visited = { [comment.id] = true }
  local seen_issues = {}

  local function visit(body, depth)
    for _, result in ipairs(M.inspect(store, body)) do
      if result.comment then
        if not visited[result.comment.id] then
          visited[result.comment.id] = true
          table.insert(linked, { comment = result.comment, depth = depth, token = result.token })
          visit(result.comment.body, depth + 1)
        end
      else
        local issue_key = result.token .. "\0" .. result.state
        if not seen_issues[issue_key] then
          seen_issues[issue_key] = true
          table.insert(issues, result)
        end
      end
    end
  end

  visit(comment.body, 1)
  return linked, issues
end

return M
