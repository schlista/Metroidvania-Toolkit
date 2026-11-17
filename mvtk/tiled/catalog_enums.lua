-- Authoring dropdown ownership. Source tables are supplied by a run-scoped loader.
local M = {}
M.ROWS = {
    {name="ability_flags", kind="derived", module="developer.config.abilities", field="abilities", flags=true, owner="g6-gate-any-logic"},
    {name="attack_tags", kind="fixed", ordered=true, flags=true, values={"light_attack","heavy_attack","charge_attack","down_strike","ranged_attack","parry_counter","parry","dash","slide","backdash","ground_pound","super_jump","bomb","throw"}, owner="G9-CMB05"},
    {name="bank_modes", kind="fixed", values={"both","deposit","withdraw"}, ordered=true, owner="G4-11"},
    {name="biomes", kind="derived", module="developer.config.biomes", sentinels={"inherit"}, unknown="warning", map_properties={"biome"}, owner="C4-U1"},
    {name="boss_music_tracks", kind="external", owner="Sync Music"},
    {name="bosses", kind="derived", module="developer.config.boss_types", owner="C4-U1"},
    {name="breakable_sides", kind="fixed", values={"left","right","above","below"}, sentinels={"any"}, owner="G9-TRV02"},
    {name="carry_kind_filters", kind="derived", module="developer.config.carry_settings", field="kinds", sentinels={"any"}, owner="TRV-16b"},
    {name="carry_kinds", kind="derived", module="developer.config.carry_settings", field="kinds", owner="TRV-16a"},
    {name="collectibles", kind="derived", module="developer.config.collectible_types", sentinels={"none"}, group="category", owner="C4-U1"},
    {name="countdown_zone_roles", kind="fixed", values={"start","finish","cancel"}, ordered=true, owner="WM09b"},
    {name="countdowns", kind="derived", module="developer.config.countdowns", field="countdowns", sentinels={"none"}, owner="WM09b"},
    {name="damage_type_flags", kind="derived", module="developer.config.damage_types", field="types", flags=true, owner="G3-F04"},
    {name="damage_types", kind="derived", module="developer.config.damage_types", field="types", sentinels={"none"}, owner="G3-F04"},
    {name="difficulty", kind="derived", module="developer.config.difficulty_settings", field="profiles", sentinels={"none"}, owner="C4-U1"},
    {name="elevator_destination_modes", kind="fixed", values={"next","direction","choose"}, ordered=true, owner="TRV-07a"},
    {name="elevator_route_axes", kind="fixed", values={"vertical","horizontal"}, ordered=true, owner="TRV-07c"},
    {name="elevator_stops", kind="fixed", values={"bottom","top","middle","left","right"}, ordered=true, sentinels={"none"}, adopted=true, owner="TRV-07a"},
    {name="encounter_start_modes", kind="fixed", values={"on_enter","on_signal"}, ordered=true, owner="G3-F11"},
    {name="enemies", kind="external", owner="Sync Enemy Art"},
    {name="enemy_ambush_styles", kind="fixed", values={"drop","rise","disguise"}, sentinels={"type_default"}, ordered=true, owner="G9-CMB08a"},
    {name="enemy_archetypes", kind="derived", module="developer.config.enemy_types", sentinels={"none"}, owner="G3-F01"},
    {name="enemy_attack_patterns", kind="fixed", values={"disabled","shoot_straight","shoot_spread","shoot_burst","shoot_circle","shoot_random","spiral_shot","homing_shot","dash_attack","swoop_attack","melee_swipe","jump_attack","charge_shoot","teleport_attack","rain_attack","summon_minion","shield","aimed_shot","spike_cycle"}, sentinels={"type_default"}, tail={"none"}, ordered=true, adopted=true, unknown="warning", owner="G3-F07"},
    {name="enemy_death_behaviors", kind="fixed", values={"none","burst","split","hazard"}, sentinels={"type_default"}, ordered=true, owner="G9-CMB08c"},
    {name="enemy_guards", kind="fixed", values={"none","front","top","all"}, sentinels={"type_default"}, ordered=true, owner="G9-CMB05"},
    {name="enemy_ledge_behaviors", kind="fixed", values={"stop","fall","fall_when_chasing"}, sentinels={"type_default"}, ordered=true, owner="G3-F12"},
    {name="enemy_mounts", kind="derived", module="developer.config.enemy_defaults", field="aim_mounts", sentinels={"type_default"}, owner="G3-F07"},
    {name="enemy_movement", kind="fixed", values={"stationary","ground_patrol","ground_patrol_chase","ground_chase","flying_chase","vertical_patrol","hover","flee","zigzag","ghost_float","surface_crawl","ambush","swim","hop","swarm"}, sentinels={"type_default"}, tail={"none","patrol","patrol_vertical","chase"}, ordered=true, adopted=true, unknown="warning", owner="G9-CMB08a"},
    {name="enemy_respawn_policies", kind="fixed", values={"always","room_reload","save","never"}, sentinels={"type_default"}, owner="C7-U3"},
    {name="enemy_skins", kind="external", owner="Sync Enemy Art"},
    {name="fluid_level_modes", kind="fixed", values={"switch","rise"}, sentinels={"none"}, owner="TRV-06a"},
    {name="fluid_rise_starts", kind="fixed", values={"signal","room_enter"}, owner="TRV-06a"},
    {name="gates", kind="derived", module="developer.config.gate_types", owner="C4-U1"},
    {name="hazard_contact_modes", kind="fixed", values={"damage","safe_return","kill"}, sentinels={"type_default"}, owner="C6-F1"},
    {name="hazard_motion_types", kind="fixed", values={"line","path","orbit","slam"}, sentinels={"none"}, owner="TRV-03a"},
    {name="hazards", kind="derived", module="developer.config.hazard_types", skip={"settings"}, owner="C4-U1"},
    {name="ladder_types", kind="fixed", values={"ladder","vine","rope","chain","hang_bar","climb_mesh"}, unknown="warning", owner="TRV-12"},
    {name="launch_aim_modes", kind="fixed", values={"fixed","sweep"}, ordered=true, owner="TRV-13b"},
    {name="launch_fire_modes", kind="fixed", values={"jump","auto"}, ordered=true, owner="TRV-13b"},
    {name="marker_types", kind="fixed", values={"poi","save","fast_travel","boss","secret","shop"}, ordered=true, adopted=true, unknown="warning", owner="G4-04"},
    {name="movement_zones", kind="derived", module="developer.config.movement_zone_types", owner="TRV-14"},
    {name="music_tracks", kind="external", owner="Sync Music"},
    {name="npcs", kind="derived", module="developer.config.npc_types", owner="C4-U1"},
    {name="optional_abilities", kind="derived", module="developer.config.abilities", field="abilities", sentinels={"none"}, owner="C4-U1"},
    {name="optional_boss_animation_keys", kind="enum", enum="boss_animation_keys", sentinels={"none"}, unknown="warning", owner="G2-F07"},
    {name="particle_effects", kind="derived", module="developer.config.particle_effects", field="effects", sources={{module="developer.config.fx_types",field="effects"}}, sentinels={"none"}, unknown="warning", owner="C4-U1"},
    {name="presence_timings", kind="fixed", values={"enter","live"}, ordered=true, owner="G8-09"},
    {name="projectile_deflect_modes", kind="fixed", values={"none","destroy","reflect"}, sentinels={"inherit"}, ordered=true, owner="CMB-07a"},
    {name="quest_states", kind="fixed", values={"not_started","active","completed","turned_in","failed"}, sentinels={"any"}, ordered=true, owner="G5-F3"},
    {name="quest_trigger_actions", kind="fixed", values={"start","advance","complete","fail"}, ordered=true, owner="G5-F3"},
    {name="requirement_logic", kind="fixed", values={"all","any"}, owner="g6-gate-any-logic"},
    {name="reveal_areas", kind="derived", module="developer.config.biomes", sentinels={"current"}, unknown="warning", owner="C4-U1"},
    {name="secret_types", kind="derived", module="developer.config.secret_types", skip={"settings"}, owner="C4-U1"},
    {name="shops", kind="derived", module="developer.config.shops", field="catalogs", sentinels={"none"}, owner="G4-03"},
    {name="sound_effects", kind="derived", module="developer.config.sound_bank", field="sfx", sentinels={"none"}, unknown="warning", owner="C4-U1"},
    {name="status_effect_flags", kind="derived", module="developer.config.status_effects", field="effects", flags=true, owner="G3-F05"},
    {name="status_effects", kind="derived", module="developer.config.status_effects", field="effects", sentinels={"none"}, owner="G3-F05"},
    {name="strike_switch_accepts", kind="derived", module="developer.config.switches", field="accept_groups", sentinels={"any"}, owner="G9-TRV04"},
    {name="strike_switch_modes", kind="fixed", values={"toggle","once","timed","momentary"}, owner="G9-TRV04"},
    {name="surface_types", kind="derived", module="developer.config.wall_surface_types", owner="G2-F08"},
    {name="trial_goals", kind="fixed", values={"clear","defeat_count","survive"}, ordered=true, owner="CMB-12b"},
    {name="vehicle_controls", kind="fixed", values={"auto","throttle"}, sentinels={"none"}, owner="TRV-15a"},
    {name="vehicle_end_actions", kind="fixed", values={"stop","return","fall_away"}, owner="TRV-15a"},
    {name="vendor_greetings", kind="fixed", values={"first_visit","every_visit","never"}, ordered=true, owner="G4-05"},
    {name="wind_modes", kind="fixed", values={"push","lift"}, owner="G1-WIND"},
}
for _,row in ipairs(M.ROWS) do row.unknown=row.unknown or "error" end
function M.rows() return M.ROWS end
function M.row(name) for _,row in ipairs(M.ROWS) do if row.name==name then return row end end end
local function set(values) local out={};for _,v in ipairs(values or {}) do out[v]=true end;return out end

function M.check_values(row,values,opts)
    local source=row.module or row.name
    local sentinels=set(row.sentinels)
    if row.flags and next(sentinels) then return nil,source..": flags cannot have sentinels" end
    if #values==0 and not next(sentinels) and not (opts and opts.allow_empty) then return nil,source..": empty dropdown; add an entry" end
    for _,key in ipairs(values) do
        if sentinels[key] then return nil,source..": key "..tostring(key).." collides with a sentinel; rename it" end
        if type(key)~="string" or key=="" or key:find("[^A-Za-z0-9_.-]") then
            return nil,source..": invalid key "..tostring(key).."; use letters, digits, _, . or -"
        end
    end
    return true
end

function M.derive(row,load,base_text,base_entries,opts)
    if row.kind=="external" then return nil,nil,"external" end
    local entries,values={},{}
    if row.kind=="fixed" then
        for _,key in ipairs(row.values or {}) do values[#values+1]=key end
    elseif row.kind=="enum" then
        local err
        values,err=require("mvtk.tiled.tiled_carriers").enum_values(base_text,row.enum,base_entries)
        if not values then return nil,err end
    else
        local sources={{module=row.module,field=row.field}}
        for _,source in ipairs(row.sources or {}) do sources[#sources+1]=source end
        local skip,seen=set(row.skip),{}
        for _,source in ipairs(sources) do
            local ok,config,err=pcall(load,source.module)
            if not ok then return nil,source.module..": "..tostring(config).."; fix this config" end
            if config==nil then
                if err=="missing" or tostring(err):match("^Missing ") then return nil,nil,"missing",source.module end
                return nil,source.module..": "..tostring(err).."; fix this config"
            end
            if source.field then
                -- Membership checks accept an empty config as an empty set;
                -- sync still refuses an empty dropdown before writing carriers.
                config=config[source.field] or (opts and opts.allow_empty and {})
            end
            if type(config)~="table" then return nil,source.module..": missing table "..tostring(source.field) end
            for key,entry in pairs(config) do
                if not skip[key] then
                    if not seen[key] then values[#values+1]=key;seen[key]=true end
                    entries[key]=entry
                end
            end
        end
    end
    local ok,err=M.check_values(row,values,opts)
    if not ok then return nil,err end
    if not row.ordered then table.sort(values) end
    return values,entries
end

function M.merge(existing,derived,row,entries)
    local available,used,out=set(derived),{},{}
    local tail=set(row.tail)
    local function append(v) if not used[v] then out[#out+1]=v;used[v]=true end end
    for _,v in ipairs(row.sentinels or {}) do append(v) end
    for _,v in ipairs(existing or {}) do if available[v] and not tail[v] then append(v) end end
    local pending={}
    local function group(v)
        local entry=entries and entries[v]
        return row.group and type(entry)=="table" and tostring(entry[row.group] or "") or ""
    end
    for _,v in ipairs(derived) do if not used[v] and not tail[v] then pending[#pending+1]=v end end
    if not row.ordered then
        table.sort(pending,function(a,b) local ga,gb=group(a),group(b);if ga~=gb then return ga<gb end;return a<b end)
    end
    for _,v in ipairs(pending) do
        local last
        if row.group then for i,current in ipairs(out) do if available[current] and group(current)==group(v) then last=i end end end
        if last then table.insert(out,last+1,v);used[v]=true else append(v) end
    end
    for _,v in ipairs(row.tail or {}) do append(v) end
    return out
end

return M
