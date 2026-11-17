-- mvtk/core/fast_travel.lua
-- Fast travel system with discovery and unlocking

local C = require "mvtk.core.constants"
local Util = require "mvtk.core.util"
local SafeRequire = require "mvtk.core.safe_require"
local Debug = Util.require_config("developer.config.debug_config", { global = {}, gameplay = {} })

local M = {}
M.points = {}  -- All registered points with metadata
M.unlocked = {}  -- IDs of unlocked points

local ft_log = Util.make_debug_log("[FAST_TRAVEL]", function()
  return (Debug.gameplay and Debug.gameplay.fast_travel) or (Debug.global and Debug.global.enable)
end)

local normalize_text = Util.normalize_hash_string

-- A lookup batch builds the published census once, without a load-time cycle
-- through Census -> BossManager -> Grants -> FastTravel.
function M.lookup_points()
  local points = {}
  local Census = require "mvtk.world.census"
  for _, point in ipairs(Census.travel_points()) do
    if point.fast_travel == true then
      points[point.id] = {
        pos = vmath.vector3(point.x, point.y, 0), room_id = point.room_id,
        name = point.name or point.id, description = point.description or "",
        show_on_map = point.show_on_map ~= false, facing = point.facing,
      }
    end
  end
  return points
end

local function rules()
  return Util.require_config("developer.config.resolved_config").fast_travel or {}
end

-- Register a fast travel point with full metadata
-- @param id: unique identifier
-- @param opts: { pos = vector3, room_id = string, name = string, description = string, auto_unlock = bool }
function M.register(id, opts)
  id = normalize_text(id)
  if not id then return false end

  opts = opts or {}
  if not opts.pos then
    ft_log(string.format("[FAST_TRAVEL] Failed to register '%s': missing position", id))
    return false
  end

  local room_id = normalize_text(opts.room_id) or "unknown"
  local name = normalize_text(opts.name) or require("developer.config.ui_text")["gameplay.travel_point"]
  local description = normalize_text(opts.description) or ""
  local show_on_map = (opts.show_on_map ~= false)
  local icon = normalize_text(opts.icon) or ""
  local facing = tonumber(opts.facing)
  if facing == 0 then facing = nil end
  local unlock_cost = tonumber(opts.unlock_cost) or 0

  if M.points[id] then
    ft_log(string.format("[FAST_TRAVEL] Point '%s' already registered, updating", id))
  end

  M.points[id] = {
    pos = vmath.vector3(opts.pos),
    room_id = room_id,
    name = name,
    description = description,
    auto_unlock = opts.auto_unlock or false,
    show_on_map = show_on_map,
    icon = icon,
    facing = facing,
    unlock_cost = unlock_cost,
  }

  -- Auto-unlock if specified
  if opts.auto_unlock then
    M.unlock(id)
  end

  ft_log(string.format("[FAST_TRAVEL] Registered point '%s' in room '%s'", id, M.points[id].room_id))
  return true
end

-- Unlock a fast travel point (discovery)
function M.unlock(id)
  id = normalize_text(id)
  if not id then return false end

  local point = M.get_point(id)
  if not point then
    ft_log(string.format("[FAST_TRAVEL] Cannot unlock '%s': not registered", id))
    return false
  end

  if M.unlocked[id] then
    ft_log(string.format("[FAST_TRAVEL] Point '%s' already unlocked", id))
    return false
  end

  M.unlocked[id] = true
  local Flags = require "mvtk.core.flags"
  Flags.set("fast_travel_" .. id, true)
  ft_log(string.format("[FAST_TRAVEL] Unlocked fast travel point: '%s'", point.name))

  -- Auto-save on unlock
  local ok_cp, CP = SafeRequire("mvtk.core.checkpoint", "mvtk.core.fast_travel")
  if ok_cp and CP then
    CP.autosave("fast_travel_unlock")
  end

  -- Trigger event for UI feedback.
  -- msg.post to a dead instance doesn't raise a Lua error — it silently
  -- queues and later logs "Instance could not be found". pcall can't catch
  -- that, so we must verify the target exists first.
  if C.URL and C.URL.PLAYER then
    local ok_exists, exists = pcall(go.exists, C.URL.PLAYER)
    if ok_exists and exists then
      Util.safe_post(C.URL.PLAYER, C.MSG.FAST_TRAVEL_UNLOCKED, { id = id, name = point.name })
    end
  end

  return true
end

-- Guaranteed rewards can target an unloaded/unregistered station. The caller
-- commits this mutation with its reward transaction; registration adds location
-- metadata later and teleporting still requires that metadata.
function M.grant_reward(id)
  id = normalize_text(id)
  if not id then return false end
  M.unlocked[id] = true
  return true
end

-- Compensation only: undo a reward that was locked before its transaction.
function M.revoke_reward(id)
  id = normalize_text(id)
  if not id then return false end
  M.unlocked[id] = nil
  return true
end

-- Check if a point is unlocked.
function M.is_unlocked(id)
  id = normalize_text(id)
  if not id then return false end
  return M.unlocked[id] == true
end

-- Get all unlocked point IDs
-- Returns all unlocked IDs - point metadata may or may not be available yet
function M.get_unlocked_ids()
  local ids = {}
  for id in pairs(M.unlocked) do
    table.insert(ids, id)
  end
  table.sort(ids)
  return ids
end

-- Check if a point has valid position data for teleporting
function M.has_point_data(id, points)
  local point = M.get_point(id, points)
  return point and point.pos and true or false
end

-- Reward ids must exist in the published census or in a live registration.
-- Save-restored metadata can still support travel but cannot validate new grants.
function M.is_known_point(id)
  id = normalize_text(id)
  if not id then return false end
  local live = M.points[id]
  return (live and not live.restored_from_save) or M.lookup_points()[id] ~= nil
end

-- Get all registered point IDs
function M.get_all_ids()
  local ids = {}
  for id in pairs(M.points) do
    table.insert(ids, id)
  end
  table.sort(ids)
  return ids
end

-- Get point metadata
function M.get_point(id, points)
  id = normalize_text(id)
  if not id then return nil end
  local live = M.points[id]
  if live and not live.restored_from_save then return live end
  return (points or M.lookup_points())[id] or live
end

function M.count()
  return Util.count_keys(M.points)
end

function M.count_unlocked()
  return Util.count_keys(M.unlocked)
end

-- Teleport to a fast travel point
-- opts:
--   fade: bool (default false)
--   load_room: legacy option; destination readiness is always required
--   update_camera: bool (default true)
--   require_unlocked: bool (default true)
function M.teleport_to(id, player_url, opts)
  id = normalize_text(id)
  if not id then return false end
  opts = opts or {}

  if not M.can_travel(opts.source) then
    Util.safe_post("main:/toast_gui#toast", "toast", { key = "gameplay.travel_unavailable" })
    return false
  end
  local point = M.get_point(id)
  if not point or not point.pos then return false end

  local require_unlocked = (opts.require_unlocked ~= false)
  if require_unlocked and not M.unlocked[id] then
    ft_log(string.format("[FAST_TRAVEL] Cannot teleport to '%s': not unlocked", id))
    return false
  end

  local p = point.pos

  player_url = player_url or (C.URL and C.URL.PLAYER)
  -- Avoid go.* lookups here because teleport can be triggered from GUI scripts.
  if not player_url then
    ft_log("[FAST_TRAVEL] Cannot teleport: player URL invalid")
    return false
  end

  ft_log(string.format("[FAST_TRAVEL] Teleporting to '%s' at (%.1f, %.1f)", point.name, p.x, p.y))

  local do_fade = opts.fade and true or false
  local do_update_camera = (opts.update_camera ~= false)

  local cfg = rules()
  local cost = tonumber(cfg.travel_cost) or 0
  local Wallet = require "mvtk.core.wallet"
  if not Wallet.can_afford(cost) then
    -- The caller says why: the travel map is open and paused, which holds toasts until play resumes,
    -- so a toast here never showed while the player could read it (F7a step 59).
    return false, "cost", cost
  end
  local duration = do_fade and (tonumber(cfg.transition_time) or 0.3) or 0
  -- Accepted means enqueueing raised no error; a later room-load failure is
  -- not refunded. The player owns the hold, motion reset and all fade exits.
  local accepted = Util.safe_post(player_url, C.MSG.SET_POSITION, {
      position = p, facing = point.facing, position_kind = "feet",
      room_id = point.room_id ~= "unknown" and point.room_id or nil,
      update_camera = do_update_camera,
      arrival_fade_out = duration, arrival_fade_in = duration,
      reset_motion = true, reason = "fast_travel",
    })
  if accepted and cost > 0 then Wallet.spend(cost, "fast_travel") end
  return accepted
end

function M.can_travel(source)
  -- A running countdown with block_travel (WM09) refuses every departure.
  -- Read through package.loaded: the countdown service reaches this module
  -- through mvtk.game.grants, and Bob refuses require cycles.
  local Countdown = package.loaded["mvtk.game.countdown"]
  if type(Countdown) == "table" and Countdown.blocks_travel and Countdown.blocks_travel() then return false end
  local cfg = rules()
  if cfg.block_in_boss_fight ~= false then
    local FightLock = require "mvtk.bosses.fight_lock"
    local RoomManager = require "mvtk.map.streaming.room_manager"
    if FightLock.is_locked(RoomManager.get_current_room()) then return false end
  end
  local from = cfg.travel_from
  if from == nil then from = cfg.allow_menu_travel == false and "stations" or "anywhere" end
  return source == "fast_travel_bench" or source == "save_point" or from == "anywhere"
end

function M.can_menu_travel()
  return M.can_travel("pause_menu")
end

-- Reset all unlocked points (for new game)
function M.reset()
  M.unlocked = {}
  ft_log("[FAST_TRAVEL] Reset all unlocked points")
end

-- Capture state for saving (checkpoint provider)
function M.capture()
  local unlocked_list = {}
  local point_data = {}
  for id in pairs(M.unlocked) do
    table.insert(unlocked_list, id)
    -- Also save point metadata so it persists even if room isn't loaded
    local point = M.points[id]
    if point then
      point_data[id] = {
        pos = { x = point.pos.x, y = point.pos.y, z = point.pos.z or 0 },
        room_id = point.room_id,
        name = point.name,
        description = point.description or "",
        show_on_map = point.show_on_map,
        icon = point.icon,
        facing = point.facing,
        unlock_cost = point.unlock_cost,
      }
    end
  end
  return { unlocked = unlocked_list, point_data = point_data }
end

-- Restore state from save (checkpoint provider)
function M.apply(data)
  M.unlocked = {}
  if data and data.unlocked then
    for _, id in ipairs(data.unlocked) do
      M.unlocked[id] = true
    end
    ft_log(string.format("[FAST_TRAVEL] Restored %d unlocked points", #data.unlocked))
  end

  -- Restore point metadata from save, so fast travel works even if rooms aren't loaded
  if data and data.point_data then
    for id, pdata in pairs(data.point_data) do
      if not M.points[id] and pdata.pos then
        local room_id = normalize_text(pdata.room_id) or "unknown"
        local name = normalize_text(pdata.name) or id
        local description = normalize_text(pdata.description) or ""
        local icon = normalize_text(pdata.icon) or ""
        local facing = tonumber(pdata.facing)
        if facing == 0 then facing = nil end
        local unlock_cost = tonumber(pdata.unlock_cost) or 0
        M.points[id] = {
          pos = vmath.vector3(pdata.pos.x or 0, pdata.pos.y or 0, pdata.pos.z or 0),
          room_id = room_id,
          name = name,
          description = description,
          auto_unlock = false,
          restored_from_save = true,  -- Mark as restored, not live-registered
          show_on_map = pdata.show_on_map ~= false,
          icon = icon,
          facing = facing,
          unlock_cost = unlock_cost,
        }
        ft_log(string.format("[FAST_TRAVEL] Restored point data for '%s' from save", id))
      end
    end
  end

end

-- Register checkpoint provider on module load
Util.register_checkpoint_provider("fast_travel", {
  capture = function() return M.capture() end,
  apply = function(data) M.apply(data) end,
  defaults = function() M.reset() end,
  version = 2,  -- v2: now stores point_data (position/room_id/name) for offline restoration
  order = 50,
  description = "Fast travel unlocked points",
})

return M
