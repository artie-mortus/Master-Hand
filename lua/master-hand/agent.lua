-- Approved suggestion handoff to external coding agents plus buffer sync.
local config = require("master-hand.config")
local state = require("master-hand.state")

local M = {}
local sync_timer = nil

local function one_line(value)
  return tostring(value or ""):gsub("%s+", " ")
end

local function shell_quote(value)
  return vim.fn.shellescape(tostring(value or ""))
end

local function replace_vars(value, vars)
  if type(value) ~= "string" then return value end
  return (value:gsub("{([%w_]+)}", function(key)
    return tostring(vars[key] or "")
  end))
end

function M.prompt(suggestion)
  local snap = state.data.last_context or {}
  local files = table.concat(suggestion.files or {}, ", ")
  local lines = {
    "You are a coding agent launched by Master Hand from Neovim.",
    "Repo root: " .. tostring(state.data.root or vim.uv.cwd()),
    "",
    "Approved suggestion:",
    "Title: " .. one_line(suggestion.title),
    "Reason: " .. one_line(suggestion.reason),
    "Files: " .. (files ~= "" and files or "none specified"),
    "Next action: " .. one_line(suggestion.next_action),
    "Action type: " .. one_line(suggestion.action_type),
    "",
    "Steering:",
    "Long-term: " .. one_line(state.data.long_term_goal or snap.long_term_goal or "none"),
    "Short-term: " .. one_line(state.data.short_term_goal or snap.short_term_goal or "none"),
    "",
    "Constraints:",
    "- Edit only this repo unless explicitly required.",
    "- Keep changes minimal and focused on approved suggestion.",
    "- Preserve uncommitted user work; inspect git status before broad edits.",
    "- Do not commit, push, or run destructive commands unless user explicitly asks.",
    "- Save modified files. Master Hand will refresh Neovim buffers with :checktime.",
  }
  if snap.changed_files and #snap.changed_files > 0 then
    table.insert(lines, "")
    table.insert(lines, "Changed files: " .. table.concat(snap.changed_files, ", "))
  end
  if snap.diagnostics then
    table.insert(lines, "Diagnostics: " .. vim.inspect(snap.diagnostics))
  end
  return table.concat(lines, "\n")
end

local function configured_executable(opts)
  if opts.executable and opts.executable ~= "" then return opts.executable end
  if opts.adapter == "codex" then return "codex" end
  return "pi"
end

local function default_command(opts, prompt, root)
  local adapter = opts.adapter or "auto"
  local exe = configured_executable(opts)
  if adapter == "codex" or exe == "codex" then
    return { "codex", "exec", prompt }
  end
  if adapter == "pi" then
    return { exe, prompt }
  end
  if adapter == "tmux" or (adapter == "auto" and vim.env.TMUX and (opts.target or vim.env.MASTER_HAND_TMUX_TARGET)) then
    local target = opts.target or vim.env.MASTER_HAND_TMUX_TARGET
    if not target or target == "" then return nil, "agent.target or MASTER_HAND_TMUX_TARGET required for tmux" end
    -- send-keys types into the target pane: every newline acts as Enter, so a
    -- multi-line prompt would execute line by line in a shell pane. Collapse to
    -- one line and send literally (-l), with Enter as a separate command.
    return { "tmux", "send-keys", "-t", target, "-l", one_line(prompt), ";", "send-keys", "-t", target, "C-m" }
  end
  if adapter == "zellij" or (adapter == "auto" and vim.env.ZELLIJ) then
    return { "zellij", "run", "--cwd", root, "--name", "Master Hand Agent", "--", exe, prompt }
  end
  if adapter == "terminal" or adapter == "auto" then
    return { exe, prompt }
  end
  return nil, "unknown agent adapter: " .. tostring(adapter)
end

function M.argv(opts, prompt, root)
  opts = opts or {}
  local vars = { prompt = prompt, root = root, prompt_q = shell_quote(prompt), root_q = shell_quote(root) }
  if type(opts.command) == "string" then return nil, "command must be an argv table (list of strings)" end
  if type(opts.command) == "table" and opts.command[1] then
    local out = {}
    for i, part in ipairs(opts.command) do
      if type(part) ~= "string" then return nil, "command must be an argv table (list of strings)" end
      out[i] = replace_vars(part, vars)
    end
    return out
  end
  if opts.command ~= nil then return nil, "command must be an argv table (list of strings)" end
  return default_command(opts, prompt, root)
end

local function run_checktime()
  if config.get().agent.set_autoread ~= false then vim.o.autoread = true end
  pcall(vim.cmd, "checktime")
end

function M.stop_sync_poll()
  if sync_timer then
    sync_timer:stop()
    sync_timer:close()
    sync_timer = nil
  end
end

function M.start_sync_poll()
  local opts = config.get().agent or {}
  if opts.auto_checktime == false then return end
  M.stop_sync_poll()
  local interval = tonumber(opts.checktime_interval_ms) or 2000
  local duration = tonumber(opts.checktime_duration_ms) or 120000
  local stop_at = vim.uv.now() + duration
  run_checktime()
  sync_timer = vim.uv.new_timer()
  sync_timer:start(interval, interval, vim.schedule_wrap(function()
    run_checktime()
    if vim.uv.now() >= stop_at then M.stop_sync_poll() end
  end))
end

function M.sync()
  run_checktime()
end

local function use_neovim_terminal(opts)
  if type(opts.command) == "table" then return false end
  local adapter = opts.adapter or "auto"
  if adapter == "terminal" then return true end
  if adapter ~= "auto" then return false end
  if vim.env.ZELLIJ then return false end
  if vim.env.TMUX and (opts.target or vim.env.MASTER_HAND_TMUX_TARGET) then return false end
  return true
end

function M.dispatch(suggestion, cb)
  local opts = config.get().agent or {}
  if not opts.enabled then return nil, "agent handoff disabled" end
  local root = state.data.root or vim.uv.cwd()
  local prompt = M.prompt(suggestion)
  local argv, err = M.argv(opts, prompt, root)
  if not argv then return nil, err end

  if use_neovim_terminal(opts) then
    if vim.fn.executable(argv[1]) ~= 1 then return nil, "agent executable not found: " .. tostring(argv[1]) end
    local ok, err = pcall(vim.cmd, opts.terminal_cmd or "botright split")
    if not ok then return nil, err end
    ok, err = pcall(vim.fn.termopen, argv, { cwd = root, on_exit = vim.schedule_wrap(function()
      M.sync()
      if cb then cb(true) end
    end) })
    if not ok then return nil, err end
    M.start_sync_poll()
    return { argv = argv, prompt = prompt }
  end

  local ok, handle = pcall(vim.system, argv, { cwd = root, text = true }, vim.schedule_wrap(function(res)
    M.sync()
    if cb then cb(res and res.code == 0, res) end
  end))
  if not ok then return nil, handle end
  M.start_sync_poll()
  return { argv = argv, prompt = prompt, handle = handle }
end

return M
