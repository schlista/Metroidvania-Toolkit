-- Read-only translation inventory. No engine/editor calls, writes or cached configs.
local Source = require "developer.tools.project_source"
local FreshConfig = require "mvtk.editor.fresh_config"
local World = require "developer.tools.world_manifest"
local Objects = require "hooks.core.tiled_objects"
local Properties = require "mvtk.tiled.property_flattener"
local TextFields = require "mvtk.tiled.text_fields"
local Util = require "mvtk.core.util"
local Dialogue = require "mvtk.dialogue.dialogue_registry"
local M = {}

-- Exact paths; * consumes one table key (including an array index).
-- Register creator fields here when adding content; the config census checks it.
M.config_fields = {
    ["steam_settings"]={"rich_presence.title", "rich_presence.playing", "rich_presence.region"},
    ["powerups"]={"powerups.*.name"},
    ["charms"]={"charms.*.name","charms.*.description"},
    ["weapons"]={"weapons.*.name","weapons.*.description","weapons.*.tiers.*.name"},
    ["completion_tracking"]={"categories.*.label"},
    ["trial_settings"]={"ranks.*.name"},
    ["crafting"]={"recipes.*.name","recipes.*.description"},
    ["quests"]={"quests.*.title","quests.*.description","quests.*.steps.*.text","quests.*.giver","categories.*.name"},
    ["goals"]={"goals.*.title","goals.*.text","goals.*.hint"},
    ["countdowns"]={"countdowns.*.label"},
    ["npc_settings"]={"markers.new_text","markers.task_text"},
    ["achievements"]={"achievements.*.name","achievements.*.description","categories.*.name"},
    ["extras"]={"jukebox.tracks.*.title","gallery.entries.*.title","gallery.entries.*.caption"},
    ["shops"]={"catalogs.*.name", "catalogs.*.entries.*.name", "catalogs.*.entries.*.description", "catalogs.*.entries.*.locked_text"},
    ["upgrades"]={"upgrades.*.name", "upgrades.*.description"},
    ["bestiary"]={"unknown_text","entries.*.name","entries.*.description","categories.*.label","bosses.*.name","bosses.*.description"},
    ["fragments"]={"sets.*.name", "sets.*.progress_text", "sets.*.complete_text"},
    ["status_effects"]={"effects.*.label"},
    ["damage_types"]={"types.*.label", "feedback.immune_label"},
    ["abilities"]={"abilities.*.name", "abilities.*.description", "abilities.*.hud_short"},
    ["collectible_types"]={"*.name", "*.description", "*.notification", "*.popup_title", "*.popup_description", "*.lore_text", "*.area_name"},
    ["items"]={"*.name", "*.desc"},
    ["npc_types"]={"*.name","*.barks.*","*.journal.title","*.journal.bio"},
    ["gate_types"]={"*.interaction.proximity_hint"},
    ["secret_types"]={"*.name", "*.description", "secret_area_trigger.notification_text", "settings.completion_notification"},
    ["hazard_types"]={"*.name"},
    ["tutorial_popups"]={"popups.*.title", "popups.*.body"},
    ["game_completion"]={"title", "body", "credits", "endings.*.title", "endings.*.body", "endings.*.credits"},
    ["boss_types"]={"*.name", "*.description"},
    ["biomes"]={"*.name", "*.subtitle"},
    ["narrative/dialogues"]={"*.*.speaker", "*.*.text", "*.*.choices.*.text"},
    ["narrative/dialogues_authored"]={"*.*.speaker", "*.*.text", "*.*.choices.*.text"},
    ["difficulty_settings"]={"profiles.*.label", "profiles.*.description"},
    ["reward_text"]={"xp_format", "count_format", "fast_travel_format", "separator"},
    ["menu_settings"]={"controller_disconnect_text", "books.*.title"},
    ["healing"]={"heal_name"},
    ["narrative/cutscene_settings"]={"skip_hint"},
    ["sound_bank"]={"sfx.*.caption"},
    ["narrative/videos"]={"*.fallback_title", "*.fallback_caption"},
    ["narrative/cutscenes"]={"*.*.text", "*.*.speaker", "*.steps.*.text", "*.steps.*.speaker"},
    ["player_settings"]={"launch.cannon_prompt"},
    ["default_bindings"]={"remappable.*.label"},
    ["hud_layout"]={"menu_button.label", "currency.format", "health_bar.text_format", "quick_item.separator"},
    ["map_markers"]={"*.*.label"},
    ["map_icons"]={"kinds.*.label","icons.*.label"},
    ["world_map_settings"]={"stamps.icons.*.glyph","stamps.icons.*.label"},
    ["room_collectibles"]={"*.*.config.relic_name", "*.*.config.description"},
}

local function matches(path, pattern)
    local escaped = pattern:gsub("([%.%-%+%?%[%]%(%)%^%$%%])", "%%%1"):gsub("%*", "[^.]+")
    return path:match("^" .. escaped .. "$") ~= nil
end

-- Used by the census too. Paths are config-relative (e.g. items.lua).
function M.config_field(file, path)
    file = file:gsub("^developer/config/", ""):gsub("%.lua$", "")
    for _, pattern in ipairs(M.config_fields[file] or {}) do
        if matches(path, pattern) then return true end
    end
    return file == "ui_text"
end

local function keys(value)
    local out = {}
    for key in pairs(value) do out[#out+1] = key end
    table.sort(out, function(a,b) return tostring(a) < tostring(b) end)
    return out
end

local function walk(value, path, visit)
    if type(value) ~= "table" then visit(path, value); return end
    for _, key in ipairs(keys(value)) do
        walk(value[key], path == "" and tostring(key) or path .. "." .. tostring(key), visit)
    end
end

-- Recursion adds deeper classes without changing the baker's one-level helper.
-- At each level it still decides legacy flat/grouped-default collisions.
local function flatten(properties)
    local flat = Properties.flatten(properties)
    local out = {}
    for _, name in ipairs(keys(flat)) do
        local value = Properties.unwrap(flat[name])
        if type(value) ~= "table" then out[name] = value end
    end
    for _, name in ipairs(keys(flat)) do
        local value = Properties.unwrap(flat[name])
        if type(value) == "table" then
            for field, child in pairs(flatten(value)) do out[field] = child end
        end
    end
    return out
end

-- Match the keys that baked objects actually hand to the displaying GUI.
-- Sign re-reads raw authored properties in init; these other families also keep
-- raw sources. Most baked captions use PU's existing text normalizer instead.
-- Compatibility runtime-spawner overlays are not the baked-room display path.
local raw_tiled = {boss_arena=true, sign=true, warp_statue=true, breakable_prop=true, zip_line=true, carryable=true}
local function add_tiled(kind, field, text, where, add)
    if type(text) ~= "string" then return end
    if kind == "enemy" and field == "champion_name" then
        if text:match("%S") then add(text, where) end
        return
    end
    if raw_tiled[kind] then add(text, where); return end
    -- Barks are |-separated lines; npc_living shows each trimmed line.
    if kind == "npc" and field == "barks" then
        for line in (text .. "|"):gmatch("([^|]*)|") do
            line = Util.trim(line)
            if line ~= "" then add(line, where) end
        end
        return
    end
    if kind == "npc" and field == "dialogue_text" then
        local normalized = Util.normalize_hash_string(text)
        if normalized then
            for i, line in ipairs(Dialogue.build_sequence_from_text(normalized)) do
                add(line.text, where .. "[box=" .. tostring(i) .. "]")
            end
        end
        return
    end
    -- Census-backed travel lists use raw authored wording for unloaded rooms;
    -- registration of a live station uses normalized names/descriptions.
    if (kind == "fast_travel" and (field == "station_name" or field == "station_description" or field == "name"))
        or (kind == "save_point" and field == "display_name") then add(text, where) end
    if kind == "boss" or kind == "elevator_node" then
        add(Util.trim(text), where)
    elseif kind == "map_marker" then
        add(Util.resolve_id(text), where)
    else
        add(Util.normalize_hash_string(text), where)
    end
end

-- collect(opts) -> sorted array of {kind="source", source=..., where={...}} or
-- {kind="ui", key=..., source=<English>, where={...}}. Exact source duplicates
-- merge; UI keys remain separate even when their English values are identical.
-- where is a sorted, unique list of config field / room-layer-object references.
-- opts.root defaults to "."; opts.read(path) may replace disk reads for tests.
-- opts.world_manifest or opts.layout can supply a preparation candidate. A selected
-- Tiled world wins over layout; otherwise read world_layout.local.lua then the
-- shipped world_layout.lua. Missing/invalid required data returns nil, diagnostic.
-- Blank strings and generated configs are excluded. Raw paths preserve whitespace;
-- baked Tiled captions mirror their existing runtime lookup normalization.
function M.collect(opts)
    opts = opts or {}
    local root, read = opts.root or ".", opts.read or Source.read
    local fresh = FreshConfig.new({root=root, read=read})
    local entries, by_id = {}, {}
    local function add(source, where, key)
        if type(source) ~= "string" or source == "" then return end
        local id = (key and "ui:" .. key or "source:" .. source)
        local entry = by_id[id]
        if not entry then
            entry = {kind=key and "ui" or "source", source=source, key=key, where={}}
            by_id[id] = entry; entries[#entries+1] = entry
        end
        for _, previous in ipairs(entry.where) do if previous == where then return end end
        entry.where[#entry.where+1] = where
    end
    local function load(path, optional)
        local text = read(root .. "/" .. path)
        if text == nil and optional then return {} end
        local value, err = Source.load_table(text, path)
        if not value then error(err) end
        return value
    end
    local function config(file)
        local path = "developer/config/" .. file .. ".lua"
        -- Files absent from smaller projects are optional; malformed files are not.
        if read(root .. "/" .. path) == nil then return end
        local value, err = fresh.load_path(path)
        if not value then error(err) end
        walk(value, "", function(field, text)
            if M.config_field(file, field) then add(text, path .. ":" .. field, file == "ui_text" and field or nil) end
            -- Boss manager trims its resolved display name before the HUD sees it.
            -- Retain the registered exact config source as well as that lookup key.
            if file == "boss_types" and field:match("^[^.]+%.name$") and type(text) == "string" then
                add(Util.trim(text), path .. ":" .. field)
            end
        end)
    end
    local function run()
        for _, file in ipairs(keys(M.config_fields)) do config(file) end
        config("ui_text")
        -- Game Settings stores authored wording here rather than rewriting baselines.
        local creator = load("developer/config/creator_settings.lua", true)
        if creator.published then
            for section, value in pairs(creator.overrides or {}) do
                local file = section == "player" and "player_settings" or section
                walk(value, "", function(field, text)
                    if M.config_field(file, field) then add(text, "developer/config/creator_settings.lua:overrides." .. section .. "." .. field) end
                end)
            end
        end
        local manifest, tiled = opts.world_manifest, opts.world_manifest ~= nil
        if not manifest then manifest, tiled = World.selected_manifest({root=root,read=read}) end
        if tiled and not manifest then error("Selected Tiled world manifest is missing or invalid") end
        local rooms
        if manifest then rooms = manifest.maps
        else
            local layout = opts.layout
            if not layout then
                local path = "developer/runtime/layout/world_layout.local.lua"
                if read(root .. "/" .. path) == nil then path = "developer/runtime/layout/world_layout.lua" end
                layout = load(path)
            end
            rooms = layout.rooms
        end
        assert(type(rooms) == "table", "Published room list is missing")
        -- Use the authored type census without loading runtime spawner modules.
        -- The resolver needs this set for its final blank-type name fallback.
        local known_types = {}
        for _, template in pairs(TextFields.templates) do known_types[template.type] = true end
        local seen = {}
        for _, room in ipairs(rooms) do
            local id = room.id
            assert(type(id) == "string" and id ~= "", "Published room has no id")
            if not seen[id] then
                seen[id] = true
                local path = "developer/assets/tiled/maps/" .. id .. ".lua"
                local map = load(path)
                -- Displayed map properties, trimmed as mvtk/world/regions.lua shows them.
                local map_props = flatten(map.properties)
                for _, field in ipairs(TextFields.map_properties) do
                    local text = map_props[field]
                    if type(text) == "string" then add(Util.trim(text), path .. ":map." .. field) end
                end
                Objects.for_each_tiled_object(map, function(raw, layer, state)
                    if not state.visible then return end
                    local obj = {}
                    for key, value in pairs(raw) do obj[key] = value end
                    obj.properties = flatten(raw.properties)
                    local kind = Objects.resolve_object_type(obj, known_types)
                    if Objects.is_background_visual_object_candidate(obj, layer.name) then return end
                    local where = path .. ":layer[" .. tostring(layer.id or layer.name or "") .. "]/object[" .. tostring(raw.id or raw.name or "") .. "]"
                    for field in pairs(TextFields.fields(kind)) do add_tiled(kind, field, obj.properties[field], where .. "." .. field, add) end
                    if TextFields.object_names[kind] then
                        local overridden = kind == "map_marker" and obj.properties.marker_label
                            or kind == "fast_travel" and obj.properties.station_name
                            or kind == "boss" and Util.trim(obj.properties.bar_name)
                        -- boss_setup also rejects generic names after trimming/case folding.
                        local boss_name = kind == "boss" and Util.trim(raw.name):lower()
                        if (not overridden or overridden == "") and boss_name ~= "boss" and boss_name ~= "boss spawn" then
                            add_tiled(kind, "name", raw.name, where .. ".name", add)
                        end
                    end
                end)
            end
        end
        table.sort(entries, function(a,b)
            if a.kind ~= b.kind then return a.kind < b.kind end
            return (a.key or a.source) < (b.key or b.source)
        end)
        for _, entry in ipairs(entries) do table.sort(entry.where) end
        return entries
    end
    local ok, result = pcall(run)
    if not ok then return nil, tostring(result) end
    return result
end

-- Sorted token multiset, retaining repeats so Import can compare multiplicity.
-- Pure inspection only: no replacement, translation or input-prompt expansion.
function M.tokens(text)
    local out, i = {}, 1
    text = tostring(text or "")
    while i <= #text do
        local tail = text:sub(i)
        local token = tail:match("^(%{input:[%w_]+%})") or tail:match("^(%{[%w_]+%})")
        if text:sub(i,i) == "%" then token = tail:match("^(%%[-+ #0]*%d*%.?%d*[cdeEfgGiouqsxX%%])") end
        if token then out[#out+1] = token; i = i + #token else i = i + 1 end
    end
    table.sort(out)
    return out
end
return M
