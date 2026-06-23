local context = require("master-hand.context")
local providers = require("master-hand.providers")
local prompts = require("master-hand.prompts")
local config = require("master-hand.config")
local path = require("master-hand.path")
local M = {}

local function unsafe(diff)
  if not diff or diff == "" then return "empty diff" end
  if diff:find("GIT binary patch", 1, true) then return "binary patches blocked" end
  local paths = {}
  for a, b in diff:gmatch("diff %-%-git a/([^%s]+) b/([^%s]+)") do table.insert(paths, a); table.insert(paths, b) end
  for p in diff:gmatch("[%+%-][%+%-][%+%-] [ab]/([^\n]+)") do table.insert(paths, p) end
  for p in diff:gmatch("rename to ([^\n]+)") do table.insert(paths, p) end
  for p in diff:gmatch("copy to ([^\n]+)") do table.insert(paths, p) end
  for _, p in ipairs(paths) do
    p = p:gsub("%s.*$", "")
    if p:sub(1,1) == "/" or p:find("%.%./") or path.is_ignored(p, config.get().ignore) then return "unsafe path: " .. p end
  end
end

function M.prepare(request)
  local snap = context.snapshot()
  local content, err = providers.complete(prompts.diff(snap, request or snap.goal or "prepare proposed edit"))
  if not content then return nil, err end
  local bad = unsafe(content); if bad then return nil, bad end
  local check = vim.system({ "git", "-C", snap.root, "apply", "--check", "-" }, { text = true, stdin = content }):wait()
  if check.code ~= 0 then return nil, check.stderr or "git apply --check failed" end
  return content
end

function M.apply(root, diff)
  local bad = unsafe(diff); if bad then return false, bad end
  local check = vim.system({ "git", "-C", root, "apply", "--check", "-" }, { text = true, stdin = diff }):wait()
  if check.code ~= 0 then return false, check.stderr or "git apply --check failed" end
  local res = vim.system({ "git", "-C", root, "apply", "-" }, { text = true, stdin = diff }):wait()
  return res.code == 0, res.stderr
end

return M
