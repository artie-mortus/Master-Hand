-- Sidebar and scratch-buffer UI rendering plus key mappings.
local state = require("master-hand.state")
local config = require("master-hand.config")
local context = require("master-hand.context")
local actions = require("master-hand.actions")

local M = { win = nil, buf = nil, augroup = nil, ns = vim.api.nvim_create_namespace("master-hand-sidebar") }

local default_highlights = {
  MasterHandTitle = { link = "Title" },
  MasterHandRule = { link = "Comment" },
  MasterHandSection = { link = "Statement" },
  MasterHandContext = { link = "Comment" },
  MasterHandModel = { link = "Identifier" },
  MasterHandLoading = { link = "Special" },
  MasterHandSuggestionIndex = { link = "Number" },
  MasterHandSuggestionTitle = { link = "Function" },
  MasterHandReason = { link = "Normal" },
  MasterHandMeta = { link = "Type" },
  MasterHandApproval = { link = "WarningMsg" },
  MasterHandFiles = { link = "Directory" },
  MasterHandNext = { link = "String" },
  MasterHandPending = { link = "Todo" },
  MasterHandKeys = { link = "Question" },
}

local function setup_highlights()
  local custom = ((config.get().ui or {}).highlights or {})
  local names = vim.tbl_keys(default_highlights)
  for name in pairs(custom) do
    if vim.startswith(name, "MasterHand") then table.insert(names, name) end
  end
  for _, name in ipairs(names) do
    local user_spec = custom[name]
    if user_spec ~= false then
      local spec = vim.deepcopy(user_spec ~= nil and user_spec or default_highlights[name] or {})
      if user_spec == nil then spec.default = true end
      pcall(vim.api.nvim_set_hl, 0, name, spec)
    end
  end
end

local function line_hl(buf, lnum, group, start_col, end_col)
  pcall(vim.api.nvim_buf_add_highlight, buf, M.ns, group, lnum, start_col or 0, end_col or -1)
end

local function apply_highlights(buf)
  setup_highlights()
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(buf_lines) do
    local lnum = i - 1
    if i == 1 then
      line_hl(buf, lnum, "MasterHandTitle")
    elseif line:match("^─+$") then
      line_hl(buf, lnum, "MasterHandRule")
    elseif line == "Steering" or line == "Suggestions" or line == "Pending approvals" then
      line_hl(buf, lnum, "MasterHandSection")
    elseif line:match("^model:") then
      line_hl(buf, lnum, "MasterHandModel")
    elseif line:match("^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]") then
      line_hl(buf, lnum, "MasterHandLoading")
    elseif line:match("^%d+%.") then
      local prefix = line:match("^%d+%.") or ""
      line_hl(buf, lnum, "MasterHandSuggestionIndex", 0, #prefix)
      line_hl(buf, lnum, "MasterHandSuggestionTitle", #prefix + 1, -1)
    elseif line:match("^   confidence:") then
      line_hl(buf, lnum, "MasterHandMeta")
    elseif line:match("^   approval required") then
      line_hl(buf, lnum, "MasterHandApproval")
    elseif line:match("^   files:") then
      line_hl(buf, lnum, "MasterHandFiles")
    elseif line:match("^   next:") then
      line_hl(buf, lnum, "MasterHandNext")
    elseif line:match("^%- .+%[.+%]") then
      line_hl(buf, lnum, "MasterHandPending")
    elseif line:match("^Keys:") then
      line_hl(buf, lnum, "MasterHandKeys")
    elseif line:match("^root:") or line:match("^branch:") or line:match("^short:") or line:match("^long:") or line:match("^buffers=") or line:match("^No context") then
      line_hl(buf, lnum, "MasterHandContext")
    elseif line:match("^  short:") or line:match("^  long:") then
      line_hl(buf, lnum, "MasterHandContext")
    elseif line:match("^   .+") then
      line_hl(buf, lnum, "MasterHandReason")
    end
  end
end

local function one_line(value)
  local text = tostring(value or "")
  return (text:gsub("%s*\n%s*", " "))
end

local function lines()
  -- Render from cached context; avoid blocking git/rg/index/model work during UI close/quit/render.
  local out = { "Master Hand", string.rep("─", 32) }
  if state.data.last_context then
    vim.list_extend(out, context.summary_lines(state.data.last_context))
  else
    table.insert(out, "No context yet; run :MHSuggest to refresh.")
  end
  local model = config.get().model or {}
  table.insert(out, "model: " .. (model.provider or "?") .. (model.name and model.name ~= "" and (" / " .. model.name) or ""))
  if state.data.loading then
    local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    table.insert(out, "")
    table.insert(out, (frames[state.data.loading_frame] or frames[1]) .. " " .. (state.data.loading_message or "Loading..."))
  end
  table.insert(out, "")
  if state.data.short_term_goal or state.data.long_term_goal then
    table.insert(out, "Steering")
    table.insert(out, "  short: " .. (state.data.short_term_goal or state.data.goal or "none") .. " (" .. (state.data.short_term_goal_source or state.data.goal_source or "inferred") .. ")")
    table.insert(out, "  long:  " .. (state.data.long_term_goal or "none") .. " (" .. (state.data.long_term_goal_source or "inferred") .. ")")
    table.insert(out, "")
  end
  table.insert(out, "Suggestions")
  for i, s in ipairs(state.data.suggestions) do
    table.insert(out, string.format("%d. %s", i, one_line(s.title)))
    table.insert(out, "   " .. one_line(s.reason))
    table.insert(out, string.format("   confidence: %.2f | action: %s", s.confidence or 0, one_line(s.action_type)))
    if s.requires_approval then table.insert(out, "   approval required") end
    if #s.files > 0 then table.insert(out, "   files: " .. one_line(table.concat(s.files, ", "))) end
    table.insert(out, "   next: " .. one_line(s.next_action))
    table.insert(out, "")
  end
  table.insert(out, "Pending approvals")
  for _, a in ipairs(actions.list()) do
    table.insert(out, string.format("- %s [%s] %s", a.id, a.status, one_line(a.title or a.type)))
  end
  if state.data.last_command then
    table.insert(out, "")
    table.insert(out, "Last command: exit " .. state.data.last_command.code)
  end
  table.insert(out, "")
  if (config.get().agent or {}).enabled then
    table.insert(out, "Keys: a approve/send  d dismiss  p postpone  r refresh  v view  q close")
  else
    table.insert(out, "Keys: a accept  d dismiss  p postpone  r refresh  v view  q close")
  end
  return out
end

function M.render()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.buf].buftype = "nofile"
    vim.bo[M.buf].bufhidden = "wipe"
    vim.bo[M.buf].filetype = "masterhand"
  end
  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines())
  vim.bo[M.buf].modifiable = false
  apply_highlights(M.buf)
end

function M.sidebar_width()
  local opts = config.get().ui or {}
  local width = tonumber(opts.width) or 46
  local ratio = tonumber(opts.max_width_ratio) or 0.45
  if ratio > 0 then
    local max_width = math.max(20, math.floor((vim.o.columns or width) * ratio))
    width = math.min(width, max_width)
  end
  return math.max(1, width)
end

function M.apply_width()
  if not (M.win and vim.api.nvim_win_is_valid(M.win)) then return end
  vim.wo[M.win].winfixwidth = true
  local width = M.sidebar_width()
  if vim.api.nvim_win_get_width(M.win) ~= width then pcall(vim.api.nvim_win_set_width, M.win, width) end
end

local function ensure_resize_autocmd()
  if M.augroup then return end
  M.augroup = vim.api.nvim_create_augroup("MasterHandSidebar", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = M.augroup,
    callback = function()
      if M.win and vim.api.nvim_win_is_valid(M.win) then vim.schedule(M.apply_width) end
    end,
  })
end

function M.open()
  M.render()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    M.apply_width()
    vim.api.nvim_set_current_win(M.win)
    return
  end
  local opts = config.get().ui
  vim.cmd(opts.side == "left" and "topleft vertical new" or "botright vertical new")
  M.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(M.win, M.buf)
  vim.wo[M.win].wrap = true
  M.apply_width()
  ensure_resize_autocmd()
  local map = function(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = M.buf, silent = true })
  end
  map("q", require("master-hand.ui").close)
  map("r", require("master-hand").suggest)
  map("a", function() require("master-hand").accept_suggestion() end)
  map("d", function() require("master-hand").feedback("dismissed") end)
  map("p", function() require("master-hand").feedback("postponed") end)
  map("v", require("master-hand.ui").view_selected)
end

function M.close()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
  end
  M.win = nil
end

function M.suggestion_under_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for i = line, 1, -1 do
    local text = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1] or ""
    local idx = tonumber(text:match("^(%d+)%."))
    if idx then return state.data.suggestions[idx] end
  end
end

function M.show_text(title, text)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text or "", "\n", { plain = true }))
  vim.bo[buf].modifiable = false
  vim.cmd("vnew")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_name(buf, title)
end

function M.view_selected()
  local s = M.suggestion_under_cursor()
  if s then
    M.show_text(s.title, vim.inspect(s))
    return
  end
  if state.data.last_command then M.show_text("Master Hand Command Output", vim.inspect(state.data.last_command)) end
end

return M
