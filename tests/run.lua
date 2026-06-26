-- Headless smoke/unit tests for core safety and repo-context behavior.
vim.opt.rtp:append(vim.fn.getcwd())
local config = require("master-hand.config")
local path = require("master-hand.path")
local schema = require("master-hand.schema")
local runner = require("master-hand.runner")
local providers = require("master-hand.providers")
local auth = require("master-hand.auth")
local agent = require("master-hand.agent")
local actions = require("master-hand.actions")
local state = require("master-hand.state")
local ui = require("master-hand.ui")
local search = require("master-hand.search")
local index = require("master-hand.index")
local git = require("master-hand.git")

local function assert_eq(a, b, msg) assert(vim.deep_equal(a, b), (msg or "assert_eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b)) end

config.setup({ storage = { enabled = false } })
assert_eq(config.get().model.provider, "auto")
assert_eq(config.get().model.timeout_ms, 60000, "model timeout allows cold local models")
assert_eq(config.get().agent.enabled, false, "agent handoff disabled by default")
assert(path.is_ignored("node_modules/x.js", config.get().ignore), "node_modules ignored")
assert(path.is_ignored(".env.local", config.get().ignore), ".env.* ignored")
assert(not path.is_ignored("lua/x.lua", config.get().ignore), "lua file not ignored")
assert(#search.goal_terms("Add configurable keybindings to plugin") >= 2, "goal terms extracted")
local idx = index.build(vim.fn.getcwd())
assert(idx.files_seen > 0, "index sees repo files")
assert(idx.languages.Lua and idx.languages.Lua > 0, "index detects Lua files")
assert(#idx.entrypoints > 0, "index detects entrypoints")

local tmp_repo = vim.fn.tempname()
vim.fn.mkdir(tmp_repo, "p")
local function git_ok(args)
  local res = vim.system(args, { cwd = tmp_repo, text = true }):wait()
  assert(res.code == 0, table.concat(args, " ") .. ": " .. (res.stderr or res.stdout or "failed"))
end
git_ok({ "git", "init" })
git_ok({ "git", "config", "user.email", "master-hand@example.invalid" })
git_ok({ "git", "config", "user.name", "Master Hand Test" })
vim.fn.writefile({ "return 1" }, tmp_repo .. "/quoted \"old\".lua")
git_ok({ "git", "add", "." })
git_ok({ "git", "commit", "-m", "init" })
git_ok({ "git", "mv", "quoted \"old\".lua", "quoted \"new\".lua" })
local changed = git.changed_files(tmp_repo)
assert_eq(#changed, 1, "git status parser handles quoted rename")
assert_eq(changed[1].file, "quoted \"new\".lua", "git status parser returns renamed target")
vim.fn.delete(tmp_repo, "rf")

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
config.setup({ storage = { enabled = false }, ui = { highlights = { MasterHandTitle = { fg = "#123456", bold = true } } } })
ui.render()
local title_hl = vim.api.nvim_get_hl(0, { name = "MasterHandTitle", link = false })
assert_eq(title_hl.fg, tonumber("123456", 16), "sidebar highlight fg configurable")
assert_eq(title_hl.bold, true, "sidebar highlight style configurable")
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
ok, err = runner.validate("git status")
assert(not ok and err:match("argv/list"), "shell strings rejected")

local original_system = vim.system
vim.system = function()
  return { wait = function() return { code = 1, signal = 0, stdout = "", stderr = "boom" } end }
end
local ran, rerr = runner.run(vim.fn.getcwd(), { "git", "status" })
assert(not ran and rerr:match("exit 1: boom"), "failed approved commands return an error")
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
local cli_call = nil
vim.system = function(argv_arg, opts_arg)
  cli_call = { argv = argv_arg, opts = opts_arg }
  return { wait = function() return { code = 0, signal = 0, stdout = "cli ok\n", stderr = "" } end }
end
content, perr = providers.complete({ { role = "user", content = "hi" } }, { provider = "claude" })
assert_eq(content, "cli ok", "subscription cli provider returns stdout")
assert_eq(cli_call.argv[1], "claude", "subscription cli provider uses provider executable")
assert(cli_call.argv[#cli_call.argv]:match("user:\nhi"), "subscription cli provider sends prompt without API")
assert_eq(perr, nil, "successful cli provider call has nil error")
content, perr = providers.complete({ { role = "user", content = "hi" } }, { provider = "pi" })
assert_eq(content, "cli ok", "Pi model provider returns stdout")
assert_eq(cli_call.argv[1], "pi", "Pi model provider uses pi executable")
assert(vim.tbl_contains(cli_call.argv, "--no-tools"), "Pi model provider disables tools")
assert(vim.tbl_contains(cli_call.argv, "--no-session"), "Pi model provider is ephemeral")
assert_eq(perr, nil, "successful Pi provider call has nil error")
vim.system = original_system

content, perr = providers.complete({}, { provider = "anthropic", name = "claude-sonnet-4-20250514", api_key_env = "MASTER_HAND_TEST_MISSING_KEY" })
assert(not content and perr:match("api key missing"), "anthropic requires api key")
content, perr = providers.complete({}, { provider = "openrouter", name = "anthropic/claude-3.5-sonnet", api_key_env = "MASTER_HAND_TEST_MISSING_KEY" })
assert(not content and perr:match("openrouter api key missing"), "openrouter requires api key")
vim.env.MASTER_HAND_TEST_OPENROUTER_KEY = "mh-secret"
assert_eq(auth.key({ provider = "openrouter", api_key_env = "MASTER_HAND_TEST_OPENROUTER_KEY" }), "mh-secret", "auth reads provider key env")
assert(auth.status({ provider = "openrouter", api_key_env = "MASTER_HAND_TEST_OPENROUTER_KEY" }):match("auth=set"), "auth status reports configured key")
vim.env.MASTER_HAND_TEST_OPENROUTER_KEY = nil
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
mh.auth({ "openai", "env:MASTER_HAND_TEST_OPENAI_KEY" })
assert_eq(config.get().model.provider, "openai_compatible", ":MHAuth can select provider")
assert_eq(config.get().model.api_key_env, "MASTER_HAND_TEST_OPENAI_KEY", ":MHAuth accepts env:VAR")
mh.auth({ "openrouter", "mh-secret" })
assert_eq(config.get().model.provider, "openrouter", ":MHAuth direct key can select provider")
assert_eq(vim.env.OPENROUTER_API_KEY, "mh-secret", ":MHAuth direct key stores process env")
assert_eq(config.get().model.api_key_env, "OPENROUTER_API_KEY", ":MHAuth direct key uses provider default env")
mh.auth({ "clear" })
assert_eq(vim.env.OPENROUTER_API_KEY, nil, ":MHAuth clear unsets process env")
mh.model({ "codex" })
assert_eq(config.get().model.provider, "codex", ":MHModel supports subscription-backed Codex provider")
assert_eq(config.get().model.api_key_env, nil, ":MHModel codex does not require api key env")
assert(auth.status(config.get().model):match("auth=account%-cli"), ":MHModel codex reports account cli auth")
mh.model({ "pi" })
assert_eq(config.get().model.provider, "pi", ":MHModel supports Pi as a background model provider")
assert_eq(config.get().model.api_key_env, nil, ":MHModel pi does not require api key env")
assert(auth.status(config.get().model):match("auth=account%-cli"), ":MHModel pi reports account cli auth")
mh.auth({ "claude" })
assert_eq(config.get().model.provider, "claude", ":MHAuth can select account cli provider without prompting for key")
local login_argv, termopen_called = nil, false
local original_login_system, original_termopen = vim.system, vim.fn.termopen
vim.system = function(argv_arg, _, cb_arg)
  login_argv = argv_arg
  if cb_arg then cb_arg({ code = 0, signal = 0, stdout = "", stderr = "" }) end
  return { pid = 456 }
end
vim.fn.termopen = function()
  termopen_called = true
  return 1
end
mh.auth({ "codex", "login" })
assert_eq(login_argv, { "codex", "login" }, ":MHAuth login runs provider login command")
assert(not termopen_called, ":MHAuth login runs in background, no Neovim terminal window")
vim.system, vim.fn.termopen = original_login_system, original_termopen
mh.model({ "provider=openrouter", "model=anthropic/claude-3.5-sonnet", "api_key_env=OPENROUTER_API_KEY" })
assert_eq(config.get().model.provider, "openrouter", ":MHModel key=value sets provider")
assert_eq(config.get().model.name, "anthropic/claude-3.5-sonnet", ":MHModel model= maps to name")
assert_eq(config.get().model.api_key_env, "OPENROUTER_API_KEY", ":MHModel sets api key env")

state.data.pending_actions = {}
local diff_mod = require("master-hand.diff")
local original_apply = diff_mod.apply
local pending = actions.create({ type = "proposed_edit", title = "Broken diff", root = vim.fn.getcwd(), diff = "bad" })
diff_mod.apply = function() return false, "stale patch" end
mh.approve(pending.id)
assert(actions.get(pending.id), "failed apply keeps action pending")
diff_mod.apply = function() return true end
mh.approve(pending.id)
assert_eq(actions.get(pending.id), nil, "successful apply approves action")
diff_mod.apply = original_apply
state.data.pending_actions = {}

providers.complete = function() error("sync model should not run during :MH open") end
local async_calls = {}
providers.complete_async = function(messages, _, cb) table.insert(async_calls, { messages = messages, cb = cb }) end
state.set_suggestions({})
require("master-hand").setup({ proactivity = "passive", storage = { enabled = false }, model = { provider = "auto" } })
require("master-hand").open()
assert(state.data.loading, ":MH shows loading state while model runs")
assert(#state.data.suggestions > 0, ":MH shows local suggestions while model runs")
assert(vim.wait(1000, function() return #async_calls == 1 end), ":MH scans project then starts async goal inference")
assert(async_calls[1].messages[1].content:match("Infer steering intent"), ":MH starts async goal inference")
assert(state.data.last_context.repo_index and state.data.last_context.repo_index.files_seen > 0, ":MH async path scans project before model goal inference")
async_calls[1].cb(vim.json.encode({ long_term_goal = "Async long goal", short_term_goal = "Async short goal", confidence = 0.9 }))
assert(state.data.loading, "loading continues while async suggestions run")
assert(#async_calls == 2, ":MH starts async model suggestions after goal inference")
async_calls[2].cb("[]")
assert(not state.data.loading, "loading stops after async model finishes")
assert_eq(state.data.short_term_goal, "Async short goal", "async path refines short-term goal")
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
require("master-hand").set_next("Finish explicit next step")
assert_eq(state.data.short_term_goal, "Finish explicit next step", "user can set short-term next step")
assert_eq(state.data.short_term_goal_source, "user", "short-term next step source tracked")
require("master-hand.context").snapshot({ quick = true })
assert_eq(state.data.short_term_goal, "Finish explicit next step", "snapshot preserves user short-term next step")
require("master-hand").set_next("")
assert_eq(state.data.short_term_goal_source, "inferred", ":MHNext without args resets short-term inference")

state.data.root = vim.fn.getcwd()
state.data.last_context = { root = vim.fn.getcwd(), branch = "test", open_buffers = {}, changed_files = { "lua/master-hand/init.lua" }, diagnostics = { errors = 0, warnings = 0 } }
state.set_suggestions({ schema.suggestion({ title = "Wire approved suggestions to agent", reason = "approval should leave Neovim", files = { "lua/master-hand/init.lua" }, next_action = "send to coding agent" }) })
local prompt = agent.prompt(state.data.suggestions[1])
assert(prompt:match("Wire approved suggestions to agent"), "agent prompt includes suggestion title")
assert(prompt:match("lua/master%-hand/init%.lua"), "agent prompt includes files")
local argv = agent.argv({ command = { "fake-agent", "--cwd", "{root}", "--task", "{prompt}" } }, "hello", "/tmp/repo")
assert_eq(argv, { "fake-agent", "--cwd", "/tmp/repo", "--task", "hello" }, "agent command templates expand root/prompt")
local captured = nil
original_system = vim.system
vim.system = function(argv_arg, opts_arg, cb_arg)
  captured = { argv = argv_arg, opts = opts_arg }
  if cb_arg then cb_arg({ code = 0, signal = 0, stdout = "", stderr = "" }) end
  return { pid = 123 }
end
require("master-hand").setup({ proactivity = "passive", storage = { enabled = false }, agent = { enabled = true, command = { "fake-agent", "--task", "{prompt}" }, auto_checktime = false } })
require("master-hand").approve_suggestion(1)
assert(captured and captured.argv[1] == "fake-agent", "approved suggestion dispatches configured agent command")
assert(captured.argv[3]:match("Wire approved suggestions to agent"), "agent receives approved suggestion prompt")
assert_eq(state.data.feedback[state.data.suggestions[1].id], "accepted", "agent handoff records accepted feedback")
vim.system = original_system

require("master-hand").setup({ proactivity = "passive", storage = { enabled = false }, agent = { enabled = true, adapter = "terminal", executable = "definitely-missing-master-hand-exe-xyz", auto_checktime = false } })
local sent, send_err = agent.dispatch(schema.suggestion({ title = "Missing terminal agent" }))
assert(not sent and send_err:match("agent executable not found"), "missing terminal agent returns clean error")

print("master-hand tests ok")
