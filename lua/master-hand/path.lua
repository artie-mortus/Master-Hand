-- Path normalization, ignore matching, and list de-duplication utilities.
local M = {}

function M.normalize(path)
  if not path or path == "" then return "" end
  return (path:gsub("\\", "/"):gsub("/+", "/"))
end

function M.relative(root, path)
  path = M.normalize(path)
  root = M.normalize(root or "")
  if root ~= "" and path:find(root .. "/", 1, true) == 1 then
    return path:sub(#root + 2)
  end
  return path
end

local function glob_to_pattern(glob)
  return "^" .. glob:gsub("([%.%+%-%^%$%(%)%%])", "%%%1"):gsub("%*", ".*") .. "$"
end

function M.is_ignored(path, patterns)
  path = M.normalize(path)
  for _, pat in ipairs(patterns or {}) do
    pat = M.normalize(pat)
    if pat:sub(-1) == "/" then
      local dir = pat:sub(1, -2)
      if path == dir or path:find(dir .. "/", 1, true) == 1 or path:find("/" .. dir .. "/", 1, true) then return true end
    elseif pat:find("*", 1, true) then
      if path:match(glob_to_pattern(pat)) or vim.fn.fnamemodify(path, ":t"):match(glob_to_pattern(pat)) then return true end
    elseif path == pat or vim.fn.fnamemodify(path, ":t") == pat then
      return true
    end
  end
  return false
end

function M.dedupe(list)
  local seen, out = {}, {}
  for _, v in ipairs(list or {}) do
    if v and v ~= "" and not seen[v] then seen[v] = true; table.insert(out, v) end
  end
  return out
end

return M
