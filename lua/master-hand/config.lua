-- Default options and setup-time config merging. Keep defaults side-effect free.
local M = {}

M.defaults = {
  -- Safe-by-default: installed plugin must not run blocking model/git/rg work from autocmds.
  proactivity = "passive", -- passive | advisory | proactive | high_initiative
  suggestion_frequency_ms = 5000,
  observation = {
    buffers = true,
    edits = true,
    diagnostics = true,
    git = true,
  },
  -- List-valued options are replaced by setup() values, not merged index-wise.
  ignore = {
    ".git/",
    "node_modules/",
    "dist/",
    "build/",
    ".env",
    ".env.*",
  },
  model = {
    provider = "auto", -- none | auto | openai_compatible | openrouter | ollama | anthropic | codex | claude | gemini | pi | cli
    selection = "auto", -- auto | fixed; fixed ignores ranked model routing
    cloud_policy = "fallback", -- fallback orders local candidates before cloud before cloud ranker chooses
    ranking_model = nil, -- optional cloud model used only to pick ranked candidate; defaults to highest-ranked cloud candidate
    ranking_max_tokens = 24,
    ranked = {}, -- optional ranked model candidates; user list replaces default list
    endpoint = nil,
    api_key_env = nil,
    api_key = nil,
    executable = nil,
    command = nil, -- CLI provider argv template list; supports {prompt}; shell strings rejected
    login_command = nil, -- login argv template list; shell strings rejected
    name = nil,
    timeout_ms = 60000,
    temperature = 0.2,
    max_tokens = 1200,
  },
  context = {
    max_files = 80,
    max_diff_bytes = 24000,
    max_file_bytes = 12000,
    max_search_results = 40,
    max_model_code_files = 8,
    max_model_file_bytes = 12000,
    include_related_files = true,
    include_symbols = true,
    include_index = true,
    index = {
      max_files = 500,
      max_file_bytes = 20000,
      max_todos = 40,
      max_symbols = 80,
    },
  },
  commands = {
    allowlist = { "git", "make", "npm", "pnpm", "yarn", "cargo", "go", "pytest", "python", "lua", "nvim" }, -- user list replaces default list
    blocklist = { "rm", "sudo", "git reset", "git clean" }, -- user list replaces default list
    timeout_ms = 10000,
  },
  agent = {
    enabled = true,
    adapter = "auto", -- auto | pi | codex | tmux | zellij | terminal
    executable = nil, -- defaults to pi, or codex when adapter/executable says codex
    command = nil, -- optional argv template list; supports {prompt}, {root}, {prompt_q}, {root_q}; shell strings rejected
    target = nil, -- tmux target pane/window; or MASTER_HAND_TMUX_TARGET
    timeout_ms = nil, -- optional kill timeout for dispatched agent processes; nil = unlimited (handoffs are long-running by design)
    auto_checktime = true,
    set_autoread = true,
    checktime_interval_ms = 2000,
    checktime_duration_ms = 120000,
  },
  storage = {
    enabled = true,
  },
  ui = {
    width = 46,
    max_width_ratio = 0.45,
    side = "right",
    highlights = {}, -- override MasterHand* sidebar highlight groups from setup()
  },
}

local is_list = vim.islist or vim.tbl_islist

local function is_list_value(value, default_value)
  if type(value) ~= "table" or not is_list(value) then return false end
  return next(value) ~= nil or (type(default_value) == "table" and is_list(default_value))
end

local function merge(defaults, opts)
  defaults = defaults or {}
  opts = opts or {}
  if type(opts) ~= "table" then return vim.deepcopy(opts) end
  if is_list_value(opts, defaults) then return vim.deepcopy(opts) end
  if type(defaults) ~= "table" or is_list(defaults) then return vim.deepcopy(opts) end

  local out = vim.deepcopy(defaults)
  for key, value in pairs(opts) do
    local default_value = defaults[key]
    if is_list_value(value, default_value) then
      out[key] = vim.deepcopy(value)
    elseif type(value) == "table" and type(default_value) == "table" and not is_list(default_value) then
      out[key] = merge(default_value, value)
    else
      out[key] = vim.deepcopy(value)
    end
  end
  return out
end

function M.setup(opts)
  M.options = merge(M.defaults, opts)
  return M.options
end

function M.get()
  return M.options or M.setup({})
end

function M.set_model(opts)
  local options = M.get()
  options.model = options.model or {}
  for k, v in pairs(opts or {}) do
    if v == vim.NIL then
      options.model[k] = nil
    else
      options.model[k] = v
    end
  end
  return options.model
end

return M
