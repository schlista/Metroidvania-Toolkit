-- Pure authoring contract shared by Game Settings, project writer and runtime.
-- Keys are editor control names; paths are the only persisted representation.
local Product = require "mvtk.core.product"
local M = { VERSION = 1, fields = {} }
-- Identity is edited alongside creator settings, but project_identity owns its
-- files. Keeping these controls separate prevents creator overrides from
-- accidentally acquiring game.project or persistence-settings fields.
M.identity_fields = {
    project_name = { key = "project_name", title = "Game name", type = "string",
        help = "The title shown in game.project and the exported game. Renaming it keeps the permanent save ID." },
    game_id = { key = "game_id", title = "Game ID", type = "string", read_only = true,
        help = "Permanent save identity, assigned by the first Prepare & Check or Save. Renaming the game does not change it." },
}
local AbilityConfig = require "developer.config.abilities"
local PlayerScale = require "mvtk.player.player_scale"
local OldPlayerUnits = require "mvtk.core.player_units_baseline"
local CreatorPixelPaths = require "mvtk.core.player_units_paths"
local Number = require "mvtk.editor.settings_number"
local AttackSettings = require "mvtk.core.attack_settings"
local AttackConfig = require "developer.config.combat_config"
local DamageTypes = require "developer.config.damage_types"
local attack_fields
attack_fields, M.attack_sections = AttackSettings.catalog(AttackConfig, DamageTypes)
for key, spec in pairs(attack_fields) do M.fields[key] = spec end

-- Cross-field diagnostics use all raw controls, including the hidden attacks.
function M.attack_issues(values)
    local attacks, issues = M.copy(AttackConfig.attacks), {}
    for key, spec in pairs(attack_fields) do
        if values[key] ~= nil then M.put(attacks[spec.attack_id], spec.attack_path, values[key]) end
        local value = values[key]
        if type(value) ~= spec.type or (spec.type == "number"
            and (value ~= value or value < spec.min or value > spec.max))
            or (spec.values and not spec.values[value]) then
            issues[key] = spec.help .. " Enter a value within the supported range or choices."
        end
    end
    for _, section in ipairs(M.attack_sections) do
        local id, attack = section.id, attacks[section.id]
        -- Scalar validation reports malformed values before timeline arithmetic.
        local scalar_ok = true
        for _, key in ipairs(section.fields) do if issues[key] then scalar_ok = false end end
        local issue = scalar_ok and AttackSettings.timeline_issue(attack)
        if issue then
            for key, spec in pairs(attack_fields) do
                if spec.attack_id == id and spec.attack_path:match("^timeline%.") then
                    issues[key] = (attack.label or id) .. ": " .. issue
                end
            end
        end
    end
    return issues
end

-- Apply a whole attack draft together: individual edits may temporarily cross
-- another timing value, while the final combination is valid.
function M.attack_document(document, values, baseline, operations)
    local out = M.copy(document)
    local defaults, before = M.controls({}, baseline), M.controls(document.overrides, baseline)
    for key, spec in pairs(attack_fields) do
        if values[key] ~= nil then
            local operation = operations and operations[key]
            if operation == "reset" then M.reset(out, key)
            elseif operation == "set" then M.put(out.overrides, spec.path, values[key])
            elseif values[key] ~= before[key] then
                if values[key] == defaults[key] then M.reset(out, key)
                else M.put(out.overrides, spec.path, values[key]) end
            end
        end
    end
    return M.validate(out)
end

function M.copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = M.copy(v) end
    return out
end

function M.merge(dst, src)
    for k, v in pairs(src or {}) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            M.merge(dst[k], v)
        else dst[k] = v end
    end
    return dst
end

local function get(tbl, path)
    for part in path:gmatch("[^.]+") do
        if type(tbl) ~= "table" then return nil end
        tbl = tbl[tonumber(part) or part]
    end
    return tbl
end

local function put(tbl, path, value)
    local parts = {}
    for part in path:gmatch("[^.]+") do parts[#parts + 1] = tonumber(part) or part end
    for i = 1, #parts - 1 do
        local key = parts[i]
        if type(tbl[key]) ~= "table" then tbl[key] = {} end
        tbl = tbl[key]
    end
    tbl[parts[#parts]] = value
end

M.get = get
M.put = put

-- Value aliases belong to the same authoring control. Start unlocks only live
-- in abilities; runtime availability and invulnerability follow acquired abilities.
M.mirrors = {
    wall_climb_speed = { "player.wall_climb.speed" },
}

local function remove(tbl, path)
    local head, tail = path:match("^([^.]+)%.(.+)$")
    if not head then tbl[tonumber(path) or path] = nil; return end
    head=tonumber(head) or head
    if type(tbl[head]) ~= "table" then return end
    remove(tbl[head], tail)
    if next(tbl[head]) == nil then tbl[head] = nil end
end

function M.prune_legacy(doc)
    for _, ability in ipairs({ "slide", "air_dash", "wall_climb", "extended_jump", "glide" }) do
        remove(doc.overrides, "player." .. ability .. ".enabled")
    end
    for _, ability in ipairs({ "slide", "air_dash" }) do
        remove(doc.overrides, "player." .. ability .. ".iframes")
    end
    return doc
end

function M.reset(doc, key)
    local spec = assert(M.fields[key], "Unknown creator field: " .. tostring(key))
    remove(doc.overrides, spec.path)
    for _, path in ipairs(M.mirrors[key] or {}) do remove(doc.overrides, path) end
    return M.prune_legacy(doc)
end

function M.controls(overrides, baseline)
    local effective = M.merge(M.copy(baseline or {}), overrides or {})
    local controls = {}
    for key, spec in pairs(M.fields) do
        local value = get(effective, spec.path)
        if spec.replace then
            value = get(overrides, spec.path)
            if value == nil then value = get(baseline, spec.path) end
        end
        if value == nil then value = spec.default end
        controls[key] = M.copy(value)
    end
    if controls.combo_chaining == false then controls.mixed_finishers = false end
    if controls.parry == false then controls.perfect_parry, controls.parry_counter = false, false end
    if controls.aerial_attacks == false then controls.aerial_juggle = false end
    return controls
end

-- Game Settings window titles are sentence case: "Swing Power" -> "Swing power".
-- Acronyms (HUD, FPS) and single letters (X, Y) keep their capitals.
local function sentence(text)
    local first = true
    return (tostring(text):gsub("%a[%w']*", function(word)
        if first then first = false; return word end
        if #word == 1 or word == word:upper() then return word end
        return word:lower()
    end))
end
local function field(key, path, kind, title, help, min, max, alias)
    M.fields[key] = { key = key, path = path, type = kind, title = title, help = help, min = min, max = max, alias = alias }
end
local function number(key, path, title, min, max, help, alias)
    field(key, path, "number", title, help, min, max, alias)
end
local function boolean(key, path, title, help) field(key, path, "boolean", title, help) end
-- Slots and their display names follow the authored rows and prompt source.
do
    local Rules = require "mvtk.core.input_binding_rules"
    local Prompts = require "mvtk.ui.input_prompt_labels"
    local config = require "developer.config.default_bindings"
    local view = Rules.creator_view(config, require "mvtk.rooms.input_actions")
    local inputs, labels = {}, { none = "None" }
    for _, input in ipairs(config.inputs) do
        inputs[input] = true
        local side = input:match("^key_([lr])shift$") or input:match("^key_([lr])ctrl$")
        labels[input] = (side and (side == "l" and "Left " or "Right ") or "") .. Prompts.label(input, "xbox")
    end
    local choices = { keyboard = { "none" }, controller = { "none" } }
    for _, input in ipairs(config.inputs) do
        if Rules.capturable_key(input, inputs) then choices.keyboard[#choices.keyboard + 1] = input end
        if Rules.CONTROLLER_INPUTS[input] and input ~= "gamepad_guide" then
            choices.controller[#choices.controller + 1] = input
        end
    end
    for _, list in pairs(choices) do
        table.sort(list, function(a,b)
            if a == "none" or b == "none" then return a == "none" and b ~= "none" end
            return labels[a] == labels[b] and a < b or labels[a] < labels[b]
        end)
    end
    M.binding_fields = {}
    for _, row in ipairs(config.remappable) do
        for _, slot in ipairs({ "keyboard", "controller", "hold_seconds" }) do
            if view[slot][row.action] ~= nil then
                local suffix = slot == "keyboard" and "key" or slot == "controller" and "pad" or "hold"
                local key = "bind_" .. row.id .. "_" .. suffix
                if suffix == "hold" then
                    number(key, "default_bindings.hold_seconds." .. row.action,
                        "Heal / item hold time (seconds)", Rules.HOLD_RANGE[1], Rules.HOLD_RANGE[2],
                        "Hold this long before Quick Use steps through quick items.")
                    M.fields[key].step = 0.05
                else
                    local noun = suffix == "key" and "keyboard key" or "controller button"
                    -- An input missing from default_bindings.inputs (a typo) has no label. Show its name, so the
                    -- model still loads and Prepare & Check can report creator_bindings_invalid.
                    local current = view[slot][row.action]
                    local help = "Default " .. noun .. " for " .. row.label .. ". Toolkit default: "
                        .. (labels[current] or tostring(current)) .. ". "
                        .. (row.player and "Players can remap it in Pause ▸ Settings ▸ Controls." or "Players cannot remap this action.")
                    field(key, "default_bindings." .. slot .. "." .. row.action, "string",
                        row.label .. (suffix == "key" and " key" or " button"), help)
                    M.fields[key].choices, M.fields[key].choice_labels = choices[slot], labels
                end
                local spec = M.fields[key]
                spec.default, spec.binding = view[slot][row.action], { id=row.id, action=row.action, slot=slot }
                M.binding_fields[#M.binding_fields + 1] = key
            end
        end
    end
    number("quick_use_step_repeat", "healing.quick.step_repeat_seconds", "Quick item step repeat (seconds)",
        0.01, 60, "Time between quick item selections while held. With Healing = channel, holding starts healing and step repeat is unused. Menu navigation is configured in menu_settings.lua.")
    M.fields.quick_use_step_repeat.default = require("developer.config.healing").quick.step_repeat_seconds
    M.fields.quick_use_step_repeat.step = 0.05
end

for _,key in ipairs({"id","condition","flag","boss_id","continue_policy","return_room","title","body","credits","music","artwork","reward_flag"}) do
    local title = key == "id" and "ID" or (key:gsub("_", " "):gsub("^%l", string.upper):gsub(" id$", " ID"))
    field("ending_"..key,"game_completion."..key,"string", title, "Ending "..key:gsub("_"," ").."; saved to project, rebuild before play.")
end
field("cutscene_opening", "cutscenes.opening", "string", "Opening cutscene", "Scene id played once when a fresh save begins; blank disables it.")
boolean("cutscene_allow_skip", "cutscenes.allow_skip", "Allow skipping", "Allow holding the skip action when the scene has no dialogue outcomes.")
number("cutscene_skip_hold", "cutscenes.skip_hold_seconds", "Skip hold time (seconds)", 0.2, 5, "Continuous hold in seconds before skipping a scene.")
M.fields.cutscene_skip_hold.step = 0.1
M.fields.cutscene_skip_hold.applies_when = { "cutscene_allow_skip" }
M.fields.cutscene_opening.default = ""
M.fields.cutscene_allow_skip.default = true
M.fields.cutscene_skip_hold.default = 0.8
boolean("combat_music_enabled", "combat_music.enabled", "Combat music", "Crossfade to the combat track for enemies the player can see within range, or accepted player hits. Boss, champion and encounter music take precedence.")
boolean("combat_music_line_of_sight", "combat_music.engage.line_of_sight", "Only enemies the player can see", "Count enemies the player can see within range. Walls and platforms block sight. Untick to count enemies through walls too. Player hits can still start combat music.")
field("combat_music_track", "combat_music.default_track", "string", "Combat track", "Registered music track id; blank needs a room combat_music property. Prepare & Check registers music files.")
number("combat_music_release", "combat_music.release_delay", "Quiet delay (seconds)", 0.5, 30, "Quiet time before returning to room music. Pausing freezes this timer.")
M.fields.combat_music_enabled.default = false
M.fields.combat_music_line_of_sight.default = true
M.fields.combat_music_track.default = ""
M.fields.combat_music_release.default = 4
M.fields.combat_music_release.step = 0.5
M.fields.combat_music_track.applies_when = {"combat_music_enabled"}
M.fields.combat_music_line_of_sight.applies_when = {"combat_music_enabled"}
M.fields.combat_music_release.applies_when = {"combat_music_enabled"}
-- Registry codes are stable creator values; the player still saves auto or a code.
field("default_language", "localization.default_language", "string", "Default language",
    "auto uses the supported system language, then this default or the fallback. A saved player language takes precedence.")
M.fields.default_language.choices = { "auto" }
M.fields.default_language.choice_labels = { auto = "auto" }
M.fields.default_language.values = { auto = true }
for _, language in ipairs(require("developer.config.localization").languages) do
    table.insert(M.fields.default_language.choices, language.code)
    M.fields.default_language.values[language.code] = true
    M.fields.default_language.choice_labels[language.code] = language.code
end
boolean("show_language_choice", "localization.show_language_choice", "Show language choice",
    "Offer Language in player Settings > Display when the game supports more than one language.")
field("ui_font_file", "localization.ui_font_file", "string", "UI font file",
    "Project-relative .ttf or .otf containing every language's letters. Keep its licence beside it; Prepare & Check builds the UI fonts.")
field("ui_text_rendering", "localization.ui_text_rendering", "string", "Text rendering",
    "Vector (the default) stays sharp at any size but cannot run on OpenGL ES 2 or WebGL 1 devices. Distance field runs everywhere and softens when text is enlarged.")
M.fields.ui_text_rendering.choices = { "distance_field", "vector" }
M.fields.ui_text_rendering.values = { distance_field=true, vector=true }
M.fields.ui_text_rendering.choice_labels = { distance_field="Distance field", vector="Vector" }
field("ui_glyph_generation", "localization.ui_glyph_generation", "string", "Glyph generation",
    "Built with the game includes the collected letters. On demand bundles the font file and needs the full text layout system; Prepare & Check prepares its app manifest.")
M.fields.ui_glyph_generation.choices = { "static", "dynamic" }
M.fields.ui_glyph_generation.values = { static=true, dynamic=true }
M.fields.ui_glyph_generation.choice_labels = { static="Built with the game", dynamic="On demand" }
M.fields.ui_font_file.check = function(value)
    if type(value) ~= "string" or value == "" or value:find("[\\:%c]") or value:sub(1,1) == "/"
        or value:find("//",1,true) then return nil, "Choose a project-relative .ttf or .otf file." end
    for part in value:gmatch("[^/]+") do
        if part == "." or part == ".." then return nil, "UI font file must stay inside this project." end
    end
    if not value:lower():match("%.ttf$") and not value:lower():match("%.otf$") then
        return nil, "UI font file must be .ttf or .otf."
    end
    if value:match("^builtins/") then return nil, "Copy the font and its licence into this project." end
    return true
end
field("difficulty_selection", "difficulty.selection", "string", "Selection mode", "fixed uses the default; new_game asks on an empty slot; anytime also allows changes from Pause.")
M.fields.difficulty_selection.choices = { "fixed", "new_game", "anytime" }
M.fields.difficulty_selection.values = { fixed = true, new_game = true, anytime = true }
field("difficulty_default", "difficulty.current", "string", "Default profile", "Starting profile; an unavailable saved or default profile falls back to the authored default.")
-- Choices guide the editor; no strict values, so deleting a custom profile
-- cannot prevent an older published settings document from booting.
M.fields.difficulty_default.choices = {}
for _, id in ipairs(require("developer.config.difficulty_settings").order) do
    if require("developer.config.difficulty_settings").profiles[id] then
        M.fields.difficulty_default.choices[#M.fields.difficulty_default.choices + 1] = id
    end
end
-- Catalog-generated controls retain source labels and real config paths.
M.status_effect_fields = {"status_effects_enabled"}
do
    local cfg = require "developer.config.status_effects"
    boolean("status_effects_enabled", "status_effects.enabled", "Status effects on",
        "Enable transient statuses. Turning off clears existing effects on the next active tick.")
    M.fields.status_effects_enabled.default = cfg.enabled
    local ids = {}; for id in pairs(cfg.effects) do ids[#ids+1] = id end; table.sort(ids)
    for _, id in ipairs(ids) do
        local effect = cfg.effects[id]
        for _, spec in ipairs({
            {"duration", "Duration (seconds)", 0.01, 3600, effect.duration, "Effect lifetime; reapplying refreshes it."},
            {"tick_interval", "Tick interval (seconds)", 0.01, 3600, effect.tick_interval or cfg.defaults.tick_interval,
                "Seconds between damage ticks; duration may end before the first tick."},
            {"damage_per_tick", "Damage per tick", 0, 1000, effect.damage_per_tick or 0,
                "Health per stack before damage factors; zero deals no tick damage."},
            {"move", "Speed multiplier", 0.25, 1, effect.move or 1,
                "Walking multiplier; speed does not slow swimming or ladders. Freeze never locks player actions."},
        }) do
            local key = "status_" .. id .. "_" .. spec[1]
            number(key, "status_effects.effects." .. id .. "." .. spec[1], effect.label .. ": " .. spec[2],
                spec[3], spec[4], spec[6])
            M.fields[key].default = spec[5]
            M.fields[key].step = 0.05
            M.fields[key].units = (spec[1] == "duration" or spec[1] == "tick_interval") and "seconds" or ""
            M.status_effect_fields[#M.status_effect_fields+1] = key
        end
    end
end
number("encounter_wave_delay", "encounter_settings.wave_delay", "Default wave delay (seconds)", 0, 3600,
    "Time between defeated waves. Encounter Wave delay -1 inherits this setting.")
number("encounter_max_alive", "encounter_settings.max_alive", "Default simultaneous cap", 1, 200,
    "Living wave enemies; pending telegraphs reserve slots. Encounter Max alive 0 inherits this setting.")
M.fields.encounter_max_alive.integer = true
M.fields.encounter_max_alive.editor_integer = true
boolean("encounter_wave_messages", "encounter_settings.show_wave_messages", "Wave messages",
    "Show translated wave toasts when the Encounter also enables Show wave messages. Reword them in ui_text.lua.")
boolean("encounter_autosave", "encounter_settings.autosave_on_clear", "Autosave on clear",
    "Save clear flags, shortcut channels and synchronous listener changes together; mid-fight state is never saved.")
do
    local config = require "developer.config.encounter_settings"
    for key, name in pairs({encounter_wave_delay="wave_delay", encounter_max_alive="max_alive",
        encounter_wave_messages="show_wave_messages", encounter_autosave="autosave_on_clear"}) do
        M.fields[key].default = config[name]
    end
end
number("champion_health_mult", "enemy_defaults.champion.health_mult", "Health multiplier", 0.001, 1000,
    "Champion health factor, stacked once with Elite and difficulty. Applies when the enemy is prepared for play.")
number("champion_damage_mult", "enemy_defaults.champion.damage_mult", "Damage multiplier", 0.001, 1000,
    "Champion contact damage factor, stacked once with Elite and difficulty.")
number("champion_engage_range", "enemy_defaults.champion.engage_range", "Engage range (world px)", 0, 100000,
    "Distance to the player before a champion engages in the current room, after the doorway is clear. 0 means the whole room; Tiled Champion engage range -1 inherits this value.")
do
    local config = require("developer.config.enemy_defaults").champion
    for _, name in ipairs({"health_mult", "damage_mult", "engage_range"}) do
        M.fields["champion_" .. name].default = config[name]
    end
    M.fields.champion_health_mult.step = 0.1
    M.fields.champion_damage_mult.step = 0.1
    M.fields.champion_engage_range.step = 16
    M.fields.champion_engage_range.units = "world px"
end
M.element_fields = {}
do
    local cfg = require "developer.config.damage_types"
    local ids = {}; for id in pairs(cfg.types) do ids[#ids + 1] = id end; table.sort(ids)
    for _, id in ipairs(ids) do
        local key = "player_taken_" .. id
        number(key, "damage_types.player_taken." .. id, "Player damage taken: " .. cfg.types[id].label, 0, 10,
            "Incoming type factor: 0 is immune, 1 is unchanged, 2 is double. Lethal hits bypass it.")
        M.fields[key].default = cfg.player_taken[id] or 1
        M.element_fields[#M.element_fields + 1] = key
    end
    number("element_weak_multiplier", "damage_types.weak_multiplier", "Weakness multiplier", 1, 10,
        "Damage factor for weak affinities without an explicit numeric override.")
    number("element_resist_multiplier", "damage_types.resist_multiplier", "Resistance multiplier", 0, 1,
        "Damage factor for resistant affinities without an explicit numeric override.")
    boolean("element_tint_numbers", "damage_types.feedback.tint_numbers", "Colour damage numbers by element",
        "Use damage_types.lua colours when Damage numbers is enabled.")
    M.fields.element_weak_multiplier.default = cfg.weak_multiplier
    M.fields.element_resist_multiplier.default = cfg.resist_multiplier
    M.fields.element_tint_numbers.default = cfg.feedback.tint_numbers
    for _, key in ipairs({"element_weak_multiplier", "element_resist_multiplier", "element_tint_numbers"}) do
        M.element_fields[#M.element_fields + 1] = key
    end
end
field("enemy_default_archetype", "enemy_defaults.default_archetype", "string", "Default archetype for art-only enemies",
    "Stats and behaviour for enemy art without a matching enemy type or an explicit Archetype. Reopen the editor after adding enemy_types.lua keys to refresh this list.")
-- Choices guide authoring without rejecting older published defaults when a
-- creator removes a preset. Content checks warn and runtime uses its fallback.
M.fields.enemy_default_archetype.choices = {}
for id in pairs(require "developer.config.enemy_types") do
    table.insert(M.fields.enemy_default_archetype.choices, id)
end
table.sort(M.fields.enemy_default_archetype.choices)
number("enemy_cap_per_room", "enemy_settings.max_enemies_per_room", "Enemy cap per room", 0, 200,
    "Maximum registered enemies in each room, including baked enemies. 0 means unlimited; a spawner can override the cap.")
M.fields.enemy_cap_per_room.integer = true
M.fields.enemy_cap_per_room.editor_integer = true
M.fields.enemy_cap_per_room.step = 1
field("enemy_ledge_behavior", "enemy_defaults.ledge_behavior", "string", "Default ledge behaviour",
    "Ground enemies: stop turns at ledges; fall walks off; fall_when_chasing drops only during a chase. Tiled Stats > Ledge behaviour and archetype settings take precedence.")
M.fields.enemy_ledge_behavior.choices = { "stop", "fall", "fall_when_chasing" }
M.fields.enemy_ledge_behavior.values = { stop=true, fall=true, fall_when_chasing=true }
number("enemy_fall_gravity", "enemy_defaults.fall_gravity_tiles", "Enemy fall gravity (tiles/s²)", 0.01, 200,
    "Downward acceleration in tiles per second squared for falling ground enemies; uses the imported tile height.")
M.fields.enemy_fall_gravity.step = 0.5
field("enemy_respawn_policy", "enemy_defaults.respawn_policy", "string", "Enemy respawn",
    "Default for placed enemies: always returns on room entry; room_reload on rebuild; save after Save Point rest, death or load; never stays defeated in saved Flags. Checkpoints save without reviving save enemies. Tiled On defeat > Respawn and archetype settings take precedence.")
M.fields.enemy_respawn_policy.choices = { "always", "room_reload", "save", "never" }
M.fields.enemy_respawn_policy.values = { always=true, room_reload=true, save=true, never=true }
boolean("enemy_autosave_on_permanent_defeat", "enemy_defaults.autosave_on_permanent_defeat", "Save after a permanent defeat",
    "Save immediately after a never enemy falls, including listener flags. When off, dying before the next save undoes that defeat.")
boolean("ending_enabled","game_completion.enabled", "Enabled","Enable the configured game ending.")
number("ending_return_x","game_completion.return_x", "Return X (world px)",-10000000,10000000,"Return checkpoint X in world pixels.")
number("ending_return_y","game_completion.return_y", "Return Y (world px)",-10000000,10000000,"Return checkpoint Y in world pixels.")
-- Ordered choices are shared by the native and in-game ending editors.
for key, choices in pairs({ ending_condition = { "region", "flag", "boss" },
    ending_continue_policy = { "completed", "explore" } }) do
    local spec = M.fields[key]
    spec.choices, spec.values = choices, {}
    for _, value in ipairs(choices) do spec.values[value] = true end
end
M.fields.ending_flag.applies_when = { "ending_condition=flag" }
M.fields.ending_boss_id.applies_when = { "ending_condition=boss" }
for _, key in ipairs({ "ending_return_room", "ending_return_x", "ending_return_y" }) do
    M.fields[key].applies_when = { "ending_continue_policy=explore" }
end
M.fields.ending_body.multiline, M.fields.ending_credits.multiline = true, true
field("ending_others", "game_completion.endings", "table", "Other endings",
    "Ordered complete endings checked before the main ending. This replaces the entire baseline list; an empty list removes all other endings.")
M.fields.ending_others.default = {}
M.fields.ending_others.replace = true
M.fields.ending_others.list_editor = true
M.fields.ending_others.check = function(value)
    -- Resolve the pure ending contract only when validating data.
    local errors = require("mvtk.game.endings").schema_errors({endings=value})
    return #errors == 0, table.concat(errors, "\n")
end

number("player_scale", "player.player_scale", "Player size (1 = 100%)", PlayerScale.MIN_SCALE, PlayerScale.MAX_SCALE, "Player Size: 1.00 (100%) uses the model's own in-game pixels; changing it stretches the model and requires rebuilding player resources.")
boolean("scale_movement", "player.scale_movement", "Scale movement with size", "Also scale movement with player size; false scales geometry only.")
number("walk_speed", "player.walk_speed", "Walk speed (px/s)", 100, 5000, "Walking speed in base pixels per second.")
number("run_speed", "player.run_speed", "Run speed (px/s)", 200, 5000, "Running speed in base pixels per second.")
number("jump_height", "player.jump_height", "Jump height (px)", 50, 1000, "Jump height in base pixels.")
number("gravity", "player.gravity", "Gravity", -5000, 0, "Downward acceleration; negative base pixels per second squared.")
number("max_health", "player.max_health", "Max health", 1, 100, "Maximum starting health.")
number("max_energy", "player.max_energy", "Max energy", 0, 100, "0 turns energy off: no energy bar, and energy gates can't open until an Energy Container raises the maximum.")
number("max_stamina", "player.max_stamina", "Max stamina", 0, 1000, "0 turns stamina off: no stamina bar, and abilities cost no stamina.")
number("health_fragment_pieces", "fragments.sets.health.pieces", "Health fragments per container", 1, 20, "Whole Health fragments needed for a permanent health increase. Changes apply at the next pickup; existing increases remain.")
number("energy_fragment_pieces", "fragments.sets.energy.pieces", "Energy fragments per container", 1, 20, "Whole Energy fragments needed for a permanent energy increase. Changes apply at the next pickup; existing increases remain.")
for _, key in ipairs({"health_fragment_pieces", "energy_fragment_pieces"}) do
    M.fields[key].step, M.fields[key].editor_integer = 1, true
end
field("healing_model", "healing.model", "string", "Healing", "Choose a refillable flask, owned potions only, or hold Quick Use to heal with energy (channel). In channel mode, select quick items in Inventory.")
M.fields.healing_model.choices = { "flask", "items", "channel" }
M.fields.healing_model.values = { flask = true, items = true, channel = true }
number("heal_channel_amount", "healing.channel.heal_amount", "Heal per channel", 1, 20, "Health restored by a completed channel.")
M.fields.heal_channel_amount.editor_integer = true
number("heal_cost", "healing.channel.cost", "Energy per heal", 0, 100, "Max energy caps the shared pool. A cost above it cannot be paid until an Energy Container raises the maximum. Max energy 0 prevents channel healing.")
M.fields.heal_cost.step = 0.25
number("heal_channel_time", "healing.channel.channel_time", "Channel time (seconds)", 0.1, 5, "Time per heal after Quick Use registers a hold; release cancels without spending.")
M.fields.heal_channel_time.step = 0.05
for _,key in ipairs({"heal_channel_amount", "heal_cost", "heal_channel_time"}) do
    M.fields[key].applies_when = { "healing_model=channel" }
end
boolean("energy_from_combat", "healing.energy.enabled", "Gain energy from combat",
    "Refill the shared energy pool from accepted player hits, parries and defeats in every healing model. Max energy caps the pool; 0 disables gains and waives attack energy costs.")
for _, row in ipairs({
    { "energy_on_hit", "gain_on_hit", "Energy per hit" },
    { "energy_on_parry", "gain_on_parry", "Energy per parry" },
    { "energy_on_perfect_parry", "gain_on_perfect_parry", "Energy per perfect parry" },
    { "energy_on_defeat", "gain_on_kill", "Energy per defeat" },
}) do
    number(row[1], "healing.energy." .. row[2], row[3], 0, 100,
        "Energy added after this combat event, capped by Max energy. Blocked and immune hits give nothing; damage-over-time ticks give no hit energy. Perfect parries replace the regular parry gain.")
    M.fields[row[1]].step = 0.05
    M.fields[row[1]].applies_when = { "energy_from_combat" }
end
M.fields.energy_on_parry.applies_when = { "energy_from_combat", "parry" }
M.fields.energy_on_perfect_parry.applies_when = { "energy_from_combat", "parry", "perfect_parry" }
number("heal_charges", "healing.flask.max_charges", "Flask charges", 0, 10, "0 removes the flask.")
number("heal_amount", "healing.flask.heal_amount", "Heal per use", 1, 20, "Health restored by a completed flask drink.")
for _, key in ipairs({ "heal_charges", "heal_amount" }) do
    M.fields[key].step, M.fields[key].editor_integer = 1, true
    M.fields[key].applies_when = { "healing_model=flask" }
end
number("air_accel_mult", "player.air_accel_mult", "Air control", 0, 2, "Air steering multiplier.")
number("coyote_time", "player.coyote_time", "Coyote time (seconds)", 0, 1, "Seconds after leaving a ledge during which jumping is allowed.")
number("attack_buffer", "player.attack_buffer", "Attack buffer (seconds)", 0, 1, "Seconds to retain a buffered attack input.")
number("air_jumps", "player.air_jumps", "Air jumps", 0, 10, "Extra mid-air jumps once Double Jump is unlocked.")
number("slide_speed", "player.slide.speed", "Slide speed (px/s)", 0, 5000, "Slide speed in base pixels per second.")
number("air_dash_speed", "player.air_dash.speed", "Air dash speed (px/s)", 0, 5000, "Air dash speed in base pixels per second.")
number("air_dash_count", "player.air_dash.max_air_dashes", "Air dash count", 0, 10, "Air dashes available before landing.")
field("air_dash_directions", "player.air_dash.directions", "string", "Air dash directions", "Eight follows the stick; horizontal preserves X-only dashes and vertical momentum.")
M.fields.air_dash_directions.values = { horizontal = true, eight = true }
M.fields.air_dash_directions.choices = { "horizontal", "eight" }
boolean("air_dash_suspend_gravity", "player.air_dash.suspend_gravity", "Pause gravity while dashing", "Hold vertical speed during an eight-direction dash; a sideways dash flies flat.")
number("extra_air_dash_bonus", "player.extra_air_dash.bonus_dashes", "Extra dashes per upgrade", 1, 5, "Charges added before landing whenever Extra Air Dash is unlocked, at the start or by pickup.")
M.fields.extra_air_dash_bonus.step, M.fields.extra_air_dash_bonus.editor_integer = 1, true
number("wall_climb_speed", "player.wall_climb.climb_speed", "Wall climb speed (px/s)", 0, 5000, "Wall climb speed in base pixels per second.")
number("wall_cling_fall_speed", "player.wall_climb.stick_speed", "Cling fall speed (px/s)", 0, 5000, "Downward speed while clinging; zero stays still.")
number("high_jump_height_mult", "player.high_jump.height_mult", "High jump height (x normal)", 1, 4,
    "Multiplies ground jump height. Player Size also applies; air jumps keep their normal height by default.")
number("super_jump_charge_time", "player.super_jump.charge_time", "Charge time (seconds)", 0.1, 3,
    "Hold Down while standing still for this many seconds, then press Jump.")
number("super_jump_height_mult", "player.super_jump.launch_height_mult", "Launch height (x normal)", 1, 8,
    "Unitless multiple of base jump height. Player Size applies; High Jump does not stack with this launch.")
number("zip_hang_offset", "player.zip_line.hang_offset_px", "Hang offset", 0, 120,
    "Distance from the cable to the player origin. Tune until the hands meet the cable after Build.")
M.fields.zip_hang_offset.units = "base px"
boolean("zip_release_on_jump", "player.zip_line.release_on_jump", "Jump lets go",
    "Allow Jump to release the zip line early.")
number("hang_bar_offset", "player.ladder_climb.hang_offset_px", "Hang offset", 0, 120,
    "Distance from a hang bar's centre line to the player origin. 0 uses the ladder hand height. Tune until the hands meet the bar after Build.")
M.fields.hang_bar_offset.units = "base px"
number("lantern_radius", "player.lantern.radius", "Radius", 32, 1200,
    "Light radius in unscaled world pixels. Player Size never changes it; colour comes from Display > Lighting.")
M.fields.lantern_radius.units, M.fields.lantern_radius.step = "world px", 8
number("lantern_intensity", "player.lantern.intensity", "Intensity", 0.1, 4,
    "Carried light strength while the Lantern ability is unlocked.")
M.fields.lantern_intensity.step = 0.05
number("lantern_flicker", "player.lantern.flicker", "Flicker", 0, 1,
    "Fraction of intensity lost at the dimmest point; zero gives steady light.")
M.fields.lantern_flicker.step = 0.05
number("lantern_min_darkness", "player.lantern.min_darkness", "Minimum darkness", 0, 0.9,
    "Show the Lantern only at or above this room or Screen Effect Zone darkness.")
M.fields.lantern_min_darkness.step = 0.05
number("ice_accel", "player.surfaces.ice.accel_mult", "Acceleration multiplier", 0.01, 1, "Painted ice and Ice Floor zones whose values are -1 use this unscaled floor multiplier. Smaller values slide or skid longer; wall ice is separate.")
M.fields.ice_accel.units, M.fields.ice_accel.step = "", 0.01
number("ice_decel", "player.surfaces.ice.decel_mult", "Stopping multiplier", 0, 1, "Painted ice and Ice Floor zones whose values are -1 use this unscaled floor multiplier. Smaller values slide or skid longer; wall ice is separate.")
M.fields.ice_decel.units, M.fields.ice_decel.step = "", 0.01
number("ice_turn", "player.surfaces.ice.turn_brake_mult", "Turn braking multiplier", 0, 1, "Painted ice and Ice Floor zones whose values are -1 use this unscaled floor multiplier. Smaller values slide or skid longer; wall ice is separate.")
M.fields.ice_turn.units, M.fields.ice_turn.step = "", 0.01
local grapple_help_suffix = " Applies whenever Grapple is unlocked - at the start or by pickup."
number("blink_distance", "player.blink.distance_px", "Blink distance (px)", 0, 2000,
    "Maximum teleport distance in base pixels. Walls, gates, platforms and room boundaries can shorten or refuse it.")
number("blink_chain_grace", "player.blink.chain_grace", "Second-press window (s)", 0, 0.5,
    "Seconds after an air dash or ground slide ends that pressing Dash again can still Blink.")
local function grapple(key, path, kind, default, label, units, help, min, max, applies_when, choices)
    local title_units = units:gsub("^base ", "")
    -- Acceleration units (px/s^2) read badly in a title; the help text keeps them.
    local title = sentence(label) .. ((title_units ~= "" and not title_units:find("^", 1, true))
        and (" (" .. title_units .. ")") or "")
    field(key, "player.grapple." .. path, kind, title, help .. grapple_help_suffix, min, max)
    local spec = M.fields[key]
    spec.default, spec.label, spec.units, spec.page = default, label, units, 7
    spec.applies_when, spec.choices = applies_when, choices
    if choices then
        spec.values = {}
        for _, value in ipairs(choices) do spec.values[value] = true end
    end
end
grapple("grapple_style", "mode", "string", "swing", "Grapple style", "",
    "Swing: hold onto the rope and swing back and forth with Left/Right (an analog stick pushes harder the further you tilt it). Pull: the rope reels you straight to the hook. With Pull hang on, you then hang at the hook until you let go.", nil, nil, nil, {"swing", "pull"})
grapple("grapple_targets", "targets", "string", "surfaces", "Hook catches", "",
    "Where the hook catches. Surfaces: only Grapple Surface rectangles, painted grapple layers and grapple points. Ceilings: also the underside of any solid terrain.", nil, nil, nil, {"surfaces", "ceilings"})
grapple("grapple_stay_hooked", "stay_hooked", "boolean", false, "Stay hooked", "",
    "Off: hold Grapple to stay on the rope; release the button to let go. On: the rope stays after you release the button, so you can keep swinging with the stick; press Grapple again or Jump to let go.")
grapple("grapple_reel", "reel_enabled", "boolean", false, "Extend / retract rope", "",
    "Let Up/Down climb or descend the rope while hooked. Off keeps the rope at the length it had when the hook caught.", nil, nil, {"grapple_style=swing"})
grapple("grapple_pull_hang", "pull_hang", "boolean", true, "Pull hang", "",
    "Pull style only. On: after the rope pulls you to the hook, you hang there until you let go: release Grapple, press it again with Stay hooked on, or press Jump for a full jump. Off: you drop as soon as you arrive.", nil, nil, {"grapple_style=pull"})
grapple("grapple_pump_with_swing", "pump_with_swing_only", "boolean", true, "Pump with swing only", "",
    "On: Left/Right adds speed only in the direction you are already swinging, and pushing the other way slows the swing (Counter-swing brake). Near a standstill either direction starts a swing. Off: Left/Right pushes either way at any time.", nil, nil, {"grapple_style=swing"})
grapple("grapple_pump_start_speed", "pump_start_speed", "number", 60, "Pump start speed", "base px/s",
    "Below this sideways speed, in base pixels per second, Left/Right may push either way, so you can start a swing from a dead hang and push off at the top of each arc. Higher values make changing direction easier.", 0, 600, {"grapple_style=swing", "grapple_pump_with_swing"})
grapple("grapple_counter_brake", "swing_counter_brake", "number", 0.5, "Counter-swing brake", "",
    "How strongly pushing against the swing slows it, as a share of Swing Power. 0: pushing the other way does nothing. 1: it brakes as hard as Swing Power pumps. Braking never reverses the swing.", 0, 2, {"grapple_style=swing", "grapple_pump_with_swing"})
grapple("grapple_break_on_impact", "release_on_impact", "boolean", true, "Break on impact", "",
    "Release the rope on landing or a fast wall or ceiling impact. Gentle wall touches keep the rope.")
grapple("grapple_walls", "allow_walls", "boolean", false, "Catch walls", "",
    "In Ceilings mode, also let the hook catch untagged terrain walls. Floors never catch.", nil, nil, {"grapple_targets=ceilings"})
grapple("grapple_range", "range_px", "number", 800, "Range", "base px",
    "Grapple reach in base pixels; match this to your authored rooms.", 0, 10000)
grapple("grapple_hook_speed", "hook_speed", "number", 0, "Hook speed", "base px/s",
    "How fast the hook flies to its target, in base pixels per second. 0 catches instantly. A target that moves or is blocked before the hook arrives is missed.", 0, 6000)
grapple("grapple_swing_strength", "swing_acceleration", "number", 2000, "Swing Power", "base px/s^2",
    "How strongly Left/Right builds swing speed, in base pixels per second squared.", 0, 10000, {"grapple_style=swing"})
grapple("grapple_swing_speed", "swing_max_speed", "number", 1200, "Swing Top Speed", "base px/s",
    "Maximum speed earned by Left/Right pumping, in base pixels per second. Gravity can carry you faster.", 100, 6000, {"grapple_style=swing"})
grapple("grapple_swing_fade", "swing_drag", "number", 0.12, "Swing Fade", "",
    "How quickly a swing dies down when you stop steering. 0 never fades; the default 0.12 fades slowly; 1 stops a swing within a few seconds.", 0, 5, {"grapple_style=swing"})
grapple("grapple_reel_speed", "reel_speed", "number", 320, "Reel Speed", "base px/s",
    "How quickly Up/Down changes rope length when reeling is on, in base pixels per second.", 0, 3000, {"grapple_style=swing", "grapple_reel"})
grapple("grapple_pull_speed", "pull_speed", "number", 2200, "Pull Speed", "base px/s",
    "Pull style only: how fast the rope pulls you to the hook, in base pixels per second.", 100, 6000, {"grapple_style=pull"})
grapple("grapple_momentum", "release_momentum_mult", "number", 1, "Momentum Kept", "multiplier",
    "How much rope speed you keep when you let go (button, second press or Jump). 1 keeps all of it, 0.5 half, 0 drops straight down; above 1 slingshots. Let-go Boost and Lift are added afterwards.", 0, 2)
grapple("grapple_release_carry", "release_carry_time", "number", 0.35, "Carry Time", "seconds",
    "Seconds that momentum carries you after letting go, losing an anchor or leaving its room. Zero restores normal air braking immediately.", 0, 2)
grapple("grapple_release_float", "release_gravity_mult", "number", 0.6, "Let-go Float", "multiplier",
    "Gravity right after letting go, while momentum carries you. Lower is floatier and gives more time to re-hook. 1 = normal.", 0.2, 1)
grapple("grapple_release_boost", "release_boost_px", "number", 150, "Let-go Boost", "base px/s",
    "Extra speed in your travel direction when you let go, in base pixels per second. Zero preserves your earned speed.", 0, 3000)
grapple("grapple_release_lift", "release_up_boost_px", "number", 0, "Let-go Lift", "base px/s",
    "Extra upward speed when you let go, in base pixels per second. Zero preserves your earned vertical speed.", 0, 3000)
grapple("grapple_rehook_window", "recast_window_s", "number", 0.3, "Re-hook Time", "seconds",
    "Hold Grapple after a miss and it keeps trying for this many seconds.", 0, 1)
number("melee_light_damage", "combat.melee_light.damage", "Light damage", 0, 1000, "First hitbox damage of the first light combo hit (light_1) only. Per-attack values in Attacks take precedence.", "light_damage")
number("melee_heavy_damage", "combat.melee_heavy.damage", "Heavy damage", 0, 1000, "First hitbox damage of Heavy (heavy_1) only. Per-attack values in Attacks take precedence.", "heavy_damage")
number("melee_up_damage", "combat.melee_up.damage", "Up attack damage", 0, 1000, "First hitbox damage of Up light (up_light), Air up light (air_up_light) and Up heavy (up_heavy), if authored. Per-attack values in Attacks take precedence.")
M.fields.melee_up_damage.step = 1
M.fields.melee_up_damage.applies_when = { "up_attacks" }
field("ranged_aim", "combat.aim.mode", "string", "Aim ranged attack", "eight follows the stick; four snaps to cardinal directions; facing restores straight shots.")
M.fields.ranged_aim.values = { facing = true, four = true, eight = true }
M.fields.ranged_aim.choices = { "facing", "four", "eight" }
field("aim_stance", "combat.aim.stance", "boolean", "Aim stance", "Hold Ranged while grounded to stop walking and aim with the stick; release to fire. Down + Ranged still places a usable bomb. Off fires on press.")
number("ranged_damage", "combat.ranged.damage", "Ranged damage", 0, 1000, "First projectile damage of Ranged shot (ranged_shot) only. Per-attack values in Attacks take precedence.")
number("ranged_projectile_speed", "combat.ranged.projectile_speed", "Projectile speed (px/s)", 0, 10000, "First projectile speed of Ranged shot (ranged_shot) only, in base pixels per second. Per-attack values in Attacks take precedence.", "ranged_speed")
number("melee_light_cooldown", "combat.melee_light.cooldown", "Light cooldown (seconds)", 0, 10, "Cooldown of the first light combo hit (light_1) only, in seconds. Per-attack values in Attacks take precedence.")
number("parry_window", "combat.parry.window", "Parry window (seconds)", 0, 5, "Parry window in seconds.")
number("parry_push", "combat.parry.knockback_px", "Parry push (px)", 0, 2000,
    "Pixels an enemy slides straight away from you after an ordinary parry, slowing to a stop during its stun. Its knockback resistance shortens the slide and walls stop it. Bosses never move, and a parried shot never pushes its shooter. 0 turns it off.")
number("perfect_parry_push", "combat.parry.perfect_knockback_px", "Perfect parry push (px)", 0, 2000,
    "Pixels an enemy slides straight away from you after a perfect parry, in place of Parry push. Its knockback resistance shortens the slide and walls stop it. Bosses never move, and a parried shot never pushes its shooter. 0 turns it off.")
for _, key in ipairs({"parry_push", "perfect_parry_push"}) do
    M.fields[key].step, M.fields[key].units = 8, "px"
end
M.fields.parry_push.applies_when = { "parry" }
M.fields.perfect_parry_push.applies_when = { "parry", "perfect_parry" }
number("damage_iframes", "player.damage_iframes", "After-hit invincibility (seconds)", 0, 5,
    "Seconds after the player is hurt during which further hits do no damage, lethal hits included. Damage over time, such as poison, keeps ticking. 0 turns it off. Player Size never changes it.")
number("slide_iframe_seconds", "player.slide.iframe_seconds", "Slide invincibility (seconds)", 0, 5,
    "Applies whenever Slide Invincibility is unlocked, at the start or by pickup. Seconds from the start of a slide during which hits do no damage, lethal hits included, never longer than the slide; 0 covers the whole slide. Damage over time, such as poison, keeps ticking. Player Size never changes it.")
number("air_dash_iframe_seconds", "player.air_dash.iframe_seconds", "Dash invincibility (seconds)", 0, 5,
    "Applies whenever Dash Invincibility is unlocked, at the start or by pickup. Seconds from the start of an air dash during which hits do no damage, lethal hits included, never longer than the dash; 0 covers the whole dash. Damage over time, such as poison, keeps ticking. Player Size never changes it.")
number("parry_iframes", "combat.parry.iframes", "After-parry invincibility (seconds)", 0, 3,
    "Seconds after a successful parry during which hits do no damage, lethal hits included. Damage over time, such as poison, keeps ticking. 0 turns it off. Player Size never changes it.")
for _, key in ipairs({"damage_iframes", "slide_iframe_seconds", "air_dash_iframe_seconds", "parry_iframes"}) do
    M.fields[key].step, M.fields[key].units = 0.05, "seconds"
end
for _, attack in ipairs({ "light", "heavy" }) do
    for _, dimension in ipairs({ "width", "height" }) do
        number(attack .. "_hitbox_" .. dimension, "combat.melee_" .. attack .. ".hitbox." .. dimension,
            (attack:gsub("^%l", string.upper)) .. " hitbox " .. dimension .. " (px)", 1, 10000, "First hitbox " .. dimension .. " of " .. (attack == "light" and "the first light combo hit (light_1)" or "Heavy (heavy_1)") .. " only, in base pixels. Per-attack values in Attacks take precedence.")
    end
end
for _, key in ipairs({ "combo_chaining", "mixed_finishers", "attack_cancels", "parry", "perfect_parry", "parry_counter", "aerial_attacks", "aerial_juggle", "up_attacks", "cut_projectiles", "parry_reflects", "parry_tells" }) do
    boolean(key, "combat.features." .. key, ((key:gsub("_", " ")):gsub("^%l", string.upper)), "Enable " .. key:gsub("_", " ") .. ".")
end
-- These children retain their saved values when their parent feature is off;
-- the editor explains the same gates already applied by controls() above.
M.fields.mixed_finishers.applies_when = { "combo_chaining" }
M.fields.perfect_parry.applies_when = { "parry" }
M.fields.parry_counter.applies_when = { "parry" }
M.fields.parry_reflects.applies_when = { "parry", "perfect_parry" }
M.fields.parry_reflects.title = "Parry reflects shots"
M.fields.parry_reflects.label = "Parry reflects shots"
M.fields.parry_reflects.help = "Perfect parries return shots whose enemy or boss pattern sets Projectile deflect to reflect."
M.fields.parry_tells.help = "Show configured parry colours on melee windups, enemy shots and parryable boss telegraphs. Off by default."
M.fields.aerial_juggle.applies_when = { "aerial_attacks" }
boolean("camera_shake", "game_settings.camera_shake", "Camera shake", "Default camera shake; player preferences may override it.")
boolean("pause_on_focus_loss", "game_settings.pause_on_focus_loss", "Pause on focus loss", "Open Pause when gameplay loses focus or is minimised. Returning never resumes automatically; player preferences may override it.")
boolean("pause_on_controller_disconnect", "game_settings.pause_on_controller_disconnect", "Pause when the controller disconnects", "Pause when the active controller was the last input device and disconnects. Player preferences may override it.")
boolean("mute_when_unfocused", "game_settings.mute_when_unfocused", "Mute in the background", "Silence gameplay audio while unfocused, preserving saved mute and volumes. Player preferences may override it.")
boolean("damage_numbers", "game_settings.damage_numbers", "Damage numbers", "Default damage number visibility.")
boolean("hazard_return_enabled", "progression.hazard_return.enabled", "Hazard returns", "Return spikes and pits to a safe point; off restores damage or lethal pits.")
number("hazard_return_damage", "progression.hazard_return.damage", "Return damage", 0, 100, "Health cost before a return; a lethal cost follows normal death.")
number("hazard_return_fade_time", "progression.hazard_return.fade_time", "Return fade (seconds)", 0, 2, "Seconds for each fade; zero is instant.")
number("hazard_return_grace_time", "progression.hazard_return.grace_time", "Protection after return (seconds)", 0, 5, "Protection after landing at a return target.")
M.fields.hazard_return_damage.step = 1
M.fields.hazard_return_fade_time.step = 0.05
M.fields.hazard_return_grace_time.step = 0.1
for _, key in ipairs({"hazard_return_damage", "hazard_return_fade_time", "hazard_return_grace_time"}) do
    M.fields[key].applies_when = {"hazard_return_enabled"}
end

boolean("death_drop_enabled", "progression.death.drop_enabled", "Death drop",
    "On: dying drops part of your currency where you died; collect it to get it back. Dying again before collecting it loses it. Off: you respawn with everything you had at your last save.")
number("death_currency_fraction", "progression.death.currency_loss_fraction", "Currency dropped", 0, 1,
    "After restoring your last save, drop this fraction of the saved currency, rounded down. Minimum Dropped can raise the amount; it never exceeds the currency you hold or a configured maximum.")
number("death_minimum", "progression.death.min_loss", "Minimum dropped (currency)", 0, 100000,
    "Drop at least this much saved currency when Death drop is on. The fraction is rounded down first; the result never exceeds the currency you hold or a configured maximum.")
M.fields.death_drop_enabled.label, M.fields.death_drop_enabled.page = "Death drop", 5
M.fields.death_currency_fraction.label, M.fields.death_currency_fraction.page = "Currency Dropped", 5
M.fields.death_minimum.label, M.fields.death_minimum.page = "Minimum Dropped", 5
M.fields.death_currency_fraction.applies_when = { "death_drop_enabled" }
M.fields.death_minimum.applies_when = { "death_drop_enabled" }
M.fields.death_currency_fraction.step, M.fields.death_minimum.step = 0.05, 10
M.fields.death_minimum.units = "currency"
boolean("npc_markers_enabled", "npc_settings.markers.enabled", "New dialogue marker",
    "Show a marker above NPCs that opted in with Show new dialogue marker while they have lines you have not heard; talking clears it. The marker text is in developer/config/npc_settings.lua.")
boolean("npc_barks_enabled", "npc_settings.barks.enabled", "Ambient lines",
    "Show an NPC's Behavior > Barks lines, or its type's barks, above it when the player walks within its Bark range. An NPC showing the new dialogue marker does not bark.")
number("npc_bark_seconds", "npc_settings.barks.show_seconds", "Line time (seconds)", 1, 10,
    "Seconds each ambient line stays above the NPC. Its Bark cooldown starts when the line hides.")
M.fields.npc_bark_seconds.step = 0.5
M.fields.npc_bark_seconds.applies_when = { "npc_barks_enabled" }
number("shop_sell_share", "shops.settings.sell_share", "Sell price share", 0, 1,
    "Stores buy eligible items for this share of their items.lua price, rounded down. Default 0.5; each store can override it. Zero-value items are hidden. Values above 1 are refused; keep discounted catalog prices at least as high as their sale value.")
M.fields.shop_sell_share.step = 0.05
boolean("leveling_enabled", "leveling.enabled", "Leveling", "Award XP, grow stats and show levels in Journal Records. Ships off.")
number("leveling_max_level", "leveling.max_level", "Maximum level", 1, 99, "Highest level and XP cap.")
number("leveling_first_level_xp", "leveling.curve.first", "First level XP", 1, 100000, "Whole XP needed from level 1 to 2.")
number("leveling_xp_growth", "leveling.curve.growth", "XP growth", 1, 3, "Multiplier for each next level's XP requirement.")
number("leveling_enemy_xp", "leveling.sources.enemy_default", "Enemy XP", 0, 10000, "Default XP when the enemy has no instance or type XP.")
number("leveling_boss_xp", "leveling.sources.boss_default", "Boss XP", 0, 100000, "Default XP when a boss has no positive reward XP.")
number("leveling_health_per_level", "leveling.per_level.max_health", "Health per level", 0, 5, "Capacity growth per level above 1; the total rounds down.")
boolean("leveling_full_heal", "leveling.level_up.full_heal", "Full heal", "Fully heal once after a gain that crosses one or more levels.")
for _, key in ipairs({"leveling_max_level", "leveling_first_level_xp", "leveling_xp_growth", "leveling_enemy_xp", "leveling_boss_xp", "leveling_health_per_level", "leveling_full_heal"}) do
    M.fields[key].applies_when = {"leveling_enabled"}
end
for _, key in ipairs({"leveling_max_level", "leveling_first_level_xp", "leveling_enemy_xp", "leveling_boss_xp"}) do
    M.fields[key].editor_integer, M.fields[key].step = true, 1
end
M.fields.leveling_first_level_xp.step = 10
M.fields.leveling_xp_growth.step = 0.05
M.fields.leveling_health_per_level.step = 0.25

boolean("weapons_quick_switch", "weapons.quick_switch", "Quick switch", "Allow Next Weapon to cycle owned weapons with C or Left Stick click. Players can remap it in Settings > Controls.")
boolean("weapons_enabled", "weapons.enabled", "Weapons", "Enable owned weapons and their attack sets. Disabled weapon pickups stay in place. Configure the ordered list in weapons.lua.")
field("weapons_starting", "weapons.starting_weapon", "string", "Starting weapon", "A virtual starting weapon, never added to Inventory. Blank uses the unarmed moveset. Choices follow weapons.lua.")
do
    local choices, labels = {""}, {[""]="Unarmed"}
    for _, entry in ipairs(require("developer.config.weapons").weapons) do
        choices[#choices + 1], labels[entry.id] = entry.id, entry.name
    end
    M.fields.weapons_starting.choices, M.fields.weapons_starting.choice_labels = choices, labels
end
boolean("charms_enabled", "charms.enabled", "Charms", "Enable charms with limited equipment slots. Change charms anywhere in the Inventory. Disabled pickups stay in place; definitions and effects are in charms.lua.")
number("charms_base_slots", "charms.base_slots", "Base slots", 0, 20, "Starting charm slot capacity before Charm Slot pickups.")
number("charms_max_slots", "charms.max_slots", "Maximum slots", 1, 20, "Maximum capacity including Charm Slot pickups. Charm slot costs use this shared capacity.")
for _, key in ipairs({"charms_base_slots", "charms_max_slots"}) do
    M.fields[key].integer, M.fields[key].editor_integer, M.fields[key].step = true, true, 1
    M.fields[key].applies_when = {"charms_enabled"}
end
boolean("crafting_enabled", "crafting.enabled", "Crafting", "Enable weapon tier and charm recipes in Inventory > Crafting. Costs and outputs are in crafting.lua; weapon tier scaling is in weapons.lua.")
boolean("random_drops_enabled", "random_drops.enabled", "Random drops", "Defeated enemies can leave one extra unowned weapon, charm or permanent upgrade. Pickups left behind are not saved. Ships off.")
number("random_drops_chance", "random_drops.chance", "Chance per defeat", 0, 1, "Chance per enemy defeat. Enemy types can override it with random_drop_chance; 0 means never.")
M.fields.random_drops_chance.step = 0.01
boolean("random_drops_weapons", "random_drops.weapons", "Weapons", "Include eligible weapons when Weapons is on. Exclude story or gate items with random_drop = false in weapons.lua.")
boolean("random_drops_charms", "random_drops.charms", "Charms", "Include eligible charms when Charms is on. Exclude items with random_drop = false in charms.lua.")
boolean("random_drops_upgrades", "random_drops.upgrades", "Permanent upgrades", "Include unapplied upgrades whose prerequisites are met. Exclude items with random_drop = false in upgrades.lua.")
for _, key in ipairs({"random_drops_chance", "random_drops_weapons", "random_drops_charms", "random_drops_upgrades"}) do
    M.fields[key].applies_when = {"random_drops_enabled"}
end

boolean("powerups_enabled", "powerups.enabled", "Power-ups", "Enable temporary world pickups. Timers stop while paused and clear at death. Configure names, effects and duration in powerups.lua.")
boolean("completion_enabled", "completion_tracking.enabled", "Enabled", "Derive weighted completion from the published world census. Configure category weights in completion_tracking.lua.")
boolean("completion_show_on_ending", "completion_tracking.show_on_ending", "Show on ending", "Capture the completion percentage on the first ending page.")
boolean("completion_show_in_journal", "completion_tracking.show_in_journal", "Show in Journal", "Show category counts and the percentage in Journal > Records.")
for _,key in ipairs({"completion_show_on_ending","completion_show_in_journal"}) do M.fields[key].applies_when={"completion_enabled"} end
boolean("quests_enabled", "quests.enabled", "Quests", "Track save-slot quests from quests.lua. Ships off; objectives can use flags, items, game events, other quests or levels.")
boolean("quests_notify", "quests.notify", "Quest notices", "Show a notice when a quest starts, advances, completes or fails.")
M.fields.quests_notify.applies_when = {"quests_enabled"}
boolean("goals_enabled", "goals.enabled", "Goals", "Track the ordered goals in goals.lua: the player's current main objective. Ships off; works with Quests off.")
boolean("goals_hint_reveals_target", "goals.hint_reveals_target", "Hints reveal targets", "A Hint Stone with Reveal goal target ticked marks the current goal's target on the map.")
M.fields.goals_hint_reveals_target.applies_when = {"goals_enabled"}
boolean("achievements_enabled", "achievements.enabled", "Achievements", "Track goals across every save slot in this game. Ships off; definitions and rewards are in achievements.lua.")
boolean("achievements_notify", "achievements.notify", "Unlock notices", "Show an achievement notice. When off, the configured unlock sound still plays.")
boolean("achievements_show_hidden_count", "achievements.show_hidden_count", "Show hidden count", "Include the number of hidden goals in the Journal summary.")
for _,key in ipairs({"achievements_notify", "achievements_show_hidden_count"}) do M.fields[key].applies_when={"achievements_enabled"} end

boolean("bestiary_enabled", "bestiary.enabled", "Bestiary",
    "Enable first-entry notices. Defeats are recorded even while off; names and recording options are in bestiary.lua.")
boolean("people_enabled", "npc_settings.people.enabled", "People",
    "Show Journal > People: who the player has talked to, with a short bio and the last thing they said. Ships off. A person is an npc_types.lua type with a journal block; the tab stays hidden while no type has one.")
boolean("people_show_unmet", "npc_settings.people.show_unmet", "Show people not met",
    "List people the player has not talked to yet as ??? rows. When off, a person appears after the first talk.")
M.fields.people_show_unmet.applies_when = {"people_enabled"}

number("trial_countdown", "trial_settings.countdown", "Countdown (seconds)", 0, 10,
    "Seconds before a trial starts its Encounter. Zero starts immediately.")
M.fields.trial_countdown.step, M.fields.trial_countdown.editor_integer = 1, true
boolean("trial_restore_health", "trial_settings.restore_health", "Restore health on clear",
    "Restore starting health after a trial clear. Failure always restores starting health.")
boolean("trial_autosave", "trial_settings.autosave_on_clear", "Save on clear",
    "Save the result and first-clear reward together after a successful trial.")

boolean("countdown_autosave", "countdowns.autosave_on_finish", "Save on finish",
    "Save the finish flag, best time and first-finish reward together when a countdown is finished.")
number("countdown_tenths_below", "countdowns.tenths_below", "Tenths below (seconds)", 0, 60,
    "The countdown clock shows tenths of a second below this many seconds left. Zero always shows whole seconds.")
M.fields.countdown_tenths_below.step, M.fields.countdown_tenths_below.editor_integer = 1, true

boolean("ng_plus_enabled", "new_game_plus.enabled", "Enabled",
    "Offer New Game+ on completed save slots. Rewrites the same slot after a verified backup; ships off.")
number("ng_plus_enemy_health_mult", "new_game_plus.cycles.1.enemy_health_mult", "Enemy health multiplier", 1, 5,
    "Enemy health factor for cycle 1, multiplied by the chosen difficulty. Later cycles live in new_game_plus.lua.")
number("ng_plus_damage_taken_mult", "new_game_plus.cycles.1.damage_taken_mult", "Damage taken multiplier", 1, 5,
    "Player damage taken factor for cycle 1, multiplied by the chosen difficulty. Later cycles live in new_game_plus.lua.")
boolean("ng_plus_carry_level", "new_game_plus.carry.level", "Carry level",
    "Keep level and total experience when leveling is on.")
boolean("ng_plus_carry_equipment", "new_game_plus.carry.equipment", "Carry equipment",
    "Keep owned weapons, charms, equipped gear, charm slots and weapon tiers.")
boolean("ng_plus_carry_currency", "new_game_plus.carry.currency", "Carry currency",
    "Keep the wallet and bank balance in the next cycle.")
for _, key in ipairs({"ng_plus_enemy_health_mult", "ng_plus_damage_taken_mult", "ng_plus_carry_equipment", "ng_plus_carry_currency"}) do
    M.fields[key].applies_when = {"ng_plus_enabled"}
end
M.fields.ng_plus_carry_level.applies_when = {"ng_plus_enabled", "leveling_enabled"}
M.fields.ng_plus_enemy_health_mult.step, M.fields.ng_plus_damage_taken_mult.step = 0.1, 0.1

boolean("extras_enabled", "extras.enabled", "Enabled",
    "Keep cross-save Extras unlocks for this game: tracks heard, flag unlocks and New Game+ cycles. Ships off; track and image lists live in developer/config/extras.lua.")
boolean("extras_notify", "extras.notify", "Unlock notices",
    "Show a notice when an entry with a flag unlock unlocks during play. Endings, achievements and heard tracks never show one.")
boolean("extras_show_locked", "extras.show_locked", "Show locked entries",
    "Show locked entries as ???. Off hides them until they unlock.")
boolean("extras_jukebox", "extras.jukebox.enabled", "Jukebox",
    "Offer the Jukebox tab for the tracks listed in extras.lua.")
boolean("extras_gallery", "extras.gallery.enabled", "Gallery",
    "Offer the Gallery tab for the images listed in extras.lua.")
boolean("extras_credits", "extras.credits.enabled", "Credits",
    "Offer one Credits row for each ending seen in any save slot of this game.")
for _, key in ipairs({"extras_notify", "extras_show_locked", "extras_jukebox", "extras_gallery", "extras_credits"}) do
    M.fields[key].applies_when = {"extras_enabled"}
end

boolean("records_statistics", "run_stats.show_in_records", "Statistics in Records",
    "Show deaths, enemy and boss defeats, permanent pickups, secrets, visited rooms and completed quests in Journal Records. Counts are recorded even while hidden.")
boolean("records_on_ending", "run_stats.show_on_ending", "Time on ending",
    "Use in-game time in the optional ending presentation, independently of Records visibility.")
field("icon_theme", "game_settings.icon_theme", "string", "Icon theme", "Controller prompt artwork: xbox, playstation, or switch.")
M.fields.icon_theme.values = { xbox = true, playstation = true, switch = true }
M.fields.icon_theme.choices = { "xbox", "playstation", "switch" }
for id, ability in pairs(AbilityConfig.abilities or {}) do
    local name = type(ability) == "table" and ability.name or id
    local description = type(ability) == "table" and ability.description or nil
    boolean(id .. "_enabled", "abilities." .. id, sentence(name), (description and (name .. ": " .. description .. ". ") or "")
        .. "Checked starts new games with " .. name .. " unlocked. Unchecked: the player finds it as a pickup. Its settings on the Advanced and Grapple pages apply either way.")
end
-- These labels are the authored Abilities-page labels. Registry names remain
-- the source for every other ability, including future configured abilities.
M.fields.air_dash_iframes_enabled.title = "Dash invincibility"
M.fields.slide_iframes_enabled.title = "Slide invincibility"
for key, name in pairs({ air_jumps = "Double Jump", slide_speed = "Slide", air_dash_speed = "Air Dash",
    air_dash_directions = "Air Dash", air_dash_suspend_gravity = "Air Dash",
    air_dash_count = "Air Dash", wall_climb_speed = "Wall Climb", wall_cling_fall_speed = "Wall Climb",
    high_jump_height_mult = "High Jump", super_jump_charge_time = "Super Jump", super_jump_height_mult = "Super Jump",
    blink_distance = "Blink", blink_chain_grace = "Blink" }) do
    M.fields[key].help = M.fields[key].help .. " Applies whenever " .. name .. " is unlocked — at the start or by pickup."
end

-- Numeric presentation metadata is shared with editor controls.
for key, step in pairs({
    player_scale = 0.05,
    walk_speed = 25,
    run_speed = 50,
    jump_height = 8,
    gravity = 50,
    max_health = 1,
    max_energy = 1,
    max_stamina = 10,
    air_accel_mult = 0.05,
    coyote_time = 0.02,
    attack_buffer = 0.01,
    air_jumps = 1,
    slide_speed = 100,
    air_dash_speed = 100,
    air_dash_count = 1,
    wall_climb_speed = 50,
    wall_cling_fall_speed = 25,
    high_jump_height_mult = 0.05,
    super_jump_charge_time = 0.05,
    super_jump_height_mult = 0.1,
    blink_distance = 25,
    blink_chain_grace = 0.01,
    melee_light_damage = 1,
    melee_light_cooldown = 0.02,
    melee_heavy_damage = 1,
    ranged_damage = 1,
    ranged_projectile_speed = 100,
    parry_window = 0.02,
    death_currency_fraction = 0.05,
    death_minimum = 10,
    grapple_range = 32,
    grapple_hook_speed = 50,
    grapple_swing_strength = 100,
    grapple_swing_speed = 50,
    grapple_swing_fade = 0.01,
    grapple_pump_start_speed = 5,
    grapple_counter_brake = 0.05,
    grapple_reel_speed = 20,
    grapple_pull_speed = 50,
    grapple_momentum = 0.05,
    grapple_release_carry = 0.05,
    grapple_release_float = 0.05,
    grapple_release_boost = 25,
    grapple_release_lift = 25,
    grapple_rehook_window = 0.05,
}) do M.fields[key].step = step end
-- Present counts as integers while preserving older fractional documents.
for _, key in ipairs({"max_health", "max_energy", "max_stamina", "air_jumps", "air_dash_count"}) do
    M.fields[key].editor_integer = true
end

local defaults = {
    ng_plus_enabled=false, ng_plus_enemy_health_mult=1.5, ng_plus_damage_taken_mult=1.5,
    ng_plus_carry_level=true, ng_plus_carry_equipment=true, ng_plus_carry_currency=true,
    extras_enabled=false, extras_notify=true, extras_show_locked=true,
    extras_jukebox=true, extras_gallery=true, extras_credits=true,
    charms_enabled=false, charms_base_slots=3, charms_max_slots=9,
    random_drops_enabled=false, random_drops_chance=0.02, random_drops_weapons=true, random_drops_charms=true, random_drops_upgrades=true,
    crafting_enabled=false, powerups_enabled=false, weapons_enabled=false, weapons_quick_switch=true, weapons_starting="training_blade",
    completion_enabled=false, completion_show_on_ending=true, completion_show_in_journal=true,
    quests_enabled=false, quests_notify=true,
    goals_enabled=false, goals_hint_reveals_target=true,
    achievements_enabled=false, achievements_notify=true, achievements_show_hidden_count=true,
    trial_countdown=3, trial_restore_health=true, trial_autosave=true,
    countdown_autosave=true, countdown_tenths_below=10,
    bestiary_enabled=false, people_enabled=false, people_show_unmet=true, records_statistics=false, records_on_ending=false,
    health_fragment_pieces=4, energy_fragment_pieces=3,
    cut_projectiles=false, parry_reflects=false, parry_tells=false,
    enemy_default_archetype="slime",
    enemy_cap_per_room=25,
    enemy_ledge_behavior="stop",
    enemy_fall_gravity=require("developer.config.enemy_defaults").fall_gravity_tiles,
    enemy_respawn_policy="room_reload",
    enemy_autosave_on_permanent_defeat=false,
    lantern_radius=280, lantern_intensity=0.9, lantern_flicker=0.08, lantern_min_darkness=0.2,
    zip_hang_offset=40, zip_release_on_jump=true, hang_bar_offset=0,
    ice_accel=0.35, ice_decel=0.08, ice_turn=0.15,
    difficulty_selection="new_game", difficulty_default="normal",
    healing_model="flask", heal_charges=2, heal_amount=2,
    heal_channel_amount=1, heal_cost=1, heal_channel_time=0.8,
    energy_from_combat=false, energy_on_hit=0.25, energy_on_parry=0.5,
    energy_on_perfect_parry=1, energy_on_defeat=0.25,
    player_scale=1, scale_movement=true, walk_speed=1200, run_speed=2000,
    jump_height=256, gravity=-2400, max_health=5, max_energy=3, max_stamina=100,
    air_accel_mult=0.8, coyote_time=0.12, attack_buffer=0.15, air_jumps=1,
    slide_speed=2200, air_dash_speed=1800, air_dash_count=1, wall_climb_speed=600,
    air_dash_directions="eight", air_dash_suspend_gravity=true, extra_air_dash_bonus=1,
    wall_cling_fall_speed=0, high_jump_height_mult=1.5, super_jump_charge_time=0.6, super_jump_height_mult=3,
    blink_distance=200, blink_chain_grace=0.08, melee_light_damage=1,
    ranged_aim="eight", aim_stance=false, melee_up_damage=1,
    melee_heavy_damage=2, ranged_damage=1, ranged_projectile_speed=1200,
    melee_light_cooldown=0.18, parry_window=0.18, parry_push=32, perfect_parry_push=128, camera_shake=true,
    damage_iframes=0.8, slide_iframe_seconds=0, air_dash_iframe_seconds=0, parry_iframes=0.30,
    hazard_return_enabled=true, hazard_return_damage=1, hazard_return_fade_time=0.25, hazard_return_grace_time=1,
    shop_sell_share=0.5, npc_markers_enabled=true, npc_barks_enabled=true, npc_bark_seconds=3, damage_numbers=false, death_drop_enabled=false, death_currency_fraction=0.20, death_minimum=0,
    pause_on_focus_loss=true, pause_on_controller_disconnect=true, mute_when_unfocused=false,
    icon_theme="xbox", light_hitbox_width=120,
    light_hitbox_height=100, heavy_hitbox_width=154, heavy_hitbox_height=116,
}
for key, spec in pairs(M.fields) do
    if spec.default == nil then spec.default = defaults[key] end
    if spec.default == nil and spec.type == "boolean" then
        local ability = AbilityConfig.abilities[key:gsub("_enabled$", "")]
        spec.default = ability and ability.starts_unlocked == true or not ability
    end
    spec.label = spec.label or key:gsub("_enabled$", ""):gsub("_", " ")
    spec.owner = "creator"
    spec.scope = Product.id
    spec.rebuild = true
    spec.units = spec.units or (spec.type ~= "number" and "" or
        (key:find("speed") and "base px/s" or key == "gravity" and "base px/s^2"
        or (key:find("time") or key:find("window") or key:find("cooldown") or key:find("buffer")) and "seconds"
        or (key:find("height") or key:find("width") or key:find("range")) and "base px" or ""))
end

-- Keep both old base-pixel values and their converted values valid. Widen the
-- bound farthest from zero; numeric steps follow the new units.
local scaled_fields = { ["combat.ranged.projectile_speed"] = true }
for _, paths in pairs(PlayerScale.SCALED_KEYS) do
    for _, path in ipairs(paths) do scaled_fields["player." .. path] = true end
end
for _, attack in ipairs({ "light", "heavy" }) do
    for _, axis in ipairs({ "width", "height" }) do
        scaled_fields["combat.melee_" .. attack .. ".hitbox." .. axis] = true
    end
end
for _, spec in pairs(M.fields) do
    if scaled_fields[spec.path] then
        if spec.default ~= nil then spec.default = spec.default * 1.75 end
        if spec.min and spec.max then
            if math.abs(spec.min) > math.abs(spec.max) then
                spec.min = spec.min * 1.75
            else spec.max = spec.max * 1.75 end
        end
        if spec.step then spec.step = spec.step * 1.75 end
    end
end

-- Toggle groups and ordering feed the editor layout and ability categories.
local function toggle(key, group, order)
    M.fields[key].toggle = { group=group, order=order }
end
toggle("camera_shake", "game", 1)
toggle("damage_numbers", "game", 2)
toggle("death_drop_enabled", "game", 3)
toggle("combo_chaining", "feature", 1)
toggle("mixed_finishers", "feature", 2)
toggle("attack_cancels", "feature", 3)
toggle("parry", "feature", 4)
toggle("perfect_parry", "feature", 5)
toggle("parry_counter", "feature", 6)
toggle("aerial_attacks", "feature", 7)
toggle("aerial_juggle", "feature", 8)
toggle("up_attacks", "feature", 9)
toggle("cut_projectiles", "feature", 10)
toggle("parry_reflects", "feature", 11)
toggle("parry_tells", "feature", 12)
toggle("grapple_stay_hooked", "grapple", 1)
toggle("grapple_reel", "grapple", 2)
toggle("grapple_break_on_impact", "grapple", 3)
toggle("grapple_walls", "grapple", 4)
-- Registry order (movement, combat, defensive, then other categories) keeps
-- keyboard/controller navigation aligned with the grouped Abilities page.
for i, entry in ipairs(require("developer.tools.ability_defaults_writer").ordered_abilities()) do
    toggle(entry.id .. "_enabled", "ability", i)
    M.fields[entry.id .. "_enabled"].toggle.category = entry.category or "other"
end
M.fields.healing_enabled.help = "Unlock the built-in flask or channel heal at a new game. Has no effect under Healing = items; owned potions never need this ability."
function M.toggle_fields(group)
    local out = {}
    for key,spec in pairs(M.fields) do
        if spec.toggle and spec.toggle.group == group then
            local field = M.copy(spec.toggle)
            field.key, field.default = key, spec.default
            field.page, field.applies_when = spec.page, M.copy(spec.applies_when)
            field.help, field.units, field.name = spec.help, spec.units, spec.label
            field.id = key:gsub("_enabled$", "")
            out[#out+1] = field
        end
    end
    table.sort(out, function(a,b) return a.order < b.order end)
    return out
end

for _,spec in ipairs(require("developer.tools.designer_fields").fields) do M.fields[spec.key]=spec end
M.fields.hud_currency_format.check = require("mvtk.core.currency_format").valid

local function validate_value(key, value, spec)
    assert(type(value) == spec.type, key .. " must be a " .. spec.type)
    if spec.type == "number" then
        assert(value == value and value > -math.huge and value < math.huge, key .. " must be finite")
        assert(value >= spec.min and value <= spec.max, key .. " is outside its supported range")
        assert(not spec.integer or value==math.floor(value),key.." must be a whole number")
    elseif spec.values then assert(spec.values[value], key .. " has an unsupported value") end
    if spec.check then
        local valid, message = spec.check(value)
        assert(valid, message)
    end
end

-- Also validates that unknown preserved data can be safely serialized.
local function encode(value, indent, ancestors, comments, path)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then
        assert(value == value and value > -math.huge and value < math.huge, "Non-finite settings value")
        -- Never write "-0". Lua 5.1 keeps one constant per numeric value in a chunk and 0 == -0, so a
        -- single "-0" makes every later literal 0 in the written file load as -0 (and the reverse), and
        -- the file no longer re-encodes to its own text (world layouts rewrote their backup each publish).
        if value == 0 then return "0" end
        return Number.general(value)
    end
    assert(kind == "table", "Settings contain unsupported " .. kind .. " data")
    assert(not ancestors[value], "Settings contain a cycle")
    ancestors[value] = true
    local keys = {}
    for k in pairs(value) do
        assert(type(k) == "string" or (type(k) == "number" and k == math.floor(k)), "Unsupported settings key")
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return type(a) == type(b) and a < b or type(a) < type(b) end)
    local rows = { "{" }
    for _, k in ipairs(keys) do
        local full = path == "" and tostring(k) or path .. "." .. tostring(k)
        if comments and comments[full] then rows[#rows + 1] = indent .. "    -- " .. comments[full] end
        local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
        rows[#rows + 1] = indent .. "    " .. key .. " = " .. encode(value[k], indent .. "    ", ancestors, comments, full) .. ","
    end
    rows[#rows + 1] = indent .. "}"
    ancestors[value] = nil
    return table.concat(rows, "\n")
end

function M.encode(value, comments)
    -- A single argument expression can forward load_document's second boolean
    -- result. Ignore incidental non-table extras as the old wrapper did.
    return encode(value, "", {}, type(comments) == "table" and comments or nil, "")
end

function M.validate(doc)
    assert(type(doc) == "table" and doc.version == M.VERSION, "Unsupported creator settings version")
    assert(doc.player_units == nil or doc.player_units == 1 or doc.player_units == 2,
        "player_units must be 1 or 2 (absent means 1)")
    assert(type(doc.overrides) == "table", "Creator settings overrides must be a table")
    assert(doc.published == nil or type(doc.published) == "boolean", "published must be a boolean")
    M.encode(doc)
    for key, spec in pairs(M.fields) do
        local parent = doc.overrides
        local prefix = spec.path:match("^(.*)%.[^.]+$")
        for part in prefix:gmatch("[^.]+") do
            if parent == nil then break end
            assert(type(parent) == "table", "Invalid settings section for " .. spec.path)
            parent = parent[tonumber(part) or part]
        end
        assert(parent == nil or type(parent) == "table", "Invalid settings section for " .. spec.path)
        local value = get(doc.overrides, spec.path)
        if value ~= nil then validate_value(key, value, spec) end
    end
    AttackSettings.resolve(AttackConfig, (doc.overrides.combat or {}).attacks, DamageTypes)
    return doc
end

-- Pixel-unit markers are independent of the unchanged version-1 document schema.
function M.baseline_units(baseline_player)
    local units = baseline_player and baseline_player.units_version or 1
    assert(units == 1 or units == 2, "player_settings.units_version must be 1 or 2")
    return units
end

function M.needs_player_units_migration(doc, baseline_player)
    return (doc.player_units or 1) == 1 and M.baseline_units(baseline_player) == 2
end

function M.migrate(doc, baseline_player)
    M.validate(doc)
    if not M.needs_player_units_migration(doc, baseline_player) then return doc, false end
    local converted = M.copy(doc)
    local old_player = doc.overrides.player or {}
    local old_scale = old_player.player_scale or OldPlayerUnits.player_scale
    local new_scale = old_scale / 1.75
    local movement = old_player.scale_movement
    if movement == nil then movement = OldPlayerUnits.scale_movement end
    if old_player.player_scale ~= nil then put(converted.overrides, "player.player_scale", new_scale) end
    local function solve(path, old_base, new_base, scaled)
        local override = get(doc.overrides, path)
        local old_value = override ~= nil and override or old_base
        if type(old_value) ~= "number" then return end
        local old_effective = old_value * (scaled and old_scale or 1)
        local new_factor = scaled and new_scale or 1
        local new_effective = type(new_base) == "number" and new_base * new_factor or nil
        if new_effective == nil or math.abs(old_effective - new_effective)
            > 1e-6 * math.max(math.abs(old_effective), math.abs(new_effective), 1) then
            put(converted.overrides, path, old_effective / new_factor)
        else remove(converted.overrides, path) end
    end
    for family, paths in pairs(CreatorPixelPaths) do
        for _, path in ipairs(paths) do
            if family == "always" then
                local override = get(doc.overrides, path)
                if type(override) == "number" then
                    put(converted.overrides, path, override * 1.75)
                end
            else
                local player_path = path:match("^player%.(.+)$")
                local old_base, new_base
                if player_path then
                    old_base, new_base = get(OldPlayerUnits, player_path), get(baseline_player, player_path)
                else
                    old_base, new_base = OldPlayerUnits.ranged_projectile_speed,
                        OldPlayerUnits.ranged_projectile_speed * 1.75
                end
                solve(path, old_base, new_base, movement ~= false)
            end
        end
    end
    converted.player_units = 2
    return M.validate(converted), true
end

-- Pure loader: no disk access, and no mutation when units already agree.
function M.load_document(doc, baseline_player)
    M.validate(doc)
    local baseline_units = M.baseline_units(baseline_player)
    if (doc.player_units or 1) == baseline_units then return doc, false end
    assert(not (doc.player_units == 2 and baseline_units == 1),
        "creator_settings.lua was saved for the new player units, but developer/config/player_settings.lua is from an older toolkit. Replace it with the toolkit's player_settings.lua (it has units_version = 2).")
    return M.migrate(doc, baseline_player)
end

function M.from_controls(values, previous, baseline_player)
    values = values or {}
    baseline_player = baseline_player or require "developer.config.player_settings"
    local doc = M.copy(M.load_document(previous or {
        version = M.VERSION, player_units = M.baseline_units(baseline_player), overrides = {},
    }, baseline_player))
    doc.player_units = M.baseline_units(baseline_player)
    doc.published = true
    for key, spec in pairs(M.fields) do
        local value = values[key]
        if value == nil and spec.alias then value = values[spec.alias] end
        if value ~= nil then
            validate_value(key, value, spec)
            put(doc.overrides, spec.path, value)
        end
    end
    if values.wall_climb_speed ~= nil then put(doc.overrides, "player.wall_climb.speed", values.wall_climb_speed) end
    -- Starting availability is separate from the count used after acquisition.
    -- The player already gates extra jumps through AbilityManager.
    return M.validate(M.prune_legacy(doc))
end

function M.serialize(doc, baseline_player)
    baseline_player = baseline_player or require "developer.config.player_settings"
    doc = M.copy(M.load_document(doc, baseline_player))
    doc.player_units = M.baseline_units(baseline_player)
    local comments = {
        player_units = "Pixel-unit generation for player, combat and imported-art overrides (unitless): 1 = old base pixels, 2 = in-game-size base pixels; safe values 1 or 2.",
    }
    for _, spec in pairs(M.fields) do comments["overrides." .. spec.path] = spec.help end
    return "-- Project-owned settings. Saved by Project > Game Settings...\n"
        .. "-- Overrides are merged over the commented baseline configuration files.\n"
        .. "-- Remove a field to inherit its baseline value; preserve version.\n"
        .. "-- published=true enables these overrides; legacy local values require explicit import.\n"
        .. "return " .. encode(doc, "", {}, comments, "") .. "\n"
end

return M
