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

function M.root()
  local out = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true, timeout = timeout_ms() }):wait()
  if out.code == 0 then return vim.trim(out.stdout) end
  return vim.uv.cwd()
end

function M.branch(root) return vim.trim(run(root, { "branch", "--show-current" })) end
local function status_z(root) return run(root, { "status", "--porcelain=v1", "-z" }) end

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
  local out = table.concat(chunks, "\n")
  max_bytes = max_bytes or config.get().context.max_diff_bytes
  if #out > max_bytes then out = out:sub(1, max_bytes) .. "\n[diff truncated]" end
  return out
end

function M.changed_files(root)
  local files = {}
  local out = status_z(root)
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

function M.ls_files(root, limit)
  local out, n = {}, 0
  for file in run(root, { "ls-files" }):gmatch("[^\n]+") do
    if not path.is_ignored(file, config.get().ignore) then
      table.insert(out, file); n = n + 1
      if limit and n >= limit then break end
    end
  end
  return out
end

return M
