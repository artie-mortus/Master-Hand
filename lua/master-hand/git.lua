local M = {}

local function run(root, args)
  if not root then
    return ""
  end
  local cmd = vim.list_extend({ "git", "-C", root }, args)
  local out = vim.system(cmd, { text = true }):wait()
  if out.code ~= 0 then
    return ""
  end
  return out.stdout or ""
end

function M.root()
  local out = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if out.code == 0 then
    return vim.trim(out.stdout)
  end
  return vim.loop.cwd()
end

function M.status(root)
  return run(root, { "status", "--short" })
end

function M.diff(root)
  return run(root, { "diff", "--", "." })
end

function M.changed_files(root)
  local files = {}
  for line in M.status(root):gmatch("[^\n]+") do
    local file = line:sub(4)
    if file and file ~= "" then
      table.insert(files, file)
    end
  end
  return files
end

return M
