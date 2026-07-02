-- Thin git wrapper for repo root, status, diffs, and tracked file discovery.
local config = require("master-hand.config")
local path = require("master-hand.path")
local M = {}

local function timeout_ms()
  return math.min(config.get().commands.timeout_ms or 10000, 3000)
end

local function run(root, args)
  if not root then return "" end
  local cmd = vim.list_extend({ "git", "-C", root }, args)
  local out = vim.system(cmd, { text = true, timeout = timeout_ms() }):wait()
  if out.code ~= 0 then return "" end
  return out.stdout or ""
end

-- Async twin of run(). Same argv/timeout; cb(stdout) runs on the main loop
-- (on_exit fires in fast-event context where vim.fn.* is banned, and callers
-- parse with path.is_ignored). Failures degrade to "" and the callback is
-- always invoked, including when spawning itself fails.
local function run_async(root, args, cb)
  if not root then cb(""); return end
  local cmd = vim.list_extend({ "git", "-C", root }, args)
  local ok = pcall(vim.system, cmd, { text = true, timeout = timeout_ms() }, function(out)
    local stdout = out.code == 0 and (out.stdout or "") or ""
    vim.schedule(function() cb(stdout) end)
  end)
  if not ok then cb("") end
end

function M.root()
  local out = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true, timeout = timeout_ms() }):wait()
  if out.code == 0 then return vim.trim(out.stdout) end
  return vim.uv.cwd()
end

function M.root_async(cb)
  local ok = pcall(vim.system, { "git", "rev-parse", "--show-toplevel" }, { text = true, timeout = timeout_ms() }, function(out)
    vim.schedule(function()
      if out.code == 0 then cb(vim.trim(out.stdout or "")) else cb(vim.uv.cwd()) end
    end)
  end)
  if not ok then cb(vim.uv.cwd()) end
end

function M.branch(root) return vim.trim(run(root, { "branch", "--show-current" })) end

function M.branch_async(root, cb)
  run_async(root, { "branch", "--show-current" }, function(out) cb(vim.trim(out)) end)
end

local function status_z(root) return run(root, { "status", "--porcelain=v1", "-z" }) end

local function truncate_diff(out, max_bytes)
  max_bytes = max_bytes or config.get().context.max_diff_bytes
  if #out > max_bytes then out = out:sub(1, max_bytes) .. "\n[diff truncated]" end
  return out
end

function M.diff(root, file, max_bytes)
  local files = file and { file } or nil
  if not files then
    files = {}
    for _, item in ipairs(M.changed_files(root)) do table.insert(files, item.file) end
  end
  local chunks = {}
  for _, f in ipairs(files) do
    if not path.is_ignored(f, config.get().ignore) then
      local with_staged = run(root, { "diff", "HEAD", "--", f })
      table.insert(chunks, with_staged ~= "" and with_staged or run(root, { "diff", "--", f }))
    end
  end
  return truncate_diff(table.concat(chunks, "\n"), max_bytes)
end

-- Async per-file diff over an explicit file list. Files run sequentially so a
-- large change set never fans out into many concurrent git processes.
function M.diff_async(root, files, max_bytes, cb)
  local queue = vim.deepcopy(files or {})
  local chunks = {}
  local function next_file()
    local f = table.remove(queue, 1)
    if not f then cb(truncate_diff(table.concat(chunks, "\n"), max_bytes)); return end
    if path.is_ignored(f, config.get().ignore) then next_file(); return end
    run_async(root, { "diff", "HEAD", "--", f }, function(with_staged)
      if with_staged ~= "" then
        table.insert(chunks, with_staged)
        next_file()
      else
        run_async(root, { "diff", "--", f }, function(unstaged)
          table.insert(chunks, unstaged)
          next_file()
        end)
      end
    end)
  end
  next_file()
end

local function parse_status(out)
  local files = {}
  local i = 1
  while i <= #out do
    local nul = out:find("\0", i, true)
    if not nul then break end
    local entry = out:sub(i, nul - 1)
    i = nul + 1
    if entry ~= "" then
      local status = entry:sub(1, 2)
      local file = entry:sub(4)
      if status:find("R", 1, true) or status:find("C", 1, true) then
        local next_nul = out:find("\0", i, true)
        i = next_nul and (next_nul + 1) or (#out + 1)
      end
      if file ~= "" and not path.is_ignored(file, config.get().ignore) then
        table.insert(files, { status = status, file = file })
      end
    end
  end
  return files
end

function M.changed_files(root)
  return parse_status(status_z(root))
end

function M.changed_files_async(root, cb)
  run_async(root, { "status", "--porcelain=v1", "-z" }, function(out) cb(parse_status(out)) end)
end

local function parse_ls_files(raw, limit)
  local out, n = {}, 0
  for file in raw:gmatch("[^\n]+") do
    if not path.is_ignored(file, config.get().ignore) then
      table.insert(out, file); n = n + 1
      if limit and n >= limit then break end
    end
  end
  return out
end

function M.ls_files(root, limit)
  return parse_ls_files(run(root, { "ls-files" }), limit)
end

function M.ls_files_async(root, limit, cb)
  run_async(root, { "ls-files" }, function(raw) cb(parse_ls_files(raw, limit)) end)
end

return M
