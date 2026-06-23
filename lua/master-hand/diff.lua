local M = {}

function M.prepare(_request)
  return nil, "proposed diff generation needs model provider; no edits prepared"
end

function M.apply(_diff)
  return false, "diff apply requires explicit approval and implementation"
end

return M
