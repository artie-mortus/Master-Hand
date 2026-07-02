-- Model-proposed diff safety checks, preview preparation, and approved apply.
local context = require("master-hand.context")
local providers = require("master-hand.providers")
local prompts = require("master-hand.prompts")
local config = require("master-hand.config")
local path = require("master-hand.path")
local M = {}

local function touches_git_dir(p)
  return p == ".git" or p:find(".git/", 1, true) == 1 or p:find("/.git/", 1, true) ~= nil
end

-- Reject patches that can escape repo, touch ignored paths, or include binary data.
local function unsafe(diff)
  if not diff or diff == "" then return "empty diff" end
  if diff:find("GIT binary patch", 1, true) then return "binary patches blocked" end
  -- Git quotes paths with special characters (`"a/..."`); the extractors below
  -- cannot parse those, so reject rather than validate a truncated path.
  if diff:match('diff %-%-git "') or diff:match('[%+%-][%+%-][%+%-] "') or diff:match('rename to "') or diff:match('copy to "') then
    return "quoted paths blocked"
  end
  local paths = {}
  for a, b in diff:gmatch("diff %-%-git a/([^%s]+) b/([^%s]+)") do table.insert(paths, a); table.insert(paths, b) end
  for p in diff:gmatch("[%+%-][%+%-][%+%-] [ab]/([^\n]+)") do table.insert(paths, p) end
  for p in diff:gmatch("rename to ([^\n]+)") do table.insert(paths, p) end
  for p in diff:gmatch("copy to ([^\n]+)") do table.insert(paths, p) end
  for _, p in ipairs(paths) do
    -- Strip only the trailing tab+metadata git appends; spaces are legal in paths.
    p = p:gsub("\t.*$", "")
    if p:sub(1,1) == "/" or p:find("%.%./") or touches_git_dir(p) or path.is_ignored(p, config.get().ignore) then return "unsafe path: " .. p end
  end
end

-- Ask provider for a patch, then validate with git before user sees approval item.
function M.prepare(request)
  local snap = context.snapshot()
  local content, err = providers.complete(prompts.diff(snap, request or snap.goal or "prepare proposed edit"))
  if not content then return nil, err end
  local bad = unsafe(content); if bad then return nil, bad end
  local check = vim.system({ "git", "-C", snap.root, "apply", "--check", "-" }, { text = true, stdin = content, timeout = config.get().model.timeout_ms }):wait()
  if check.code ~= 0 then return nil, check.stderr or "git apply --check failed" end
  return content
end

-- Re-check before apply so approved stale patches cannot sneak through.
function M.apply(root, diff)
  local bad = unsafe(diff); if bad then return false, bad end
  local check = vim.system({ "git", "-C", root, "apply", "--check", "-" }, { text = true, stdin = diff, timeout = config.get().model.timeout_ms }):wait()
  if check.code ~= 0 then return false, check.stderr or "git apply --check failed" end
  local res = vim.system({ "git", "-C", root, "apply", "-" }, { text = true, stdin = diff, timeout = config.get().model.timeout_ms }):wait()
  return res.code == 0, res.stderr
end

return M
