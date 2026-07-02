-- Deterministic local repo index. No model calls here.
local git = require("master-hand.git")
local config = require("master-hand.config")
local path = require("master-hand.path")

local M = {}

local ext_lang = {
  lua = "Lua", js = "JavaScript", jsx = "JavaScript", ts = "TypeScript", tsx = "TypeScript",
  py = "Python", rb = "Ruby", go = "Go", rs = "Rust", c = "C", h = "C/C++", cpp = "C++",
  hpp = "C++", java = "Java", kt = "Kotlin", swift = "Swift", php = "PHP", sh = "Shell",
  bash = "Shell", zsh = "Shell", fish = "Shell", md = "Markdown", json = "JSON", yaml = "YAML",
  yml = "YAML", toml = "TOML", vim = "Vimscript", rpy = "Ren'Py",
}

local function file_ext(file)
  return (file:match("%.([%w_%-]+)$") or ""):lower()
end

local function lang_for(file)
  return ext_lang[file_ext(file)] or (file_ext(file) ~= "" and file_ext(file) or "other")
end

-- Read only small file heads; indexing should never pull huge files into memory.
local function read_head(root, file, max_bytes)
  local full = root .. "/" .. file
  local stat = vim.uv.fs_stat(full)
  if not stat or stat.type ~= "file" then return nil, 0 end
  if stat.size > max_bytes then return nil, stat.size end
  local ok, lines = pcall(vim.fn.readfile, full, "", 400)
  if not ok then return nil, stat.size end
  return table.concat(lines, "\n"), stat.size
end

local function add_count(t, key, n)
  key = key or "other"
  t[key] = (t[key] or 0) + (n or 1)
end

local function symbols_for(file, text, limit)
  local out = {}
  local patterns = {
    "function%s+([%w_%.:]+)%s*%(",
    "local%s+function%s+([%w_%.:]+)%s*%(",
    "class%s+([%w_]+)",
    "def%s+([%w_]+)%s*%(",
    "([%w_]+)%s*=%s*function%s*%(",
  }
  for _, pat in ipairs(patterns) do
    for name in text:gmatch(pat) do
      table.insert(out, { file = file, name = name })
      if #out >= limit then return out end
    end
  end
  return out
end

local function todos_for(file, text, limit)
  local out, lnum = {}, 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    lnum = lnum + 1
    local hit = line:match("%f[%w](TODO[:%s].*)") or line:match("%f[%w](FIXME[:%s].*)") or line:match("%f[%w](HACK[:%s].*)")
    if hit then
      table.insert(out, { file = file, lnum = lnum, text = vim.trim(hit) })
      if #out >= limit then break end
    end
  end
  return out
end

-- Build compact repo facts for prompts/UI without calling external models.
function M.build(root)
  root = root or git.root()
  local opts = config.get().context.index or {}
  local max_files = opts.max_files or 500
  local max_file_bytes = opts.max_file_bytes or 20000
  local files = git.ls_files(root, max_files)
  local idx = {
    files_seen = #files,
    dirs = {},
    languages = {},
    extensions = {},
    largest_files = {},
    entrypoints = {},
    tests = {},
    docs = {},
    todos = {},
    symbols = {},
  }

  for _, file in ipairs(files) do
    if not path.is_ignored(file, config.get().ignore) then
      local dir = file:match("^(.+)/[^/]+$") or "."
      add_count(idx.dirs, dir)
      add_count(idx.languages, lang_for(file))
      add_count(idx.extensions, file_ext(file) ~= "" and file_ext(file) or "none")
      if file:match("^tests?/") or file:match("/tests?/") or file:match("[_%.%-]test%.") or file:match("[_%.%-]spec%.") then table.insert(idx.tests, file) end
      if file:lower():match("readme") or file:match("%.md$") then table.insert(idx.docs, file) end
      if file:match("^main%.") or file:match("/main%.") or file:match("^init%.") or file:match("/init%.") or file:match("^plugin/") then table.insert(idx.entrypoints, file) end

      local text, size = read_head(root, file, max_file_bytes)
      table.insert(idx.largest_files, { file = file, bytes = size })
      if text then
        vim.list_extend(idx.todos, todos_for(file, text, opts.max_todos or 40))
        vim.list_extend(idx.symbols, symbols_for(file, text, opts.max_symbols or 80))
      end
    end
  end

  table.sort(idx.largest_files, function(a, b) return a.bytes > b.bytes end)
  while #idx.largest_files > 10 do table.remove(idx.largest_files) end
  return idx
end

return M
