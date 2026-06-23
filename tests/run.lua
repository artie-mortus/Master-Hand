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

local content, perr = providers.complete({}, { provider = "anthropic", name = "claude-sonnet-4-20250514", api_key_env = "MASTER_HAND_TEST_MISSING_KEY" })
assert(not content and perr:match("api key missing"), "anthropic requires api key")
content, perr = providers.complete({}, { provider = "openrouter", name = "anthropic/claude-3.5-sonnet", api_key_env = "MASTER_HAND_TEST_MISSING_KEY" })
assert(not content and perr:match("openrouter api key missing"), "openrouter requires api key")

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
