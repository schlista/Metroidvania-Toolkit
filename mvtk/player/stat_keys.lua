-- Pure registry shared by runtime sources and creator effect validators.
-- Add a key only alongside its read site. Consumer schemas declare these floors.
local M = {}
local layers = { permanent = true, equipment = true, temporary = true, assist = true }
M.LAYERS = layers
M.KEYS = {
    max_health = { kind = "add", layers = layers, supported = true, description = "Additional health capacity." },
    max_energy = { kind = "add", layers = layers, supported = true, description = "Additional energy capacity." },
    max_stamina = { kind = "add", layers = layers, supported = true, description = "Additional stamina capacity." },
    currency_mult = { kind = "mult", min = 0, max = 10, layers = layers, supported = true, description = "Currency pickup amount." },
    xp_mult = { kind = "mult", min = 0, max = 10, layers = layers, supported = true, description = "XP awarded by event sources." },
    speed_mult = { kind = "mult", min = 0.25, max = 3, layers = layers, supported = true, description = "Walk and run target speed." },
    ground_accel_mult = { kind = "mult", min = 0.01, max = 4, layers = layers, supported = true, description = "Ground acceleration." },
    ground_decel_mult = { kind = "mult", min = 0, max = 4, layers = layers, supported = true, description = "Ground deceleration." },
    ground_turn_mult = { kind = "mult", min = 0, max = 4, layers = layers, supported = true, description = "Ground turn braking." },
    jump_mult = { kind = "mult", min = 0.25, max = 3, layers = layers, supported = true, description = "Ordinary ground, buffered and air jump velocity." },
    max_fall_mult = { kind = "mult", min = 0.01, max = 3, layers = layers, supported = true, description = "Global terminal fall speed; swim/glide caps retain their own settings." },
    gravity_mult = { kind = "mult", min = 0.1, max = 3, layers = layers, supported = true, description = "Movement gravity." },
    damage_mult = { kind = "mult", min = 0, max = 10, layers = layers, supported = true, description = "Outgoing player damage." },
    damage_taken_mult = { kind = "mult", min = 0.1, max = 10, sub = true, layers = layers, supported = true, description = "Incoming player damage; resistance cannot grant immunity." },
    invulnerable = { kind = "flag", layers = layers, supported = true, description = "Blocks ordinary hits; lethal hits bypass this flag." },
}

function M.definition(key)
    if type(key) ~= "string" then return nil end
    local base, sub = key:match("^([^:]+):(.+)$")
    local def = M.KEYS[base or key]
    if sub and (not def or not def.sub) then return nil end
    return def
end

function M.effect_error(key, value, layer, opts)
    local def = M.definition(key)
    if not def then return "unknown key: " .. tostring(key) end
    if def.supported == false then return "unsupported key: " .. key end
    if layer and (not layers[layer] or (def.layers and not def.layers[layer])) then
        return "key restricted to another layer: " .. key
    end
    if def.kind == "flag" then
        if type(value) ~= "boolean" then return "expected boolean: " .. key end
    elseif type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
        return "expected finite number: " .. key
    elseif opts and opts.composed == true and def.kind == "mult" then
        -- Owners combine individually validated effects before the final read clamp.
        if value < 0 then return "value out of range: " .. key end
    elseif (def.min and value < def.min) or (def.max and value > def.max) then
        return "value out of range: " .. key
    end
end

function M.validate_effects(effects, opts)
    local errors, warnings = {}, {}
    if type(effects) ~= "table" then return { "effects must be a table" }, warnings end
    for key, value in pairs(effects) do
        local err = M.effect_error(key, value, opts and opts.layer)
        if err then errors[#errors + 1] = err end
    end
    table.sort(errors)
    return errors, warnings
end

return M
