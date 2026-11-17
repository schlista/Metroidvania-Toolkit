local Rows = require "mvtk.ui.pause_rows"
local M = {}

function M.new(deps)
  deps = deps or {}
  local model = { entries = {
    { id = "resume", action = "resume" },
    { id = "inventory", action = "open_inventory" },
    { id = "map", action = "open_map", visible = function(ctx) return ctx.world_map_enabled end },
    { id = "fast_travel", action = "open_fast_travel", visible = function(ctx)
      return ctx.world_map_enabled and ctx.can_menu_travel()
    end },
    { id = "settings", action = "open_settings" },
    { id = "quit", action = "quit_to_menu" },
  } }
  local providers, warned = {}, {}
  function model.warn(key, err)
    if warned[key] then return end
    warned[key] = true
    (deps.log or print)("[PAUSE_MENU] " .. key .. ": " .. tostring(err))
  end
  -- Repeated module loads update an id in place, without duplicating rows.
  function model.register_entry(id, spec)
    for _, entry in ipairs(model.entries) do
      if entry.id == id then
        for key, value in pairs(spec) do
          if key ~= "after" and key ~= "replace" and key ~= "id" then entry[key] = value end
        end
        return entry
      end
    end
    local entry = { id = id }
    for key, value in pairs(spec) do if key ~= "id" then entry[key] = value end end
    local index = #model.entries + 1
    if spec.after then
      index = nil
      for i, existing in ipairs(model.entries) do if existing.id == spec.after then index = i + 1; break end end
      assert(index, "unknown preceding pause row: " .. tostring(spec.after))
    end
    table.insert(model.entries, index, entry)
    return entry
  end
  function model.add_info(id, priority, fn)
    providers[id] = { id = id, priority = priority, fn = fn }
  end
  function model.visible_entries(ctx)
    local shown, errors = Rows.visible(model.entries, ctx)
    for _, err in ipairs(errors) do model.warn("visible/" .. err.id, err.error) end
    return shown
  end
  function model.info_text(ctx)
    local ordered = {}
    for _, provider in pairs(providers) do ordered[#ordered + 1] = provider end
    table.sort(ordered, function(a, b)
      if a.priority == b.priority then return a.id < b.id end
      return a.priority > b.priority
    end)
    for _, provider in ipairs(ordered) do
      local ok, text = pcall(provider.fn, ctx)
      if ok and text ~= nil and text ~= false and tostring(text) ~= "" then return text end
      if not ok then model.warn("info/" .. provider.id, text) end
    end
    return ""
  end
  function model.label(entry, ctx, source)
    if not entry.label then return source end
    local ok, text = pcall(entry.label, ctx)
    if ok then return text end
    model.warn("label/" .. entry.id, text)
    return source
  end
  function model.run(entry, ctx)
    local ok, result = pcall(entry.run, ctx)
    if not ok then model.warn("run/" .. entry.id, result); return false end
    return type(result) ~= "table" or result.close ~= false
  end
  return model
end

local default = M.new()
default.new = M.new
return default
