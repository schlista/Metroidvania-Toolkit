-- Require-free at load time: providers also run under isolated loaders.
-- Keep source text and plural descriptions intact until the displaying GUI.
local M = {}
function M.new(deps)
    deps = deps or {}
    local provider = {}
    local function charms() return deps.charms or require "mvtk.player.charms" end
    function provider.title() return {key="inventory.charms"} end
    function provider.enabled() return charms().enabled() end
    function provider.header_right()
        local state = charms()
        return {key="charms.slots", params={used=state.used_slots(), total=state.capacity()}}
    end
    function provider.owns_item(id)
        if not provider.enabled() then return false end
        local cfg = charms().settings()
        if id == cfg.slot_item then return true end
        for _, entry in ipairs(cfg.charms or {}) do
            if id == "charm_" .. entry.id then return true end
        end
        return false
    end
    function provider.rows()
        local state, out = charms(), {}
        if not state.enabled() then return out end
        local free = state.capacity() - state.used_slots()
        for _, entry in ipairs(state.settings().charms or {}) do
            if state.owns(entry.id) then
                local equipped = state.is_equipped(entry.id)
                local row = {id=entry.id, label={text=entry.name}, detail={text=entry.description or ""},
                    icon={texture="gameplay_visuals", anim=entry.icon_animation or "prop_base"},
                    value={forms={one="charms.cost_one", other="charms.cost_other"},
                        count=entry.cost, params={count=entry.cost}},
                    cost=equipped and {key="charms.equipped"} or nil,
                    state=equipped and "equipped" or "available"}
                if not equipped and entry.cost > free then
                    row.enabled, row.state = false, "locked"
                    row.disabled_reason = {key="charms.no_room"}
                end
                out[#out + 1] = row
            end
        end
        return out
    end
    function provider.on_confirm(ctx, row)
        local state = charms()
        if not row or not state.enabled() then return {} end
        local changed
        if state.is_equipped(row.id) then changed = state.unequip(row.id)
        else changed = state.equip(row.id) end
        if changed then return {refresh=true} end
        return {}
    end
    return provider
end
local default = M.new()
default.new = M.new
return default
