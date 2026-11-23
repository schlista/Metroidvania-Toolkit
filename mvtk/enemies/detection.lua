--- Enemy Detection and Aggro System
-- Provides utilities for enemies to detect and track the player
-- Handles line-of-sight checks, distance calculations, and player state tracking
--
-- @module detection

local C = require "mvtk.core.constants"
local SurfaceClassifier = require "mvtk.core.surface_classifier"

local M = {}

local DEFAULT_LOS_GROUPS = SurfaceClassifier.RAYCAST.TERRAIN

local function normalize_collision_groups(groups)
    if not groups then
        return nil
    end
    if type(groups) ~= "table" then
        return groups
    end
    local out = {}
    for i, g in ipairs(groups) do
        if type(g) == "string" then
            out[i] = hash(g)
        else
            out[i] = g
        end
    end
    if #out == 0 then
        for _, g in pairs(groups) do
            if type(g) == "string" then
                table.insert(out, hash(g))
            else
                table.insert(out, g)
            end
        end
    end
    return out
end

-- The player publishes motion in pixels per game second. Read the root
-- directly on the draw that uses it, including all decisions on a long draw.
local player_data = {}
local player_url = msg.url("main:/collection2/player#player")

local function read_root(url)
    if not url then return nil end
    local ok, pos = pcall(go.get_position, url)
    if ok then return pos end
end

function M.init(url)
    if url then M.set_player_url(url) end
end

function M.get_player_url()
    if read_root(player_url) then return player_url end
    return C.URL.PLAYER or player_url
end

local function read_player_root()
    local pos = read_root(player_url)
    if pos or player_url == C.URL.PLAYER then return pos end
    return read_root(C.URL.PLAYER)
end

function M.get_player_position()
    local root = read_player_root()
    local body = player_data.body
    if root and body and body.position then
        local pos = body.position
        return vmath.vector3(pos.x + body.x, pos.y + body.y, pos.z)
    end
    return root
end

M.peek_player_position = M.get_player_position

function M.set_player_velocity(vx, vy)
    player_data.vx, player_data.vy = vx, vy
end

--- Publish the player's actual movement floor contact. Nil clears the sample.
function M.set_player_grounded(grounded)
    player_data.grounded = grounded
end

--- Before the player publishes floor contact, treat them as grounded.
function M.get_player_grounded()
    return player_data.grounded ~= false
end

--- Mark a player whose separately positioned collider has yet to publish.
function M.expect_collision_body()
    local body = player_data.body
    if not body or not body.owner and body.half_w then player_data.body = {} end
end

local function same_player(a, b)
    return a == b or a and b and a.path and a.path == b.path and a.socket == b.socket
end

--- Publish local fixture bounds and, for a separate collider, its world origin.
-- The owning player URL prevents a departing collider from clearing its successor.
function M.set_player_body(half_w, half_h, offset_x, offset_y, position, owner)
    if owner then
        if not same_player(owner, player_url) then return end
        if not half_w and not (player_data.body and player_data.body.owner) then return end
    end
    player_data.body = half_w and {
        half_w = half_w, half_h = half_h, x = offset_x or 0, y = offset_y or 0,
        position = position, owner = owner,
    } or owner and {owner = owner}
end

--- Read the published hurtbox and the current movement root.
function M.get_published_player_body()
    local body = player_data.body
    if not body or not body.half_w then return nil end
    local root = body.position and read_player_root() or M.get_player_position()
    if not root then return nil end
    local pos = body.position or root
    return {x = pos.x + body.x, y = pos.y + body.y, half_w = body.half_w, half_h = body.half_h,
        root_x = root.x, root_y = root.y, animated = body.position ~= nil or nil}
end

function M.get_player_body()
    if player_data.body then return M.get_published_player_body() end
    local pos = M.get_player_position()
    return pos and {x = pos.x, y = pos.y, half_w = 0, half_h = 0, root_x = pos.x, root_y = pos.y}
end

function M.get_player_velocity()
    if player_data.vx ~= nil then return vmath.vector3(player_data.vx, player_data.vy, 0) end
end

function M.is_player_alive()
    return M.get_player_position() ~= nil
end

--- Get distance to player from position
-- @param pos Position to measure from
-- @return Distance to player, or nil if player not available
function M.get_distance_to_player(pos)
    local player_pos = M.get_player_position()
    if not player_pos then
        return nil
    end

    return vmath.length(player_pos - pos)
end

--- Check if player is within detection range
-- @param pos Enemy position
-- @param range Detection range
-- @return true if player is in range
function M.is_player_in_range(pos, range)
    local distance = M.get_distance_to_player(pos)
    if not distance then
        return false
    end

    return distance <= range
end

--- Check if there's line of sight to player
-- @param from_pos Starting position
-- @param max_distance Optional max distance to check (default: infinite)
-- @param collision_groups Optional table of collision groups to check against (default: terrain/solid layers)
-- @return true if clear line of sight, false otherwise
function M.has_line_of_sight(from_pos, max_distance, collision_groups)
    local player_pos = M.get_player_position()
    if not player_pos then
        return false
    end

    -- Check distance limit
    if max_distance then
        local distance = vmath.length(player_pos - from_pos)
        if distance > max_distance then
            return false
        end
    end

    -- An enemy on the player's own origin sees them. Box2D refuses a ray whose
    -- ends meet and warns on every frame it is asked (Stage 9 A46).
    local dx, dy = player_pos.x - from_pos.x, player_pos.y - from_pos.y
    if dx * dx + dy * dy < 1 then
        return true
    end

    -- Default collision groups
    collision_groups = normalize_collision_groups(collision_groups) or DEFAULT_LOS_GROUPS

    -- Raycast to check for obstacles
    local result = physics.raycast(from_pos, player_pos, collision_groups)

    -- If raycast hit something, no line of sight
    return result == nil
end

--- Check if player is on similar vertical level (same platform)
-- @param pos Enemy position
-- @param vertical_threshold Max vertical difference to consider "same level" (default: 50)
-- @return true if player is on same level
function M.is_player_on_same_level(pos, vertical_threshold)
    vertical_threshold = vertical_threshold or 50

    local player_pos = M.get_player_position()
    if not player_pos then
        return false
    end

    local vertical_diff = math.abs(player_pos.y - pos.y)
    return vertical_diff <= vertical_threshold
end

--- Get direction to player
-- @param pos Position to measure from
-- @param normalize If true, returns normalized direction vector (default: true)
-- @return Direction vector to player, or nil if player not available
function M.get_direction_to_player(pos, normalize)
    if normalize == nil then
        normalize = true
    end

    local player_pos = M.get_player_position()
    if not player_pos then
        return nil
    end

    local direction = player_pos - pos

    if normalize then
        local length = vmath.length(direction)
        if length > 0 then
            direction = direction / length
        end
    end

    return direction
end

--- Get horizontal direction to player (1 or -1)
-- @param pos Position to measure from
-- @return 1 if player is to the right, -1 if to the left, 0 if player not available
function M.get_horizontal_direction_to_player(pos)
    local player_pos = M.get_player_position()
    if not player_pos then
        return 0
    end

    if player_pos.x > pos.x then
        return 1
    elseif player_pos.x < pos.x then
        return -1
    else
        return 0
    end
end

--- Check if player can be detected (composite check)
-- @param pos Enemy position
-- @param detection_range Max detection range
-- @param require_los If true, requires line of sight (default: true)
-- @param require_same_level If true, requires similar Y position (default: false)
-- @param vertical_threshold Vertical threshold for same level check (default: 50)
-- @return true if player detected, false otherwise
function M.can_detect_player(pos, detection_range, require_los, require_same_level, vertical_threshold)
    require_los = require_los == nil and true or require_los
    require_same_level = require_same_level or false

    -- Check if player is alive
    if not M.is_player_alive() then
        return false
    end

    -- Check range
    if not M.is_player_in_range(pos, detection_range) then
        return false
    end

    -- Check line of sight if required
    if require_los then
        if not M.has_line_of_sight(pos, detection_range) then
            return false
        end
    end

    -- Check same level if required
    if require_same_level then
        if not M.is_player_on_same_level(pos, vertical_threshold) then
            return false
        end
    end

    return true
end

--- Lead a shot from the live player position. The first argument remains
--- the caller's position for compatibility with existing behavior actions.
function M.predict_player_position(_, time_ahead)
    local pos = M.get_player_position()
    if not pos then return nil end
    local velocity = M.get_player_velocity()
    return velocity and pos + velocity * time_ahead or pos
end

--- Replace the player binding on spawn.
function M.set_player_url(url)
    if player_url ~= url then
        if player_data.body and player_data.body.owner and not same_player(player_url, url) then
            player_data.body = nil
        end
        M.set_player_velocity(nil, nil)
        player_url = url
    end
end

function M.reset()
    player_data = {}
end

return M
