-- Ripgrep and tree-sitter helpers for related files and current-buffer symbols.
local config = require("master-hand.config")
local path = require("master-hand.path")
local M = {}

local function ignored_args()
  local args = {}
  for _, pat in ipairs(config.get().ignore or {}) do
    table.insert(args, "--glob")
    table.insert(args, "!" .. pat)
  end
  return args
end

function M.rg(root, query, limit)
  if not query or query == "" then return {} end
  limit = limit or 40
  local args = { "rg", "--line-number", "--column", "--no-heading", "--smart-case", "--max-count", "5" }
  vim.list_extend(args, ignored_args())
  table.insert(args, query)
  local res = vim.system(args, { cwd = root, text = true, timeout = config.get().model.timeout_ms }):wait()
  local out = {}
  if res.code ~= 0 and (res.stdout or "") == "" then return out end
  for line in (res.stdout or ""):gmatch("[^\n]+") do
    local file, lnum, col, text = line:match("^([^:]+):(%d+):(%d+):(.*)$")
    if file and not path.is_ignored(file, config.get().ignore) then
      table.insert(out, { file = file, lnum = tonumber(lnum), col = tonumber(col), text = vim.trim(text) })
      if #out >= limit then break end
    end
  end
  return out
end

function M.goal_terms(goal)
  local terms, seen = {}, {}
  for word in tostring(goal or ""):gmatch("[%w_%-]+") do
    if #word >= 4 and not seen[word:lower()] then
      seen[word:lower()] = true
      table.insert(terms, word)
    end
  end
  return terms
end

function M.related_to_goal(root, goal, limit)
  local out, seen = {}, {}
  for _, term in ipairs(M.goal_terms(goal)) do
    for _, hit in ipairs(M.rg(root, term, limit or 20)) do
      local key = hit.file .. ":" .. hit.lnum
      if not seen[key] then
        seen[key] = true
        hit.term = term
        table.insert(out, hit)
      end
    end
  end
  return out
end

function M.symbols(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return {} end
  local lang = parser:lang()
  local okq, query = pcall(vim.treesitter.query.get, lang, "locals")
  if not okq or not query then return {} end
  local tree = parser:parse()[1]
  if not tree then return {} end
  local out = {}
  for id, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
    local name = query.captures[id]
    if name and name:match("definition") then
      local text = vim.treesitter.get_node_text(node, bufnr)
      local row = node:range()
      table.insert(out, { name = text, lnum = row + 1, kind = name })
    end
  end
  return out
end

return M
