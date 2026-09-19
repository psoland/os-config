local presentation = require("document_comments.presentation")

local M = {}

local function summary(body)
  local one_line = body:gsub("%s+", " ")
  if vim.fn.strchars(one_line) > 52 then
    return vim.fn.strcharpart(one_line, 0, 51) .. "…"
  end
  return one_line
end

local function marker(comment)
  if comment.anchor.state ~= "attached" or presentation.needs_review(comment) then
    return "!"
  end
  return comment.status == "resolved" and "○" or "●"
end

local function qualifier(comment)
  if comment.anchor.state ~= "attached" then
    return "[" .. comment.anchor.state .. "] "
  end
  if presentation.needs_review(comment) then
    return "[changed] "
  end
  return ""
end

function M.format_file(comment)
  local line = comment.anchor.current.position.start.line + 1
  return ("%s L%d  %s%s"):format(marker(comment), line, qualifier(comment), summary(comment.body))
end

function M.project_formatter(comments)
  local paths_by_basename = {}
  for _, comment in ipairs(comments) do
    local basename = vim.fs.basename(comment.source.path)
    paths_by_basename[basename] = paths_by_basename[basename] or {}
    paths_by_basename[basename][comment.source.path] = true
  end
  local collisions = {}
  for basename, paths in pairs(paths_by_basename) do
    local count = 0
    for _ in pairs(paths) do
      count = count + 1
    end
    collisions[basename] = count > 1
  end
  return function(comment)
    local line = comment.anchor.current.position.start.line + 1
    local basename = vim.fs.basename(comment.source.path)
    local path = collisions[basename] and comment.source.path or basename
    return ("%s %s:%d  %s%s"):format(marker(comment), path, line, qualifier(comment), summary(comment.body))
  end
end

M.format = M.format_file

function M.comment(comments, prompt, callback, always_select, formatter)
  if #comments == 0 then
    vim.notify("No matching document comments", vim.log.levels.INFO, { title = "Document comments" })
    return
  end
  if #comments == 1 and not always_select then
    callback(comments[1])
    return
  end
  vim.ui.select(comments, {
    prompt = prompt or "Document comment",
    format_item = formatter or M.format_file,
  }, callback)
end

return M
