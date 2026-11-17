-- Pure placement policy: all coordinates and row definitions belong to callers.
local M = {}

function M.visible(defs, ctx)
  local shown, errors = {}, {}
  for _, def in ipairs(defs) do
    local ok, visible = true, true
    if def.visible then ok, visible = pcall(def.visible, ctx) end
    if ok and visible then shown[#shown + 1] = def
    elseif not ok then errors[#errors + 1] = { id = def.id, error = visible } end
  end
  return shown, errors
end

function M.place(slots, shown_count)
  local sorted, seen = {}, {}
  for _, y in ipairs(slots) do
    if not seen[y] then sorted[#sorted + 1] = y; seen[y] = true end
  end
  table.sort(sorted, function(a, b) return a > b end)
  assert(shown_count >= 0 and shown_count <= #sorted, "more shown rows than authored slots")
  local positions = {}
  for i = 1, shown_count do positions[i] = sorted[i] end
  local footer_dy = shown_count > 0 and sorted[shown_count] - sorted[#sorted] or 0
  return positions, footer_dy
end

return M
