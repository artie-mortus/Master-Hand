local config = require("master-hand.config")
local M = {}

local blocked = { rm=true, sudo=true, shutdown=true, reboot=true }
local bad = "[|&;<>`]"

function M.validate(argv)
  if type(argv) == "string" then argv = vim.split(argv, "%s+", { trimempty = true }) end
  if type(argv) ~= "table" or not argv[1] then return nil, "command must be argv/list" end
  if blocked[argv[1]] then return nil, "blocked command: " .. argv[1] end
  local joined = table.concat(argv, " ")
  for _, rule in ipairs(config.get().commands.blocklist or {}) do
    if joined:find(rule, 1, true) then return nil, "blocked command: " .. rule end
  end
  if argv[1] == "git" then
    for _, part in ipairs(argv) do
      if part == "clean" or part == "reset" then return nil, "blocked command: git " .. part end
    end
  end
  for _, part in ipairs(argv) do if tostring(part):match(bad) then return nil, "shell metacharacters blocked" end end
  local allow = config.get().commands.allowlist
  if #allow > 0 then
    local ok = false
    for _, cmd in ipairs(allow) do if argv[1] == cmd then ok = true end end
    if not ok then return nil, "command not allowlisted: " .. argv[1] end
  end
  return argv
end

function M.run(root, argv)
  local ok, err = M.validate(argv); if not ok then return nil, err end
  local res = vim.system(ok, { cwd = root, text = true }):wait()
  return { code = res.code, stdout = res.stdout or "", stderr = res.stderr or "", argv = ok }
end

return M
