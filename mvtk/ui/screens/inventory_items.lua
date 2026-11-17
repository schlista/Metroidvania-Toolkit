-- Item data stays independent of GUI context; dependencies load only on use.
local M = {}

function M.display_name(id, items, types, title_case)
  local GrantSpec = require "mvtk.game.grant_spec"
  local KeyIds = require "mvtk.core.key_ids"
  return GrantSpec.item_name(id, {
    items = items, collectible_types = types, canonicalize = KeyIds.canonicalize,
  })
end

function M.new(deps)
  deps = deps or {}
  local provider = { display_name = M.display_name }
  local function inventory() return deps.inventory or require "mvtk.core.inventory" end
  function provider.title() return { key = "inventory.items" } end
  function provider.enabled() return true end
  function provider.header_right()
    return { currency = inventory().get_currency(), formatter = deps.currency_text }
  end
  function provider.rows(ctx)
    local items = deps.items or require "developer.config.items"
    local types = deps.collectible_types or require "developer.config.collectible_types"
    local util = deps.util or require "mvtk.core.util"
    local out = {}
    for id, count in pairs(inventory().all()) do
      if not ctx.registry.owns_item(id) then
        out[#out + 1] = { id = id, label = M.display_name(id, items, types, util.title_case_id),
          value = { forms = { one = "inventory.count_one", other = "inventory.count_other" }, count = count, params = { count = count } }, detail = items[id] and
            (items[id].quick_use and { key = "inventory.quick_hint" } or items[id].desc), state = "available" }
      end
    end
    table.sort(out, function(a, b)
      local an, bn = type(a.label) == "string" and a.label or "", type(b.label) == "string" and b.label or ""
      return an == bn and a.id < b.id or an < bn
    end)
    return out
  end
  function provider.on_confirm(ctx, row)
    local items = deps.items or require "developer.config.items"
    if row and items[row.id] and items[row.id].quick_use then
      (deps.healing or require "mvtk.player.healing").select(row.id)
      local name = M.display_name(row.id, items, deps.collectible_types or require "developer.config.collectible_types")
      return { status = { key = "inventory.quick_selected", params = { name = type(name) == "string" and { text = name } or name } }, refresh = true }
    end
    return {}
  end
  return provider
end

local default = M.new()
default.new = M.new
return default
