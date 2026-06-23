-- Thin git wrapper for repo root, status, diffs, and tracked file discovery.
local config = require("master-hand.config")
local path = require("master-hand.path")
local M = {}

local function run(root, args)
  if not root then return "" end
  local cmd = vim.list_extend({ "git", "-C", root }, args)
  local out = vim.system(cmd, { text = true, timeout = config.get().model.timeout_ms }):wait()
  if out.code ~= 0 then return "" end
  return out.stdout or ""
end

function M.root()
  local out = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if out.code == 0 then return vim.trim(out.stdout) end
  return vim.loop.cwd()
end

function M.branch(root) return vim.trim(run(root, { "branch", "--show-current" })) end
function M.status(root) return run(root, { "status", "--porcelain=v1" }) end

function M.status_filtered(root)
  local out = {}
  for _, item in ipairs(M.changed_files(root)) do
    table.insert(out, string.format("%s %s", item.status, item.file))
  end
  return table.concat(out, "\n")
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
      table.insert(chunks, run(root, { "diff", "--", f }))
    end
  end
  local out = table.concat(chunks, "\n")
  max_bytes = max_bytes or config.get().context.max_diff_bytes
  if #out > max_bytes then out = out:sub(1, max_bytes) .. "\n[diff truncated]" end
  return out
end

function M.changed_files(root)
  local files = {}
  for line in M.status(root):gmatch("[^\n]+") do
    local status = line:sub(1, 2)
    local file = vim.trim(line:sub(4))
    if file:find(" -> ", 1, true) then file = file:match("%-%> (.+)$") end
    if file ~= "" and not path.is_ignored(file, config.get().ignore) then
      table.insert(files, { status = status, file = file })
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
