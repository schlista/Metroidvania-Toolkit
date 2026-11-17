-- Require-free at load time: menu providers also run under isolated loaders.
local M = {}
function M.new(deps)
    deps = deps or {}
    local provider = {}
    local function weapons() return deps.weapons or require "mvtk.combat.weapon_state" end
    function provider.title() return {key="inventory.weapons"} end
    function provider.enabled() return weapons().enabled() end
    function provider.owns_item(id)
        if not provider.enabled() then return false end
        for _, entry in ipairs(weapons().settings().weapons or {}) do
            if id == "weapon_" .. entry.id then return true end
        end
        return false
    end
    function provider.rows()
        local state, out = weapons(), {}
        local current = state.current()
        for _, entry in ipairs(state.settings().weapons or {}) do
            if state.owns(entry.id) then
                local equipped = current and current.id == entry.id
                local row = {id=entry.id, label={text=entry.name}, detail={text=entry.description or ""},
                    icon={texture="gameplay_visuals", anim=entry.icon_animation or "prop_base"},
                    value=equipped and {key="weapons.equipped"} or nil,
                    state=equipped and "equipped" or "available"}
                local tier = state.tier and state.tier(entry.id) or 1
                if tier > 1 then
                    local tier_text = {key="grants.weapon_tier",params={name={text=entry.name},tier=tier}}
                    row.value = equipped and {parts={row.value,tier_text},separator=" / "} or tier_text
                    local definition = (entry.tiers or {})[tier-1]
                    if definition and definition.name then
                        row.detail = {parts={row.detail,{text=definition.name}},separator="\n"}
                    end
                end
                local ability = entry.requires_ability
                if ability and ability ~= "" then
                    local manager = deps.ability or require "mvtk.abilities.ability_manager"
                    if not manager.is_ability_unlocked(ability) then
                        local config = manager.get_ability_info(ability)
                        row.disabled_reason = {key="weapons.requires", params={name=config and config.name and {text=config.name} or {key="list.missing_name"}}}
                        row.enabled, row.state = false, "locked"
                    end
                end
                out[#out + 1] = row
            end
        end
        if #out == 0 then out[1] = {id="none", label={key="weapons.none"}, selectable=false} end
        return out
    end
    function provider.on_confirm(ctx, row)
        if row and row.id ~= "none" and weapons().equip(row.id) then
            local entry = weapons().current()
            return {refresh=true, status={key="weapons.equipped_status", params={name={text=entry.name}}}}
        end
        return {}
    end
    return provider
end
local default = M.new()
default.new = M.new
return default
