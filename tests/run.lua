vim.opt.rtp:append(vim.fn.getcwd())
local config = require("master-hand.config")
local path = require("master-hand.path")
local schema = require("master-hand.schema")
local runner = require("master-hand.runner")
local providers = require("master-hand.providers")

local function assert_eq(a, b, msg) assert(vim.deep_equal(a, b), (msg or "assert_eq") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b)) end

config.setup({ storage = { enabled = false }, model = { provider = "none" } })
assert_eq(config.get().model.provider, "none")
assert(path.is_ignored("node_modules/x.js", config.get().ignore), "node_modules ignored")
assert(path.is_ignored(".env.local", config.get().ignore), ".env.* ignored")
assert(not path.is_ignored("lua/x.lua", config.get().ignore), "lua file not ignored")

local s = schema.suggestion({ title = "Do thing", confidence = 9, action_type = "command" })
assert_eq(s.confidence, 1)
assert_eq(s.requires_approval, true)

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

local content, perr = providers.complete({})
assert(not content and perr:match("no model"), "provider none returns error")

require("master-hand").setup({ proactivity = "passive", storage = { enabled = false }, model = { provider = "none" } })
require("master-hand.suggestions").generate()
assert(#require("master-hand.state").data.suggestions > 0, "fallback suggestions exist")

print("master-hand tests ok")
