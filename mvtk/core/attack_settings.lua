-- Shared, engine-free attack field catalog and sparse override validation.
-- Authoring and runtime use the same paths, ranges and timeline rules.
local M = {}

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

local function merge(dst, src)
    for k, v in pairs(src or {}) do
        if type(v) == "table" then dst[k] = merge(copy(dst[k] or {}), v)
        else dst[k] = v end
    end
    return dst
end

local function get(value, path)
    for part in path:gmatch("[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[tonumber(part) or part]
    end
    return value
end

-- Optional directional projectile values only get controls when authored:
-- their absence selects dynamic aim/knockback, which has no numeric default.
local projectile_numbers = {
    damage = {"Damage", 0, 1000, 0.25},
    speed = {"Speed (px/s)", 0, 10000, 10},
    lifetime = {"Lifetime (seconds)", 0.01, 3600, 0.01},
    stun_t = {"Stun (seconds)", 0, 60, 0.01},
    kx = {"Knockback X (px/s)", -10000, 10000, 1},
    ky = {"Knockback Y (px/s)", -10000, 10000, 1},
    dir_x = {"Direction X", -1, 1, 0.1},
    dir_y = {"Direction Y", -1, 1, 0.1},
}

function M.catalog(config, damage_types)
    local fields, sections, ids = {}, {}, {}
    for id in pairs(config.attacks or {}) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local x, y = config.attacks[a].settings_order or math.huge, config.attacks[b].settings_order or math.huge
        return x == y and a < b or x < y
    end)
    local choices, labels, allowed = {}, {}, {}
    for id, entry in pairs(damage_types.types) do
        choices[#choices + 1], labels[id], allowed[id] = id, entry.label, true
    end
    table.sort(choices)
    for _, id in ipairs(ids) do
        local attack = config.attacks[id]
        local section = { id=id, title=attack.label or id, fields={} }
        sections[#sections + 1] = section
        local function add(path, title, default, min, max, step)
            local key = "attack_" .. id .. "_" .. path:gsub("%.", "_")
            fields[key] = {key=key, path="combat.attacks." .. id .. "." .. path,
                attack_id=id, attack_path=path, title=title, default=default,
                type="number", min=min, max=max, step=step, units=title:match("%(([^)]+)%)$") or "",
                help=section.title .. ": " .. title .. ". Overrides this attack only; takes precedence over Combat quick fields."}
            section.fields[#section.fields + 1] = key
            return fields[key]
        end
        add("cooldown", "Cooldown (seconds)", attack.cooldown or 0, 0, 60, 0.01)
        add("energy_cost", "Energy cost", attack.energy_cost or 0, 0, 10000, 0.25)
        local timeline = attack.timeline or {}
        add("timeline.startup", "Startup (seconds)", timeline.startup or 0, 0, 60, 0.01)
        add("timeline.recovery", "Recovery (seconds)", timeline.recovery or 0, 0, 60, 0.01)
        for wi, window in ipairs(timeline.active_windows or {}) do
            local path, prefix = "timeline.active_windows." .. wi, "Window " .. wi .. " "
            add(path .. ".start", prefix .. "start (seconds)", window.start, 0, 60, 0.01)
            add(path .. ".duration", prefix .. "duration (seconds)", window.duration, 0.001, 60, 0.01)
            for hi, hitbox in ipairs(window.hitboxes or {}) do
                for _, row in ipairs({{"damage", "damage", 0, 1000, 0.25},
                    {"width", "width (px)", 1, 10000, 1}, {"height", "height (px)", 1, 10000, 1},
                    {"knockback", "knockback (px/s)", 0, 10000, 1}}) do
                    add(path .. ".hitboxes." .. hi .. "." .. row[1],
                        prefix .. "hitbox " .. hi .. " " .. row[2], hitbox[row[1]] or 0, row[3], row[4], row[5])
                end
            end
            for _, name in ipairs({"damage", "speed", "lifetime", "stun_t", "kx", "ky", "dir_x", "dir_y"}) do
                local value = (window.projectile or {})[name]
                if type(value) == "number" then
                    local row = projectile_numbers[name]
                    add(path .. ".projectile." .. name, prefix .. "projectile " .. row[1]:gsub("^%u", string.lower),
                        value, row[2], row[3], row[4])
                end
            end
            for _, axis in ipairs({"x", "y"}) do
                local value = ((window.projectile or {}).offset or {})[axis]
                if type(value) == "number" then
                    add(path .. ".projectile.offset." .. axis, prefix .. "projectile muzzle " .. axis:upper() .. " (px)",
                        value, -10000, 10000, 1)
                end
            end
        end
        local spec = add("damage_type", "Damage type", attack.damage_type
            or damage_types.player_attacks[attack.weapon_class] or "physical")
        spec.type, spec.choices, spec.choice_labels, spec.values = "string", choices, labels, allowed
    end
    return fields, sections
end

function M.timeline_issue(attack)
    local timeline = attack.timeline or {}
    local finish = timeline.startup or 0
    if finish < 0 or (timeline.recovery or 0) < 0 then return "Startup and recovery must not be negative." end
    for wi, window in ipairs(timeline.active_windows or {}) do
        if window.start < 0 or window.duration <= 0 then return "Window " .. wi .. " must have a non-negative start and positive duration." end
        if window.start + 1e-9 < finish then
            return "Window " .. wi .. " starts before startup ends or overlaps the previous active window."
        end
        finish = window.start + window.duration
    end
end

function M.resolve(config, overrides, damage_types)
    assert(overrides == nil or type(overrides) == "table", "Attack overrides must be a table.")
    local fields = M.catalog(config, damage_types)
    local known = {}
    for _, spec in pairs(fields) do
        known[spec.attack_id .. "." .. spec.attack_path] = spec
    end
    local function check(value, path)
        local spec = known[path]
        if spec then
            assert(type(value) == spec.type, path .. " must be a " .. spec.type)
            if spec.type == "number" then
                assert(value == value and value >= spec.min and value <= spec.max, path .. " is outside its supported range")
            else assert(spec.values[value], path .. " has an unsupported damage type") end
        else
            assert(type(value) == "table", "Unknown attack override: " .. path)
            for key, child in pairs(value) do check(child, path == "" and tostring(key) or path .. "." .. tostring(key)) end
        end
    end
    check(overrides or {}, "")
    local attacks = merge(copy(config.attacks or {}), overrides)
    for id in pairs(overrides or {}) do
        assert(config.attacks[id], "Unknown attack: " .. tostring(id))
        local issue = M.timeline_issue(attacks[id])
        assert(not issue, (attacks[id].label or id) .. ": " .. tostring(issue))
    end
    return attacks
end

return M
