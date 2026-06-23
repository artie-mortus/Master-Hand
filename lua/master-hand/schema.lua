-- Normalizes untrusted suggestion tables into one safe internal shape.
local M = {}
local allowed = { advice=true, proposed_edit=true, command=true }

function M.suggestion(item)
  if type(item) ~= "table" then return nil end
  local title = tostring(item.title or "")
  if title == "" then return nil end
  local action_type = allowed[item.action_type] and item.action_type or "advice"
  return {
    id = tostring(item.id or title:gsub("%s+", "-"):lower()),
    title = title,
    reason = tostring(item.reason or ""),
    files = type(item.files) == "table" and item.files or {},
    confidence = math.max(0, math.min(1, tonumber(item.confidence) or 0.5)),
    next_action = tostring(item.next_action or ""),
    action_type = action_type,
    requires_approval = action_type ~= "advice" or item.requires_approval == true,
    command = item.command,
    diff_request = item.diff_request,
  }
end

function M.list(items)
  local out = {}
  if type(items) ~= "table" then return out end
  for _, item in ipairs(items) do
    local ok = M.suggestion(item)
    if ok then table.insert(out, ok) end
  end
  return out
end

return M
