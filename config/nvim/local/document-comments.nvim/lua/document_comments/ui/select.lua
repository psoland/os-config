local M = {}

local function summary(body)
  local one_line = body:gsub("%s+", " ")
  if vim.fn.strchars(one_line) > 52 then
    return vim.fn.strcharpart(one_line, 0, 51) .. "…"
  end
  return one_line
end

function M.format(comment)
  local line = comment.anchor.current.position.start.line + 1
  return ("[%s/%s] %s:%d  %s"):format(
    comment.status,
    comment.anchor.state,
    comment.source.path,
    line,
    summary(comment.body)
  )
end

function M.comment(comments, prompt, callback, always_select)
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
    format_item = M.format,
  }, callback)
end

return M
