local M = {}

local options = { command = { "merman-nvim" }, timeout = 10000 }
local namespace = vim.api.nvim_create_namespace("merman-preview")
local state = { generation = 0 }

local style_links = {
  node = "NormalFloat",
  nodeBorder = "Type",
  database = "NormalFloat",
  databaseBorder = "Type",
  edge = "Comment",
  label = "String",
  group = "Comment",
  groupLabel = "Title",
  participant = "Type",
  lifeline = "Comment",
  request = "DiagnosticOk",
  response = "DiagnosticWarn",
  fragment = "Type",
  note = "DiagnosticInfo",
  noteFg = "DiagnosticInfo",
  noteBg = "NormalFloat",
  state = "NormalFloat",
  stateBorder = "Type",
  composite = "Comment",
  compositeLabel = "Title",
  transition = "Comment",
  noteBorder = "DiagnosticInfo",
  noteText = "DiagnosticInfo",
  noteConnector = "Comment",
  start = "DiagnosticOk",
  ["end"] = "DiagnosticWarn",
  choice = "Type",
  title = "Title",
  section = "Type",
  period = "Number",
  spine = "Comment",
  event = "String",
  axis = "Comment",
  task = "String",
  active = "DiagnosticOk",
  critical = "DiagnosticWarn",
  done = "Comment",
  milestone = "Special",
  primary = "Type",
  secondary = "String",
  muted = "Comment",
  warning = "DiagnosticWarn",
  text = "NormalFloat",
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.WARN, { title = "Mermaid Preview" })
end

local function highlight(style, italic)
  local link = style_links[style] or "Comment"
  if style:find("Fade") or style:find("Ramp") then
    link = "Comment"
  end
  local name = "Merman" .. link .. (italic and "Italic" or "")
  if italic then
    local attributes = vim.api.nvim_get_hl(0, { name = link, link = false })
    attributes.italic = true
    vim.api.nvim_set_hl(0, name, attributes)
  else
    vim.api.nvim_set_hl(0, name, { link = link })
  end
  return name
end

-- Parser-free fallback for ordinary Markdown fences. Tracking every fence
-- avoids mistaking a Mermaid example inside another code block for a diagram.
function M.extract_fence(lines, row)
  local block
  for index, line in ipairs(lines) do
    if block then
      local fence = line:match("^ ? ? ?([`~]+)%s*$")
      if
        fence
        and fence:sub(1, 1) == block.char
        and not fence:find("[^" .. block.char .. "]")
        and #fence >= block.length
      then
        if block.mermaid and row >= block.start and row <= index then
          return table.concat(vim.list_slice(lines, block.start + 1, index - 1), "\n")
        end
        block = nil
      end
    else
      local fence, info = line:match("^ ? ? ?([`~]+)(.*)$")
      if fence and #fence >= 3 and not fence:find("[^" .. fence:sub(1, 1) .. "]") then
        local char = fence:sub(1, 1)
        if char ~= "`" or not info:find("`", 1, true) then
          block = { start = index, char = char, length = #fence, mermaid = info:match("^%s*(%S+)") == "mermaid" }
        end
      end
    end
  end
  if block and block.mermaid and row >= block.start then
    return table.concat(vim.list_slice(lines, block.start + 1), "\n")
  end
end

function M.source(buf, row, col)
  if vim.bo[buf].filetype == "mermaid" then
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  end
  if vim.bo[buf].filetype ~= "markdown" then
    return nil, "Open a Markdown or Mermaid buffer first"
  end
  -- Tree-sitter also handles fenced blocks nested in lists and blockquotes.
  local ok, node = pcall(function()
    vim.treesitter.get_parser(buf, "markdown"):parse()
    return vim.treesitter.get_node({ bufnr = buf, pos = { row - 1, col or 0 }, ignore_injections = true })
  end)
  while ok and node do
    if node:type() == "fenced_code_block" then
      local language, content
      for child in node:iter_children() do
        if child:type() == "info_string" then
          language = vim.treesitter.get_node_text(child, buf):match("^%s*(%S+)")
        elseif child:type() == "code_fence_content" then
          content = vim.treesitter.get_node_text(child, buf)
        end
      end
      if language == "mermaid" then
        -- Tree-sitter's range includes Markdown quote markers on subsequent
        -- physical lines. They are not part of the Mermaid source.
        local start_row, start_col = node:start()
        local header = vim.api.nvim_buf_get_lines(buf, start_row, start_row + 1, false)[1]
        if header:sub(1, start_col):find(">", 1, true) then
          content = (content or ""):gsub("\n([ \t>]+)", function(prefix)
            while prefix:find("^%s*>") do
              prefix = prefix:gsub("^%s*> ?", "")
            end
            return "\n" .. prefix
          end)
        end
        return content or ""
      end
      return nil, "Place the cursor inside a Mermaid code block"
    end
    node = node:parent()
  end
  local source = M.extract_fence(vim.api.nvim_buf_get_lines(buf, 0, -1, false), row)
  if source ~= nil then
    return source
  end
  return nil, "Place the cursor inside a Mermaid code block"
end

function M.close()
  state.generation = state.generation + 1
  if state.process then
    state.process:kill(15)
    state.process = nil
  end
  local buf = state.buf
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  state.win, state.buf = nil, nil
end

local function bounds(lines)
  local width = 1
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  width = math.min(width, math.max(1, vim.o.columns - 4))
  local height = math.min(#lines, math.max(1, vim.o.lines - vim.o.cmdheight - 4))
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
  }
end

local function show(diagram)
  assert(type(diagram.lines) == "table" and #diagram.lines > 0, "Renderer returned no diagram lines")
  local buf = vim.api.nvim_create_buf(false, true)
  state.buf = buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, diagram.lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "mermanpreview"
  local config = bounds(diagram.lines)
  config.style, config.border = "minimal", "rounded"
  config.title = " Mermaid: " .. diagram.kind .. " · q/Esc close "
  config.title_pos = "center"
  local win = vim.api.nvim_open_win(buf, true, config)
  state.buf, state.win = buf, win
  vim.wo[win].wrap = false
  vim.wo[win].list = false
  vim.wo[win].spell = false
  vim.wo[win].foldenable = false
  vim.wo[win].scrolloff = 1
  vim.wo[win].sidescrolloff = 1
  local groups = {}
  for _, span in ipairs(diagram.highlights or {}) do
    local key = span.style .. (span.italic and ":italic" or "")
    groups[key] = groups[key] or highlight(span.style, span.italic)
    vim.api.nvim_buf_set_extmark(buf, namespace, span.line, span.start, {
      end_col = span["end"],
      hl_group = groups[key],
    })
  end
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, M.close, { buffer = buf, silent = true, desc = "Close Mermaid Preview" })
  end
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if state.win == win then
        state.win, state.buf = nil, nil
      end
    end,
  })
end

function M.preview()
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  local source, err = M.source(buf, cursor[1], cursor[2])
  if not source or not source:find("%S") then
    return notify(err or "The Mermaid block is empty")
  end
  if #source > 128 * 1024 then
    return notify("Mermaid source exceeds 128 KiB")
  end
  if vim.fn.executable(options.command[1]) ~= 1 then
    return notify("merman-nvim is missing. Apply the Home Manager configuration first", vim.log.levels.ERROR)
  end
  M.close()
  local generation, tick = state.generation, vim.api.nvim_buf_get_changedtick(buf)
  local started, process = pcall(vim.system, options.command, {
    text = true,
    timeout = options.timeout,
    stdin = vim.json.encode({ source = source, width = math.max(1, math.min(120, vim.o.columns - 6)) }),
  }, function(result)
    vim.schedule(function()
      if generation ~= state.generation then
        return
      end
      state.process = nil
      if result.code ~= 0 then
        local message = result.code == 124 and "Mermaid rendering timed out" or vim.trim(result.stderr or "")
        return notify(message ~= "" and message or "Mermaid rendering failed", vim.log.levels.ERROR)
      end
      if
        not vim.api.nvim_buf_is_valid(buf)
        or not vim.api.nvim_win_is_valid(win)
        or vim.api.nvim_get_current_win() ~= win
        or vim.api.nvim_win_get_buf(win) ~= buf
      then
        return -- Never steal focus if the user moved away while rendering.
      end
      if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        return notify("The source changed while rendering. Run MermaidPreview again")
      end
      local success, failure = pcall(function()
        show(vim.json.decode(result.stdout))
      end)
      if not success then
        M.close()
        notify("Could not open the Mermaid preview: " .. tostring(failure), vim.log.levels.ERROR)
      end
    end)
  end)
  if started then
    state.process = process
  else
    notify("Could not start the Mermaid renderer: " .. tostring(process), vim.log.levels.ERROR)
  end
end

function M.setup(opts)
  options = vim.tbl_deep_extend("force", options, opts or {})
  vim.api.nvim_create_user_command(
    "MermaidPreview",
    M.preview,
    { desc = "Preview Mermaid diagram under cursor", force = true }
  )
  local group = vim.api.nvim_create_augroup("MermanPreview", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_set_config(state.win, bounds(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)))
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      for style in pairs(style_links) do
        highlight(style, false)
        highlight(style, true)
      end
    end,
  })
end

return M
