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
  permissions = {
    auto_read = true,
    require_edit_approval = true,
    require_command_approval = true,
    trusted_actions = {},
  },
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
    endpoint = nil,
    api_key_env = nil,
    api_key = nil,
    executable = nil,
    command = nil, -- CLI provider argv template; supports {prompt}
    login_command = nil,
    name = nil,
    context_limit = 32000,
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
    allowlist = { "git", "make", "npm", "pnpm", "yarn", "cargo", "go", "pytest", "python", "lua", "nvim" },
    blocklist = { "rm", "sudo", "git reset", "git clean" },
    timeout_ms = 10000,
  },
  agent = {
    enabled = true,
    adapter = "auto", -- auto | pi | codex | tmux | zellij | terminal
    executable = nil, -- defaults to pi, or codex when adapter/executable says codex
    command = nil, -- optional argv template; supports {prompt}, {root}, {prompt_q}, {root_q}
    target = nil, -- tmux target pane/window; or MASTER_HAND_TMUX_TARGET
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
    show_diff_preview = true,
    highlights = {}, -- override MasterHand* sidebar highlight groups from setup()
  },
}

local function merge(defaults, opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(defaults or {}), opts or {})
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
