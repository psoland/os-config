local anchor = require("document_comments.anchor")
local model = require("document_comments.model")

local M = {}

local ctrl_v = string.char(22)

local function char_start(line, byte_column)
  byte_column = math.min(byte_column, #line)
  while byte_column > 0 do
    local byte = line:byte(byte_column + 1)
    if not byte or byte < 0x80 or byte >= 0xC0 then
      break
    end
    byte_column = byte_column - 1
  end
  return byte_column
end

local function char_length(line, byte_column)
  if byte_column >= #line then
    return 0
  end
  local byte = line:byte(byte_column + 1)
  if byte < 0x80 then
    return 1
  elseif byte < 0xE0 then
    return 2
  elseif byte < 0xF0 then
    return 3
  end
  return 4
end

local function before(left, right)
  return left[2] < right[2] or (left[2] == right[2] and left[3] <= right[3])
end

function M.from_visual(bufnr, allow_inactive)
  bufnr = bufnr or 0
  local active_mode = vim.fn.mode()
  local visual_active = active_mode == "v" or active_mode == "V" or active_mode == ctrl_v
  if not visual_active and not allow_inactive then
    return nil, "this command must be started from Visual mode"
  end
  local visual_type = visual_active and active_mode or vim.fn.visualmode()
  if visual_type == ctrl_v then
    return nil, "blockwise Visual selections are not supported"
  end
  if visual_type ~= "v" and visual_type ~= "V" then
    return nil, "DocumentCommentsAdd must be started from characterwise or linewise Visual mode"
  end

  local first = vim.fn.getpos(visual_active and "v" or "'<")
  local last = vim.fn.getpos(visual_active and "." or "'>")
  if first[2] == 0 or last[2] == 0 then
    return nil, "could not read the Visual selection"
  end
  if not before(first, last) then
    first, last = last, first
  end

  local opts = { type = visual_type, exclusive = false }
  local ok_pos, region_positions = pcall(vim.fn.getregionpos, first, last, opts)
  local ok_text, region_text = pcall(vim.fn.getregion, first, last, opts)
  if not ok_pos or not ok_text or #region_positions == 0 or #region_text == 0 then
    return nil, "could not normalize the Visual selection"
  end

  local start_row = first[2] - 1
  local end_row = last[2] - 1
  local start_column
  local end_column
  if visual_type == "V" then
    start_column = 0
    end_column = #vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1]
  else
    local first_line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
    local last_line = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1]
    start_column = char_start(first_line, first[3] - 1)
    local selected_column = char_start(last_line, last[3] - 1)
    end_column = selected_column + char_length(last_line, selected_column)
  end

  local position = {
    start = { line = start_row, byte_column = start_column },
    ["end"] = { line = end_row, byte_column = end_column },
  }
  local exact_lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_column, end_row, end_column, {})
  local exact = table.concat(exact_lines, "\n")
  local region = table.concat(region_text, "\n")
  if exact == "" then
    return nil, "the Visual selection is empty"
  end
  if exact ~= region then
    return nil, "Visual selection normalization disagreed with the buffer text"
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local start_offset = anchor.position_to_offset(lines, position.start)
  local end_offset = anchor.position_to_offset(lines, position["end"])
  local text = model.canonical_text(lines)
  return {
    position = position,
    quote = model.quote(text, start_offset, end_offset),
    document_hash = model.hash(text),
    exact = exact,
  }
end

return M
