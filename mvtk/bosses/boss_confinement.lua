-- mvtk/bosses/boss_confinement.lua
-- Keeps a boss inside its fight area. Before this, boss movement had no bounds
-- (get_arena_center was a stub and leash_radius was never applied), so a boss
-- could chase the player out of the room.
--
-- Area: the boss's Tiled boss_arena rectangle (BossArena bounds), or the
-- boss's room rectangle when it has no arena. Pure clamp logic is unit-tested.
local M = {}

local Moves = require "mvtk.bosses.moving_attack_defaults"
local Motion = require "mvtk.bosses.boss_motion"
local Defaults = require("mvtk.core.util").require_config("developer.config.boss_defaults", {})

local function arena_body(boss)
    local body = boss._body
    if boss._base_scale then
        local scale = go.get_scale(boss.self_url)
        -- Respect a growing phase pulse and preserve space for a blink to regrow.
        local size = Motion.collision_body(scale.x, scale.y)
        if size.half_height > body.half_height then return size end
    end
    return body
end

-- Use the same extents for cast geometry and the boss's post-motion clamp.
function M.half_extents(config, boss)
    config = config or {}
    local size = config.size or {}
    local pad = math.max(0, tonumber(config.charge_edge_padding) or 0)
    local motion = boss and boss._locomotion
    if motion and motion.active and motion.feet_offset then
        return boss._body.half_width + pad, boss._body.half_height, motion.feet_offset
    end
    if boss and boss._confine_kind == "arena" and boss._body then
        local body = arena_body(boss)
        local rect = boss._confine_rect
        if rect and 2 * (body.half_width + pad) > rect.max_x - rect.min_x then pad = 0 end
        return body.half_width + pad, body.half_height
    end
    return (tonumber(size.width) or 0) * 0.5 + pad, (tonumber(size.height) or 0) * 0.5
end

-- With no solution on an axis, center the ungrounded body on that axis.
-- Keep arena-edge padding whenever it fits around the body.
function M.clamp_boss(boss, x, y)
    local rect = boss._confine_rect
    if not rect then return x, y end
    local hw, hh, feet = M.half_extents(boss.config, boss)
    if boss._confine_kind == "arena" and not feet then
        local width, height = rect.max_x - rect.min_x, rect.max_y - rect.min_y
        if 2 * hw > width then x = rect.min_x + width * 0.5 end
        if 2 * hh > height then y = rect.min_y + height * 0.5 end
    end
    return M.clamp(x, y, rect, hw, hh, feet, feet and M.floor_min(boss))
end

function M.clamp_attack(cue, x, y, feet)
    local boss = cue.boss
    if boss and boss._confine_kind == "arena" and not cue.feet_offset then
        if feet and cue.rect then y = math.max(y, cue.rect.min_y + feet) end
        return M.clamp_boss(boss, x, y)
    end
    return M.clamp(x, y, cue.rect, cue.half_width, cue.half_height, feet or cue.feet_offset, cue.floor_min)
end

--- { min_x, min_y, max_x, max_y } from BossArena bounds { x, y, width, height }.
function M.rect_from_arena_bounds(bounds)
    if type(bounds) ~= "table" then return nil end
    local x, y = tonumber(bounds.x), tonumber(bounds.y)
    local w, h = tonumber(bounds.width), tonumber(bounds.height)
    if not (x and y and w and h) or w <= 0 or h <= 0 then return nil end
    return { min_x = x, min_y = y, max_x = x + w, max_y = y + h }
end

--- Clamp a position so a box of half extents (hw, hh) stays inside rect.
-- Returns x, y (unchanged when rect is nil or narrower than the box).
function M.clamp(x, y, rect, hw, hh, feet, floor_min)
    if type(rect) ~= "table" then return x, y end
    hw, hh = math.max(0, tonumber(hw) or 0), math.max(0, tonumber(hh) or 0)
    local min_x, max_x = rect.min_x + hw, rect.max_x - hw
    local min_y, max_y = (floor_min or rect.min_y) + (feet or hh), rect.max_y - hh
    if min_x <= max_x then x = math.max(min_x, math.min(max_x, x)) end
    if min_y <= max_y then y = math.max(min_y, math.min(max_y, y)) end
    return x, y
end

--- World point inset by the given half extents. Ground anchors use the boss's height.
function M.anchor(rect, name, boss_pos, player_pos, half_width, half_height, feet, floor_min)
    if not rect or not Moves.is_anchor(name) then return nil end
    local hw = math.max(0, tonumber(half_width) or 0)
    local hh = math.max(0, tonumber(half_height) or 0)
    local left, right = rect.min_x + hw, rect.max_x - hw
    local bottom, ceiling = (floor_min or rect.min_y) + (feet or hh), rect.max_y - hh
    if left > right or bottom > ceiling then return nil end
    local x
    local y = Moves.top[name] and ceiling or boss_pos.y
    if Moves.relative[name] then
        if not player_pos then return nil end
        if name == "far_from_player" then
            x = player_pos.x <= (left + right) * 0.5 and right or left
        elseif name == "near_player" then
            x = player_pos.x
        else
            local direction = player_pos.x >= boss_pos.x and 1 or -1
            local distance = tonumber(Defaults.behind_player_distance) or Moves.behind_player_distance
            x = player_pos.x + direction * math.max(0, distance)
        end
    else
        x = left + (right - left) * Moves.anchor_x[name]
    end
    x, y = M.clamp(x, y, rect, hw, hh, feet, floor_min)
    return vmath.vector3(x, y, boss_pos.z or 0)
end

-- An opted-in boss can fall below a fight rectangle into a pit in its room.
function M.floor_min(boss)
    local motion = boss._locomotion
    return motion and motion.active and motion.room_min_y or nil
end

local function room_manager()
    local ok, manager = pcall(require, "mvtk.map.streaming.room_manager")
    if ok then return manager end
end

function M.room_rect(config)
    if not config.room_id then return end
    local manager = room_manager()
    local bounds = manager and manager.get_room_bounds and manager.get_room_bounds(config.room_id)
    if type(bounds) == "table" and bounds.min_x and bounds.max_x and bounds.min_y and bounds.max_y then
        return {min_x = bounds.min_x, min_y = bounds.min_y, max_x = bounds.max_x, max_y = bounds.max_y}
    end
end

-- Find the bottom of published rooms in this column, including streamed
-- neighbours below the boss. Used only for the spawn containment probe.
function M.ray_bottom(config, x, bottom)
    local room = M.room_rect(config)
    if room then bottom = math.min(bottom, room.min_y) end
    local manager = room_manager()
    if manager and manager.list_rooms then
        for _, id in ipairs(manager.list_rooms()) do
            local bounds = manager.get_room_bounds(id)
            if bounds and x >= bounds.min_x and x <= bounds.max_x then
                bottom = math.min(bottom, bounds.min_y)
            end
        end
    end
    return bottom
end

--- Resolve the confinement rectangle for a boss config (arena, then room).
function M.resolve_rect(config)
    config = config or {}
    local arena_id = config.arena_id or config.arena
    if arena_id then
        local ok, BossArena = pcall(require, "mvtk.bosses.boss_arena")
        local arena = ok and BossArena and BossArena.get_arena and BossArena.get_arena(arena_id) or nil
        -- Only authored (Tiled) rectangles; setup_arena's placeholder is not a place.
        local authored = arena and arena.config and arena.config.bounds_authored == true
        local rect = authored and M.rect_from_arena_bounds(arena.bounds) or nil
        if rect then return rect, "arena" end
    end
    local room = M.room_rect(config)
    if room then return room, "room" end
    return nil, nil
end

return M
