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
    provider = "none",
    endpoint = nil,
    api_key_env = nil,
    name = nil,
    context_limit = 32000,
  },
  ui = {
    width = 46,
    side = "right",
  },
}

local function merge(a, b)
  return vim.tbl_deep_extend("force", a or {}, b or {})
end

function M.setup(opts)
  M.options = merge(M.defaults, opts or {})
  return M.options
end

function M.get()
  return M.options or M.setup({})
end

return M
