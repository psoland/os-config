-- MERMAN_COMMAND=/path/to/merman-nvim nvim --clean --headless -l config/nvim/tests/merman.lua
local file = debug.getinfo(1, "S").source:sub(2)
local config_root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(file)))
vim.opt.runtimepath:prepend(config_root)
vim.opt.runtimepath:prepend(config_root .. "/local/merman.nvim")
vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/site")
local snacks_path = vim.fn.stdpath("data") .. "/lazy/snacks.nvim"
if vim.uv.fs_stat(snacks_path) then
  vim.opt.runtimepath:append(snacks_path)
end

local merman = require("merman")
local command = vim.env.MERMAN_COMMAND or "merman-nvim"
assert(vim.fn.executable(command) == 1, "Build/install merman-nvim or set MERMAN_COMMAND")
local notifications = {}
local system = vim.system
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = message, level = level }
end
local count = 0
local function test(name, callback)
  merman.close()
  merman.setup({ command = { command }, timeout = 10000 })
  notifications = {}
  local ok, err = xpcall(callback, debug.traceback)
  vim.system = system
  merman.close()
  if not ok then
    io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
    vim.cmd("cquit 1")
  end
  count = count + 1
  print("ok " .. name)
end

local function buffer(lines, ft, row, col)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = ft or "markdown"
  vim.api.nvim_win_set_cursor(0, { row or 2, col or 0 })
  return buf
end

local function preview_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "mermanpreview" then
      return win
    end
  end
end

local function await_result()
  assert(
    vim.wait(15000, function()
      return preview_window() ~= nil or #notifications > 0
    end, 10),
    "No preview result before timeout"
  )
end

local function mock_system()
  local jobs = {}
  vim.system = function(cmd, opts, callback)
    local job = { cmd = cmd, opts = opts, callback = callback }
    function job:kill(signal)
      self.signal = signal
    end
    jobs[#jobs + 1] = job
    return job
  end
  return jobs
end

local function finish(job, result)
  job.callback(
    result or { code = 0, stdout = vim.json.encode({ kind = "flowchart", lines = { "Preview" }, highlights = {} }) }
  )
  vim.wait(100, function()
    return preview_window() ~= nil or #notifications > 0
  end, 5)
end

local source_lines = { "```mermaid", "flowchart LR", " A[Hello] --> B[World]", "```" }

test("fallback extracts only the fenced diagram containing the cursor", function()
  local lines =
    { "Text", "```lua", "```mermaid", "not a diagram", "```", "~~~mermaid", "flowchart LR", "A --> B", "~~~", "Text" }
  assert(merman.extract_fence(lines, 3) == nil)
  assert(merman.extract_fence(lines, 7) == "flowchart LR\nA --> B")
  assert(merman.extract_fence(lines, 6) ~= nil and merman.extract_fence(lines, 9) ~= nil)
  assert(merman.extract_fence(lines, 10) == nil)
end)

test("fallback respects fence length, indentation and unfinished fences", function()
  assert(
    merman.extract_fence({ "````mermaid", "flowchart LR", "```", "A --> B", "````" }, 2) == "flowchart LR\n```\nA --> B"
  )
  assert(merman.extract_fence({ "    ```mermaid", "A --> B", "    ```" }, 2) == nil)
  assert(merman.extract_fence({ "  ```mermaid", "A --> B", "  ```" }, 2) == "A --> B")
  assert(merman.extract_fence({ "```mermaid", "flowchart LR", "A --> B" }, 3) == "flowchart LR\nA --> B")
  assert(merman.extract_fence({ "```mermaid", "```" }, 1) == "")
end)

test("Tree-sitter extraction includes complete blocks and handles quoted diagrams", function()
  assert(vim.treesitter.language.add("markdown"), "Markdown Tree-sitter parser required for integration test")
  local buf = buffer(source_lines)
  assert(merman.source(buf, 3, 2):find("A%[Hello%]"))
  local quoted = buffer({ "> ```mermaid", "> flowchart LR", "> A --> B", "> ```" }, "markdown", 3, 3)
  local source = assert(merman.source(quoted, 3, 3))
  assert(not source:find("^%s*>") and not source:find("\n%s*>"), source)
  assert(source:find("flowchart LR") and source:find("A %-%-> B"), source)
  local listed = buffer({ "- Diagram:", "  ```mermaid", "  flowchart LR", "  A --> B", "  ```" }, "markdown", 4, 3)
  assert(merman.source(listed, 4, 3):find("A %-%-> B"))
end)

test("LazyVim registers the shortcut, command and standalone filetypes", function()
  local spec = require("plugins.merman")[1]
  assert(spec.main == "merman" and spec.cmd == "MermaidPreview")
  assert(spec.keys[1][1] == "<leader>cm")
  spec.init()
  assert(vim.fn.exists(":MermaidPreview") == 2)
  assert(vim.filetype.match({ filename = "diagram.mmd" }) == "mermaid")
  assert(vim.filetype.match({ filename = "diagram.mermaid" }) == "mermaid")
  local buf = buffer({ "flowchart LR", "A --> B" }, "mermaid")
  assert(merman.source(buf, 2) == "flowchart LR\nA --> B")
end)

test("Snacks Markdown query ignores Mermaid but retains math blocks", function()
  local query = assert(vim.treesitter.query.get("markdown", "images"))
  local function matches(lines)
    local buf = buffer(lines)
    local tree = vim.treesitter.get_parser(buf, "markdown"):parse()[1]
    local found = 0
    for _ in query:iter_matches(tree:root(), buf) do
      found = found + 1
    end
    return found
  end
  assert(matches(source_lines) == 0, "Snacks must not invoke mmdc")
  assert(matches({ "```math", "x + y", "```" }) == 1)
  assert(vim.treesitter.query.get("markdown_inline", "images"), "Ordinary image query remains available")
end)

test("real renderer opens a highlighted read-only float without modifying source", function()
  local buf = buffer(source_lines)
  local before = vim.api.nvim_buf_get_changedtick(buf)
  vim.cmd("MermaidPreview")
  await_result()
  local win = assert(preview_window(), notifications[1] and notifications[1].message)
  local preview = vim.api.nvim_win_get_buf(win)
  local text = table.concat(vim.api.nvim_buf_get_lines(preview, 0, -1, false), "\n")
  assert(text:find("Hello") and text:find("World"), text)
  assert(not vim.bo[preview].modifiable and vim.bo[preview].buftype == "nofile")
  assert(not vim.wo[win].wrap)
  assert(vim.api.nvim_buf_get_changedtick(buf) == before)
  local ns = vim.api.nvim_get_namespaces()["merman-preview"]
  assert(#vim.api.nvim_buf_get_extmarks(preview, ns, 0, -1, {}) > 0)
  assert(vim.fn.maparg("<Esc>", "n", false, true).buffer == 1)
  vim.fn.maparg("q", "n", false, true).callback()
  assert(not vim.api.nvim_win_is_valid(win) and not vim.api.nvim_buf_is_valid(preview))
  assert(vim.api.nvim_get_current_buf() == buf)
end)

test("Unicode labels and italic highlights survive rendering and colorscheme changes", function()
  buffer({ "flowchart LR", 'A["日本語 👋"] --> B["<i>Italic</i>"]' }, "mermaid")
  merman.preview()
  await_result()
  local win = assert(preview_window(), notifications[1] and notifications[1].message)
  local preview = vim.api.nvim_win_get_buf(win)
  assert(table.concat(vim.api.nvim_buf_get_lines(preview, 0, -1, false)):find("日本語 👋", 1, true))
  local function italic()
    return vim.api.nvim_get_hl(0, { name = "MermanNormalFloatItalic", link = false }).italic
  end
  assert(italic())
  vim.api.nvim_set_hl(0, "MermanNormalFloatItalic", {})
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  assert(italic())
  vim.api.nvim_exec_autocmds("VimResized", {})
  assert(vim.api.nvim_win_get_config(win).width <= vim.o.columns - 4)
end)

test("invalid and unsupported diagrams report errors rather than opening a window", function()
  for _, source in ipairs({ "pie\n title Unsupported", "flowchart LR\n A[Broken" }) do
    notifications = {}
    buffer(vim.split(source, "\n"), "mermaid")
    merman.preview()
    await_result()
    assert(not preview_window() and notifications[1].level == vim.log.levels.ERROR)
  end
end)

test("missing helper and empty/non-Mermaid buffers are handled before spawning", function()
  local jobs = mock_system()
  buffer({ "Text", "More text" })
  merman.preview()
  assert(notifications[1].message:find("cursor"))
  buffer({ "```mermaid", "```" }, "markdown", 1)
  merman.preview()
  assert(notifications[2].message:find("empty"))
  buffer(source_lines)
  merman.setup({ command = { "/no-such-merman-helper" } })
  merman.preview()
  assert(notifications[3].message:find("missing"))
  assert(#jobs == 0)
end)

test("new requests cancel previous jobs and discard late results", function()
  local jobs = mock_system()
  buffer(source_lines)
  merman.preview()
  merman.preview()
  assert(jobs[1].signal == 15)
  finish(jobs[1])
  assert(not preview_window())
  finish(jobs[2])
  assert(preview_window())
end)

test("edited sources and switched buffers cannot open stale previews", function()
  local jobs = mock_system()
  local buf = buffer(source_lines)
  merman.preview()
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, { " A --> C" })
  finish(jobs[1])
  assert(not preview_window() and notifications[1].message:find("source changed"))
  notifications = {}
  merman.preview()
  buffer({ "Another", "buffer" })
  finish(jobs[2])
  assert(not preview_window() and #notifications == 0)
end)

test("process launch failures are reported cleanly", function()
  buffer(source_lines)
  vim.system = function()
    error("Spawn failed")
  end
  merman.preview()
  assert(notifications[1].message:find("Could not start"))
  assert(not preview_window())
end)

test("timeout and invalid helper output are reported without leaking scratch buffers", function()
  local jobs = mock_system()
  buffer(source_lines)
  merman.preview()
  finish(jobs[1], { code = 124, stderr = "" })
  assert(notifications[1].message:find("timed out"))
  notifications = {}
  local before = #vim.api.nvim_list_bufs()
  merman.preview()
  finish(jobs[2], { code = 0, stdout = '{"kind":false,"lines":["Invalid"],"highlights":[]}' })
  assert(notifications[1].message:find("Could not open"))
  assert(not preview_window() and #vim.api.nvim_list_bufs() == before)
end)

print(("merman.nvim: %d tests passed"):format(count))
vim.cmd("qa!")
