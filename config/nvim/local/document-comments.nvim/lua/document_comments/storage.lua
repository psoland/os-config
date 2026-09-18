local model = require("document_comments.model")

local M = {}
local uv = vim.uv
local missing_hash = "<missing>"
local cache = {}

local default_io = {
  fs_open = uv.fs_open,
  fs_close = uv.fs_close,
  fs_fsync = uv.fs_fsync,
  fs_mkdir = uv.fs_mkdir,
  fs_open_dir = uv.fs_open,
  fs_read = uv.fs_read,
  fs_rename = uv.fs_rename,
  fs_rmdir = uv.fs_rmdir,
  fs_scandir = uv.fs_scandir,
  fs_scandir_next = uv.fs_scandir_next,
  fs_stat = uv.fs_stat,
  fs_unlink = uv.fs_unlink,
  fs_write = uv.fs_write,
}

M.io = default_io

local function fail(path, message)
  return nil, ("document-comments store %s: %s"):format(path, message)
end

local function read_raw(path)
  local stat, stat_err = M.io.fs_stat(path)
  if not stat then
    if stat_err and not tostring(stat_err):match("ENOENT") then
      return nil, stat_err
    end
    return false
  end
  local fd, open_err = M.io.fs_open(path, "r", 384)
  if not fd then
    return nil, open_err
  end
  local raw, read_err = M.io.fs_read(fd, stat.size, 0)
  local _, close_err = M.io.fs_close(fd)
  if not raw then
    return nil, read_err
  end
  if close_err then
    return nil, close_err
  end
  return raw
end

local function current_hash(path)
  local raw, err = read_raw(path)
  if raw == nil then
    return nil, err
  end
  return raw == false and missing_hash or model.hash(raw), raw
end

local function mkdir_p(path)
  local stat = M.io.fs_stat(path)
  if stat then
    return stat.type == "directory" or nil, stat.type ~= "directory" and "path exists but is not a directory" or nil
  end
  local parent = vim.fs.dirname(path)
  if parent and parent ~= path then
    local ok, err = mkdir_p(parent)
    if not ok then
      return nil, err
    end
  end
  local ok, err = M.io.fs_mkdir(path, 448)
  if not ok and not tostring(err):match("EEXIST") then
    return nil, err
  end
  return true
end

local function encode(store)
  return vim.json.encode(store, { indent = "  ", sort_keys = true }) .. "\n"
end

local function write_all(fd, raw)
  local offset = 0
  while offset < #raw do
    local written, err = M.io.fs_write(fd, raw:sub(offset + 1), offset)
    if not written then
      return nil, err
    end
    if written == 0 then
      return nil, "short write"
    end
    offset = offset + written
  end
  return true
end

local function atomic_write(path, raw)
  local directory = vim.fs.dirname(path)
  local ok, err = mkdir_p(directory)
  if not ok then
    return nil, err
  end
  local temp =
    vim.fs.joinpath(directory, (".%s.tmp.%d.%s"):format(vim.fs.basename(path), uv.os_getpid(), tostring(uv.hrtime())))
  local fd
  local function cleanup()
    if fd then
      pcall(M.io.fs_close, fd)
      fd = nil
    end
    pcall(M.io.fs_unlink, temp)
  end
  fd, err = M.io.fs_open(temp, "wx", 384)
  if not fd then
    return nil, err
  end
  ok, err = write_all(fd, raw)
  if not ok then
    cleanup()
    return nil, err
  end
  ok, err = M.io.fs_fsync(fd)
  if not ok then
    cleanup()
    return nil, err
  end
  ok, err = M.io.fs_close(fd)
  fd = nil
  if not ok then
    cleanup()
    return nil, err
  end
  ok, err = M.io.fs_rename(temp, path)
  if not ok then
    cleanup()
    return nil, err
  end

  -- Directory fsync is not available on every supported filesystem. The data file
  -- has already been fsynced and atomically renamed when this best-effort step runs.
  local dirfd = M.io.fs_open_dir(directory, "r", 448)
  if dirfd then
    pcall(M.io.fs_fsync, dirfd)
    pcall(M.io.fs_close, dirfd)
  end
  return true
end

local function cleanup_temporary_files(path)
  local directory = vim.fs.dirname(path)
  local prefix = "." .. vim.fs.basename(path) .. ".tmp."
  local scanner = M.io.fs_scandir(directory)
  if not scanner then
    return
  end
  while true do
    local name, kind = M.io.fs_scandir_next(scanner)
    if not name then
      break
    end
    if kind == "file" and name:sub(1, #prefix) == prefix then
      pcall(M.io.fs_unlink, vim.fs.joinpath(directory, name))
    end
  end
end

function M.load(ctx, opts)
  opts = opts or {}
  if cache[ctx.store_path] and not opts.force then
    local entry = cache[ctx.store_path]
    if entry.error then
      return nil, entry.error
    end
    return entry.store, entry
  end
  local hash, raw = current_hash(ctx.store_path)
  if not hash then
    local _, message = fail(ctx.store_path, tostring(raw))
    cache[ctx.store_path] = { error = message, write_blocked = true }
    return nil, message
  end
  local store
  if raw == false then
    store = model.new_store()
  else
    local ok, decoded = pcall(vim.json.decode, raw)
    if not ok then
      local _, message = fail(ctx.store_path, "invalid JSON: " .. tostring(decoded))
      cache[ctx.store_path] = { error = message, write_blocked = true, raw_hash = hash }
      return nil, message
    end
    local valid, validation_error = model.validate(decoded)
    if not valid then
      local _, message = fail(ctx.store_path, validation_error)
      cache[ctx.store_path] = { error = message, write_blocked = true, raw_hash = hash }
      return nil, message
    end
    store = decoded
    cleanup_temporary_files(ctx.store_path)
  end
  local entry = { store = store, raw_hash = hash, write_blocked = false }
  cache[ctx.store_path] = entry
  return store, entry
end

function M.mutate(ctx, mutation)
  local store, entry_or_error = M.load(ctx)
  if not store then
    return nil, entry_or_error
  end
  local entry = entry_or_error
  if entry.write_blocked then
    return fail(ctx.store_path, "writing is blocked because loading failed")
  end
  local disk_hash, read_error = current_hash(ctx.store_path)
  if not disk_hash then
    return fail(ctx.store_path, "could not check for concurrent changes: " .. tostring(read_error))
  end
  if disk_hash ~= entry.raw_hash then
    return fail(ctx.store_path, "conflict: the store changed in another process; reload before saving")
  end
  local next_store = vim.deepcopy(store)
  local ok, mutation_error = pcall(mutation, next_store)
  if not ok then
    return fail(ctx.store_path, "mutation failed: " .. tostring(mutation_error))
  end
  if mutation_error == false then
    return fail(ctx.store_path, "mutation was rejected")
  end
  next_store.store_revision = next_store.store_revision + 1
  next_store.updated_at = model.now()
  local valid, validation_error = model.validate(next_store)
  if not valid then
    return fail(ctx.store_path, "refusing to write invalid data: " .. validation_error)
  end
  local raw = encode(next_store)
  local written, write_error = atomic_write(ctx.store_path, raw)
  if not written then
    return fail(ctx.store_path, "atomic write failed: " .. tostring(write_error))
  end
  entry.store = next_store
  entry.raw_hash = model.hash(raw)
  entry.error = nil
  return next_store, entry
end

function M.reload(ctx)
  cache[ctx.store_path] = nil
  return M.load(ctx, { force = true })
end

function M.changed(ctx)
  local entry = cache[ctx.store_path]
  if not entry or not entry.raw_hash then
    return false
  end
  local hash, err = current_hash(ctx.store_path)
  if not hash then
    return nil, err
  end
  return hash ~= entry.raw_hash
end

function M.raw_hash(ctx)
  local _, entry = M.load(ctx)
  return type(entry) == "table" and entry.raw_hash or nil
end

function M.write_snapshot(path, raw)
  local ok, err = atomic_write(vim.fs.abspath(path), raw)
  if not ok then
    return nil, ("could not write export %s: %s"):format(path, tostring(err))
  end
  return true
end

function M._reset()
  cache = {}
  M.io = default_io
end

return M
