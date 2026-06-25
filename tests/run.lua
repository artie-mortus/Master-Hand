-- Headless smoke/unit tests for core safety and repo-context behavior.
vim.opt.rtp:append(vim.fn.getcwd())
local config = require("master-hand.config")
local path = require("master-hand.path")
local schema = require("master-hand.schema")
local runner = require("master-hand.runner")
local providers = require("master-hand.providers")
local actions = require("master-hand.actions")
local state = require("master-hand.state")
local ui = require("master-hand.ui")
local search = require("master-hand.search")
local index = require("master-hand.index")

local function assert_eq(a, b, msg) assert(vim.deep_equal(a, b), (msg or "assert_eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b)) end

config.setup({ storage = { enabled = false } })
assert_eq(config.get().model.provider, "auto")
assert_eq(config.get().model.timeout_ms, 60000, "model timeout allows cold local models")
assert(path.is_ignored("node_modules/x.js", config.get().ignore), "node_modules ignored")
assert(path.is_ignored(".env.local", config.get().ignore), ".env.* ignored")
assert(not path.is_ignored("lua/x.lua", config.get().ignore), "lua file not ignored")
assert(#search.goal_terms("Add configurable keybindings to plugin") >= 2, "goal terms extracted")
local idx = index.build(vim.fn.getcwd())
assert(idx.files_seen > 0, "index sees repo files")
assert(idx.languages.Lua and idx.languages.Lua > 0, "index detects Lua files")
assert(#idx.entrypoints > 0, "index detects entrypoints")

local s = schema.suggestion({ title = "Do thing", confidence = 9, action_type = "command" })
assert_eq(s.confidence, 1)
assert_eq(s.requires_approval, true)
s = schema.suggestion({ title = "Run thing", action_type = "command", requires_approval = false })
assert_eq(s.requires_approval, true, "untrusted command suggestions still require approval")

state.data.pending_actions = {}
local action = actions.create({ type = "command", title = "Run safe command", argv = { "git", "status" } })
assert_eq(#actions.list(), 1)
actions.approve(action.id)
assert_eq(actions.get(action.id), nil, "approved actions stop being pending")
assert_eq(#actions.list(), 0)
state.set_suggestions({ schema.suggestion({ title = "Multiline", reason = "line one\nline two", next_action = "retry\nnow" }) })
ui.render()
local old_columns = vim.o.columns
vim.o.columns = 120
config.setup({ storage = { enabled = false }, ui = { width = 46, max_width_ratio = 0.45 } })
ui.open()
assert_eq(vim.api.nvim_win_get_width(ui.win), 46, "sidebar uses configured width when room exists")
assert_eq(vim.wo[ui.win].winfixwidth, true, "sidebar keeps fixed width across terminal resize")
vim.o.columns = 80
ui.apply_width()
assert_eq(vim.api.nvim_win_get_width(ui.win), 36, "sidebar clamps to max screen ratio")
ui.close()
vim.o.columns = old_columns
config.setup({ storage = { enabled = false } })

local ok, err = runner.validate({ "rm", "-rf", "." })
assert(not ok and err:match("blocked"), "rm blocked")
ok, err = runner.validate({ "git", "clean", "-fd" })
assert(not ok and err:match("blocked"), "git clean blocked")
ok, err = runner.validate({ "git", "reset", "--hard" })
assert(not ok and err:match("blocked"), "git reset blocked")
ok, err = runner.validate({ "git", "-C", ".", "clean", "-fd" })
assert(not ok and err:match("blocked"), "git -C clean blocked")
ok, err = runner.validate({ "git", "-C", ".", "reset", "--hard" })
assert(not ok and err:match("blocked"), "git -C reset blocked")
ok, err = runner.validate({ "git", "status" })
assert(ok and ok[1] == "git", "git status allowed")
ok, err = runner.validate({ "npm", "run", "format" })
assert(ok and ok[1] == "npm", "safe command with blocklist substring allowed")

local original_system = vim.system
vim.system = function()
  return { wait = function() return { code = 124, signal = 15, stdout = "", stderr = "" } end }
end
local content, perr = providers.complete({}, { provider = "openai_compatible", endpoint = "http://example.invalid", name = "x", timeout_ms = 1234 })
assert(not content and perr:match("timed out after 1%.2s"), "provider timeout includes actionable error")
vim.system = function()
  return { wait = function() return { code = 0, signal = 0, stdout = '{"choices":[{"message":{"content":"[]"}}]}', stderr = "" } end }
end
content, perr = providers.complete({}, { provider = "openai_compatible", endpoint = "http://example.invalid", name = "x" })
assert_eq(content, "[]", "provider returns content")
assert_eq(perr, nil, "successful provider call has nil error")
vim.system = original_system

content, perr = providers.complete({}, { provider = "anthropic", name = "claude-sonnet-4-20250514", api_key_env = "MASTER_HAND_TEST_MISSING_KEY" })
assert(not content and perr:match("api key missing"), "anthropic requires api key")
content, perr = providers.complete({}, { provider = "openrouter", name = "anthropic/claude-3.5-sonnet", api_key_env = "MASTER_HAND_TEST_MISSING_KEY" })
assert(not content and perr:match("openrouter api key missing"), "openrouter requires api key")
content, perr = providers.complete({}, { provider = "none" })
assert(not content and perr:match("disabled"), "provider none disables model calls")

local mh = require("master-hand")
mh.setup({ proactivity = "passive", storage = { enabled = false }, model = { provider = "auto", name = "old", endpoint = "http://old" } })
mh.model({ "ollama", "qwen3-coder-local:latest" })
assert_eq(config.get().model.provider, "ollama", ":MHModel sets provider")
assert_eq(config.get().model.name, "qwen3-coder-local:latest", ":MHModel sets model name")
mh.model({ "openai", "gpt-5.5" })
assert_eq(config.get().model.provider, "openai_compatible", ":MHModel openai maps to OpenAI-compatible provider")
assert_eq(config.get().model.name, "gpt-5.5", ":MHModel openai sets model name")
assert_eq(config.get().model.endpoint, "https://api.openai.com/v1/chat/completions", ":MHModel openai sets default endpoint")
assert_eq(config.get().model.api_key_env, "OPENAI_API_KEY", ":MHModel openai sets default api env")
mh.model({ "gpt-5.5" })
assert_eq(config.get().model.provider, "openai_compatible", ":MHModel infers OpenAI for versioned gpt models")
assert_eq(config.get().model.name, "gpt-5.5", ":MHModel keeps inferred OpenAI model name")
mh.model({ "gpt-oss:120b" })
assert_eq(config.get().model.provider, "ollama", ":MHModel does not treat gpt-oss as OpenAI")
assert_eq(config.get().model.name, "gpt-oss:120b", ":MHModel keeps gpt-oss model name")
mh.model({ "ollama-cloud", "gpt-oss:120b" })
assert_eq(config.get().model.provider, "ollama", ":MHModel ollama-cloud uses Ollama provider")
assert_eq(config.get().model.name, "gpt-oss:120b", ":MHModel ollama-cloud sets model name")
assert_eq(config.get().model.endpoint, "https://ollama.com/api/chat", ":MHModel ollama-cloud sets cloud endpoint")
assert_eq(config.get().model.api_key_env, "OLLAMA_API_KEY", ":MHModel ollama-cloud sets api env")
mh.model({ "auto" })
assert_eq(config.get().model.provider, "auto", ":MHModel auto sets provider")
assert_eq(config.get().model.name, nil, ":MHModel auto clears stale model name")
assert_eq(config.get().model.endpoint, nil, ":MHModel auto clears stale endpoint")
mh.model({ "openrouter", "anthropic/claude-3.5-sonnet" })
assert_eq(config.get().model.provider, "openrouter", ":MHModel openrouter sets provider")
assert_eq(config.get().model.name, "anthropic/claude-3.5-sonnet", ":MHModel openrouter sets model")
assert_eq(config.get().model.api_key_env, "OPENROUTER_API_KEY", ":MHModel openrouter sets default api env")
mh.model({ "provider=openrouter", "model=anthropic/claude-3.5-sonnet", "api_key_env=OPENROUTER_API_KEY" })
assert_eq(config.get().model.provider, "openrouter", ":MHModel key=value sets provider")
assert_eq(config.get().model.name, "anthropic/claude-3.5-sonnet", ":MHModel model= maps to name")
assert_eq(config.get().model.api_key_env, "OPENROUTER_API_KEY", ":MHModel sets api key env")

providers.complete = function() error("sync model should not run during :MH open") end
local async_cb = nil
providers.complete_async = function(_, _, cb) async_cb = cb end
state.set_suggestions({})
require("master-hand").setup({ proactivity = "passive", storage = { enabled = false }, model = { provider = "auto" } })
require("master-hand").open()
assert(state.data.loading, ":MH shows loading state while model runs")
assert(#state.data.suggestions > 0, ":MH shows local suggestions while model runs")
assert(async_cb, ":MH starts async model suggestions")
async_cb("[]")
assert(not state.data.loading, "loading stops after async model finishes")
require("master-hand").close()

providers.complete = function() return nil, "boom" end
require("master-hand").setup({ proactivity = "passive", storage = { enabled = false }, model = { provider = "auto" } })
require("master-hand.suggestions").generate()
for _, sug in ipairs(state.data.suggestions) do assert(sug.id ~= "provider-error", "auto provider failures stay hidden") end

providers.complete = function(messages)
  if messages[1].content:match("Infer steering intent") then
    return vim.json.encode({ long_term_goal = "Model inferred long goal", short_term_goal = "Model inferred short goal", confidence = 0.9 })
  end
  return "[]"
end
require("master-hand").setup({ proactivity = "passive", storage = { enabled = false } })
require("master-hand.suggestions").generate()
assert(#state.data.suggestions > 0, "fallback suggestions exist")
assert(state.data.short_term_goal and state.data.short_term_goal ~= "", "short-term goal is always inferred")
assert(state.data.long_term_goal and state.data.long_term_goal ~= "", "long-term goal is always inferred")
assert(state.data.short_term_goal_source == "model", "default short-term goal refined by model")
require("master-hand").set_goal("Ship explicit goal override")
assert(state.data.long_term_goal == "Ship explicit goal override", "user goal steers long-term intent")
assert(state.data.long_term_goal_source == "user", "user steering source tracked")
assert(state.data.short_term_goal and state.data.short_term_goal ~= "", "short-term goal remains available")

print("master-hand tests ok")
