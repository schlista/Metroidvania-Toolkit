-- mvtk/developer/game/interaction_manager.lua
-- Central registry for context-sensitive player interactions.
-- Interactable prefabs register/unregister themselves when the player enters/leaves range.
-- The player queries the manager each frame to fetch hint text and triggers on demand.

local Util = require "mvtk.core.util"
local Presentation = require "mvtk.tiled.object_presentation"

local M = {}

-- Debug-gate all print() calls in this module so they only fire when enabled.
local _orig_print = print
local _Dbg = Util.require_config("developer.config.debug_config")
local function print(...)  -- luacheck: ignore 121
    if _Dbg.global and _Dbg.global.enable and _Dbg.gameplay and _Dbg.gameplay.interaction then
        _orig_print(...)
    end
end

local InteractionConfig = Util.require_config("developer.config.interaction")
local DEFAULT_RANGE = (InteractionConfig and InteractionConfig.default_range) or 192
local DEFAULT_PRIORITY = (InteractionConfig and InteractionConfig.default_priority) or 0

local interactions = {}
local serial = 0

local function url_key(url)
    if not url then return nil end
    local ok, resolved = pcall(msg.url, url)
    if not ok or not resolved then return nil end
    return resolved.socket .. "|" .. resolved.path .. "|" .. tostring(resolved.fragment)
end

local function ensure_entry(url)
    local key = url_key(url)
    if not key then return nil end
    local entry = interactions[key]
    if not entry then
        local resolved = msg.url(url)
        local go_url = msg.url(resolved.socket, resolved.path, nil)
        entry = {
            url = resolved,
            go_url = go_url,
            range = DEFAULT_RANGE,
            priority = DEFAULT_PRIORITY,
            label = nil,
            get_position = nil,
            tags = nil,
        }
        interactions[key] = entry
        serial = serial + 1
    end
    return entry, key
end

local function remove_entry(url)
    local key = url_key(url)
    if not key then return end
    if interactions[key] then
        interactions[key] = nil
        serial = serial + 1
    end
end

local function entry_position(entry)
    local target_go = entry and (entry.go_url or entry.url)
    if entry.get_position then
        local ok, pos = pcall(entry.get_position, target_go)
        if ok and pos then return pos end
    end
    if target_go and go.exists(target_go) then
        return go.get_world_position(target_go)
    end
    return nil
end

local function distance_sq(a, b)
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    return dx * dx + dy * dy
end

function M.register(url, opts)
    print(string.format("[INTERACT] M.register called: url=%s", tostring(url)))
    local entry = ensure_entry(url)
    if not entry then 
        print("[INTERACT] Failed to create entry!")
        return nil 
    end
    opts = opts or {}
    if opts.range then entry.range = tonumber(opts.range) or entry.range end
    if opts.priority then entry.priority = tonumber(opts.priority) or entry.priority end
    if opts.label ~= nil then entry.label = opts.label end
    if opts.position_fn then entry.get_position = opts.position_fn end
    if opts.tags then entry.tags = opts.tags end
    if opts.reports_result ~= nil then entry.reports_result = opts.reports_result end
    print(string.format("[INTERACT] Registered: url=%s, range=%s, priority=%s, label=%s", 
        tostring(entry.url), tostring(entry.range), tostring(entry.priority), tostring(entry.label)))
    return entry.url
end

function M.update(url, opts)
    if not opts then return end
    local entry = ensure_entry(url)
    if not entry then return end
    M.register(url, opts)
end

function M.unregister(url)
    remove_entry(url)
end

function M.is_registered(url)
    return interactions[url_key(url)] ~= nil
end

local function default_range(opts, entry)
    if opts and opts.default_range then
        return opts.default_range
    end
    if entry and entry.range then
        return entry.range
    end
    return DEFAULT_RANGE
end

-- The player peeks every frame for the HUD prompt, so this search stays silent.
local function find_best(world_pos, opts)
    if not world_pos then return nil end

    local best_entry, best_dist_sq, best_priority = nil, math.huge, -math.huge
    for _, entry in pairs(interactions) do
        local target_go = entry and (entry.go_url or entry.url)
        if target_go and go.exists(target_go) then
            local pos = entry_position(entry)
            if pos then
                local range = default_range(opts, entry)
                local dist_sq = distance_sq(world_pos, pos)
                -- Authored rectangles extend the usable area for large objects.
                -- They must not shrink the configured range to a center-point
                -- hit test: a player's origin can sit above a small floor prop.
                local inside = Presentation.contains(target_go, world_pos)
                if not Presentation.is_removed(target_go)
                    and (inside == true or dist_sq <= (range * range)) then
                    local priority = entry.priority or 0
                    if priority > best_priority or (priority == best_priority and dist_sq < best_dist_sq) then
                        best_entry = entry
                        best_dist_sq = dist_sq
                        best_priority = priority
                    end
                end
            end
        end
    end
    if not best_entry then return nil end
    return best_entry, math.sqrt(best_dist_sq)
end

function M.peek(world_pos, opts)
    local entry, dist = find_best(world_pos, opts)
    if not entry then return nil end
    return {
        url = entry.url,
        label = entry.label,
        distance = dist,
        range = entry.range,
        priority = entry.priority,
        reports_result = entry.reports_result,
    }
end

local INTERACT_MSG = hash("mvtk_interact")

function M.trigger(world_pos, opts)
    print("[INTERACT] M.trigger called")
    local candidate = M.peek(world_pos, opts)
    if not candidate or not candidate.url then
        print("[INTERACT] M.trigger: No candidate found")
        return false
    end
    print(string.format("[INTERACT] M.trigger: Found candidate %s (label=%s)", 
        tostring(candidate.url), tostring(candidate.label)))
    local payload = {
        actor = opts and opts.actor or nil,
        position = world_pos,
        label = candidate.label,
        interaction_result = candidate.reports_result == true and opts and opts.result_url ~= nil or false,
        result_url = opts and opts.result_url or nil,
    }
    print(string.format("[INTERACT] Posting mvtk_interact to %s", tostring(candidate.url)))
    local ok, err = pcall(msg.post, candidate.url, INTERACT_MSG, payload)
    if not ok then
        print(string.format("[INTERACT] Failed to post mvtk_interact to %s: %s", tostring(candidate.url), tostring(err)))
        return false
    end
    print("[INTERACT] Message posted successfully!")
    if opts and opts.consume_on_trigger then
        M.unregister(candidate.url)
    end
    return true, candidate
end

function M.serial()
    return serial
end

function M.debug_list()
    local list = {}
    for _, entry in pairs(interactions) do
        list[#list + 1] = {
            url = entry.url,
            range = entry.range,
            priority = entry.priority,
            label = entry.label,
        }
    end
    table.sort(list, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)
    return list
end

function M.reset()
    interactions = {}
    serial = 0
end

return M
