--- Boss Attack Telegraphs
-- Spawns visual telegraph objects during the wind-up phase of boss attacks
-- so the player can read and react. Telegraphs are short-lived factories
-- that expire at the end of the wind-up or when the owning attack fires.
--
-- Integration:
--   boss_state_machine.enter_attacking() calls M.begin(boss, pattern, duration)
--   The boss prefab must expose a factory at "#telegraph_factory" that spawns
--   tiled/templates/combat/telegraph.tx (or equivalent). If the factory is
--   absent the module degrades to a screen-shake cue only.
--
-- Telegraph shapes (set on the spawned object via go.property):
--   "line"   — horizontal swing/slam line
--   "circle" — AOE ring
--   "cone"   — directional cone (projectile volley, beam)
--
-- @module boss_telegraph

local Util = require "mvtk.core.util"
local Feedback = Util.require_module("mvtk.combat.combat_feedback")
local SafeSound = require "mvtk.audio.safe_sound"
local Schema = require "mvtk.bosses.attack_pattern_schema"
local AttackScale = require "mvtk.bosses.attack_scale"
local Runtime = require "mvtk.bosses.attack_runtime"
local Detection = require "mvtk.enemies.detection"
local Preview = {get_player_position = Detection.peek_player_position or Detection.get_player_position}
local Confinement = require "mvtk.bosses.boss_confinement"
local Locomotion = require "mvtk.bosses.boss_locomotion"
local Geometry = require "mvtk.combat.attack_geometry"
local Indicator = require "mvtk.bosses.indicator_geometry"
local Floor = require "mvtk.bosses.boss_floor_attacks"
local Visual = require "mvtk.bosses.boss_indicator"
local Arena = Util.require_module("mvtk.bosses.boss_arena")
local Defaults = Util.require_config("developer.config.boss_defaults", {
    telegraph_time = 0.5,
    default_aoe_radius = 150,
    default_melee_width = 60,
    default_melee_height = 80,
    default_mine_radius = 48,
    default_wave_radius_step = 80,
    default_beam_length = 400,
    default_beam_width = 40,
})

local M = {}

local TELEGRAPH_FACTORY = "#telegraph_factory"
local NON_AREA_CAST = {
    buff = true, combo = true, environmental = true, hazard_pulse = true,
    heal = true, parry_window = true, shield = true, summon = true,
}

function M.sweep_angle(angle, facing)
    local radians = math.rad(angle)
    return facing < 0 and math.pi - radians or radians
end

local function warn_rain(boss, pattern, reason)
    local name = pattern._attack_name or "rain"
    boss._rain_warnings = boss._rain_warnings or {}
    if boss._rain_warnings[name] then return end
    boss._rain_warnings[name] = true
    print(string.format("[BOSS] Skipped rain pattern '%s': %s", name, reason))
end

function M.arena_fit_failure(boss, pattern, rect)
    if not pattern then return end
    local width = rect and rect.max_x - rect.min_x
    if pattern.type == "rain" then
        return Schema.arena_fit_failure(pattern, Defaults, width)
    end
    if pattern.type ~= "zone" and pattern.type ~= "leap" and pattern.type ~= "reposition" then return end
    local hw, hh, feet = Confinement.half_extents(boss.config, boss)
    local height = rect and rect.max_y - (Confinement.floor_min(boss) or rect.min_y)
    return Schema.arena_fit_failure(pattern, Defaults, width, height, hw, (hh + (feet or hh)) * 0.5)
end

function M.body_target(body)
    if body.animated then return body.x, body.y end
    return body.root_x or body.x, body.root_y or body.y
end

function M.player_target()
    local body = Detection.get_player_body()
    if body then
        local x, y = M.body_target(body)
        return {x = x, y = y}
    end
    return Detection.get_player_position and Detection.get_player_position()
end

local function prepare_rain(boss, pattern, settings, cue)
    local rect = boss._confine_rect or Confinement.resolve_rect(boss.config)
    local _, failure = M.arena_fit_failure(boss, pattern, rect)
    if failure then
        warn_rain(boss, pattern, failure)
        return
    end
    local width = rect.max_x - rect.min_x
    local gap = settings.gap_width
    local start
    if settings.gap_at == "random" then
        start = rect.min_x + math.random() * (width - gap)
    else
        local player = M.player_target()
        if not player then return end
        if settings.gap_at == "away" then
            local middle = (rect.min_x + rect.max_x) * 0.5
            start = player.x <= middle and rect.max_x - gap or rect.min_x
        else
            start = math.max(rect.min_x, math.min(rect.max_x - gap, player.x - gap * 0.5))
        end
    end
    cue.rect, cue.gap_left, cue.gap_right = rect, start, start + gap
end

local function prepare_stationary(boss, pattern, settings, origin)
    local pos = origin or go.get_position()
    local cue = {boss = boss, pattern = pattern, origin = pos, facing = boss.facing or 1, ids = {}}
    if pattern.type == "zone" then
        if settings.target == "player" then
            local player = M.player_target()
            if player then cue.center = vmath.vector3(player.x, player.y, pos.z) end
        elseif settings.target == "anchor" then
            local rect = boss._confine_rect or Confinement.resolve_rect(boss.config)
            local hw, hh, feet = Confinement.half_extents(boss.config, boss)
            local player = M.player_target()
            cue.center = Confinement.anchor(rect, settings.anchor, pos, player, hw, hh, feet, Confinement.floor_min(boss))
        else
            cue.center = pos
        end
    elseif pattern.type == "rain" then
        prepare_rain(boss, pattern, settings, cue)
    end
    return cue
end

-- The warning and hit are on the boss's feet, while its transform is at its centre.
function M.dive_landing(cue, x, player, settings)
    local boss = cue.boss
    local feet = cue.feet_offset
    if feet == nil then
        local measured = Locomotion.feet_y(boss, cue.origin)
        if measured then
            feet = cue.origin.y - measured
        else
            feet = tonumber(boss.config.feet_offset)
            if not feet or feet <= 0 then feet = tonumber(Defaults.feet_offset) end
            if not feet or feet <= 0 then feet = boss._body and boss._body.half_height or cue.half_height end
        end
    end
    if settings and settings.land.ground_only then
        local center_x, ceiling = Confinement.clamp_attack(cue, x, cue.origin.y + settings.rise)
        local floor_y = Locomotion.attack_floor(boss, vmath.vector3(center_x, ceiling, cue.origin.z), true)
        if not floor_y then return center_x end
        local target_y = floor_y + feet
        local _, center_y = Confinement.clamp_attack(cue, center_x, target_y, feet)
        if center_y ~= target_y or center_y > ceiling then return center_x end
        return center_x, center_y, floor_y
    end
    local y = player and player.y - (player.half_h or 0) + feet or cue.origin.y
    local center_x, center_y = Confinement.clamp_attack(cue, x, y, feet)
    return center_x, center_y, center_y - feet
end

function M.dive_player()
    local player = Detection.get_player_body()
    if player then return player end
    local pos = Detection.get_player_position and Detection.get_player_position()
    if pos then return {x = pos.x, y = pos.y} end
end

function M.move_landing(cue, x, y)
    cue.center = vmath.vector3(x, y, cue.origin.z)
    local id = cue.ids[1]
    if id and go.exists(id) then
        go.set_position(vmath.vector3(x, y + (cue.marker_y_offset or 0), cue.origin.z + 0.05), id)
    end
end

local function moving_destination(cue, x, y, settings, decision)
    local kind = cue.pattern.type
    if Locomotion.active(cue.boss) and (kind == "leap" or kind == "reposition" and settings.style == "blink") then
        local rise = kind == "leap" and settings.height or cue.boss._body.half_height
        local landing_y, probed = Locomotion.landing(cue.boss, vmath.vector3(x, y, cue.origin.z), rise, decision)
        if not probed then return false, x, y end
        if not landing_y then return end
        y = landing_y
    end
    M.move_landing(cue, x, y)
end

local function retarget_moving(cue, settings, player, decision)
    local origin, rect = cue.origin, cue.rect
    local hw, hh = cue.half_width, cue.half_height
    local feet = cue.feet_offset
    local floor_min = cue.floor_min
    local kind = cue.pattern.type
    player = player or (kind == "dive" and M.dive_player() or M.player_target())
    if kind == "leap" and settings.target == "player" then
        if not player then return end
        local dx = math.max(-settings.max_distance, math.min(settings.max_distance, player.x - origin.x))
        local x, y = Confinement.clamp_attack(cue, origin.x + dx, origin.y)
        return moving_destination(cue, x, y, settings, decision)
    elseif kind == "dive" then
        if not player then return end
        local x = origin.x
        if settings.land.ground_only then
            local distance = settings.track_speed * settings.track_time
            local target_x = M.body_target(player)
            x = x + math.max(-distance, math.min(distance, target_x - x))
        end
        local landing_x, _, y = M.dive_landing(cue, x, player, settings)
        if y then M.move_landing(cue, landing_x, y) end
    else
        local target = Confinement.anchor(rect, settings.target or settings.anchor, origin, player, hw, hh, feet, floor_min)
        if target then
            return moving_destination(cue, target.x, kind == "leap" and origin.y or target.y, settings, decision)
        end
    end
end

local function prepare_moving(boss, pattern)
    local hw, hh, feet = Confinement.half_extents(boss.config, boss)
    return {
        boss = boss, pattern = pattern, ids = {},
        origin = go.get_position(boss.self_url), half_width = hw, half_height = hh, feet_offset = feet,
        floor_min = Confinement.floor_min(boss),
        rect = boss._confine_rect or Confinement.resolve_rect(boss.config),
    }
end

local function floor_landing(boss, pattern, settings, body)
    local cue = prepare_moving(boss, pattern)
    local x, y = M.body_target(body)
    local target = pattern.type == "dive" and body or {x = x, y = y}
    local ready = retarget_moving(cue, settings, target, true)
    if not cue.center then return nil, ready ~= false end
    if pattern.type == "dive" then return cue.center.y, true end
    return Floor.feet_y(boss, cue.center), true
end

-- Use the executor's floor and the current decision's player sample.
function M.floor_reach(boss, pattern, body, pos, height, settings)
    if not body then return false, "height" end
    local y, probed
    if pattern.type == "ground_wave" then
        y, probed = Locomotion.attack_floor(boss, pos, true)
    elseif settings then
        y, probed = floor_landing(boss, pattern, settings, body)
    else
        local x, target_y = M.body_target(body)
        local target = pattern.aoe.target == "player" and vmath.vector3(x, target_y, pos.z) or pos
        y, probed = Floor.slam_floor(boss, pos, target, true)
    end
    if not y then return false, probed and "floor" or "floor_probe" end
    return Floor.reaches(body, y, height), "height"
end

function M.take_moving(boss, pattern, settings)
    local cue = boss._moving_attack_cue
    if not cue or cue.pattern ~= pattern then cue = prepare_moving(boss, pattern) end
    if boss._moving_attack_cue == cue then boss._moving_attack_cue = nil end
    cue.taken = true
    cue.origin = go.get_position(boss.self_url)
    cue.center = nil
    local ready, x, y = retarget_moving(cue, settings)
    return cue, ready ~= false, x, y
end

function M.retry_moving(cue, settings, x, y)
    return moving_destination(cue, x, y, settings) ~= false
end

-- The state machine's resolved pattern is the same table for warning and
-- execution. Direct dispatch (including combo steps) can prepare its own cue.
function M.take_stationary(boss, pattern, settings)
    local cue = boss._stationary_attack_cue
    if cue and cue.pattern == pattern then
        boss._stationary_attack_cue = nil
        cue.taken = true
        return cue
    end
    return prepare_stationary(boss, pattern, settings)
end

local function telegraph_geometry(pattern)
    if pattern.type == "melee" then
        local offset, half_w, half_h = AttackScale.melee_box(pattern, Defaults)
        return half_w * 2, half_h * 2, offset, "line"
    end
    local size = pattern.telegraph_size or {}
    return size.x or pattern.range or 80,
        size.y or pattern.width or 40,
        pattern.telegraph_offset or 0,
        pattern.telegraph_shape or "line"
end

local function color_props(props, color)
    if color then
        props.color_r, props.color_g, props.color_b, props.color_a = color.x, color.y, color.z, color.w
    end
    return props
end

function M.mark_blink_destination(boss, target, diameter)
    local pos = vmath.vector3(target.x, target.y, target.z + 0.05)
    local ok, id = pcall(factory.create, TELEGRAPH_FACTORY, pos, nil, {
        managed = true, neutral = true, shape = "circle", size_x = diameter, size_y = diameter,
    })
    if ok and id then return {boss = boss, ids = {id}} end
end

local function beam_visual(origin, direction, length, width)
    return vmath.vector3(origin.x + direction.x * length * 0.5,
        origin.y + direction.y * length * 0.5, (origin.z or 0) + 0.05),
        length, width, "beam", math.atan2(direction.y, direction.x)
end

local function place(handle, position, angle)
    local id = handle.ids[1]
    if id and go.exists(id) then
        go.set_position(position, id)
        if angle then go.set_rotation(vmath.quat_rotation_z(angle), id) end
    end
end

local function body()
    local published = Detection.get_published_player_body or Detection.get_player_body
    return published and published()
end

local function area_visual(origin, options, radius)
    local y, height = origin.y, radius * 2
    if options.ground_only then
        y, height = Indicator.floor_band(y, Indicator.clearance(options))
    end
    return vmath.vector3(origin.x, y, (origin.z or 0) + 0.05),
        radius * 2, height, options.ground_only and "box" or "circle"
end

local function legacy_visual(boss, pattern, pos)
    local facing = boss.facing or 1
    local width, height, offset, shape = telegraph_geometry(pattern)
    local x, y = pos.x + offset * facing, pos.y
    if pattern.type == "beam" then
        local direction, length, thickness = Indicator.beam(boss, pattern, Defaults, pos, Preview, Geometry)
        return beam_visual(pos, direction, length, thickness)
    elseif pattern.type == "aoe" then
        local area = pattern.aoe or {}
        local center = Indicator.area_origin(pos, area, Preview)
        if area.ground_only then
            local y = Floor.slam_floor(boss, pos, center)
            if not y then return end
            center = vmath.vector3(center.x, y, center.z)
        end
        return area_visual(center, area, area.radius or Defaults.default_aoe_radius)
    elseif pattern.type == "mine" then
        local mine = pattern.mine or {}
        local center = Indicator.area_origin(pos, {target = mine.position}, Preview)
        return area_visual(center, mine, mine.radius or Defaults.default_mine_radius or 48)
    elseif pattern.type == "wave" then
        local wave = pattern.wave or {}
        local step = wave.radius_step or Defaults.default_wave_radius_step or 80
        local inner, radius = Indicator.wave_band(step, wave.thickness or 40, 1)
        return vmath.vector3(pos.x, y, (pos.z or 0) + 0.05), radius * 2, radius * 2,
            inner > 0 and "ring" or "circle"
    elseif pattern.type == "charge" then
        local arena = Arena and Arena.get_active_arena and Arena.get_active_arena()
        local dash = AttackScale.charge_distance(pattern)
        local target_x = Indicator.charge_target(pos.x, pos.x + facing * dash, pattern, arena, 0.001, boss)
        local half_width, clearance = Indicator.charge_extents(pattern, Defaults)
        width = math.abs(target_x - pos.x) + half_width * 2
        x = (pos.x + target_x) * 0.5
        y, height = Indicator.charge_band(y, clearance, body())
        shape = "box"
    elseif pattern.type == "grab" then
        local reach, half_width, half_height = Indicator.grab_box(pattern, Defaults)
        x = pos.x + facing * reach * 0.5
        width, height, shape = half_width * 2, half_height * 2, "box"
    end
    return vmath.vector3(x, y, (pos.z or 0) + 0.05), width, height, shape
end

function M.refresh(boss, handle)
    if type(handle) ~= "table" or handle.locked then return end
    if handle.lanes then
        local pos = go.get_position()
        if pos.x == handle.origin.x and pos.y == handle.origin.y then return end
        local floor_y = Locomotion.attack_floor(boss, pos)
        if not floor_y then return end
        local y = Indicator.floor_band(floor_y, handle.lanes.height)
        for i, id in ipairs(handle.ids) do
            if go.exists(id) then
                go.set_position(vmath.vector3(pos.x + handle.lanes[i], y, (pos.z or 0) + 0.05), id)
            end
        end
        handle.origin = pos
        return
    end
    if not handle.track then return end
    local position, width, height, shape, angle = legacy_visual(boss, handle.visual_pattern, go.get_position())
    if not position then return end
    place(handle, position, angle)
    local id = handle.ids[1]
    if id and (shape == "box" or shape == "beam") and go.exists(id)
        and (width ~= handle.width or height ~= handle.height) then
        Visual.resize_box(msg.url(nil, id, "sprite"), width, height)
        handle.width, handle.height = width, height
    end
end

function M.lock_indicator(boss, pattern, instance)
    local handle = boss._indicator_cue
    if not handle or handle.pattern ~= pattern then return end
    handle.locked = true
    if instance then
        local id = handle.ids[1]
        if id then
            handle.owner:disown(id)
            instance:own(id)
        end
        handle.execution_owned = true
    end
    return handle
end

local function place_locked(handle, instance, position, width, height, shape, angle)
    if handle.ids[1] then
        place(handle, position, angle)
        return
    end
    local rotation = angle and vmath.quat_rotation_z(angle)
    local ok, id = pcall(factory.create, TELEGRAPH_FACTORY, position, rotation, color_props({
        managed = true, shape = shape, size_x = width, size_y = height,
    }, handle.color))
    if ok and id then handle.ids[1] = instance:own(id) end
end

function M.lock_beam(boss, pattern, instance, position, direction, length, width)
    local handle = M.lock_indicator(boss, pattern, instance)
    if not handle then return end
    place_locked(handle, instance, beam_visual(position, direction, length, width))
    return handle
end

function M.track_beam(boss, pattern, instance, origin, direction, length, width)
    local handle = M.lock_beam(boss, pattern, instance, origin, direction, length, width)
    if not handle then
        handle = {boss = boss, ids = {}, color = pattern.telegraph_color}
        place_locked(handle, instance, beam_visual(origin, direction, length, width))
    end
    return handle
end

function M.move_beam_warning(handle, origin, direction, length, width)
    local position, _, _, _, angle = beam_visual(origin, direction, length, width)
    place(handle, position, angle)
end

function M.lock_area(boss, pattern, instance, position, radius, options)
    local handle = M.lock_indicator(boss, pattern, instance)
    if not handle then return end
    place_locked(handle, instance, area_visual(position, options, radius))
    return handle
end

local function warning_owner(boss)
    return Runtime.start(boss, {persist = false}, {
        background = true, delete = M.cancel, exists = go.exists,
    })
end

local function spawn_managed(cue, settings, color, duration)
    local boss, pattern, pos = cue.boss, cue.pattern, cue.origin
    local kind = pattern.type
    local owner
    local function mark(x, y, size_x, size_y, shape, angle, neutral)
        if size_x <= 0 or size_y <= 0 then return end
        local rotation = angle and vmath.quat_rotation_z(angle)
        local ok, id = pcall(factory.create, TELEGRAPH_FACTORY,
            vmath.vector3(x, y, pos.z + 0.05), rotation, color_props({
                managed = true, shape = shape, size_x = size_x, size_y = size_y,
                neutral = neutral,
            }, color))
        if not ok or not id then return end
        owner = owner or warning_owner(boss)
        cue.ids[#cue.ids + 1] = owner:own(id)
    end
    if Schema.is_moving and Schema.is_moving(kind) and cue.center then
        local x, y, _, shape = telegraph_geometry(pattern)
        if settings.land then
            x = settings.land.radius * 2
            local position
            local center = cue.center
            if kind == "leap" and settings.land.ground_only then
                center = vmath.vector3(center.x, Floor.feet_y(boss, center), center.z)
            end
            position, _, y, shape = area_visual(center, settings.land, settings.land.radius)
            cue.marker_y_offset = position.y - cue.center.y
        end
        mark(cue.center.x, cue.center.y + (cue.marker_y_offset or 0), x, y, shape, nil, not settings.land)
        if owner then
            owner:each_frame(function()
                if cue.taken or cue.cancelled then return false end
                retarget_moving(cue, settings)
            end)
        end
    elseif kind == "zone" and cue.center then
        local circle = settings.shape == "circle"
        local x = circle and settings.radius * 2 or settings.width
        local y = circle and x or settings.height
        mark(cue.center.x, cue.center.y, x, y, settings.shape)
    elseif kind == "ground_wave" then
        local floor_y = Locomotion.attack_floor(boss, pos)
        if not floor_y then return end
        local y, height = Indicator.floor_band(floor_y, settings.height)
        local lanes = {width = settings.distance + settings.width, height = height}
        cue.lanes = lanes
        local function lane(direction)
            local offset = direction * settings.distance * 0.5
            local before = #cue.ids
            mark(pos.x + offset, y, lanes.width, height, "line")
            if #cue.ids > before then lanes[#cue.ids] = offset end
        end
        lane(cue.facing)
        if settings.both_sides then lane(-cue.facing) end
    elseif kind == "sweep" then
        local function ray(degrees)
            local angle = M.sweep_angle(degrees, cue.facing)
            local half = settings.length * 0.5
            mark(pos.x + math.cos(angle) * half, pos.y + math.sin(angle) * half,
                settings.length, settings.width, "line", angle)
        end
        ray(settings.from_angle)
        if settings.to_angle ~= settings.from_angle then ray(settings.to_angle) end
    elseif kind == "rain" and cue.rect then
        local rect = cue.rect
        local y, height = (rect.max_y + rect.min_y) * 0.5, rect.max_y - rect.min_y
        mark((rect.min_x + cue.gap_left) * 0.5, y, cue.gap_left - rect.min_x, height, "box")
        mark((rect.max_x + cue.gap_right) * 0.5, y, rect.max_x - cue.gap_right, height, "box")
    elseif kind == "ring" then
        local x, y = telegraph_geometry(pattern)
        mark(pos.x, pos.y, x, y, "circle", nil, true)
    elseif kind == "summon" then
        local x, y, _, shape = telegraph_geometry(pattern)
        for _, point in ipairs(Geometry.ring_positions(pos, settings.spawn_radius or 100, settings.count or 2)) do
            mark(point.x, point.y, x, y, shape, nil, true)
        end
        if owner then owner:after(duration, function() M.cancel(cue) end) end
    end
    if owner then owner:finish() end
end

local function attach_warning(handle, slot, detached)
    handle.slot = slot
    if not detached then handle.boss[slot] = handle end
end

local function resolve_legacy(pattern)
    if pattern.type == "hazard" and not (pattern.hazard and pattern.hazard.type ~= nil) then
        return Indicator.hazard_attack(pattern, Defaults)
    end
    return pattern
end

local function delayed(attack)
    if attack.type == "beam" then
        return ((attack.beam or {}).windup or Defaults.default_beam_windup or 0.5) > 0
    elseif attack.type == "aoe" then
        return ((attack.aoe or {}).delay or Defaults.default_aoe_delay or 0.5) > 0
    end
    return false
end

--- Spawn a telegraph for an attack pattern.
-- @param boss Boss instance (needs .facing, .id)
-- @param pattern Attack pattern table. Respected fields:
--          telegraph_shape ("line"|"circle"|"cone"), telegraph_color,
--          telegraph_size, telegraph_offset, telegraph_sound
-- @param duration Override telegraph time (defaults to pattern.telegraph_time).
-- @return opaque telegraph handle (id or nil)
function M.begin(boss, pattern, duration, detached)
    if not boss or not pattern then return nil end
    duration = duration or pattern.telegraph_time or Defaults.telegraph_time
    local settings, cue
    if Schema.is_stationary(pattern.type) then
        settings = Schema.stationary_options(pattern, Defaults)
        if not settings then return nil end
        cue = prepare_stationary(boss, pattern, settings)
        attach_warning(cue, "_stationary_attack_cue", detached)
        if (pattern.type == "rain" and not cue.rect) or (pattern.type == "zone" and not cue.center) then
            return cue
        end
    elseif Schema.is_moving and Schema.is_moving(pattern.type) then
        settings = Schema.moving_options(pattern, Defaults)
        if not settings then return nil end
        cue = prepare_moving(boss, pattern)
        attach_warning(cue, "_moving_attack_cue", detached)
        retarget_moving(cue, settings)
    elseif pattern.type == "summon" and pattern.telegraph_shape then
        settings = pattern.summon or {}
        -- The existing summon service places helpers in world coordinates.
        cue = prepare_stationary(boss, pattern, settings, go.get_world_position())
    end
    local visual_pattern = not cue and resolve_legacy(pattern)
    if duration <= 0 then
        if visual_pattern and delayed(visual_pattern) then
            local handle = {boss = boss, pattern = pattern, ids = {}, color = pattern.telegraph_color}
            attach_warning(handle, "_indicator_cue", detached)
            return handle
        end
        return cue
    end

    -- Follow existing executor parry defaults; never change damage rules.
    -- An authored colour wins for both the marker and the boss flash.
    local tell
    if not pattern.telegraph_color then
        local Tells = require "mvtk.combat.attack_tells"
        local parryable = Tells.boss_parryable(pattern)
        if cue and pattern.type ~= "reposition" and pattern.type ~= "summon" and parryable == nil then
            parryable = true
        end
        if parryable ~= nil then
            tell = Tells.cue(parryable)
            if tell then Tells.windup(boss, parryable, tell) end
        end
    end
    local color = pattern.telegraph_color or (tell and tell.color)

    -- Audio cue
    if pattern.telegraph_sound then
        SafeSound.play(pattern.telegraph_sound)
    end

    if cue then
        cue.color = color
        spawn_managed(cue, settings, color, duration)
        return cue
    end

    if NON_AREA_CAST[visual_pattern.type] or visual_pattern.type == "special" then
        if Feedback and Feedback.screen_shake then
            pcall(Feedback.screen_shake, 0.15 * duration, 0.8)
        end
        return nil
    end

    -- Visual cue via factory (optional; not every boss ships a telegraph factory)
    local pos = pcall(go.get_position) and go.get_position() or vmath.vector3()
    local facing = boss.facing or 1
    local spawn_pos, size_x, size_y, shape, angle = legacy_visual(boss, visual_pattern, pos)
    local managed = visual_pattern.type == "beam" or visual_pattern.type == "aoe" or visual_pattern.type == "wave"
    if not spawn_pos then
        local handle = {boss = boss, pattern = pattern, ids = {}, color = color}
        attach_warning(handle, "_indicator_cue", detached)
        return handle
    end
    local record = boss.boss_data
    local began = record and record._boss_clock_at
    -- A late draw can create a warning for a cast already on the timeline.
    -- The self-expiring visual only has the rest of that warning to show.
    local visible_time = duration
    if not managed and began and record.fight_time then
        visible_time = duration - math.max(0, record.fight_time - began)
        if visible_time <= 0 then return end
    end

    local props = color_props({
        shape = shape,
        duration = visible_time,
        size_x = size_x,
        size_y = size_y,
        managed = managed,
        neutral = visual_pattern.type == "projectile",
        -- The melee indicator is symmetric. Its offset already follows the
        -- boss, and keeping a positive scale lets it draw on the left too.
        facing = pattern.type == "melee" and 1 or facing,
    }, color)
    local rotation = angle and vmath.quat_rotation_z(angle)
    local ok, id = pcall(factory.create, TELEGRAPH_FACTORY, spawn_pos, rotation, props)
    if not ok then
        -- Factory missing — degrade to screen-shake only (still provides
        -- a visual cue that an attack is incoming).
        if Feedback and Feedback.screen_shake then
            pcall(Feedback.screen_shake, 0.2 * duration, 1.0)
        end
        return nil
    end

    -- Subtle shake near the end of telegraph to reinforce imminent hit.
    if Feedback and Feedback.screen_shake then
        pcall(Feedback.screen_shake, 0.15 * duration, 0.8)
    end
    if id and (managed or pattern.type == "mine" or pattern.type == "charge") then
        local handle = {boss = boss, pattern = pattern, visual_pattern = visual_pattern,
            ids = {id}, track = true, color = color, width = size_x, height = size_y}
        if managed then
            handle.owner = warning_owner(boss)
            handle.owner:own(id)
            handle.owner:finish()
        end
        attach_warning(handle, "_indicator_cue", detached)
        return handle
    end
    return id
end

-- A child gets its own warning even when several combo steps overlap. Bind
-- just for the synchronous launch so the existing executor can take it.
function M.with_child_warning(handle, launch, instance)
    local cue = type(handle) == "table" and handle
    local boss = cue and cue.boss
    local slot = cue and cue.slot
    local previous = slot and boss[slot]
    if slot then boss[slot] = cue end
    launch(instance)
    if not (cue and cue.taken) then M.leave_state(handle) end
    if previous and not previous.cancelled and not boss[slot] then boss[slot] = previous end
end

M._telegraph_geometry = telegraph_geometry
M._legacy_visual = legacy_visual

-- Once a hit timer owns the warning, even a cast that has already returned
-- to idle can keep its warning until firing. Runtime owns cancellation.
function M.leave_state(handle)
    if type(handle) == "table" and handle.execution_owned then
        if handle.boss._indicator_cue == handle then handle.boss._indicator_cue = nil end
    else
        M.cancel(handle)
    end
end

--- Cancel a live telegraph (if attack was interrupted).
function M.cancel(handle)
    if type(handle) == "table" and handle.ids then
        handle.cancelled = true
        if handle.boss._stationary_attack_cue == handle then
            handle.boss._stationary_attack_cue = nil
        end
        if handle.boss._moving_attack_cue == handle then
            handle.boss._moving_attack_cue = nil
        end
        if handle.boss._indicator_cue == handle then
            handle.boss._indicator_cue = nil
        end
        for _, id in ipairs(handle.ids) do
            if go.exists(id) then pcall(go.delete, id) end
        end
        handle.ids = {}
    elseif handle then
        pcall(go.delete, handle)
    end
end

return M
