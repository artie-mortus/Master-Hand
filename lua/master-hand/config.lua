-- Default options and setup-time config merging. Keep defaults side-effect free.
local M = {}

M.defaults = {
  proactivity = "advisory", -- passive | advisory | proactive | high_initiative
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
    provider = "auto", -- auto | openai_compatible | openrouter | ollama | anthropic
    endpoint = nil,
    api_key_env = nil,
    name = nil,
    context_limit = 32000,
    timeout_ms = 30000,
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
  },
  storage = {
    enabled = true,
  },
  ui = {
    width = 46,
    side = "right",
    show_diff_preview = true,
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

return M
