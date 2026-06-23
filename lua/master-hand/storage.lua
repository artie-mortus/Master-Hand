local config = require("master-hand.config")
local M = {}

function M.path()
  return vim.fn.stdpath("state") .. "/master-hand/state.json"
end

function M.load()
  if not config.get().storage.enabled then return {} end
  local p = M.path()
  if vim.fn.filereadable(p) ~= 1 then return {} end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(p), "\n"))
  return ok and data or {}
end

function M.save(data)
  if not config.get().storage.enabled then return end
  local p = M.path()
  vim.fn.mkdir(vim.fn.fnamemodify(p, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(data or {}) }, p)
end

return M
