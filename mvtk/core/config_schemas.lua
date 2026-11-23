-- mvtk/core/config_schemas.lua
-- Validation schemas for all config files
-- Defines required fields, types, and validation rules

local SafeRequire = require "mvtk.core.safe_require"
local PlayerScale = require "mvtk.player.player_scale"
local Number = require "mvtk.editor.settings_number"
local CurrencyFormat = require "mvtk.core.currency_format"

local M = {}

-- One migration warning per config, even when both retired fields are present.
local function champion_checkbox_warnings(config, path)
    local champion = type(config) == "table" and config.champion
    if type(champion) == "table" and (champion.seal_room ~= nil or champion.show_bar ~= nil) then
        return {path .. ": champion.seal_room and champion.show_bar are ignored. "
            .. "Remove these fields; set each champion's Champion seal and Champion bar checkboxes in Tiled, "
            .. "then export the room and run Prepare & Check."}
    end
    return {}
end

M.accessibility = {
    name = "Accessibility", file = "config/accessibility.lua", allow_unknown = false,
    required = {
        player = { type = "table", fields = {
            text_size = { type = "number", range = {0.1, 10} },
            shake = { type = "string", values = {"auto", "full", "reduced", "off"} },
            flashes = { type = "string", values = {"full", "reduced", "off"} },
            freeze_frames = { type = "string", values = {"full", "reduced", "off"} },
            assist = { type = "table", fields = {
                damage_taken = { type = "number", range = {0, 1} },
                game_speed = { type = "number", range = {0.5, 1} },
                pit_rescue = { type = "boolean" },
            } },
        } },
        show = { type = "table", fields = {
            text_size = { type = "boolean" }, shake = { type = "boolean" },
            flashes = { type = "boolean" }, freeze_frames = { type = "boolean" },
            vibration = { type = "boolean" },
            toggles = { type = "boolean" },
        } },
        toggles = { type = "table", fields = {
            grab = { type = "boolean" }, grapple = { type = "boolean" }, heal = { type = "boolean" },
            run = { type = "boolean" }, glide = { type = "boolean" }, aim = { type = "boolean" },
        } },
        text_sizes = { type = "table" },
        captions = { type = "table", fields = {
            enabled = { type = "boolean" }, background = { type = "string", values = {"off", "dim", "solid"} },
            show_options = { type = "boolean" }, sound = { type = "boolean" },
            sound_seconds = { type = "number", range = {0, 60} },
            sound_repeat_gap = { type = "number", range = {0, 60} },
        } },
        assist = { type = "table", fields = {
            allowed = { type = "boolean" },
            record_use = { type = "boolean" }, block_achievements = { type = "boolean" },
            damage_taken = { type = "table" }, game_speed = { type = "table" },
            pit_damage = { type = "number", range = {0, 100} },
        } },
        reduced = { type = "table", fields = {
            shake = { type = "number", range = {0, 1} },
            freeze = { type = "number", range = {0, 1} },
            flash_alpha = { type = "number", range = {0, 1} },
            flash_min_seconds = { type = "number", range = {0, 60} },
            flash_min_gap = { type = "number", range = {0, 60} },
        } },
    },
    custom_validate = function(config)
        local errors, found = {}, false
        local sizes = type(config.text_sizes) == "table" and config.text_sizes or {}
        if #sizes == 0 then errors[#errors + 1] = "text_sizes must contain at least one scale" end
        for _, scale in ipairs(sizes) do
            if type(scale) ~= "number" or scale ~= scale or scale < 0.1 or scale > 10 then
                errors[#errors + 1] = "text_sizes must contain scales from 0.1 to 10"
            end
            if type(config.player) == "table" and scale == config.player.text_size then found = true end
        end
        if not found then errors[#errors + 1] = "player.text_size must be a text_sizes choice" end
        for key, minimum in pairs({damage_taken = 0, game_speed = 0.5}) do
            local values = type(config.assist) == "table" and config.assist[key] or nil
            local normal = false
            if type(values) ~= "table" or #values == 0 then
                errors[#errors + 1] = "assist." .. key .. " must contain choices"
            else
                for _, value in ipairs(values) do
                    if type(value) ~= "number" or value ~= value or value < minimum or value > 1 then
                        errors[#errors + 1] = "assist." .. key .. " must contain scales from " .. minimum .. " to 1"
                    end
                    if value == 1 then normal = true end
                end
                if not normal then errors[#errors + 1] = "assist." .. key .. " must include 1" end
            end
        end
        return errors, {}
    end,
}
M.enemy_defaults = {
    name="Enemy Defaults", file="config/enemy_defaults.lua", allow_unknown=true,
    required={champion={type="table", fields={
        health_mult={type="number", range={0.001,1000}},
        damage_mult={type="number", range={0.001,1000}},
        scale_mult={type="number", range={0.001,100}},
        engage_range={type="number", range={0,100000}},
        enrage_below={type="number", range={0,1}}, enrage_sfx={type="string"},
    }}},
    custom_validate=function(config)
        return {}, champion_checkbox_warnings(config, "developer/config/enemy_defaults.lua")
    end,
}
M.encounter_settings = {
    name="Encounters", file="config/encounter_settings.lua", allow_unknown=false,
    required={wave_delay={type="number", range={0,3600}}, max_alive={type="number", range={1,200}},
        spawn_telegraph_time={type="number", range={0,3600}}, telegraph_effect={type="string"},
        show_wave_messages={type="boolean"}, toast_duration={type="number", range={1.5,60}},
        autosave_on_clear={type="boolean"}},
    custom_validate=function(config)
        local errors = {}
        if type(config.max_alive) == "number" and config.max_alive % 1 ~= 0 then
            errors[#errors+1] = "max_alive must be a whole number"
        end
        local effect = config.telegraph_effect
        local effects = require "developer.config.fx_types"
        if type(effect) == "string" and effect ~= "" and not (effects.effects[effect] or effects.aliases[effect]) then
            errors[#errors+1] = "telegraph_effect must name an fx_types.lua effect or be blank"
        end
        return errors, {}
    end,
}
M.status_effects = {
    name="Status Effects", file="config/status_effects.lua", allow_unknown=false,
    required={enabled={type="boolean"}, defaults={type="table"}, effects={type="table"},
        player={type="table"}, bosses={type="table"}, feedback={type="table"}},
    custom_validate=function(config)
        local errors = {}
        local function bad(path) errors[#errors+1] = path.." is invalid" end
        local function number(value, min, max, path, positive)
            if type(value) ~= "number" or value ~= value or value == math.huge
                or value < min or value > max or (positive and value == 0) then bad(path) end
        end
        local effects = type(config.effects) == "table" and config.effects or {}
        local defaults = type(config.defaults) == "table" and config.defaults or {}
        for _, key in ipairs({"tick_interval","refresh_interval"}) do
            number(defaults[key],0,math.huge,"defaults."..key,true)
        end
        for id, def in pairs(effects) do
            local path = "effects."..tostring(id)
            if type(id) ~= "string" or id == "none" or not id:match("^[A-Za-z0-9_][A-Za-z0-9_.%-]*$") then bad(path) end
            if type(def) ~= "table" then bad(path)
            else
                number(def.duration,0,math.huge,path..".duration",true)
                if type(def.label) ~= "string" or def.label == "" then bad(path..".label") end
                if type(def.color) ~= "table" or #def.color ~= 3 then bad(path..".color")
                else for i=1,3 do number(def.color[i],0,1,path..".color") end end
                if def.move ~= nil then number(def.move,0.25,1,path..".move") end
                if def.tick_interval ~= nil then number(def.tick_interval,0,math.huge,path..".tick_interval",true) end
                if def.damage_per_tick ~= nil then
                    number(def.damage_per_tick,0,math.huge,path..".damage_per_tick")
                    if not require("developer.config.damage_types").types[def.damage_type] then bad(path..".damage_type") end
                end
                if def.max_stacks ~= nil then
                    number(def.max_stacks,1,math.huge,path..".max_stacks")
                    if type(def.max_stacks) == "number" and def.max_stacks%1 ~= 0 then bad(path..".max_stacks") end
                end
                if def.stops_enemies ~= nil and type(def.stops_enemies) ~= "boolean" then bad(path..".stops_enemies") end
            end
        end
        for _, kind in ipairs({"player","bosses"}) do
            local entry = type(config[kind]) == "table" and config[kind] or {}
            if type(entry.immune) ~= "table" then bad(kind..".immune")
            else
                for key, value in pairs(entry.immune) do
                    local id = type(key) == "number" and value or key
                    if not effects[id] or (type(key) ~= "number" and value ~= true) then bad(kind..".immune") end
                end
            end
            if kind == "bosses" then number(entry.min_move_multiplier,0.25,1,"bosses.min_move_multiplier") end
        end
        local feedback = type(config.feedback) == "table" and config.feedback or {}
        if type(feedback.tint) ~= "boolean" then bad("feedback.tint") end
        number(feedback.flash_duration,0,math.huge,"feedback.flash_duration",true)
        return errors, {}
    end,
}
M.damage_types = {
    name = "Damage Types", file = "config/damage_types.lua", allow_unknown = false,
    required = {
        weak_multiplier = {type="number", range={1,10}},
        resist_multiplier = {type="number", range={0,1}},
        types = {type="table"}, player_taken = {type="table"}, ability_taken = {type="table"},
        tag_multipliers = {type="table"}, player_attacks = {type="table"},
        player_attack_infusions = {type="table"}, water_types = {type="table"}, feedback = {type="table"},
    },
    custom_validate = function(config)
        local errors = {}
        local types = type(config.types) == "table" and config.types or {}
        local function bad(path, rule) errors[#errors+1] = path .. " " .. rule end
        local function number(n, lo, hi, path)
            if type(n) ~= "number" or n ~= n or n < lo or n > hi then
                bad(path, "must be a finite number in [" .. lo .. "," .. hi .. "]")
            end
        end
        local function known(id, path)
            if type(id) ~= "string" or type(types[id]) ~= "table" then bad(path, "must name a known damage type") end
        end
        local function color(rgb, path)
            if type(rgb) ~= "table" or #rgb ~= 3 then bad(path, "must be {r,g,b}"); return end
            for i=1,3 do number(rgb[i], 0, 1, path .. "." .. i) end
        end
        local function factors(values, lo, path)
            if type(values) ~= "table" then bad(path, "must be a type-to-factor table"); return end
            for id, n in pairs(values) do
                known(id, path .. "." .. tostring(id)); number(n, lo, 10, path .. "." .. tostring(id))
            end
        end
        if not types.physical then bad("types.physical", "is required for default hits") end
        for id, entry in pairs(types) do
            local path = "types." .. tostring(id)
            if type(id) ~= "string" or not id:match("^[A-Za-z0-9_][A-Za-z0-9_.%-]*$")
                or id == "none" or id == "contact" then bad(path, "needs a stable id other than none/contact") end
            if type(entry) ~= "table" then bad(path, "must be a table")
            else
                if type(entry.label) ~= "string" or entry.label == "" then bad(path .. ".label", "must be source text") end
                color(entry.color, path .. ".color")
                number(entry.outgoing, 0, 10, path .. ".outgoing")
                if entry.status ~= nil then
                    if type(entry.status) ~= "table" then bad(path..".status", "must be {id,chance}")
                    else
                        local effects = require("developer.config.status_effects").effects
                        if not effects[entry.status.id] then bad(path..".status.id", "must name a known status") end
                        number(entry.status.chance,0,1,path..".status.chance")
                    end
                end
                if entry.family ~= nil then
                    known(entry.family, path .. ".family")
                    if entry.family == id then bad(path .. ".family", "cannot name itself") end
                end
            end
        end
        factors(config.player_taken, 0, "player_taken")
        for _, row in ipairs({{"ability_taken",0.1},{"tag_multipliers",0}}) do
            local groups = config[row[1]]
            if type(groups) == "table" then
                for id, values in pairs(groups) do
                    if type(id) ~= "string" or id == "" then bad(row[1], "needs nonempty text ids") end
                    factors(values, row[2], row[1] .. "." .. tostring(id))
                end
            end
        end
        local attacks = type(config.player_attacks) == "table" and config.player_attacks or {}
        for _, id in ipairs({"melee","ranged","movement"}) do known(attacks[id], "player_attacks." .. id) end
        if type(config.player_attack_infusions) == "table" then
            for i, entry in ipairs(config.player_attack_infusions) do
                local path = "player_attack_infusions." .. i
                if type(entry) ~= "table" then bad(path, "must be a table")
                else
                    if type(entry.ability) ~= "string" or entry.ability == "" then bad(path .. ".ability", "needs an ability id") end
                    if entry.melee == nil and entry.ranged == nil then bad(path, "needs melee or ranged") end
                    for _, kind in ipairs({"melee","ranged"}) do
                        if entry[kind] ~= nil then known(entry[kind], path .. "." .. kind) end
                    end
                end
            end
        end
        if type(config.water_types) == "table" then
            for water, id in pairs(config.water_types) do known(id, "water_types." .. tostring(water)) end
        end
        local feedback = type(config.feedback) == "table" and config.feedback or {}
        for _, key in ipairs({"tint_numbers","weak_as_critical"}) do
            if type(feedback[key]) ~= "boolean" then bad("feedback." .. key, "must be boolean") end
        end
        for _, key in ipairs({"immune_label","immune_sfx"}) do
            if type(feedback[key]) ~= "string" then bad("feedback." .. key, "must be text") end
        end
        color(feedback.weak_color, "feedback.weak_color")
        number(feedback.weak_flash, 0, 10, "feedback.weak_flash")
        color(feedback.immune_color, "feedback.immune_color")
        number(feedback.immune_flash, 0, 10, "feedback.immune_flash")
        return errors, {}
    end,
}
M.localization = {
    name = "Languages", file = "config/localization.lua", allow_unknown = false,
    required = { languages = {type = "table"}, default_language = {type = "string"},
        fallback = {type = "string"}, show_language_choice = {type = "boolean"} },
    optional = { ui_font_file = {type = "string"},
        ui_text_rendering = {type = "string", values = {"distance_field", "vector"}},
        ui_glyph_generation = {type = "string", values = {"static", "dynamic"}} },
    custom_validate = function(config)
        local errors, codes = {}, {}
        for _, entry in ipairs(type(config.languages) == "table" and config.languages or {}) do
            if type(entry) ~= "table" then errors[#errors + 1] = "languages entries must be tables"
            else
                if type(entry.code) ~= "string" or not entry.code:match("^[a-z][a-z%d_%-]*$") or entry.code == "auto" then
                    errors[#errors + 1] = "language code must be a stable lowercase code, not auto"
                elseif codes[entry.code] then errors[#errors + 1] = "duplicate language code: " .. entry.code
                else codes[entry.code] = true end
                if type(entry.name) ~= "string" or entry.name == "" then errors[#errors + 1] = "language needs its own name" end
                if entry.plural ~= "one_other" and entry.plural ~= "none" and entry.plural ~= "one_few_many" then
                    errors[#errors + 1] = "language plural must be one_other, none or one_few_many"
                end
            end
        end
        if not codes.en then errors[#errors + 1] = "languages must include English (en)" end
        if not codes[config.fallback] then errors[#errors + 1] = "fallback must be a supported language" end
        if config.default_language ~= "auto" and not codes[config.default_language] then
            errors[#errors + 1] = "default_language must be auto or a supported language"
        end
        return errors, {}
    end,
}
M.positional_audio = {
    name = "Positional Audio", file = "config/positional_audio.lua", allow_unknown = false,
    required = {
        listener = {type = "string", values = {"camera", "player"}},
        fade_per_second = {type = "number", range = {0.001, 1000}},
        stop_below_gain = {type = "number", range = {0, 0.99}},
        pan_strength = {type = "number", range = {0, 1}},
        pan_distance_px = {type = "number", range = {0, 1000000}},
    },
}
M.cutscene_settings = {
    name="Cutscene Settings", file="config/narrative/cutscene_settings.lua", allow_unknown=false,
    required={opening={type="string"},allow_skip={type="boolean"},
        skip_hold_seconds={type="number",range={0.2,5}},skip_action={type="string"},skip_hint={type="string"}},
}
M.world_lint = {
  name="World Lint", file="config/world_lint.lua", allow_unknown=false,
  optional={flags={type="table"},pacing={type="table"},player_size={type="table"}},
  custom_validate=function(config)
    local errors={}; local flags=config.flags or {}
    if config.player_size~=nil then
      local size=config.player_size
      if type(size)~="table" then return {"player_size must be a table"},{} end
      local fields={min_height_tiles=true,max_height_tiles=true,target_height_tiles=true}
      local valid=true
      for key in pairs(size) do
        if not fields[key] then errors[#errors+1]="player_size."..tostring(key).." is not a known setting" end
      end
      for key in pairs(fields) do
        local value=size[key]
        if type(value)~="number" or value~=value or value<=0 or value==math.huge then
          errors[#errors+1]="player_size."..key.." must be a positive finite number";valid=false
        end
      end
      if valid and (size.min_height_tiles>=size.max_height_tiles
          or size.target_height_tiles<size.min_height_tiles or size.target_height_tiles>size.max_height_tiles) then
        errors[#errors+1]="player_size needs min_height_tiles < max_height_tiles and a target between them"
      end
    end
    if type(flags)~="table" then return {"flags must be a table"},{} end
    local pacing=config.pacing or {}
    if type(pacing)~="table" then return {"pacing must be a table"},{} end
    for key in pairs(pacing) do
      if key~="enabled" and key~="max_rooms_without_save" and key~="dead_end_info" then errors[#errors+1]="pacing."..tostring(key).." is not a known setting" end
    end
    if pacing.enabled~=nil and type(pacing.enabled)~="boolean" then errors[#errors+1]="pacing.enabled must be boolean" end
    if pacing.dead_end_info~=nil and type(pacing.dead_end_info)~="boolean" then errors[#errors+1]="pacing.dead_end_info must be boolean" end
    local limit=pacing.max_rooms_without_save
    if limit~=nil and (type(limit)~="number" or limit<1 or limit%1~=0) then errors[#errors+1]="pacing.max_rooms_without_save must be a positive whole number" end
    if flags.errors~=nil and type(flags.errors)~="boolean" then errors[#errors+1]="flags.errors must be boolean" end
    if flags.allow~=nil and type(flags.allow)~="table" then errors[#errors+1]="flags.allow must be a list"
    else
      for key,value in pairs(flags.allow or {}) do
        if type(key)~="number" or key<1 or key%1~=0 or type(value)~="string" or value==""
            or (value:find("*",1,true) and (value:sub(-2)~="_*" or value:sub(1,-2):find("*",1,true))) then
          errors[#errors+1]="flags.allow requires exact names or prefix_* patterns"
        end
      end
    end
    return errors,{}
  end,
}
M.menu_settings = {
  name = "Menu Settings", file = "config/menu_settings.lua", allow_unknown = false,
  required = { navigation = { type = "table" }, list = { type = "table" },
    pause_while_open = { type = "boolean" }, books = { type = "table" },
    controller_disconnect_text = { type = "string" } },
  custom_validate = function(config)
    local errors, allowed, seen = {}, {}, {}
    for _, id in ipairs(require("developer.config.default_bindings").inputs) do allowed[id] = true end
    for _, command in ipairs({ "confirm", "back", "close", "up", "down", "left", "right", "tab_prev", "tab_next", "pointer" }) do
      local inputs = type(config.navigation) == "table" and config.navigation[command]
      if type(inputs) ~= "table" or #inputs == 0 then errors[#errors + 1] = "navigation." .. command .. " needs input ids"
      else
        for _, id in ipairs(inputs) do
          if not allowed[id] or id == "gamepad_connected" or id == "gamepad_disconnected" then
            errors[#errors + 1] = "navigation." .. command .. " has an unavailable input: " .. tostring(id)
          elseif seen[id] then errors[#errors + 1] = "navigation input has two commands: " .. id
          else seen[id] = true end
        end
      end
    end
    local list = type(config.list) == "table" and config.list or {}
    for _, row in ipairs({ { "page_size", 1, 12 }, { "hold_to_confirm_seconds", 0, 60 },
        { "repeat_delay", 0, 10 }, { "repeat_interval", 0.01, 10 },
        { "stick_press_threshold", 0, 1 }, { "stick_release_threshold", 0, 1 }, { "stick_rebound_seconds", 0, 10 } }) do
      local value = list[row[1]]
      if type(value) ~= "number" or value ~= value or value < row[2] or value > row[3]
          or (row[1] == "page_size" and value % 1 ~= 0) then errors[#errors + 1] = "list." .. row[1] .. " is outside its range" end
    end
    if type(list.stick_release_threshold) == "number" and type(list.stick_press_threshold) == "number"
        and list.stick_release_threshold > list.stick_press_threshold then
      errors[#errors + 1] = "list.stick_release_threshold must not be above list.stick_press_threshold"
    end
    for _, key in ipairs({ "move", "confirm", "back", "error" }) do
      if type(list.sfx) ~= "table" or type(list.sfx[key]) ~= "string" then errors[#errors + 1] = "list.sfx." .. key .. " needs a sound id or empty text" end
    end
    if type(config.books) == "table" then
      for id, book in pairs(config.books) do
        if type(book) ~= "table" or type(book.title) ~= "string" or
            (book.pause ~= true and book.pause ~= false and book.pause ~= "with_gear") then
          errors[#errors + 1] = "books." .. id .. " needs a title and true, false or with_gear pause"
        end
      end
    end
    return errors, {}
  end,
}
M.game_completion={
    name="Game Completion",file="config/game_completion.lua",allow_unknown=true,
    required={enabled={type="boolean"},id={type="string"},condition={type="string"},
        continue_policy={type="string"},title={type="string"},body={type="string"},credits={type="string"}},
    custom_validate=function(config)
        local errors={}
        if config.condition~="region" and config.condition~="flag" and config.condition~="boss" then errors[#errors+1]="Ending condition must be region, flag, or boss" end
        if config.continue_policy~="explore" and config.continue_policy~="completed" then errors[#errors+1]="Ending Continue policy must be explore or completed" end
        if type(config.id)~="string" or not config.id:match("^[%w_%-]+$") then errors[#errors+1]="Ending ID needs letters, digits, underscores or hyphens" end
        if config.enabled and config.condition=="flag" and config.flag=="" then errors[#errors+1]="Flag ending requires a flag" end
        if config.enabled and config.condition=="boss" and config.boss_id=="" then errors[#errors+1]="Boss ending requires a boss ID" end
        for _,key in ipairs({"return_x","return_y"}) do
            local n=config[key]; if type(n)~="number" or n~=n or n==math.huge or n==-math.huge then errors[#errors+1]=key.." must be finite" end
        end
        for _,key in ipairs({"flag","boss_id","return_room","music","artwork","reward_flag","font"}) do
            if type(config[key])~="string" then errors[#errors+1]=key.." must be a string" end
        end
        if type(config.credits_per_page)~="number" or config.credits_per_page<1 or config.credits_per_page>8 or config.credits_per_page%1~=0 then errors[#errors+1]="credits_per_page must be an integer from 1 to 8" end
        if type(config.text_scale)~="number" or config.text_scale<=0 or config.text_scale>2 then errors[#errors+1]="text_scale must be above zero and at most 2" end
        local Endings=require "mvtk.game.endings"
        for _,err in ipairs(Endings.schema_errors(config)) do errors[#errors+1]=err end
        -- Startup also calls this schema: use bundled catalogs, never fresh I/O.
        for _,ending in ipairs(Endings.list(config)) do
            if type(ending.reward)=="string" and ending.reward~="" then
                local env=require("mvtk.game.grant_spec").authoring_env({items=require "developer.config.items",
                abilities=require "developer.config.abilities",upgrades=require "developer.config.upgrades",
                weapons=require "developer.config.weapons",charms=require "developer.config.charms",
                collectible_types=require "developer.config.collectible_types",key_ids=require "mvtk.core.key_ids",
                world_census=require "developer.config.world_census_generated",leveling=require "developer.config.leveling"})
                env.once_key="ending:"..tostring(ending.id)
                local _,ds=require("mvtk.game.grant_spec").validate(ending.reward,env)
                for _,d in ipairs(ds) do
                    if d.severity=="error" then errors[#errors+1]="Ending '"..tostring(ending.id).."': "..d.message end
                end
            end
        end
        return errors,{}
    end,
}

M.persistence_settings = {
  name = "Persistence Settings", file = "config/persistence_settings.lua", allow_unknown = true,
  required = {game_id={type="string"}},
  custom_validate = function(config)
    if type(config.game_id)=="string" and (config.game_id=="" or config.game_id:match("^[%w_.-]+$")) then return {},{} end
    return {"game_id must contain only letters, digits, _, . or -"},{}
  end,
}

M.save_migrations = {
  name = "Save Migrations", file = "config/save_migrations.lua", allow_unknown = true,
  required = {version={type="number"},identifier_aliases={type="table"}},
  custom_validate = function(config)
    if config.version~=1 then return {"Unsupported save migration settings version"},{} end
    local ok,err=pcall(require("mvtk.core.save_migrations").validate_aliases,config.identifier_aliases)
    return ok and {} or {tostring(err)},{}
  end,
}

M.creator_settings = {
  name = "Creator Settings",
  file = "config/creator_settings.lua",
  allow_unknown = true,
  required = {
    version = { type = "number" },
    overrides = { type = "table" },
  },
  optional = { published = { type = "boolean" }, player_units = { type = "number", values = {1, 2} } },
  custom_validate = function(config)
    local ok, err = pcall(function()
      require("mvtk.core.creator_settings_model").validate(config)
      local Rules = require "mvtk.core.input_binding_rules"
      local merged, problems = Rules.apply_creator(require "developer.config.default_bindings",
        config.overrides.default_bindings, require "mvtk.rooms.input_actions")
      for _, problem in ipairs(Rules.validate(merged)) do problems[#problems + 1] = problem end
      assert(#problems == 0, table.concat(problems, "; "))
    end)
    local overrides = type(config.overrides) == "table" and config.overrides or {}
    return ok and {} or { tostring(err) }, champion_checkbox_warnings(overrides.enemy_defaults,
      "developer/config/creator_settings.lua overrides.enemy_defaults")
  end,
}

-- Game Settings baselines use the same field contract as their editor tabs.
for _,section in ipairs({"player_art","movement_test","healing","lighting","combat_music","fragments","shops","run_stats","leveling","achievements","quests","goals","bestiary","powerups","weapons","charms","crafting","completion_tracking","trial_settings","countdowns","new_game_plus","extras","npc_settings"}) do
  local section_name=section
  M[section_name]={name=section_name,file="config/"..section_name..".lua",allow_unknown=true,
    custom_validate=function(config)
      local Model=require "mvtk.core.creator_settings_model"
      local values={}
      for key,spec in pairs(Model.fields) do
        if spec.path:sub(1,#section_name+1)==section_name.."." then
          values[key]=Model.get({[section_name]=config},spec.path)
          if values[key]==nil then return {"Missing "..spec.path},{} end
        end
      end
      local ok,err=pcall(Model.from_controls,values)
      return ok and {} or {tostring(err)},{}
    end}
end

-- Replay policy is data-only and validated at startup without project reads.
do
  local baseline = M.new_game_plus.custom_validate
  M.new_game_plus.allow_unknown = false
  M.new_game_plus.required = {enabled={type="boolean"},endings={type="table"},cycles={type="table"},carry={type="table"}}
  M.new_game_plus.custom_validate = function(config)
    local errors, warnings = baseline(config)
    local function bad(message) errors[#errors+1] = "new_game_plus.lua: " .. message end
    local function list(value, label)
      if type(value) ~= "table" then bad(label .. " must be a list"); return {} end
      local count = 0
      for k in pairs(value) do
        count = count + 1
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then bad(label .. " must be an ordered list") end
      end
      if count ~= #value then bad(label .. " must be contiguous") end
      return value
    end
    local seen = {}
    for _, id in ipairs(list(config.endings, "endings")) do
      if type(id) ~= "string" or id == "" or seen[id] then bad("endings need unique nonempty ids") end
      if type(id) == "string" then seen[id] = true end
    end
    local cycles = list(config.cycles, "cycles")
    if #cycles == 0 then bad("cycles needs at least one entry") end
    local keys = {enemy_health_mult=true,boss_health_mult=true,damage_taken_mult=true,damage_dealt_mult=true,loot_mult=true}
    for _, factors in ipairs(cycles) do
      if type(factors) ~= "table" then bad("cycle must be a multiplier table")
      else
        for k, n in pairs(factors) do
          if not keys[k] or type(n) ~= "number" or n ~= n or n < 0.1 or n > 10 then bad("invalid cycle factor " .. tostring(k)) end
        end
      end
    end
    local carry = {level=true,equipment=true,currency=true,items=true,abilities=true,upgrades=true,bestiary=true,cutscenes_seen=true}
    if type(config.carry) ~= "table" then bad("carry must be a table")
    else
      for k in pairs(carry) do if type(config.carry[k]) ~= "boolean" then bad("carry." .. k .. " must be boolean") end end
      for k in pairs(config.carry) do if not carry[k] then bad("unknown carry rule " .. tostring(k)) end end
    end
    return errors, warnings
  end
end

-- NPC settings (WM12a-c): the marker switch and its source texts, barks,
-- wander pauses and the Journal People tab.
do
  local baseline = M.npc_settings.custom_validate
  M.npc_settings.allow_unknown = false
  M.npc_settings.required = {markers={type="table"}, barks={type="table"}, wander={type="table"}, people={type="table"}}
  M.npc_settings.custom_validate = function(config)
    local errors, warnings = baseline(config)
    local markers = type(config.markers) == "table" and config.markers or {}
    if type(markers.enabled) ~= "boolean" then errors[#errors+1] = "npc_settings.lua: markers.enabled must be true or false" end
    for _, key in ipairs({"new_text", "task_text"}) do
      if type(markers[key]) ~= "string" then errors[#errors+1] = "npc_settings.lua: markers." .. key .. " must be text" end
    end
    local scale = markers.scale
    if type(scale) ~= "number" or scale ~= scale or scale < 0.25 or scale > 16 then
      errors[#errors+1] = "npc_settings.lua: markers.scale must be a number from 0.25 to 16"
    end
    for key in pairs(markers) do
      if key ~= "enabled" and key ~= "new_text" and key ~= "task_text" and key ~= "scale" then
        errors[#errors+1] = "npc_settings.lua: unknown markers field " .. tostring(key)
      end
    end
    -- WM12b: barks and wander blocks.
    local function number_in(value, lo, hi)
      return type(value) == "number" and value == value and value >= lo and value <= hi
    end
    local function known(block, name, keys)
      for key in pairs(block) do
        if not keys[key] then errors[#errors+1] = "npc_settings.lua: unknown " .. name .. " field " .. tostring(key) end
      end
    end
    if type(config.barks) == "table" then
      if type(config.barks.enabled) ~= "boolean" then errors[#errors+1] = "npc_settings.lua: barks.enabled must be true or false" end
      if not number_in(config.barks.show_seconds, 1, 10) then
        errors[#errors+1] = "npc_settings.lua: barks.show_seconds must be a number from 1 to 10"
      end
      if not number_in(config.barks.scale, 0.25, 16) then
        errors[#errors+1] = "npc_settings.lua: barks.scale must be a number from 0.25 to 16"
      end
      known(config.barks, "barks", {enabled=true, show_seconds=true, scale=true})
    end
    if type(config.wander) == "table" then
      local lo, hi = config.wander.pause_min, config.wander.pause_max
      if not number_in(lo, 0, 60) then errors[#errors+1] = "npc_settings.lua: wander.pause_min must be a number from 0 to 60" end
      if not number_in(hi, 0, 60) then errors[#errors+1] = "npc_settings.lua: wander.pause_max must be a number from 0 to 60"
      elseif number_in(lo, 0, 60) and hi < lo then
        errors[#errors+1] = "npc_settings.lua: wander.pause_max must not be below pause_min"
      end
      known(config.wander, "wander", {pause_min=true, pause_max=true})
    end
    local people = type(config.people) == "table" and config.people or {}
    for _, key in ipairs({"enabled", "show_unmet"}) do
      if type(people[key]) ~= "boolean" then errors[#errors+1] = "npc_settings.lua: people." .. key .. " must be true or false" end
    end
    for key in pairs(people) do
      if key ~= "enabled" and key ~= "show_unmet" then
        errors[#errors+1] = "npc_settings.lua: unknown people field " .. tostring(key)
      end
    end
    return errors, warnings
  end
end

-- Extras: shape only. Unknown tracks, endings and achievements belong to
-- Prepare & Check's relationship gate (content_checks), never to startup.
do
  local baseline = M.extras.custom_validate
  M.extras.allow_unknown = false
  M.extras.required = {enabled={type="boolean"},notify={type="boolean"},show_locked={type="boolean"},
    jukebox={type="table"},gallery={type="table"},credits={type="table"}}
  local TYPES = {always=true,heard=true,ending=true,achievement=true,flag=true,cycle=true}
  M.extras.custom_validate = function(config)
    local errors, warnings = baseline(config)
    local function bad(message) errors[#errors+1] = "extras.lua: " .. message end
    local function list(value, label)
      if type(value) ~= "table" then bad(label .. " must be a list"); return {} end
      local count = 0
      for k in pairs(value) do
        count = count + 1
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then bad(label .. " must be an ordered list") end
      end
      if count ~= #value then bad(label .. " must be contiguous") end
      return value
    end
    local function text(value) return value == nil or type(value) == "string" end
    local function unlock(value, label)
      if value == nil then return end
      if type(value) ~= "table" or not TYPES[value.type] then bad(label .. ".unlock.type is unknown"); return end
      if value.type == "cycle" and (type(value.cycle) ~= "number" or value.cycle < 1 or value.cycle % 1 ~= 0) then
        bad(label .. ".unlock.cycle must be a whole number of at least 1")
      end
      for _, key in ipairs({"ending_id","id","flag"}) do
        if not text(value[key]) then bad(label .. ".unlock." .. key .. " must be text") end
      end
    end
    for _, name in ipairs({"jukebox","gallery","credits"}) do
      local section = config[name]
      if type(section) == "table" and type(section.enabled) ~= "boolean" then bad(name .. ".enabled must be boolean") end
    end
    for i, row in ipairs(list((config.jukebox or {}).tracks, "jukebox.tracks")) do
      local label = "jukebox.tracks." .. i
      if type(row) ~= "table" or type(row.track) ~= "string" or row.track == "" then bad(label .. ".track must be a track id")
      else
        if not text(row.title) then bad(label .. ".title must be text") end
        unlock(row.unlock, label)
      end
    end
    for i, row in ipairs(list((config.gallery or {}).entries, "gallery.entries")) do
      local label = "gallery.entries." .. i
      if type(row) ~= "table" or type(row.id) ~= "string" or row.id == "" then bad(label .. ".id must be an id")
      else
        for _, key in ipairs({"image","title","caption"}) do
          if not text(row[key]) then bad(label .. "." .. key .. " must be text") end
        end
        unlock(row.unlock, label)
      end
    end
    return errors, warnings
  end
end

-- Trial validation also runs in exported builds; all catalogs are bundled modules.
do
  local baseline=M.trial_settings.custom_validate
  M.trial_settings.allow_unknown=false
  M.trial_settings.required={countdown={type="number"},restore_health={type="boolean"},
    autosave_on_clear={type="boolean"},return_fade_out={type="number"},return_fade_in={type="number"},
    ranks={type="table"},start_sfx={type="string"},success_sfx={type="string"},fail_sfx={type="string"},
    result_duration={type="number"}}
  M.trial_settings.custom_validate=function(config)
    local errors,warnings=baseline(config)
    for _,key in ipairs({"countdown","return_fade_out","return_fade_in","result_duration"}) do
      local n=config[key]
      if type(n)~="number" or n~=n or n<0 or n==math.huge then errors[#errors+1]=key.." must be finite and non-negative" end
    end
    if type(config.ranks)~="table" or #config.ranks~=3 then errors[#errors+1]="ranks must contain three names"
    else for i=1,3 do
      if type(config.ranks[i])~="table" or type(config.ranks[i].name)~="string" then errors[#errors+1]="ranks need source-text names" end
    end end
    local bank=require "developer.config.sound_bank"
    for _,key in ipairs({"start_sfx","success_sfx","fail_sfx"}) do
      local id=config[key]
      if type(id)=="string" and id~="" and not (bank.sfx or {})[id] then errors[#errors+1]=key.." needs a sound_bank id" end
    end
    return errors,warnings
  end
end

-- Derived completion uses bundled data only; relationship validation reads fresh files.
do
  local baseline=M.completion_tracking.custom_validate
  M.completion_tracking.file="developer/config/completion_tracking.lua"
  M.completion_tracking.allow_unknown=false
  M.completion_tracking.required={enabled={type="boolean"},rounding={type="string"},
    show_in_journal={type="boolean"},show_on_ending={type="boolean"},categories={type="table"}}
  M.completion_tracking.custom_validate=function(config)
    local errors,warnings=baseline(config)
    local known={upgrades=true,bosses=true,map=true,secrets=true,chests=true,collection=true,quests=true,bestiary=true,guardians=true,trials=true}
    local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
    local function bad(id,why) errors[#errors+1]="completion_tracking.lua category '"..tostring(id).."': "..why end
    if config.rounding~="floor" and config.rounding~="round" then errors[#errors+1]="rounding must be floor or round" end
    if type(config.categories)~="table" then errors[#errors+1]="categories must be a table"
    else for id,rule in pairs(config.categories) do
      if type(id)~="string" or not id:match("^[%w_%-]+$") or type(rule)~="table" then bad(id,"needs a stable id and table")
      else
        if not finite(rule.weight) or rule.weight<0 then bad(id,"weight must be finite and non-negative") end
        if rule.order~=nil and not finite(rule.order) then bad(id,"order must be finite") end
        if rule.label~=nil and type(rule.label)~="string" then bad(id,"label must be source text") end
        if rule.lore_items~=nil and type(rule.lore_items)~="boolean" then bad(id,"lore_items must be boolean") end
        if not known[id] and type(rule.collectible_categories)~="table" then bad(id,"needs collectible_categories") end
        if rule.collectible_categories~=nil then
          local cats=rule.collectible_categories
          if type(cats)~="table" then bad(id,"collectible_categories must be a list")
          else
            for i=1,#cats do if cats[i]==nil then bad(id,"collectible_categories must be dense") end end
            for i,value in pairs(cats) do
              if type(i)~="number" or i%1~=0 or i<1 or i>#cats or type(value)~="string" or not value:find("%S") then bad(id,"collectible_categories must be a list of names") end
            end
          end
        end
      end
    end end
    return errors,warnings
  end
end

-- Runtime schemas use bundled catalogs. Prepare & Check separately reads fresh sources.
do
  local baseline = M.weapons.custom_validate
  M.weapons.file = "developer/config/weapons.lua"
  M.weapons.allow_unknown = false
  M.weapons.required = {enabled={type="boolean"}, quick_switch={type="boolean"},
    starting_weapon={type="string"}, duplicate_currency={type="number"}, weapons={type="table"}}
  M.weapons.custom_validate = function(config)
    local errors, warnings = baseline(config)
    local function bad(path, rule) errors[#errors+1] = "weapons.lua "..path.." "..rule end
    local function finite(n, minimum, strict)
      return type(n)=="number" and n==n and n<math.huge and (strict and n>minimum or not strict and n>=minimum)
    end
    if not finite(config.duplicate_currency,0) or config.duplicate_currency%1~=0 then bad("duplicate_currency","must be a whole non-negative amount") end
    if type(config.quick_switch)~="boolean" then bad("quick_switch","must be boolean") end
    local seen, entries = {}, type(config.weapons)=="table" and config.weapons or {}
    local sets = require("developer.config.combat_config").attack_sets or {}
    local types = require("developer.config.damage_types").types or {}
    local abilities = require("developer.config.abilities").abilities or {}
    for index, entry in pairs(entries) do
      local path = "weapons."..tostring(index)
      if type(index)~="number" or index%1~=0 or index<1 or index>#entries then bad(path,"must be an ordered list entry") end
      if type(entry)~="table" then bad(path,"must be a table")
      else
        local id = entry.id
        if type(id)~="string" or not id:match("^[%w_%-]+$") then bad(path..".id","must be a stable id")
        elseif seen[id] then bad(path..".id","duplicates another weapon") else seen[id]=true end
        if type(entry.name)~="string" or not entry.name:find("%S") then bad(path..".name","must be nonblank text") end
        if type(entry.description)~="string" then bad(path..".description","must be text") end
        if not sets[entry.attack_set or "default"] then bad(path..".attack_set","must name a combat_config.lua attack set") end
        for _, key in ipairs({"icon_animation","collect_sound"}) do
          if entry[key]~=nil and (type(entry[key])~="string" or entry[key]=="") then bad(path.."."..key,"must be nonblank text") end
        end
        if entry.requires_ability~=nil and entry.requires_ability~="" and not abilities[entry.requires_ability] then bad(path..".requires_ability","must name an ability") end
        if entry.damage_type~=nil and not types[entry.damage_type] then bad(path..".damage_type","must name a damage_types.lua type") end
        if entry.count_in_census~=nil and type(entry.count_in_census)~="boolean" then bad(path..".count_in_census","must be boolean") end
        if entry.random_drop~=nil and type(entry.random_drop)~="boolean" then bad(path..".random_drop","must be boolean") end
        local variants = {entry}
        if entry.tiers ~= nil then
          if type(entry.tiers) ~= "table" then bad(path..".tiers","must be an ordered list")
          else
          for ti=1,#entry.tiers do
            if entry.tiers[ti]==nil then bad(path..".tiers","must be dense, with no missing tier definitions") end
          end
          for ti, tier in pairs(entry.tiers) do
            if type(ti)~="number" or ti%1~=0 or ti<1 or ti>#entry.tiers then bad(path..".tiers","must be an ordered list") end
            if type(tier)~="table" then bad(path..".tiers","entries must be tables")
            else
              if tier.name~=nil and (type(tier.name)~="string" or not tier.name:find("%S")) then bad(path..".tiers.name","must be nonblank text") end
              variants[#variants+1]=tier
            end
          end end
        end
        for _, variant in ipairs(variants) do
        for _, group in ipairs({"scale","ranged"}) do
          local values=variant[group]
          if values~=nil then
            if type(values)~="table" then bad(path.."."..group,"must be a table")
            else
              local keys=group=="scale" and {damage=true,reach=true,cooldown=true,knockback=true}
                or {damage=true,speed=true,lifetime=true,energy_cost=true}
              for key,value in pairs(values) do
                if not keys[key] or not finite(value,0,key~="energy_cost") then bad(path.."."..group.."."..tostring(key),"must be finite and positive (energy_cost permits zero)") end
              end
            end
          end
        end
        end -- variants
      end
    end
    if config.starting_weapon~="" and not seen[config.starting_weapon] then bad("starting_weapon","must be blank or a weapon id") end
    return errors,warnings
  end
end

-- Crafting uses bundled catalogs at startup; relationships supply fresh catalogs.
do
  local baseline = M.crafting.custom_validate
  M.crafting.file = "developer/config/crafting.lua"
  M.crafting.allow_unknown = false
  M.crafting.required = {enabled={type="boolean"},recipes={type="table"}}
  M.crafting.custom_validate = function(config)
    local errors, warnings = baseline(config)
    local Spec = require "mvtk.game.grant_spec"
    local env = Spec.authoring_env({weapons=require "developer.config.weapons",charms=require "developer.config.charms",
      items=require "developer.config.items",collectible_types=require "developer.config.collectible_types",key_ids=require "mvtk.core.key_ids"})
    for _, err in ipairs(Spec.validate_crafting(config,env)) do errors[#errors+1] = err end
    return errors, warnings
  end
end

-- Charm effects are persistent equipment, validated with bundled runtime data.
do
  local baseline = M.charms.custom_validate
  M.charms.file = "developer/config/charms.lua"
  M.charms.allow_unknown = false
  M.charms.required = {enabled={type="boolean"}, base_slots={type="number"},
    max_slots={type="number"}, slot_item={type="string"}, duplicate_currency={type="number"}, charms={type="table"}}
  M.charms.custom_validate = function(config)
    local errors, warnings = baseline(config)
    local function bad(path, rule) errors[#errors+1] = "charms.lua "..path.." "..rule end
    local function whole(n, minimum, maximum)
      return type(n)=="number" and n==n and n<math.huge and n>=minimum and n%1==0 and (not maximum or n<=maximum)
    end
    if not whole(config.base_slots,0,20) then bad("base_slots","must be a whole number from 0 to 20") end
    if not whole(config.max_slots,1,20) then bad("max_slots","must be a whole number from 1 to 20") end
    if not whole(config.duplicate_currency,0) then bad("duplicate_currency","must be a whole non-negative amount") end
    local items = require "developer.config.items"
    if type(config.slot_item)~="string" or not items[config.slot_item] then bad("slot_item","must name an Inventory item") end
    local seen, entries = {}, type(config.charms)=="table" and config.charms or {}
    for index, entry in pairs(entries) do
      local path = "charms."..tostring(index)
      if type(index)~="number" or index%1~=0 or index<1 or index>#entries then bad(path,"must be an ordered list entry") end
      if type(entry)~="table" then bad(path,"must be a table")
      else
        local id = entry.id
        if type(id)~="string" or not id:match("^[%w_%-]+$") then bad(path..".id","must be a stable id")
        elseif id=="slot" then bad(path..".id","slot is reserved for the Charm Slot pickup")
        elseif seen[id] then bad(path..".id","duplicates another charm") else seen[id]=true end
        if type(entry.name)~="string" or not entry.name:find("%S") then bad(path..".name","must be nonblank text") end
        if type(entry.description)~="string" then bad(path..".description","must be text") end
        if not whole(entry.cost,1) then bad(path..".cost","must be a whole slot cost of at least 1")
        elseif whole(config.max_slots,1,20) and entry.cost>config.max_slots then
          warnings[#warnings+1]="charms.lua "..path..".cost exceeds max_slots; this charm cannot fit"
        end
        for _, err in ipairs(require("mvtk.player.stat_keys").validate_effects(entry.effects, {layer = "equipment"})) do bad(path..".effects",err) end
        if type(entry.effects)=="table" and entry.effects.invulnerable~=nil then bad(path..".effects.invulnerable","is forbidden for charms") end
        for _, key in ipairs({"icon_animation","collect_sound"}) do
          if entry[key]~=nil and (type(entry[key])~="string" or entry[key]=="") then bad(path.."."..key,"must be nonblank text") end
        end
        if entry.count_in_census~=nil and type(entry.count_in_census)~="boolean" then bad(path..".count_in_census","must be boolean") end
        if entry.random_drop~=nil and type(entry.random_drop)~="boolean" then bad(path..".random_drop","must be boolean") end
      end
    end
    return errors,warnings
  end
end

-- Temporary effects use the bundled registry at startup, with no project reads.
do
  local baseline = M.powerups.custom_validate
  M.powerups.allow_unknown = false
  M.powerups.required = {enabled={type="boolean"}, stacking={type="string",values={"refresh","extend"}}, powerups={type="table"}}
  M.powerups.custom_validate = function(config)
    local errors, warnings = baseline(config)
    if config.stacking ~= "refresh" and config.stacking ~= "extend" then errors[#errors+1]="stacking must be refresh or extend" end
    for id, entry in pairs(type(config.powerups)=="table" and config.powerups or {}) do
      if type(id)~="string" or not id:match("^[%w_%-]+$") then errors[#errors+1]="Invalid power-up id" end
      if type(entry)~="table" then errors[#errors+1]="Power-up must be a table: "..tostring(id)
      else
        if type(entry.name)~="string" or entry.name=="" then errors[#errors+1]="Power-up needs a name: "..tostring(id) end
        local d=entry.duration
        if type(d)~="number" or d~=d or d<0.5 or d>600 then errors[#errors+1]="Power-up duration must be 0.5-600: "..tostring(id) end
        for _, err in ipairs(require("mvtk.player.stat_keys").validate_effects(entry.effects,{layer="temporary"})) do
          errors[#errors+1]=tostring(id)..": "..err
        end
        for _,key in ipairs({"icon_animation","collect_sound"}) do
          if entry[key]~=nil and type(entry[key])~="string" then errors[#errors+1]="Power-up "..key.." must be text: "..tostring(id) end
        end
      end
    end
    return errors, warnings
  end
end

-- File-only Steam settings: validate shape at startup using bundled data only.
-- Fresh catalog relationships and add-on state checks belong to Prepare & Check.
M.steam_settings = {
  name="Steam Settings", file="config/steam_settings.lua", allow_unknown=false,
  required={app_id={type="number"}, achievement_names={type="table"}},
  optional={
    rich_presence={type="table",fields={enabled={type="boolean"},title={type="string"},
      playing={type="string"},region={type="string"}}},
    cloud_saves={type="table",fields={enabled={type="boolean"},
      include_preferences={type="boolean"},include_controls={type="boolean"}}},
    steam_languages={type="table"},
  },
  custom_validate=function(config)
    local errors={}
    local id=config.app_id
    if type(id)~="number" or id~=id or id==math.huge or id<0 or id~=math.floor(id) then
      errors[#errors+1]="app_id must be a finite non-negative integer (0 means not set)"
    end
    if type(config.achievement_names)=="table" then
      for key,value in pairs(config.achievement_names) do
        if type(key)~="string" or key=="" or type(value)~="string" or value=="" then
          errors[#errors+1]="achievement_names must map non-empty achievement ids to non-empty API Names"
        end
      end
    end
    for _, block in ipairs({"rich_presence", "cloud_saves"}) do
      local value=config[block]
      if type(value)=="table" then
        for key in pairs(value) do
          if not M.steam_settings.optional[block].fields[key] then
            errors[#errors+1]=block..": unknown key "..tostring(key)
          end
        end
      end
    end
    local presence=config.rich_presence
    if type(presence)=="table" then
      for _, key in ipairs({"title", "playing", "region"}) do
        if type(presence[key])~="string" or presence[key]=="" then
          errors[#errors+1]="rich_presence."..key.." must be non-empty text"
        end
      end
      if type(presence.region)=="string" then
        local remainder,count=presence.region:gsub("{region}", "")
        if count~=1 or remainder:find("[{}%%]") then
          errors[#errors+1]="rich_presence.region must contain {region} exactly once and no other braces or percent signs"
        end
      end
    end
    if type(config.steam_languages)=="table" then
      local codes=require("mvtk.platform.steam_languages").api_codes
      for key,value in pairs(config.steam_languages) do
        if type(key)~="string" or type(value)~="string" or not codes[value] then
          errors[#errors+1]="steam_languages must map string language keys to known Steam API codes"
        end
      end
    end
    return errors,{}
  end,
}

-- Achievement rules are shared with the fatal authored-relationships gate.
do
  local baseline = M.achievements.custom_validate
  M.achievements.allow_unknown = false
  M.achievements.required = {enabled={type="boolean"},notify={type="boolean"},show_hidden_count={type="boolean"},
    sfx={type="string"},categories={type="table"},achievements={type="table"}}
  M.achievements.custom_validate = function(config)
    local errors,warnings=baseline(config)
    -- Bundled modules, never disk reads: game startup also runs this check, and an
    -- exported build cannot open project files. Prepare & Check's gate reads fresh copies.
    local env=require("mvtk.game.grant_spec").authoring_env({items=require "developer.config.items",
      abilities=require "developer.config.abilities",upgrades=require "developer.config.upgrades",weapons=require "developer.config.weapons",
      collectible_types=require "developer.config.collectible_types",key_ids=require "mvtk.core.key_ids",
      world_census=require "developer.config.world_census_generated",leveling=require "developer.config.leveling"})
    for _,err in ipairs(require("mvtk.game.progression.achievement_rules").validate(config,require("mvtk.core.game_events").EVENTS,env)) do
      errors[#errors+1]=err
    end
    if type(config.sfx)=="string" and config.sfx~="" and not require("developer.config.sound_bank").sfx[config.sfx] then errors[#errors+1]="Unknown achievement sfx" end
    return errors,warnings
  end
end

-- Quest validation also runs in exported builds: use bundled catalogs only.
do
  local baseline=M.quests.custom_validate
  M.quests.allow_unknown=false
  M.quests.required={enabled={type="boolean"},notify={type="boolean"},categories={type="table"},quests={type="table"}}
  M.quests.custom_validate=function(config)
    local errors,warnings=baseline(config)
    local env=require("mvtk.game.grant_spec").authoring_env({items=require "developer.config.items",
      abilities=require "developer.config.abilities",upgrades=require "developer.config.upgrades",weapons=require "developer.config.weapons",
      collectible_types=require "developer.config.collectible_types",key_ids=require "mvtk.core.key_ids",
      world_census=require "developer.config.world_census_generated",leveling=require "developer.config.leveling"})
    for _,err in ipairs(require("mvtk.game.quests.quest_rules").validate(config,env)) do errors[#errors+1]=err end
    return errors,warnings
  end
end

-- Goal validation also runs in exported builds: bundled requires only.
do
  local baseline=M.goals.custom_validate
  M.goals.allow_unknown=false
  M.goals.required={enabled={type="boolean"},hint_reveals_target={type="boolean"},goals={type="table"}}
  M.goals.custom_validate=function(config)
    local errors,warnings=baseline(config)
    local env={abilities=(require "developer.config.abilities").abilities}
    for _,err in ipairs(require("mvtk.game.goal_rules").validate(config,env)) do errors[#errors+1]=err end
    return errors,warnings
  end
end

-- Countdown validation (WM09) also runs in exported builds: bundled requires only.
do
  local baseline=M.countdowns.custom_validate
  M.countdowns.allow_unknown=false
  M.countdowns.required={warning_sfx={type="string"},finish_sfx={type="string"},fail_sfx={type="string"},
    tenths_below={type="number"},autosave_on_finish={type="boolean"},return_fade_out={type="number"},
    return_fade_in={type="number"},result_duration={type="number"},countdowns={type="table"}}
  M.countdowns.custom_validate=function(config)
    local errors,warnings=baseline(config)
    local env={sfx=(require "developer.config.sound_bank").sfx or {}}
    for _,err in ipairs(require("mvtk.game.countdown_rules").validate(config,env)) do errors[#errors+1]=err end
    return errors,warnings
  end
end

-- Bestiary keeps creator text separate from persistent creature identities.
do
  local baseline = M.bestiary.custom_validate
  M.bestiary.allow_unknown = false
  M.bestiary.required = {enabled={type="boolean"},include_bosses={type="boolean"},include_spawned={type="boolean"},
    details_after={type="number"},notify_new_entry={type="boolean"},unknown_text={type="string"},
    categories={type="table"},entries={type="table"},bosses={type="table"}}
  M.bestiary.custom_validate = function(config)
    local errors,warnings=baseline(config)
    local function bad(path) errors[#errors+1]=path.." is invalid" end
    if type(config.details_after)~="number" or config.details_after~=config.details_after
      or config.details_after<1 or config.details_after==math.huge or config.details_after%1~=0 then bad("details_after") end
    local seen={}
    for _,category in ipairs(type(config.categories)=="table" and config.categories or {}) do
      if type(category)~="table" or type(category.id)~="string" or category.id=="" or seen[category.id]
        or type(category.label)~="string" then bad("categories row")
      else seen[category.id]=true end
    end
    for _,kind in ipairs({"entries","bosses"}) do
      for id,entry in pairs(type(config[kind])=="table" and config[kind] or {}) do
        if type(id)~="string" or id=="" or type(entry)~="table" then bad(kind.." row")
        else
          for _,key in ipairs({"name","description","category"}) do
            if entry[key]~=nil and type(entry[key])~="string" then bad(kind.."."..id.."."..key) end
          end
          if entry.order~=nil and (type(entry.order)~="number" or entry.order~=entry.order or math.abs(entry.order)==math.huge) then bad(kind.."."..id..".order") end
          if entry.hidden_until_defeated~=nil and type(entry.hidden_until_defeated)~="boolean" then bad(kind.."."..id..".hidden_until_defeated") end
        end
      end
    end
    return errors,warnings
  end
end

-- Level growth is pure data and uses the same controls contract as Game Settings.
do
  local baseline = M.leveling.custom_validate
  M.leveling.allow_unknown = false
  M.leveling.required = {enabled={type="boolean"}, max_level={type="number",range={1,99}},
    curve={type="table"},per_level={type="table"},milestones={type="table"},level_up={type="table"},sources={type="table"}}
  M.leveling.custom_validate = function(config)
    local errors, warnings = baseline(config)
    local function bad(path) errors[#errors+1]=path.." is invalid" end
    local function number(n, path, min, max, integer)
      if type(n)~="number" or n~=n or math.abs(n)==math.huge or n<min or n>max
        or (integer and n%1~=0) then bad(path) end
    end
    number(config.max_level,"max_level",1,99,true)
    local curve = type(config.curve)=="table" and config.curve or {}
    if curve.mode~="formula" and curve.mode~="table" then bad("curve.mode") end
    number(curve.first,"curve.first",1,100000,true); number(curve.growth,"curve.growth",1,3)
    if type(curve.table)~="table" then bad("curve.table") else
      for level, xp in pairs(curve.table) do
        number(level,"curve.table level",1,98,true); number(xp,"curve.table XP",1,1e15,true)
      end
    end
    for _, err in ipairs(require("mvtk.player.stat_keys").validate_effects(config.per_level, {layer="permanent"})) do
      errors[#errors+1]="per_level: "..err
    end
    for key, n in pairs(type(config.per_level)=="table" and config.per_level or {}) do
      if key~="max_health" and key~="max_energy" and key~="max_stamina" and key~="damage_mult" then bad("per_level."..tostring(key))
      else number(n,"per_level."..key,0,key=="damage_mult" and 9 or 100000) end
    end
    for level, reward in pairs(type(config.milestones)=="table" and config.milestones or {}) do
      number(level,"milestones level",2,99,true)
      if type(reward)~="table" or type(reward.set_flag)~="string" or reward.set_flag=="" then bad("milestones reward") end
    end
    local feedback=type(config.level_up)=="table" and config.level_up or {}
    if type(feedback.full_heal)~="boolean" then bad("level_up.full_heal") end
    if type(feedback.sfx)~="string" then bad("level_up.sfx")
    elseif feedback.sfx~="" and not require("developer.config.sound_bank").sfx[feedback.sfx] then bad("level_up.sfx") end
    local sources=type(config.sources)=="table" and config.sources or {}
    for _,key in ipairs({"enemy_default","boss_default","secret_found","room_first_visit"}) do number(sources[key],"sources."..key,0,100000,true) end
    number(sources.elite_mult,"sources.elite_mult",0,1000)
    if type(sources.skip_spawned)~="boolean" then bad("sources.skip_spawned") end
    for _, key in ipairs({"collectible_type_xp","skip_causes"}) do
      if type(sources[key])~="table" then bad("sources."..key) else
        for id, value in pairs(sources[key]) do
          if type(id)~="string" or id=="" then bad("sources."..key.." id") end
          if key=="skip_causes" then if type(value)~="boolean" then bad("sources.skip_causes value") end
          else number(value,"sources.collectible_type_xp value",0,100000,true) end
        end
      end
    end
    return errors, warnings
  end
end

-- Fragment sets share the editor baseline checks and validate custom sets too.
do
  local baseline = M.fragments.custom_validate
  M.fragments.required = {sets = {type = "table"}}
  M.fragments.custom_validate = function(config)
    local errors, warnings = baseline(config)
    local upgrades = {max_health=true, max_energy=true, max_stamina=true, heal_charges=true}
    for id, set in pairs(type(config.sets)=="table" and config.sets or {}) do
      local function bad(field) errors[#errors+1]="sets."..tostring(id).."."..field.." is invalid" end
      if type(set)~="table" then bad("set")
      else
        if not upgrades[set.upgrade] then bad("upgrade") end
        for _, field in ipairs({"pieces", "amount"}) do
          local n=set[field]
          if type(n)~="number" or n~=n or n<=0 or n>=math.huge or n%1~=0
              or (field=="pieces" and n>20) then bad(field) end
        end
        for _, field in ipairs({"name", "progress_text", "complete_text"}) do
          if type(set[field])~="string" or not set[field]:find("%S") then bad(field) end
        end
      end
    end
    return errors, warnings
  end
end

-- Combat fields not shown in Game Settings retain a strict data schema.
do
  local baseline = M.combat_music.custom_validate
  M.combat_music.required = {
    enabled={type="boolean"}, default_track={type="string"},
    release_delay={type="number",range={0.5,30}},
    fade_in={type="number",range={0.5,3600}}, fade_out={type="number",range={0.5,3600}},
    ignore_spawned={type="boolean"}, engage={type="table",fields={
      radius={type="number",range={0,1000000}}, count={type="number",range={1,1000000}},
        min_time={type="number",range={0,3600}}, on_player_hit={type="boolean"}, line_of_sight={type="boolean"}}},
  }
  M.combat_music.allow_unknown = false
  M.combat_music.custom_validate = function(config)
    local errors,warnings = baseline(config)
    local count = type(config.engage)=="table" and config.engage.count
    if type(count)=="number" and count%1~=0 then errors[#errors+1]="engage.count must be a whole number" end
    return errors,warnings
  end
end

-- Extend the editor baseline contract with file-only drink and channel settings.
do
  local baseline = M.healing.custom_validate
  M.healing.custom_validate = function(config)
    local errors,warnings = baseline(config)
    local function number(path,value,min,max,integer)
      if type(value)~="number" or value~=value or value<min or value>max or (integer and value%1~=0) then
        errors[#errors+1]=path.." is outside its range"
      end
    end
    local function text(path,value)
      if type(value)~="string" then errors[#errors+1]=path.." must be text" end
    end
    local function boolean(path,value)
      if type(value)~="boolean" then errors[#errors+1]=path.." must be boolean" end
    end
    local flask,use,quick=config.flask or {},config.use or {},config.quick or {}
    if type(flask)~="table" or type(use)~="table" or type(quick)~="table" then
      errors[#errors+1]="flask, use and quick must be tables"; return errors,warnings
    end
    text("heal_name",config.heal_name); text("hint_event",config.hint_event)
    local channel=config.channel or {}
    if type(channel)~="table" then
      errors[#errors+1]="channel must be a table"; return errors,warnings
    end
    boolean("channel.repeat_while_held",channel.repeat_while_held)
    text("channel.hint_event",channel.hint_event)
    number("flask.use_time",flask.use_time,0,60)
    number("flask.upgrade_charges",flask.upgrade_charges,1,100,true)
    boolean("flask.refill_at_save_points",flask.refill_at_save_points); boolean("flask.refill_on_respawn",flask.refill_on_respawn)
    number("use.move_mult",use.move_mult,0.25,1)
    for _,key in ipairs({"allow_in_air","allow_in_water","interrupt_on_damage","cancel_on_action"}) do boolean("use."..key,use[key]) end
    for _,key in ipairs({"use_animation","sound_use","sound_refuse","fx"}) do text("use."..key,use[key]) end
    boolean("quick.auto_fallback",quick.auto_fallback)
    number("quick.step_repeat_seconds",quick.step_repeat_seconds,0.01,60)
    if type(quick.order)~="table" then errors[#errors+1]="quick.order must be a list"
    else for _,id in ipairs(quick.order) do text("quick.order entry",id) end end
    return errors,warnings
  end
end

-- Display fields use the baseline contract; remaining lighting controls are file-only.
do
  local baseline = M.lighting.custom_validate
  M.lighting.custom_validate = function(config)
    local errors,warnings = baseline(config)
    for _,row in ipairs({{"max_darkness",0,1},{"mask_scale",0.25,1},{"glow_with_mask",0,1},{"max_lights",1,64}}) do
      local value=config[row[1]]
      if type(value)~="number" or value~=value or value<row[2] or value>row[3]
          or (row[1]=="max_lights" and value%1~=0) then
        errors[#errors+1]=row[1].." is outside its range"
      end
    end
    if type(config.light_shape)~="string" or not config.light_shape:match("%S") then
      errors[#errors+1]="light_shape must be a non-empty animation id"
    end
    return errors,warnings
  end
end

-- Helper to check if a value is a valid file path
local function is_valid_path(path)
  if type(path) ~= "string" then return false end
  -- Check if file exists (basic check)
  return path:match("^/") or path:match("^[a-zA-Z]:") -- Starts with / or drive letter
end

-- Helper to check if value is a number in range
local function in_range(min, max)
  return function(value)
    return type(value) == "number" and value >= min and value <= max
  end
end

-- Helper to check if value is one of allowed values
local function one_of(...)
  local allowed = {...}
  return function(value)
    for _, v in ipairs(allowed) do
      if value == v then return true end
    end
    return false
  end
end

-----------------------------------------------------------
-- PLAYER SETTINGS SCHEMA
-----------------------------------------------------------
M.player_settings = {
  name = "Player Settings",
  file = "config/player_settings.lua",
  -- Player settings carries many ability/tuning sub-tables (slide, air_dash,
  -- wall_climb, glide, jump curve tuning, etc.). The required/optional lists
  -- below cover the load-bearing fields; everything else is intentional.
  allow_unknown = true,
  required = {
    -- Movement
    walk_speed = { type = "number", range = {100, 8750}, description = "Player walking speed (pixels/second)" },
    run_speed = { type = "number", range = {200, 8750}, description = "Player running speed (pixels/second)" },
    accel = { type = "number", range = {1, 1000}, description = "Acceleration rate" },
    decel = { type = "number", range = {1, 1000}, description = "Deceleration rate" },

    -- Jumping
    gravity = { type = "number", range = {-8750, 0}, description = "Gravity force (negative number)" },
    jump_height = { type = "number", range = {50, 1750}, description = "Base jump height (pixels)" },
    coyote_time = { type = "number", range = {0, 1.0}, description = "Coyote time (seconds)" },
    jump_buffer = { type = "number", range = {0, 2}, description = "Jump buffer time (seconds)" },

    -- Stats
    max_health = { type = "number", range = {1, 100}, description = "Maximum health" },
    max_energy = { type = "number", range = {0, 100}, description = "Maximum energy" },
    max_stamina = { type = "number", range = {0, 1000}, description = "Maximum stamina" },
  },
  optional = {
    -- Movement controls without earlier config bounds keep accepting authored numbers.
    run_accel = { type = "number", range = {0, 120} },
    speed_jump_bonus = { type = "number", range = {0, 0.5} },
    corner_correction_px = { type = "number", range = {0, 64} },
    turn_brake_mult = { type = "number" },
    air_accel_mult = { type = "number" },
    air_decel_mult = { type = "number" },
    fall_gravity_mult = { type = "number" },
    variable_jump_mode = { type = "string", values = {"gravity_scale", "cut"} },
    jump_release_gravity_mult = { type = "number" },
    jump_cut_speed_mult = { type = "number", range = {0, 1} },
    jump_min_hold_time = { type = "number" },
    apex_hang_speed = { type = "number" },
    apex_gravity_mult = { type = "number" },
    fast_fall_mult = { type = "number" },
    fast_fall_max_mult = { type = "number", range = {1, 3} },
    max_fall_speed_px = { type = "number" },
    air_dash = { fields = {
      speed = { type = "number", optional = true },
      duration = { type = "number", optional = true },
      cooldown = { type = "number", optional = true },
      max_air_dashes = { type = "number", optional = true },
      directions = { type = "string", optional = true },
      suspend_gravity = { type = "boolean", optional = true },
      end_vertical_speed_mult = { type = "number", optional = true },
    }},
    extra_air_dash = { fields = {
      bonus_dashes = { type = "number", optional = true },
    }},
    slide = { fields = {
      speed = { type = "number", optional = true },
      duration = { type = "number", optional = true },
    }},
    glide = { fields = {
      gravity_mult = { type = "number", optional = true },
      max_fall_speed = { type = "number", optional = true },
    }},
    zip_line = { type = "table", fields = {
      hang_offset_px = { type = "number", range = {0, 1000} },
      release_on_jump = { type = "boolean" },
      release_jump_speed = { type = "number", range = {0, 8750} },
      animation = { type = "string" },
    }},
    ladder_climb = { type = "table", fields = {
      hang_idle_animation = { type = "string" },
      hang_move_animation = { type = "string" },
      mesh_animation = { type = "string" },
      hang_offset_px = { type = "number", range = {0, 1000} },
    }},
    lantern = { type = "table", fields = {
      ability_id = { type = "string" },
      radius = { type = "number", range = {32, 1200} },
      intensity = { type = "number", range = {0.1, 4} },
      flicker = { type = "number", range = {0, 1} },
      flicker_hz = { type = "number", range = {0, 100} },
      min_darkness = { type = "number", range = {0, 0.9} },
    }},
    surfaces = { type = "table", fields = {
      ice = { type = "table", fields = {
        accel_mult = { type = "number", range = {0, 1} },
        decel_mult = { type = "number", range = {0, 1} },
        turn_brake_mult = { type = "number", range = {0, 1} },
      }},
    }},
    units_version = { type = "number", values = {1, 2}, description = "Pixel-unit generation; absent means old units (1)" },
    player_scale = { type = "number", range = {PlayerScale.MIN_SCALE, PlayerScale.MAX_SCALE}, description = "Uniform player body and pixel-value scale" },
    scale_movement = { type = "boolean", description = "Scale movement pixel values with player_scale" },
    walk_speed_mode = { type = "string", values = {"scaled", "constant"} },
    run_mode = { type = "string", values = {"hold_button", "toggle"} },
    run_threshold = { type = "number", range = {0, 1.0} },
    walk_stop_deadzone = { type = "number", range = {0, 1.0}, description = "Neutral movement threshold used to clear the run gate" },
    extended_jump_height = { type = "number", range = {0, 875} },
    air_jumps = { type = "number", range = {0, 10} },
    collider_half_height = { type = "number", range = {10, 350} },
    collider_half_width = { type = "number", range = {10, 350} },
    head_margin = { type = "number", range = {0, 350}, description = "Extra head clearance in base pixels" },
    collision_response = { type = "table" },
    spine_physics = { type = "table", fields = {
      bone_map = { type = "table", fields = {
        body = { type = "string" },
        foot_l = { type = "string" },
        foot_r = { type = "string" },
        head = { type = "string" },
      }},
    }},
    wall_climb = { type = "table", fields = {
      contact_grace = { type = "number", range = {0, 1.0} },
      speed = { type = "number", optional = true },
      climb_speed = { type = "number", optional = true },
      stick_speed = { type = "number", optional = true },
      wall_jump = { optional = true, fields = {
        slide_fall_speed = { type = "number", optional = true },
        slide_coyote_time = { type = "number", optional = true },
        push_h = { type = "number", optional = true },
        steer_lock = { type = "number", range = {0, 0.5}, optional = true },
      }},
      ledge_climb = { type = "table", fields = {
        enabled = { type = "boolean" },
        climb_x = { type = "number", range = {0, 1750} },
        climb_y = { type = "number", range = {0, 1750} },
        up_threshold = { type = "number", range = {0, 1.0} },
        climb_time = { type = "number", range = {0.05, 5.0} },
        hang_enabled = { type = "boolean" },
      }},
    }},
    block_grab = { type = "table", fields = {
      enabled = { type = "boolean" },
      pull_speed = { type = "number", range = {0, 8750} },
      release_grace = { type = "number", range = {0, 1.0} },
    }},
  }
}

-----------------------------------------------------------
-- PLAYER ACTIONS SCHEMA
-----------------------------------------------------------
M.player_actions = {
  name = "Player Actions",
  file = "config/player_actions.lua",
  -- Action tuning lives in many optional sub-tables (parry, interact, potion,
  -- grapple, contact attacks, etc.). Validate the load-bearing actions and
  -- allow extra ones without warning.
  allow_unknown = true,
  required = {
    melee_light = { type = "table", fields = {
      damage = { type = "number", range = {0, 100} },
      cooldown = { type = "number", range = {0, 5.0} },
      active = { type = "number", range = {0, 2.0} },
    }},
    melee_heavy = { type = "table", fields = {
      damage = { type = "number", range = {0, 100} },
      cooldown = { type = "number", range = {0, 5.0} },
      active = { type = "number", range = {0, 2.0} },
    }},
  },
  optional = {
    ranged = { type = "table" },
    down_strike = { type = "table" },
    charge_attack = { type = "table" },
    air_dash = { type = "table" },
    slide = { type = "table" },
    backdash = { type = "table" },
    ground_pound = { type = "table" },
  }
}

-----------------------------------------------------------
-- ENEMY SETTINGS SCHEMA
-----------------------------------------------------------
M.enemy_settings = {
  name = "Enemy Settings",
  file = "config/enemy_settings.lua",
  allow_unknown = true,
  optional = {
    remove_spawned_enemies_on_room_exit = { type = "boolean" },
    global_difficulty_mult = { type = "number", range = {0.1, 10.0} },
    global_health_mult = { type = "number", range = {0.1, 10.0} },
    global_damage_mult = { type = "number", range = {0.1, 10.0} },
    global_speed_mult = { type = "number", range = {0.1, 10.0} },
  }
}

-----------------------------------------------------------
-- GAMEPLAY CONSTANTS SCHEMA
-----------------------------------------------------------
M.gameplay_constants = {
  name = "Gameplay Constants",
  file = "config/gameplay_constants.lua",
  -- Top-level groups (player, audio, physics, ui, rooms, tiles, combat)
  -- are intentionally open-ended tuning buckets.
  allow_unknown = true,
  optional = {
    TILE_SIZE = { type = "number", range = {8, 128} },
    PIXELS_PER_METER = { type = "number", range = {10, 1000} },
    TARGET_FPS = { type = "number", range = {30, 144} },
  }
}

-----------------------------------------------------------
-- DEFAULT BINDINGS SCHEMA
-----------------------------------------------------------
M.default_bindings = {
  name = "Default Bindings",
  file = "config/default_bindings.lua",
  required = {
    inputs = { type = "table", description = "Allowlist of low-level actions emitted by the input binding asset" },
    actions = { type = "table", description = "Physical keyboard and controller inputs mapped to high-level actions" },
  },
  optional = {
    remappable = { type = "table", description = "Ordered action rows with separate keyboard/controller capture slots" },
    -- The pure custom validator applies this range to each action's value.
    hold_seconds = { type = "table", range = require("mvtk.core.input_binding_rules").HOLD_RANGE,
      description = "Per-action hold thresholds, 0.05 to 5 seconds" },
  },
  custom_validate = function(config)
    return require("mvtk.core.input_binding_rules").validate(config), {}
  end,
}

-----------------------------------------------------------
-- DEBUG CONFIG SCHEMA
-----------------------------------------------------------
M.debug_config = {
  name = "Debug Config",
  file = "config/debug_config.lua",
  -- Per-subsystem debug toggles (gameplay/rendering/audio/ui/physics/etc.)
  -- are open-ended; only `global` is required.
  allow_unknown = true,
  required = {
    global = { type = "table", fields = {
      enable = { type = "boolean" },
    }},
  },
  optional = {
    gameplay = { type = "table" },
    rendering = { type = "table" },
    audio = { type = "table" },
  }
}

-----------------------------------------------------------
-- ADDITIONAL CRITICAL CONFIGS
-----------------------------------------------------------

M.boss_behaviors = {
    name = "Boss Behaviours",
    file = "developer/config/boss_behaviors.lua",
    allow_unknown = true,
    custom_validate = function(config)
        local shipped = require("mvtk.bosses.attack_schedule_defaults").behaviors
        local errors = {}
        for name, profile in pairs(config) do
            if not shipped[name] or type(profile) ~= "table" then
                errors[#errors + 1] = tostring(name) .. ": expected a known boss behaviour and a table of weights"
            else
                for kind, value in pairs(profile) do
                    if not shipped[name][kind] then
                        errors[#errors + 1] = name .. ": unknown attack kind " .. tostring(kind)
                    elseif type(value) ~= "number" or not (value > 0 and value < math.huge)
                        or kind == "max_repeat" and (value < 1 or value % 1 ~= 0) then
                        errors[#errors + 1] = name .. ": invalid value for " .. kind
                    end
                end
            end
        end
        table.sort(errors)
        return errors
    end,
}

M.boss_movesets = {
    name = "Boss Movesets",
    file = "developer/config/boss_movesets.lua",
    allow_unknown = true,
    custom_validate = function(config)
        local Scheduler = require "mvtk.bosses.attack_scheduler"
        local patterns = {}
        for name, pattern in pairs(require "mvtk.bosses.patterns.attack_patterns") do
            patterns[name] = type(pattern) == "table"
        end
        for name, pattern in pairs(require "developer.config.attack_patterns") do
            patterns[name] = type(pattern) == "table"
        end

        local errors, warnings, valid = {}, {}, {}
        for name, moveset in pairs(config) do
            local found, notes = Scheduler.validate(name, moveset, patterns)
            if type(name) ~= "string" or not name:match("%S") or name == "none" then
                found[#found + 1] = "invalid moveset name " .. tostring(name)
            end
            for _, err in ipairs(found) do errors[#errors + 1] = err end
            for _, warning in ipairs(notes) do warnings[#warnings + 1] = warning end
            if #found == 0 then valid[name] = moveset end
        end
        for name, preset in pairs(require "developer.config.boss_types") do
            for index, phase in ipairs(preset.phases or {}) do
                local moveset = valid[phase.moveset]
                if moveset then
                    -- Validate coverage using the profile of this assignment.
                    local view = setmetatable({movement_profile = phase.movement_profile or preset.movement_profile
                        or "ground_chase"}, {__index = moveset})
                    local _, notes = Scheduler.validate(name .. " phase " .. index .. " (" .. phase.moveset .. ")",
                        view, patterns)
                    for _, warning in ipairs(notes) do warnings[#warnings + 1] = warning end
                end
            end
        end
        table.sort(errors)
        table.sort(warnings)
        return errors, warnings
    end,
}

M.boss_types = {
    name = "Boss Types",
    file = "developer/config/boss_types.lua",
    entries = {
        optional = {
            ground_motion = {type = "boolean", description = "Opt in to boss terrain movement"},
            feet_offset = {type = "number", description = "Pixels below the boss centre that stand on the floor"},
            teleport_interval = {type = "number", range = {0, math.huge}, description = "Seconds between idle blinks"},
            teleport_anchors = {type = "table", description = "Ordered anchor names for idle blinks"},
        },
        allow_unknown = true,
    },
    custom_validate = function(config)
        local errors = {}
        for name, preset in pairs(config) do
            local feet = type(preset) == "table" and preset.feet_offset
            if type(feet) == "number" and not (feet > 0 and feet < math.huge) then
                errors[#errors + 1] = tostring(name) .. ".feet_offset must be finite and greater than 0"
            end
        end
        table.sort(errors)
        return errors
    end,
}

M.enemy_types = {
  name = "Enemy Types",
  file = "developer/config/enemy_types.lua",
  entries = {
    required = {
      health = { type = "number", range = {1, 10000}, description = "Base health points" },
      damage = { type = "number", range = {0, 1000}, description = "Base damage dealt" },
      speed = { type = "number", range = {0, 2000}, description = "Movement speed" },
    },
    optional = {
      random_drop_chance = {type="number", range={0,1}, description="Override the project random equipment chance; 0 never rolls"},
      respawn = { type = "string", values = {"always", "room_reload", "save", "never"}, description = "Placed defeat policy; instance overrides archetype, then project default" },
      behavior = { type = "string", description = "AI behavior type" },
      stop_at_ledges = { type = "boolean", description = "Ground movers stop at drops; overrides enemy_defaults" },
      ledge_margin = { type = "number", description = "World pixels from the enemy centre to the edge; overrides enemy_defaults" },
      drops = { type = "table", description = "Loot drop table reference" },
      abilities = { type = "table", description = "Special enemy abilities" },
      spawn_fx = { type = "string", description = "Spawn effect name" },
      death_fx = { type = "string", description = "Death effect name" },
      collision_groups = { type = "table", description = "Physics collision groups" },
      hitbox_width = { type = "number", range = {1, 500}, description = "Hitbox width in pixels" },
      hitbox_height = { type = "number", range = {1, 500}, description = "Hitbox height in pixels" },
    },
    allow_unknown = true, -- allow extra tuning fields
  },
}

M.room_enemies = {
  name = "Room Enemies",
  file = "developer/config/room_enemies.lua",
  entries = {
    required = {
      enemies = { type = "table", description = "Array of enemy spawn configs" },
    },
    optional = {
      difficulty_tier = { type = "number", range = {1, 10}, description = "Room difficulty level" },
      spawn_delay = { type = "number", range = {0, 60}, description = "Delay before spawning (seconds)" },
      max_active = { type = "number", range = {1, 100}, description = "Maximum concurrent enemies" },
    },
    allow_unknown = true,
  },
}

M.tile_settings = {
  name = "Tile Settings",
  file = "developer/config/tile_settings.lua",
  -- Tile authors may add derived helpers (half_width, half_height, size_half).
  allow_unknown = true,
  required = {},
  optional = {
    tile_width = { type = "number", range = {8, 512}, description = "Tile width in pixels" },
    tile_height = { type = "number", range = {8, 512}, description = "Tile height in pixels" },
    width = { type = "number", range = {8, 512}, description = "Alias for tile_width" },
    height = { type = "number", range = {8, 512}, description = "Alias for tile_height" },
    size = { type = "number", range = {8, 512}, description = "Alias for square tile size" },
    tileset_path = { type = "string", description = "Path to tileset image" },
    collision_layer = { type = "string", description = "Default collision layer name" },
    tile_mappings = { type = "table", description = "Tile ID to type mappings" },
  },
  custom_validate = function(cfg)
    local errs, warns = {}, {}
    if type(cfg) ~= "table" then return {"tile_settings: expected table"}, warns end
    local w = cfg.tile_width or cfg.width or cfg.size
    local h = cfg.tile_height or cfg.height or cfg.size
    if not w then table.insert(errs, "tile_settings missing tile_width (set tile_width or width/size)") end
    if not h then table.insert(errs, "tile_settings missing tile_height (set tile_height or height/size)") end
    return errs, warns
  end,
}

M.collectible_types = {
  name = "Collectible Types",
  file = "developer/config/collectible_types.lua",
  entries = {
    required = {},
    optional = {
      type = { type = {"string"}, values = {"health", "energy", "currency", "key", "upgrade", "lore", "progression", "ability"}, description = "Collectible category" },
      category = { type = {"string"}, description = "Alias for type/category" },
      on_collect = { type = {"string", "function"}, description = "Handler function name or callback function" },
      value = { type = "number", range = {0, 10000}, description = "Numeric value (health, currency, etc.)" },
      notification = { type = {"boolean", "string"}, description = "Show pickup notification (bool or message)" },
      sfx = { type = "string", description = "Pickup sound effect" },
      sprite_path = { type = "string", description = "Visual sprite asset path" },
      flag_set = { type = "string", description = "Flag to set on collection" },
    },
    allow_unknown = true,
  },
  custom_validate = function(cfg)
    local errs, warns = {}, {}
    if type(cfg) ~= "table" then return {"collectible_types: expected table"}, warns end
    for id, entry in pairs(cfg) do
      if type(entry) == "table" then
        local t = entry.type or entry.category
        if not t then
          table.insert(errs, string.format("collectible_types[%s]: provide 'type' (or 'category') to describe the collectible category", tostring(id)))
        end
      end
    end
    -- Also runs at game startup: bundled catalogs only, never project-file IO.
    local generator = require "mvtk.collectibles.generated_types"
    local catalogs, checked = {}, {}
    for _, spec in ipairs(generator.SPECS) do
      local ok, catalog = pcall(require, spec.module)
      if ok then catalogs[spec.catalog] = catalog end
    end
    catalogs.upgrades = require "developer.config.upgrades"
    for id, entry in pairs(cfg) do checked[id] = entry end
    setmetatable(checked, getmetatable(cfg))
    local _, diagnostics = generator.append(checked, catalogs)
    for _, diagnostic in ipairs(diagnostics) do
      errs[#errs + 1] = "collectible_types[" .. diagnostic.key .. "]: authored id collides with "
        .. diagnostic.source .. " id '" .. diagnostic.id .. "'"
    end
    return errs, warns
  end,
}

M.loot_tables = {
  name = "Loot Tables",
  file = "developer/config/loot_tables.lua",
  entries = {
    required = {
      items = { type = "table", description = "Array of drop entries" },
    },
    optional = {
      drop_limit = { type = "number", range = {1, 100}, description = "Maximum items to drop" },
    },
    allow_unknown = true,
  },
  custom_validate = function(cfg)
    local errs, warns = {}, {}
    if type(cfg) ~= "table" then return {"loot_tables: expected table"}, warns end
    for table_id, entry in pairs(cfg) do
      if type(entry) == "table" and type(entry.items) == "table" then
        for i, drop in ipairs(entry.items) do
          if type(drop) ~= "table" then
            table.insert(errs, string.format("loot_tables[%s].items[%d] must be a table", tostring(table_id), i))
          elseif not drop.type then
            table.insert(errs, string.format("loot_tables[%s].items[%d] missing 'type'", tostring(table_id), i))
          end
        end
      end
    end
    return errs, warns
  end,
}

M.loot_tables_authored = {
  name = "Loot Tables (authored)",
  file = "developer/config/loot_tables_authored.lua",
  entries = M.loot_tables.entries,
  custom_validate = M.loot_tables.custom_validate,
}

M.gates = {
  name = "Gates",
  file = "developer/config/gates.lua",
  entries = {
    required = {
      gate_type = { type = "string", description = "Gate type id from gate_types.lua" },
    },
    optional = {
      required_action = { type = "string", description = "Action tag needed to open action barriers" },
      required_ability = { type = "string", description = "Ability needed to open gate" },
      required_item = { type = "string", description = "Item needed to open gate" },
      required_flag = { type = "string", description = "Flag that must be set" },
      position = { type = "table", description = "Gate world position {x, y}" },
      one_way = { type = "boolean", description = "Can only pass in one direction" },
      locked_message = { type = "string", description = "Message shown when locked" },
    },
    allow_unknown = true,
  },
  custom_validate = function(cfg)
    local errs, warns = {}, {}
    local ok_types, gate_types = SafeRequire("developer.config.gate_types", "mvtk.core.config_schemas")
    local valid = {}
    if ok_types and type(gate_types) == "table" then
      for id, _ in pairs(gate_types) do
        valid[id] = true
      end
    end

    for idx, entry in pairs(cfg or {}) do
      if type(entry) == "table" then
        local gate_type = entry.gate_type
        if gate_type and not valid[gate_type] then
          table.insert(errs, string.format("gates[%s] uses unknown gate_type '%s' (define in developer/config/gate_types.lua)", tostring(entry.id or idx), tostring(gate_type)))
        end
      end
    end

    return errs, warns
  end,
}

M.biomes = {
  name = "Biomes",
  file = "developer/config/biomes.lua",
  entries = {
    required = {
      name = { type = "string", description = "Region name shown to players; blank means an unnamed region" },
    },
    optional = {
      tileset = { type = "string", description = "Tileset used for this biome" },
      subtitle = { type = "string", description = "Optional line under the region name" },
      title_card = { type = "string", values = { "first_visit", "every_entry", "never" },
        description = "When the region title card shows; absent inherits Game Settings" },
      music = { type = "string", description = "Music track id for rooms in this region without their own music" },
      ambience = { type = "string", description = "Ambient sound id for rooms in this region without their own" },
      enemy_spawn_table = { type = "string", description = "Reference to enemy spawn config" },
      lighting = { type = "table", description = "Biome lighting settings" },
      parallax_layers = { type = "table", description = "Background parallax layers" },
      hazards = { type = "table", description = "Environmental hazards (spikes, lava, etc.)" },
    },
    allow_unknown = true,
  },
}

M.abilities = {
  name = "Abilities",
  file = "developer/config/abilities.lua",
  required = {
    abilities = { type = "table", description = "Ability definitions keyed by id" },
  },
  optional = {
    stamina = { type = "table", description = "Stamina defaults" },
  },
  custom_validate = function(cfg)
    local errs, warns = {}, {}
    local defs = cfg.abilities or {}
    for id, def in pairs(defs) do
      if type(def) ~= "table" then
        table.insert(errs, string.format("abilities[%s] must be a table", tostring(id)))
      else
        if not def.name then table.insert(errs, string.format("abilities[%s] missing 'name'", tostring(id))) end
        if def.cooldown and type(def.cooldown) ~= "number" then
          table.insert(errs, string.format("abilities[%s].cooldown must be number", tostring(id)))
        end
      end
    end
    return errs, warns
  end,
}

M.items = {
  name = "Items",
  file = "developer/config/items.lua",
  entries = {
    required = {
      name = { type = "string", description = "Display name" },
    },
    optional = {
      desc = { type = "string", description = "Short description" },
      unique = { type = "boolean", description = "Only one owned copy in grants" },
      sellable = { type = "boolean", description = "False prevents selling" },
      price = { type = "number", range = {0, math.huge}, description = "Integer buying and selling base" },
    },
    allow_unknown = true,
  },
}

M.items.custom_validate = function(config)
  local errors = {}
  for id, item in pairs(config) do
    local price
    if type(item) == "table" then price = item.price end
    if price ~= nil and (type(price) ~= "number" or price ~= price
        or price < 0 or price == math.huge or price % 1 ~= 0) then
      errors[#errors+1] = tostring(id)..".price must be an integer >= 0"
    end
  end
  return errors, {}
end

M.random_drops = {
  name="Random drops", file="developer/config/random_drops.lua", allow_unknown=false,
  required={enabled={type="boolean"}, chance={type="number", range={0,1}},
    weapons={type="boolean"}, charms={type="boolean"}, upgrades={type="boolean"},
    duplicate_currency={type="number", range={0,math.huge}}},
  custom_validate=function(config)
    local n = config.duplicate_currency
    if type(n) ~= "number" or n ~= n or n == math.huge or n < 0 or n % 1 ~= 0 then
      return {"random_drops.duplicate_currency must be a whole non-negative amount"}, {}
    end
    return {}, {}
  end,
}

-- Map item tracking (developer/config/map_icons.lua). Pure data, also editor-loaded.
M.map_icons = {
  name="Map icons", file="developer/config/map_icons.lua", allow_unknown=false,
  required={item_tracking={type="table"}, room_complete={type="table"}, minimap={type="table"},
    dim_alpha={type="number", range={0,1}}, kinds={type="table"}, icons={type="table"}},
  custom_validate=function(config)
    local errors = {}
    local function bad(path, rule) errors[#errors+1] = "map_icons."..path.." "..rule end
    local shapes = {square=true, diamond=true, circle=true, ring=true}
    local styles = {hide=true, dim=true, outline=true, normal=true}
    local function rule_ok(rule)
      if rule=="always" or rule=="visited" or rule=="seen" or rule=="mapped" or rule=="never" then return true end
      return type(rule)=="string" and (rule:match("^ability:%S+$") or rule:match("^flag:%S+$")) ~= nil
    end
    local function color_ok(c)
      if type(c) ~= "table" then return false end
      for _, key in ipairs({"r","g","b","a"}) do
        local v = c[key]
        if (key ~= "a" or v ~= nil) and (type(v) ~= "number" or v ~= v or v < 0 or v > 1) then return false end
      end
      return true
    end
    local tracking = type(config.item_tracking)=="table" and config.item_tracking or {}
    if type(tracking.enabled) ~= "boolean" then bad("item_tracking.enabled","must be true or false") end
    if ({seen=true, visited=true, mapped=true, always=true})[tracking.rule] == nil then
      bad("item_tracking.rule","must be seen, visited, mapped or always")
    end
    if type(tracking.require_flag) ~= "string" then bad("item_tracking.require_flag","must be text (\"\" for none)") end
    local complete = type(config.room_complete)=="table" and config.room_complete or {}
    if type(complete.enabled) ~= "boolean" then bad("room_complete.enabled","must be true or false") end
    if not color_ok(complete.color) then bad("room_complete.color","must be {r, g, b, a} from 0 to 1") end
    local minimap = type(config.minimap)=="table" and config.minimap or {}
    if type(minimap.show) ~= "boolean" then bad("minimap.show","must be true or false") end
    local n = minimap.max_icons
    if type(n) ~= "number" or n ~= n or n < 0 or n > 192 or n % 1 ~= 0 then bad("minimap.max_icons","must be a whole number from 0 to 192") end
    for _, section in ipairs({"kinds","icons"}) do
      for id, row in pairs(type(config[section])=="table" and config[section] or {}) do
        local path = section.."."..tostring(id)
        if type(id) ~= "string" or not id:match("^[%w_]+$") then bad(path,"has an invalid id")
        elseif type(row) ~= "table" then bad(path,"must be a table")
        else
          if row.shape ~= nil and not shapes[row.shape] then bad(path..".shape","must be square, diamond, circle or ring") end
          if row.color ~= nil and not color_ok(row.color) then bad(path..".color","must be {r, g, b, a} from 0 to 1") end
          if row.label ~= nil and type(row.label) ~= "string" then bad(path..".label","must be text") end
          if section == "kinds" then
            if row.rule ~= nil and not rule_ok(row.rule) then bad(path..".rule","must be always, visited, seen, mapped, never, ability:<id> or flag:<name>") end
            if row.collected ~= nil and not styles[row.collected] then bad(path..".collected","must be hide, dim, outline or normal") end
            if row.color_from ~= nil and type(row.color_from) ~= "string" then bad(path..".color_from","must be a world map colour name") end
            if row.hidden_until_found ~= nil and type(row.hidden_until_found) ~= "boolean" then bad(path..".hidden_until_found","must be true or false") end
            for key in pairs(row) do
              if not ({shape=true,color=true,label=true,rule=true,collected=true,color_from=true,hidden_until_found=true})[key] then
                bad(path.."."..tostring(key),"is not a map icon kind field")
              end
            end
          else
            for key in pairs(row) do
              if not ({shape=true,color=true,label=true})[key] then bad(path.."."..tostring(key),"is not a map icon field") end
            end
          end
        end
      end
    end
    return errors, {}
  end,
}

M.upgrades = {
  name = "Upgrades", file = "developer/config/upgrades.lua", allow_unknown = false,
  required = {upgrades = {type = "table"}},
  custom_validate = function(config)
    local errors = {}
    local defs = type(config.upgrades) == "table" and config.upgrades or {}
    local effects = {max_health=true, max_energy=true, max_stamina=true, damage_mult=true}
    local function bad(path, rule) errors[#errors+1] = path.." "..rule end
    for id, def in pairs(defs) do
      local path = "upgrades."..tostring(id)
      if type(id) ~= "string" or not id:match("^[A-Za-z0-9_][A-Za-z0-9_.%-]*$") then bad(path,"has an invalid id") end
      if type(def) ~= "table" then bad(path,"must be a table")
      else
        if type(def.name) ~= "string" or not def.name:find("%S") then bad(path..".name","must be nonblank text") end
        if type(def.description) ~= "string" then bad(path..".description","must be text") end
        for _, key in ipairs({"random_drop", "count_in_census"}) do
          if def[key] ~= nil and type(def[key]) ~= "boolean" then bad(path.."."..key,"must be boolean") end
        end
        for _, key in ipairs({"icon_animation", "collect_sound"}) do
          if def[key] ~= nil and (type(def[key]) ~= "string" or def[key] == "") then bad(path.."."..key,"must be nonblank text") end
        end
        local values = {}
        for key, value in pairs(def) do
          if effects[key] then values[key] = value
          elseif key ~= "name" and key ~= "description" and key ~= "requires"
              and key ~= "random_drop" and key ~= "count_in_census" and key ~= "icon_animation" and key ~= "collect_sound" then
            bad(path.."."..tostring(key),"is not a permanent ledger effect")
          end
        end
        local effect_errors = require("mvtk.player.stat_keys").validate_effects(values, {layer = "permanent"})
        for _, err in ipairs(effect_errors) do bad(path,err) end
        if def.requires ~= nil then
          if type(def.requires) ~= "table" then bad(path..".requires","must be a list")
          else
            for key, required in pairs(def.requires) do
              if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #def.requires
                  or type(required) ~= "string" or not defs[required] then
                bad(path..".requires","must list known upgrades")
              end
            end
          end
        end
      end
    end
    local visiting, visited = {}, {}
    local function visit(id)
      if visiting[id] then bad("upgrades."..id..".requires","contains a cycle"); return end
      if visited[id] then return end
      visiting[id] = true
      local def = defs[id]
      if type(def) == "table" and type(def.requires) == "table" then
        for _, required in ipairs(def.requires) do if type(required) == "string" and defs[required] then visit(required) end end
      end
      visiting[id], visited[id] = nil, true
    end
    for id in pairs(defs) do if type(id) == "string" then visit(id) end end
    return errors, {}
  end,
}

local shops_baseline_validate = M.shops.custom_validate
M.shops = {
  name = "Shops", file = "developer/config/shops.lua", allow_unknown = false,
  required = {settings = {type = "table"}, catalogs = {type = "table"}},
  custom_validate = function(config)
    local errors = shops_baseline_validate(config)
    local function bad(path, rule) errors[#errors+1] = path.." "..rule end
    local function integer(n, min) return type(n) == "number" and n == n and n < math.huge and n >= min and n % 1 == 0 end
    local settings = type(config.settings) == "table" and config.settings or {}
    if type(settings.autosave_after_purchase) ~= "boolean" then bad("settings.autosave_after_purchase","must be boolean") end
    -- Older creator configs may omit bank and use the shipped defaults.
    if settings.bank ~= nil then
      local bank_settings = settings.bank
      if type(bank_settings) ~= "table" then bad("settings.bank", "must be a table")
      else
        if type(bank_settings.autosave) ~= "boolean" then bad("settings.bank.autosave", "must be boolean") end
        if type(bank_settings.steps) ~= "table" then bad("settings.bank.steps", "must be an ordered list")
        else
          local count = 0
          for i, n in pairs(bank_settings.steps) do
            count = count + 1
            if not integer(i, 1) or i > #bank_settings.steps or not integer(n, 1) then
              bad("settings.bank.steps", "must list positive whole amounts in order")
            end
          end
          if count ~= #bank_settings.steps then bad("settings.bank.steps", "must not have gaps") end
        end
      end
    end
    local sounds = type(settings.sounds) == "table" and settings.sounds or {}
    local bank = require "developer.config.sound_bank"
    for _, key in ipairs({"buy", "fail"}) do
      if type(sounds[key]) ~= "string" or not bank.sfx[sounds[key]] then bad("settings.sounds."..key,"must name a sound_bank sfx") end
    end
    local Spec = require "mvtk.game.grant_spec"
    local env = Spec.authoring_env({items = require "developer.config.items",
      upgrades = require "developer.config.upgrades", abilities = require "developer.config.abilities", weapons = require "developer.config.weapons",
      collectible_types = require "developer.config.collectible_types", key_ids = require "mvtk.core.key_ids",
      skip_travel_validation = true, instance_id = "config:shop", position = {x=0,y=0}})
    for id, catalog in pairs(type(config.catalogs) == "table" and config.catalogs or {}) do
      local path = "catalogs."..tostring(id)
      if type(id) ~= "string" or id == "none" or not id:match("^[A-Za-z0-9_][A-Za-z0-9_.%-]*$") then bad(path,"has an invalid id") end
      if type(catalog) ~= "table" then bad(path,"must be a table")
      else
        if type(catalog.name) ~= "string" or not catalog.name:find("%S") then bad(path..".name","must be nonblank text") end
        if type(catalog.entries) ~= "table" then bad(path..".entries","must be a list (which may be empty)")
        else
          local seen = {}
          for i, entry in pairs(catalog.entries) do
            local at = path..".entries."..tostring(i)
            if type(i) ~= "number" or i < 1 or i % 1 ~= 0 or i > #catalog.entries then bad(at,"must be an ordered list entry") end
            if type(entry) ~= "table" then bad(at,"must be a table")
            else
              if type(entry.id) ~= "string" or not entry.id:match("^[A-Za-z0-9_][A-Za-z0-9_.%-]*$") then bad(at..".id","must be a stable id")
              elseif seen[entry.id] then bad(at..".id","duplicates another entry") else seen[entry.id] = true end
              if not integer(entry.price,0) then bad(at..".price","must be an integer >= 0") end
              if entry.stock ~= nil and not integer(entry.stock,1) then bad(at..".stock","must be an integer >= 1") end
              local ok, ds, gives = Spec.validate(entry.gives,env)
              if not ok or #gives == 0 then bad(at..".gives","must contain valid grants") end
              for _, d in ipairs(ds) do if d.severity == "error" then bad(at..".gives",d.message) end end
              if entry.requires ~= nil then bad(at..".requires","belongs in upgrades.lua") end
              for _, key in ipairs({"requires_flag", "locked_text", "set_flag", "name", "description"}) do
                if entry[key] ~= nil and type(entry[key]) ~= "string" then bad(at.."."..key,"must be text") end
              end
              for _, key in ipairs({"show_locked", "confirm"}) do
                if entry[key] ~= nil and type(entry[key]) ~= "boolean" then bad(at.."."..key,"must be boolean") end
              end
              if entry.cost_items ~= nil then
                if type(entry.cost_items) ~= "table" then bad(at..".cost_items","must be an item/count map")
                else
                  for item, count in pairs(entry.cost_items) do
                    local valid = type(item) == "string" and item:match("^[A-Za-z0-9_][A-Za-z0-9_.%-]*$")
                        and Spec.validate("item:"..item,env)
                    if not valid or not integer(count,1) then bad(at..".cost_items","requires known items and positive integer counts") end
                  end
                end
              end
            end
          end
        end
      end
    end
    return errors, {}
  end,
}

M.reward_text = {
  name = "Reward Text", file = "developer/config/reward_text.lua", allow_unknown = false,
  required = {
    xp_format = { type = "string" }, separator = { type = "string" }, count_format = { type = "string" },
    fast_travel_format = { type = "string" }, notice_duration = { type = "number", range = { 0, 60 } },
    hidden_kinds = { type = "table" },
  },
  custom_validate = function(config)
    local errors = {}
    for kind, hidden in pairs(config.hidden_kinds or {}) do
      if type(kind) ~= "string" or type(hidden) ~= "boolean" then
        errors[#errors + 1] = "hidden_kinds requires text keys and boolean values"
      end
    end
    return errors, {}
  end,
}

M.npc_types = {
  name = "NPC Types",
  file = "developer/config/npc_types.lua",
  entries = {
    required = {
      name = { type = "string", description = "Display name" },
    },
    optional = {
      sprite = { type = "string" },
      dialogue_id = { type = "string" },
      vendor_shop = { type = "string" },
      -- WM12a: NPCs of this type show the new-dialogue marker unless a placed
      -- NPC's Behavior group overrides it.
      show_new_dialogue_marker = { type = "boolean" },
      -- WM12b: ambient lines for NPCs of this type with no Barks of their own.
      barks = { type = "table", description = "List of short source-text lines" },
      -- WM12c: {title = text, bio = text, order = number} lists this type in
      -- Journal > People.
      journal = { type = "table" },
    },
    allow_unknown = true,
  },
  custom_validate = function(config)
    local errors = {}
    for id, def in pairs(type(config) == "table" and config or {}) do
      local journal = type(def) == "table" and def.journal or nil
      if type(journal) == "table" then
        local where = "npc_types.lua: " .. tostring(id) .. ".journal"
        for _, key in ipairs({"title", "bio"}) do
          if journal[key] ~= nil and type(journal[key]) ~= "string" then errors[#errors+1] = where .. "." .. key .. " must be text" end
        end
        local order = journal.order
        if order ~= nil and (type(order) ~= "number" or order ~= order or order == math.huge or order == -math.huge) then
          errors[#errors+1] = where .. ".order must be a number"
        end
        for key in pairs(journal) do
          if key ~= "title" and key ~= "bio" and key ~= "order" then errors[#errors+1] = where .. ": unknown field " .. tostring(key) end
        end
      end
    end
    return errors, {}
  end,
}

M.map_markers = {
  name = "Map Markers",
  file = "developer/config/map_markers.lua",
  custom_validate = function(cfg)
    local errs, warns = {}, {}
    if type(cfg) ~= "table" then return {"map_markers.lua must return a table"}, warns end
    for room_id, markers in pairs(cfg) do
      if type(markers) == "table" then
        for i, m in ipairs(markers) do
          if type(m) ~= "table" then
            table.insert(errs, string.format("map_markers[%s][%d] must be a table", tostring(room_id), i))
          else
            if not m.x or not m.y then
              table.insert(errs, string.format("map_markers[%s][%d] missing x/y", tostring(room_id), i))
            end
          end
        end
      end
    end
    return errs, warns
  end,
}

M.tiled_object_config = {
  name = "Tiled Object Config",
  file = "developer/config/tiled_object_config.lua",
  required = {
    paths = { type = "table" },
    y_offsets = { type = "table" },
  },
  optional = {
    surface_layers = { type = "table", fields = {
      ice = { type = "table", fields = {
        probe_margin_px = { type = "number", range = {0, 1000} },
      }},
    }},
  },
}

local function loose_table_schema(name, file)
  return {
    name = name,
    file = file,
    allow_unknown = true,
    required = {},
    optional = {},
  }
end

M.ability_defaults = loose_table_schema("Ability Defaults", "developer/config/ability_defaults.lua")
M.gate_types = loose_table_schema("Gate Types", "developer/config/gate_types.lua")
M.hazard_types = loose_table_schema("Hazard Types", "developer/config/hazard_types.lua")
M.hazard_types.custom_validate = function(config)
  local errors = {}
  local blink = (config.settings or {}).arena_warn_blink_period
  if blink ~= nil and (type(blink) ~= "number" or blink ~= blink or blink < 0.01 or blink > 2) then
    errors[#errors+1] = "settings.arena_warn_blink_period must be in [0.01,2]"
  end
  for id, cfg in pairs(config) do
    if id ~= "settings" and type(cfg) == "table" then
      if cfg.on_contact ~= nil and cfg.on_contact ~= "damage" and cfg.on_contact ~= "safe_return" and cfg.on_contact ~= "kill" then
        errors[#errors+1] = tostring(id) .. ".on_contact must be damage, safe_return or kill"
      end
      local value = cfg.return_damage
      if value ~= nil and (type(value) ~= "number" or value ~= value or value < 0 or value == math.huge) then
        errors[#errors+1] = tostring(id) .. ".return_damage must be a finite number >= 0"
      end
      local slow = cfg.slow_multiplier
      if slow ~= nil and (type(slow) ~= "number" or slow ~= slow or slow < 0.25 or slow > 1) then
        errors[#errors+1] = tostring(id)..".slow_multiplier must be in [0.25,1]"
      end
      if cfg.status_effect ~= nil and not require("developer.config.status_effects").effects[cfg.status_effect] then
        errors[#errors+1] = tostring(id)..".status_effect must name a known status"
      end
      local chance = cfg.status_chance
      if chance ~= nil and (type(chance) ~= "number" or chance ~= chance or chance < 0 or chance > 1) then
        errors[#errors+1] = tostring(id)..".status_chance must be in [0,1]"
      end
    end
  end
  return errors, {}
end
M.movement_zone_types = loose_table_schema("Movement Zone Types", "developer/config/movement_zone_types.lua")
M.carry_settings = {
  name="Carry Settings", file="developer/config/carry_settings.lua", allow_unknown=false,
  required={hold_above_ratio={type="number",range={0,10}}, throw_angle={type="number",range={0,180}},
    up_throw_angle={type="number",range={0,180}}, return_delay={type="number",range={0,60}},
    kinds={type="table"}, animations={type="table"}},
  custom_validate=function(config)
    local errors = {}
    for id,kind in pairs(config.kinds or {}) do
      if type(kind) ~= "table" then errors[#errors+1]=tostring(id).." must be a table"
      else
        for _,key in ipairs({"impact_damage","radius_tiles","damage"}) do
          local v=kind[key]
          if v ~= nil and (type(v) ~= "number" or v ~= v or v < 0 or v == math.huge
            or (key == "radius_tiles" and v == 0)) then errors[#errors+1]=tostring(id).."."..key.." must be finite and positive (damage permits zero)" end
        end
        if kind.explodes and (type(kind.radius_tiles) ~= "number" or type(kind.damage) ~= "number") then
          errors[#errors+1]=tostring(id).." exploding kind requires radius_tiles and damage"
        end
        if kind.hit_tag ~= nil and type(kind.hit_tag) ~= "string" then errors[#errors+1]=tostring(id)..".hit_tag must be text" end
      end
    end
    for _,key in ipairs({"idle","move"}) do
      if type((config.animations or {})[key]) ~= "string" then errors[#errors+1]="animations."..key.." must be text (blank keeps normal states)" end
    end
    table.sort(errors)
    return errors, {}
  end,
}
M.movement_zone_types.custom_validate = function(config)
  local errors = {}
  local Keys = require "mvtk.player.stat_keys"
  for id, preset in pairs(config) do
    if type(preset) ~= "table" then
      errors[#errors + 1] = tostring(id) .. " must be a table"
    else
      for key, value in pairs(preset) do
        local err
        if key == "sink_speed" then
          if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
            err = "must be finite with floor 0"
          end
        elseif key == "escape_jumps" then
          if type(value) ~= "boolean" then err = "must be boolean" end
        elseif key == "gravity_mult" or key == "max_fall_mult" or key == "speed_mult" or key == "jump_mult" then
          local def = Keys.definition(key)
          if Keys.effect_error(key, value, "temporary") then
            err = "must be finite in [" .. def.min .. ", " .. def.max .. "]; floor " .. def.min
          end
        else err = "unknown movement zone field" end
        if err then errors[#errors + 1] = tostring(id) .. "." .. tostring(key) .. " " .. err end
      end
    end
  end
  table.sort(errors)
  return errors, {}
end
M.wall_surface_types = loose_table_schema("Wall Surface Types", "developer/config/wall_surface_types.lua")
M.secret_settings = loose_table_schema("Secret Settings", "developer/config/secret_settings.lua")
M.secret_types = loose_table_schema("Secret Types", "developer/config/secret_types.lua")
M.secret_rooms = loose_table_schema("Secret Rooms", "developer/config/secret_rooms.lua")
M.tileset_mapping = loose_table_schema("Tileset Mapping", "developer/config/tileset_mapping.lua")
M.performance_budgets = loose_table_schema("Performance Budgets", "developer/config/performance_budgets.lua")
M.rooms_config = loose_table_schema("Rooms Config", "developer/config/rooms_config.lua")
M.stream_settings = loose_table_schema("Stream Settings", "developer/config/stream_settings.lua")
M.sound_bank = loose_table_schema("Sound Bank", "developer/config/sound_bank.lua")
M.ambience_tracks = loose_table_schema("Ambience Tracks", "developer/config/ambience_tracks.lua")
M.ambient_zones = loose_table_schema("Ambient Zones", "developer/config/ambient_zones.lua")
M.hud_layout = {
  name = "HUD Layout", file = "developer/config/hud_layout.lua", allow_unknown = true,
  required = { currency = { type = "table" } },
  optional = { toast = { type = "table" } },
  custom_validate = function(config)
    local errors = {}
    if type(config.currency) == "table" then
      local valid, message = CurrencyFormat.valid(config.currency.format)
      if not valid then errors[#errors + 1] = "currency.format: " .. message end
      local separator = config.currency.thousands_separator
      if separator ~= nil and type(separator) ~= "string" then
        errors[#errors + 1] = "currency.thousands_separator must be text"
      end
    end
    local read_more
    if type(config.toast) == "table" then read_more = config.toast.read_more end
    if read_more ~= nil then
      if type(read_more) ~= "table" then
        errors[#errors + 1] = "toast.read_more must be a table"
      else
        if type(read_more.enabled) ~= "boolean" then
          errors[#errors + 1] = "toast.read_more.enabled must be boolean"
        end
        local speed = read_more.speed_px_per_second
        if type(speed) ~= "number" or speed ~= speed or speed <= 0 or speed == math.huge then
          errors[#errors + 1] = "toast.read_more.speed_px_per_second must be finite and greater than zero"
        end
        for key in pairs(read_more) do
          if key ~= "enabled" and key ~= "speed_px_per_second" then
            errors[#errors + 1] = "toast.read_more has unknown field " .. tostring(key)
          end
        end
      end
    end
    return errors
  end,
}
M.ui_theme = loose_table_schema("UI Theme", "developer/config/ui_theme.lua")
M.settings_defaults = loose_table_schema("Settings Defaults", "developer/config/settings_defaults.lua")
M.game_config = loose_table_schema("Game Config", "developer/config/game_config.lua")

M.display_settings = {
  name = "Display Settings", file = "developer/config/display_settings.lua",
  required = { letterbox_color = { type = "table" } },
  optional = { view = { type = "table" }, post = { type = "table" }, startup = { type = "table" } },
  custom_validate = function(config, design_aspect)
    local errors = {}
    local rgb = config.letterbox_color
    if type(rgb) == "table" then
      for _, key in ipairs({ "r", "g", "b" }) do
        local value = rgb[key]
        if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
          errors[#errors + 1] = "letterbox_color." .. key .. " must be a finite number from 0 to 1"
        end
      end
      for key in pairs(rgb) do
        if key ~= "r" and key ~= "g" and key ~= "b" then
          errors[#errors + 1] = "letterbox_color only accepts r, g and b (bars are always opaque)"
        end
      end
    end
    local allowed = { letterbox_color = true, view = true, post = true, startup = true }
    for key in pairs(config) do
      if not allowed[key] then
        errors[#errors + 1] = "display_settings only accepts letterbox_color, view, post and startup"
      end
    end
    if config.startup ~= nil then
      local startup = config.startup
      if type(startup) ~= "table" then
        errors[#errors + 1] = "startup must be a table"
      else
        for key in pairs(startup) do
          if key ~= "color" and key ~= "fade_out_seconds" and key ~= "max_wait_seconds" then errors[#errors + 1] = "Unknown startup field: " .. tostring(key) end
        end
        local wait = startup.max_wait_seconds
        if wait ~= nil and (type(wait) ~= "number" or wait ~= wait or wait <= 0 or wait == math.huge) then
          errors[#errors + 1] = "startup.max_wait_seconds must be a positive number of seconds"
        end
        local seconds = startup.fade_out_seconds
        if type(seconds) ~= "number" or seconds ~= seconds or seconds < 0 or seconds == math.huge then
          errors[#errors + 1] = "startup.fade_out_seconds must be finite and nonnegative"
        end
        if type(startup.color) ~= "table" then
          errors[#errors + 1] = "startup.color must be an RGB table"
        else
          for _, key in ipairs({"r", "g", "b"}) do
            local v = startup.color[key]
            if type(v) ~= "number" or v ~= v or v < 0 or v > 1 then errors[#errors + 1] = "startup.color." .. key .. " must be from 0 to 1" end
          end
          for key in pairs(startup.color) do
            if key ~= "r" and key ~= "g" and key ~= "b" then errors[#errors + 1] = "startup.color only accepts r, g and b" end
          end
        end
      end
    end
    if config.post ~= nil then
      local post = config.post
      if type(post) ~= "table" then
        errors[#errors + 1] = "post must be a table"
      else
        local ranges = { brightness={0.5,1.5}, gamma={0.5,2}, saturation={0,2},
          scanlines={0,1}, scanline_count={60,1080}, curvature={0,0.25}, vignette={0,1} }
        for key, value in pairs(post) do
          local range = ranges[key]
          if range then
            if type(value) ~= "number" or value ~= value or value < range[1] or value > range[2] then
              errors[#errors + 1] = "post." .. key .. " is outside its finite range"
            end
          elseif key == "player_brightness" then
            if type(value) ~= "boolean" then errors[#errors + 1] = "post.player_brightness must be a boolean" end
          elseif key == "tint" then
            if type(value) ~= "table" then
              errors[#errors + 1] = "post.tint must be a table"
            else
              local keys = {r=true,g=true,b=true,strength=true}
              for channel, amount in pairs(value) do
                if not keys[channel] or type(amount) ~= "number" or amount ~= amount or amount < 0 or amount > 1 then
                  errors[#errors + 1] = "post.tint only accepts r, g, b and strength from 0 to 1"
                end
              end
            end
          else
            errors[#errors + 1] = "unknown post key: " .. tostring(key)
          end
        end
      end
    end
    if config.view ~= nil then
      local view = config.view
      if type(view) ~= "table" then
        errors[#errors + 1] = "view must be a table"
      else
        if not design_aspect then
          local window_config = require("developer.config.game_config").window
          design_aspect = window_config.target_width / window_config.target_height
        end
        local view_keys = { mode = true, player_choice = true, min_aspect = true, max_aspect = true,
          mask_outside_room = true, hud_frame = true, scale_rule = true }
        for key in pairs(view) do
          if not view_keys[key] then errors[#errors + 1] = "unknown view key: " .. tostring(key) end
        end
        if view.mode ~= nil and view.mode ~= "expand" and view.mode ~= "letterbox" then
          errors[#errors + 1] = "view.mode must be expand or letterbox"
        end
        if view.player_choice ~= nil and type(view.player_choice) ~= "boolean" then
          errors[#errors + 1] = "view.player_choice must be a boolean"
        end
        if view.mask_outside_room ~= nil and type(view.mask_outside_room) ~= "boolean" then
          errors[#errors + 1] = "view.mask_outside_room must be a boolean"
        end
        if view.hud_frame ~= nil and view.hud_frame ~= "safe" and view.hud_frame ~= "picture" then
          errors[#errors + 1] = "view.hud_frame must be safe or picture"
        end
        if view.scale_rule ~= nil and view.scale_rule ~= "fit" and view.scale_rule ~= "integer" then
          errors[#errors + 1] = "view.scale_rule must be fit or integer"
        end
        for _, rule in ipairs({ {"min_aspect", 1, design_aspect}, {"max_aspect", design_aspect, 4} }) do
          local value = view[rule[1]]
          if value ~= nil and (type(value) ~= "number" or value ~= value or value < rule[2] or value > rule[3]) then
            errors[#errors + 1] = "view." .. rule[1] .. " is outside the design aspect limits"
          end
        end
      end
    end
    return errors, {}
  end,
}

M.narrative_dialogues = loose_table_schema("Narrative Dialogues", "developer/config/narrative/dialogues.lua")
M.narrative_dialogues_authored = loose_table_schema("Narrative Dialogues (authored)", "developer/config/narrative/dialogues_authored.lua")
M.combat_config = loose_table_schema("Combat Config", "config/combat_config.lua")
M.combat_overrides = loose_table_schema("Combat Overrides", "config/combat_overrides.lua")
for _, kind in ipairs({ "combat_config", "combat_overrides", "player_art" }) do
  M[kind].optional = M[kind].optional or {}
  M[kind].optional.units_version = { type = "number", values = {1, 2},
    description = "Pixel-unit generation; absent means old units (1)" }
end

-----------------------------------------------------------
-- VALIDATION HELPERS
-----------------------------------------------------------

-- Validate a single field against schema
function M.validate_field(value, field_schema, field_name)
  local errors = {}

  -- Check type
  if field_schema.type then
    local actual_type = type(value)
    local expected = field_schema.type
    local function matches_expected()
      if type(expected) == "table" then
        for _, t in ipairs(expected) do
          if actual_type == t then return true end
        end
        return false
      else
        return actual_type == expected
      end
    end
    if not matches_expected() then
      local expected_str = type(expected) == "table" and table.concat(expected, " | ") or tostring(expected)
      table.insert(errors, string.format(
        "Field '%s': Expected %s, got %s",
        field_name, expected_str, actual_type
      ))
      return errors -- Type mismatch, can't do further validation
    end
  end

  -- Check range (for numbers)
  if field_schema.range and type(value) == "number" then
    local min, max = field_schema.range[1], field_schema.range[2]
    if value < min or value > max then
      table.insert(errors, string.format(
        "Field '%s': Value %s out of range [%s, %s]",
        field_name, Number.fixed(value, 2), Number.fixed(min, 2), Number.fixed(max, 2)
      ))
    end
  end

  -- Check allowed values
  if field_schema.values then
    local found = false
    for _, allowed in ipairs(field_schema.values) do
      if value == allowed then
        found = true
        break
      end
    end
    if not found then
      table.insert(errors, string.format(
        "Field '%s': Invalid value '%s'. Allowed: %s",
        field_name, tostring(value), table.concat(field_schema.values, ", ")
      ))
    end
  end

  -- Check boolean
  if field_schema.type == "boolean" and type(value) ~= "boolean" then
    table.insert(errors, string.format(
      "Field '%s': Expected boolean, got %s",
      field_name, type(value)
    ))
  end

  -- Check nested table fields
  if field_schema.fields and type(value) == "table" then
    for nested_name, nested_schema in pairs(field_schema.fields) do
      local nested_value = value[nested_name]
      if nested_value ~= nil then
        local nested_errors = M.validate_field(nested_value, nested_schema, field_name .. "." .. nested_name)
        for _, err in ipairs(nested_errors) do
          table.insert(errors, err)
        end
      elseif not nested_schema.optional then
        table.insert(errors, string.format(
          "Field '%s.%s': Missing required field",
          field_name, nested_name
        ))
      end
    end
  end

  return errors
end

-- Get human-readable description of expected type
function M.get_type_description(field_schema)
  local desc
  if type(field_schema.type) == "table" then
    desc = table.concat(field_schema.type, " | ")
  else
    desc = field_schema.type or "any"
  end

  if field_schema.range then
    desc = desc .. string.format(" [%s - %s]", Number.fixed(field_schema.range[1], 1), Number.fixed(field_schema.range[2], 1))
  end

  if field_schema.values then
    desc = desc .. " (" .. table.concat(field_schema.values, " | ") .. ")"
  end

  if field_schema.description then
    desc = desc .. " - " .. field_schema.description
  end

  return desc
end

return M
