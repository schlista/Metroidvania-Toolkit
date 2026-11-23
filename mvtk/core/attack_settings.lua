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

-- Legacy shipped recoveries for projects that saved startup or a hit window
-- while leaving recovery inherited. Zero recovery today cannot recover the
-- old number when the old hit window swallowed it.
local legacy_recovery = {
    air_launcher=0.16, air_light_1=0.12, air_up_light=0.14, charged_slash=0.22,
    counter_attack=0.16, down_strike=0.12, heavy_1=0.24, light_1=0.14,
    light_2=0.15, light_3=0.18, mixed_finisher_1=0.20, mixed_finisher_2=0.22,
    ranged_shot=0.12, up_light=0.14,
}

function M.recovery_start(timeline)
    local finish = tonumber(timeline.startup) or 0
    for _, window in ipairs(timeline.active_windows or {}) do
        finish = math.max(finish, (tonumber(window.start) or 0) + (tonumber(window.duration) or 0))
    end
    return finish
end

function M.combo_start(window, finish, recovery)
    return tonumber(window.start) or finish - math.max(0.08, tonumber(recovery) or 0)
end

local function timing_override(timeline)
    if timeline.startup ~= nil or timeline.recovery ~= nil then return true end
    for _, window in pairs(timeline.active_windows or {}) do
        if window.start ~= nil or window.duration ~= nil then return true end
    end
    return false
end

-- Return the sparse values to replace so load preserves all unrelated overrides.
function M.recovery_migration(config, authored, saved)
    local converted = {}
    for id, attack in pairs(saved or {}) do
        local override = attack.timeline
        if override and timing_override(override) then
            local baseline = config.attacks[id]
            local authored_timeline = ((authored or {})[id] or {}).timeline
            local old_recovery = override.recovery
            if old_recovery == nil and not (authored_timeline and authored_timeline.recovery ~= nil) then
                old_recovery = legacy_recovery[id]
            end
            if old_recovery ~= nil then
                local timeline = merge(copy(baseline.timeline or {}), override)
                local startup, active_end = timeline.startup or 0, M.recovery_start(timeline)
                -- Match the old addition before subtracting. Reassociating
                -- the three numbers can miss an exact reference-frame edge.
                local old_finish = math.max(startup + old_recovery, active_end)
                local recovery = active_end == startup and old_recovery
                    or math.min(old_recovery, old_finish - active_end)
                local row = { recovery = recovery }
                local combo = baseline.combo_window or {}
                if next(baseline.combo_links or {}) and combo.start == nil and get(attack, "combo_window.start") == nil then
                    local old_start = M.combo_start(combo, old_finish, old_recovery)
                    local new_start = M.combo_start(combo, active_end + recovery, recovery)
                    if old_start ~= new_start then row.combo_start = old_start end
                end
                converted[id] = row
            end
        end
    end
    return converted
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
        add("timeline.recovery", "Post-hit recovery (seconds)", timeline.recovery or 0, 0, 60, 0.01).help =
            "Seconds to wait after the last hit window closes, or after startup if this attack has no hit windows. Zero ends the attack immediately at that point."
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
    -- Migration can pin a formerly implicit combo start. A lead longer than
    -- the attack can make that start negative, which means immediately open.
    local combo_start = { type = "number", min = -math.huge, max = math.huge }
    for id in pairs(config.attacks or {}) do
        known[id .. ".combo_window.start"] = combo_start
    end
    local function check(value, path)
        local spec = known[path]
        if spec then
            assert(type(value) == spec.type, path .. " must be a " .. spec.type)
            if spec.type == "number" then
                assert(math.abs(value) < math.huge and value >= spec.min and value <= spec.max,
                    path .. " is outside its supported range")
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
