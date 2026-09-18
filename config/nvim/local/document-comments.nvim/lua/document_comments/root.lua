local config = require("document_comments.config")

local M = {}

local function canonical(path)
  path = vim.fs.abspath(path)
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

local function slash(path)
  return path:gsub("\\", "/")
end

function M.for_path(path)
  vim.validate({ path = { path, "string" } })
  if path == "" then
    return nil, "buffer has no file name"
  end
  local document = canonical(path)
  local custom = config.options.root
  local root = custom and custom(document) or vim.fs.root(document, ".git")
  root = root and canonical(root) or vim.fs.dirname(document)
  local relative = vim.fs.relpath(root, document)
  if not relative then
    return nil, ("document %s is outside project root %s"):format(document, root)
  end
  relative = slash(relative)
  if relative == "" or relative == "." or relative:match("^%.%./") then
    return nil, "could not create a project-relative source path"
  end
  local storage_dir = vim.fs.joinpath(root, config.options.storage_dir)
  return {
    root = root,
    document_path = document,
    source_path = relative,
    storage_dir = storage_dir,
    store_path = vim.fs.joinpath(storage_dir, "comments.json"),
    export_path = vim.fs.joinpath(storage_dir, "export.md"),
  }
end

function M.for_buffer(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil, "document-comments requires a named file buffer"
  end
  return M.for_path(name)
end

return M
