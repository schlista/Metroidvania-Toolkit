-- Runtime actor wiring. The pure rules stay in elements.lua; damage still
-- scales only in DamageCalc. Lazy branch requires keep enemy callback budgets.
local Elements = require "mvtk.combat.elements"
local RuntimeSettings = require "developer.config.runtime_settings"
local M = {}

local function config()
    return RuntimeSettings.section("damage_types", require "developer.config.damage_types")
end

-- Status immunity is additive across preset and placement. Authored ids remain
-- text; configs may also supply arrays or sets.
local function add_status_immunity(out, values)
    if type(values) == "string" then
        for id in values:gmatch("[^,;]+") do
            id = id:match("^%s*(.-)%s*$")
            if id ~= "" and id ~= "none" then out[id] = true end
        end
    elseif type(values) == "table" then
        for key, value in pairs(values) do
            local id = type(key) == "number" and value or (value == true and key)
            if id then out[id] = true end
        end
    end
end

function M.configure(actor, preset, instance)
    actor._elements = Elements.profile(preset, instance, config())
    actor._status_immune = {}
    add_status_immunity(actor._status_immune, preset and preset.status_immune)
    add_status_immunity(actor._status_immune, instance and instance.status_immune)
    local status = instance and instance.status_on_hit
    if not status or status == "" or status == "none" then status = preset and preset.status_on_hit end
    local chance = instance and tonumber(instance.status_chance)
    local preset_status = preset and preset.status_on_hit
    actor._status_on_hit = type(status) == "table" and status.id or status
    actor._status_chance = chance and chance >= 0 and chance
        or (type(preset_status) == "table" and preset_status.chance) or 1
    local dtype = instance and instance.damage_type
    if dtype == nil or dtype == "" or dtype == "none" then dtype = preset and preset.damage_type end
    actor._attack_damage_type = dtype ~= "" and dtype ~= "none" and dtype or nil
end

-- Producers pass source text. Gamefeel controls number visibility, and the
-- displaying label resolves translation. Immune sound/flash ignore that toggle.
-- Optional source/overrides identify confirmed player hits across both damage
-- owners. Guard sparks omit source so their impact is never doubled here.
function M.feedback(amount, position, dtype, verdict, anim_url, numbers, go_url, source, overrides)
    local cfg = config().feedback
    -- Manager positions are spawn anchors. Both particles and numbers follow
    -- the live actor, even when a weak point owns the number display.
    if go_url and (numbers or source) then
        local ok, current = pcall(function()
            go.update_world_transform(go_url)
            return go.get_world_position(go_url)
        end)
        if ok and current then position = current end
    end
    if amount > 0 and verdict ~= "immune" and type(source) == "table"
        and not source.damage_over_time and source.source_attack ~= "parry_stun"
        and require("mvtk.combat.damage_payload").source_is(source, require("mvtk.core.constants").URL.PLAYER) then
        local feedback = require("mvtk.combat.config").get().feedback or {}
        local effect = feedback.hit_effect
        if overrides and overrides.hit_effect ~= nil then effect = overrides.hit_effect end
        require("mvtk.fx.fx").play(effect, source.hit_position or position)
    end
    if verdict == "immune" then
        if cfg.immune_sfx ~= "" then require("mvtk.audio.audio").sfx(cfg.immune_sfx) end
    end
    if anim_url and (verdict == "immune" or verdict == "weak") then
        local color = verdict == "immune" and cfg.immune_color or cfg.weak_color
        local duration = verdict == "immune" and cfg.immune_flash or cfg.weak_flash
        if duration > 0 then
            pcall(msg.post, anim_url, "anim.flash", {
                color = vmath.vector4(color[1], color[2], color[3], 1), duration = duration,
            })
        end
    end
    if numbers then
        local ok, feel = pcall(require, "mvtk.core.gamefeel")
        if ok and feel.damage_number then
            pcall(feel.damage_number, amount, position, {dtype=dtype, verdict=verdict,
                label=verdict == "immune" and cfg.immune_label or "", target="enemy"})
        end
    end
end

return M
