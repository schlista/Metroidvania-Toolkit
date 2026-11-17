-- Pure settings row model. The caller supplies creator visibility and the settings store.
-- The menu only paints a page; descriptors share eight pooled row triples.
local Config = require "developer.config.accessibility"
local M = { PAGE_SIZE = 8 }

local function effect(id, label_key, values)
    local keys = {}
    for i, value in ipairs(values) do keys[i] = "settings.acc." .. value end
    return {
        id = id, kind = "cycle", label_key = label_key, values = values, value_keys = keys,
        visible = function(view) return (view.show or {})[id] ~= false end,
        get = function(settings)
            return settings.get("accessibility." .. id) or settings.get_defaults().accessibility[id]
        end,
        set = function(settings, value) return settings.set_accessibility(id, value) end,
    }
end

local function hold(id)
    return {
        id = id, kind = "toggle", label_key = "settings.acc.toggle_" .. id,
        values = { false, true }, value_keys = { "settings.acc.off", "settings.acc.on" },
        visible = function(view)
            return (view.show or {}).toggles ~= false and require("mvtk.player.hold_toggles").available(id)
        end,
        get = function(settings) return settings.get("accessibility.toggles." .. id) == true end,
        set = function(settings, value) return settings.set_accessibility("toggles." .. id, value) end,
    }
end

local function assist(id, values)
    local keys, params = {}, {}
    for i, value in ipairs(values) do
        keys[i] = type(value) == "boolean" and (value and "settings.acc.on" or "settings.acc.off")
            or "settings.acc.percent"
        params[i] = { percent = math.floor((tonumber(value) or 0) * 100 + 0.5) }
    end
    return {
        id = id, kind = id == "pit_rescue" and "toggle" or "cycle",
        label_key = "settings.acc." .. id, values = values, value_keys = keys, value_params = params,
        visible = function(view) return (view.assist or {}).allowed ~= false end,
        get = function(settings)
            local value = settings.get("accessibility.assist." .. id)
            if id == "pit_rescue" then return value == true end
            -- A saved choice may have left the creator's list. Show and cycle
            -- from the same nearest choice gameplay uses, without rewriting it.
            value = tonumber(value) or 1
            local nearest, distance = 1, math.huge
            for _, candidate in ipairs(values) do
                local delta = math.abs(candidate - value)
                if delta < distance then nearest, distance = candidate, delta end
            end
            return nearest
        end,
        set = function(settings, value) return settings.set_accessibility("assist." .. id, value) end,
    }
end

local function text_size(values)
    local row = effect("text_size", "settings.acc.text_size", values)
    row.value_keys, row.value_params = {}, {}
    for i, value in ipairs(values) do
        row.value_keys[i] = "settings.acc.text_size_value"
        row.value_params[i] = { percent = math.floor(value * 100 + 0.5) }
    end
    return row
end

local function caption(id, values, keys)
    return {
        id = id == "enabled" and "captions" or "caption_background",
        kind = id == "enabled" and "toggle" or "cycle",
        label_key = id == "enabled" and "settings.acc.captions" or "settings.acc.caption_background",
        values = values, value_keys = keys,
        visible = function(view) return (view.captions or {}).show_options ~= false end,
        get = function(settings)
            local value = settings.get("accessibility.captions." .. id)
            if value ~= nil then return value end
            return settings.get_defaults().accessibility.captions[id]
        end,
        set = function(settings, value) return settings.set_accessibility("captions." .. id, value) end,
    }
end

function M.accessibility(cfg)
    cfg = cfg or Config
    return {
        text_size(cfg.text_sizes),
        effect("shake", "settings.acc.shake", { "auto", "full", "reduced", "off" }),
        effect("flashes", "settings.acc.flashes", { "full", "reduced", "off" }),
        effect("freeze_frames", "settings.acc.freeze", { "full", "reduced", "off" }),
        {
            id = "vibration", kind = "toggle", label_key = "settings.acc.vibration",
            values = { true, false }, value_keys = { "settings.acc.on", "settings.acc.off" },
            visible = function(view) return (view.show or {}).vibration ~= false end,
            get = function(settings) return settings.get("gameplay.rumble") ~= false end,
            set = function(settings, value)
                settings.set("gameplay.rumble", value)
                settings.apply_gamefeel()
                return settings.save()
            end,
        },
        caption("enabled", { true, false }, { "settings.acc.on", "settings.acc.off" }),
        caption("background", { "off", "dim", "solid" }, { "settings.acc.off", "settings.acc.dim", "settings.acc.solid" }),
        hold("grab"),
        hold("grapple"),
        hold("heal"),
        hold("run"),
        hold("glide"),
        hold("aim"),
        assist("damage_taken", cfg.assist.damage_taken),
        assist("game_speed", cfg.assist.game_speed),
        assist("pit_rescue", { true, false }),
    }
end

function M.visible(rows, view)
    local result = {}
    for _, row in ipairs(rows) do
        if row.visible(view) then result[#result + 1] = row end
    end
    return result
end

function M.page(rows, page)
    local count = math.max(1, math.ceil(#rows / M.PAGE_SIZE))
    page = math.max(1, math.min(count, page or 1))
    local result = {}
    for i = (page - 1) * M.PAGE_SIZE + 1, math.min(page * M.PAGE_SIZE, #rows) do
        result[#result + 1] = rows[i]
    end
    return result, page, count
end

function M.value_index(row, settings)
    local current = row.get(settings)
    for i, value in ipairs(row.values) do if value == current then return i end end
    return 1
end

function M.cycle(row, settings, direction)
    local index = (M.value_index(row, settings) - 1 + (direction or 1)) % #row.values + 1
    return row.set(settings, row.values[index])
end

function M.reset(settings)
    -- Vibration shares the tab, but its established save path remains in gameplay.
    settings.set("gameplay.rumble", settings.get_defaults().gameplay.rumble ~= false)
    return settings.reset_to_defaults("accessibility") -- Re-applies all settings and saves once.
end

return M
