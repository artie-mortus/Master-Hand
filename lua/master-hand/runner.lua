-- Approval-gated command validation and execution. Shell strings stay blocked.
local config = require("master-hand.config")
local M = {}

local blocked = { rm = true, sudo = true, shutdown = true, reboot = true }
local bad = "[|&;<>`]"

local function has_subcommand(argv, command, subcommand)
  if argv[1] ~= command then return false end
  for i = 2, #argv do
    if argv[i] == subcommand then return true end
  end
  return false
end

-- Match blocklist entries by argv tokens, not substrings, to avoid false positives.
local function is_blocked(argv, rule)
  local parts = vim.split(rule, "%s+", { trimempty = true })
  if #parts == 1 then return argv[1] == parts[1] end
  if argv[1] ~= parts[1] then return false end
  for i = 2, #parts do
    if not has_subcommand(argv, parts[1], parts[i]) then return false end
  end
  return true
end

-- Validate before enqueue/run. Only argv-style commands are considered safe.
function M.validate(argv)
  if type(argv) ~= "table" or not argv[1] then return nil, "command must be argv/list" end
  if blocked[argv[1]] then return nil, "blocked command: " .. argv[1] end
  for _, rule in ipairs(config.get().commands.blocklist or {}) do
    if is_blocked(argv, rule) then return nil, "blocked command: " .. rule end
  end
  if argv[1] == "git" then
    for _, part in ipairs(argv) do
      if part == "clean" or part == "reset" then return nil, "blocked command: git " .. part end
    end
  end
  for _, part in ipairs(argv) do
    if tostring(part):match(bad) then return nil, "shell metacharacters blocked" end
  end
  local allow = config.get().commands.allowlist
  if #allow > 0 then
    local ok = false
    for _, cmd in ipairs(allow) do
      if argv[1] == cmd then ok = true end
    end
    if not ok then return nil, "command not allowlisted: " .. argv[1] end
  end
  return argv
end

function M.run(root, argv)
  local ok, err = M.validate(argv)
  if not ok then return nil, err end
  local timeout = config.get().commands.timeout_ms or config.get().model.timeout_ms
  local res = vim.system(ok, { cwd = root, text = true, timeout = timeout }):wait()
  return { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "", argv = ok }
end

return M
