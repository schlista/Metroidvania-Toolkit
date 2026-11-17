-- mvtk/player/player_interaction.lua
-- Interaction, consumable and map-marker helpers extracted from player.script.

local M = {}
local ToastInteract = require "mvtk.ui.toast_interact"
-- The existing host polls in gameobject context; GUI scripts cannot call go.*.
M.id = "interaction_prompt"
M.order = 90

local ACTIONS = {}
local Inventory
local Items
local Gamefeel
local ScreenshotMarkers
local RoomManager
local _Audio
local zone_interact_msg

local player_log = function() end
local get_interaction_manager = function() return nil end

function M.configure(opts)
  opts = opts or {}
  ACTIONS = opts.ACTIONS or ACTIONS
  Inventory = opts.Inventory or Inventory
  Items = opts.Items or Items
  Gamefeel = opts.Gamefeel or Gamefeel
  ScreenshotMarkers = opts.ScreenshotMarkers or ScreenshotMarkers
  RoomManager = opts.RoomManager or RoomManager
  _Audio = opts.Audio or _Audio
  zone_interact_msg = opts.zone_interact_msg or zone_interact_msg
  player_log = opts.player_log or player_log
  get_interaction_manager = opts.get_interaction_manager or get_interaction_manager
end

-- Reserve Interact before held/toggle grabs and carried-object input run.
-- Keep the frame's interaction priority even though its input edge is gone.
function M.filter_input(self, input)
  self._toast_interacted = false
  if not ToastInteract.active() then return end
  if input.interact_down then
    self._toast_interacted = ToastInteract.request()
    input.light_down, input.heavy_down, input.ranged_down = false, false, false
  end
  input.interact_down, input.interact_held = false, false
end

function M.pre_physics(self)
  local mgr = get_interaction_manager()
  if not mgr then return end
  local blocked = require("mvtk.core.pause").get() or require("mvtk.rooms.input_controller").get_blocked()
  local candidate = not blocked and mgr.peek(go.get_world_position()) or nil
  local url = candidate and candidate.url
  local label = candidate and candidate.label or ""
  local previous = self._interact_hint_url
  local same = url and previous and url.socket == previous.socket
    and url.path == previous.path and url.fragment == previous.fragment
  if (not url and not previous or same) and self._interact_hint_label == label then return end
  self._interact_hint_url, self._interact_hint_label = url, label
  msg.post(require("mvtk.core.constants").URL.MODE_HUD, "hud_interact_hint", {
    label = label, active = url ~= nil, keep_used = true, candidate_url = url
  })
end

function M.reset(self)
  if self._interact_hint_label == nil then return end
  self._interact_hint_url, self._interact_hint_label = nil, nil
  msg.post(require("mvtk.core.constants").URL.MODE_HUD, "hud_interact_hint", {label = "", active = false})
end

function M.do_interact(self)
  -- Also protect direct callers and manual-zone fallback, without a false
  -- object "Used" result. The GUI handles the pending request on its update.
  if ToastInteract.request() then return true end
  player_log('[PLAYER] Interact pressed')
  local pos = go.get_world_position()
  player_log(string.format('[PLAYER] Player world position: (%.1f, %.1f)', pos.x, pos.y))

  -- Use InteractionManager to find and trigger nearest interactable
  local mgr = get_interaction_manager()
  if mgr then
    local success, candidate = mgr.trigger(pos, {
      actor = msg.url(), result_url = require("mvtk.core.constants").URL.MODE_HUD,
    })
    if success then
      if not (candidate and candidate.reports_result) then
        msg.post(require("mvtk.core.constants").URL.MODE_HUD, "hud_interact", {
          label = candidate and candidate.label
        })
      end
      player_log(string.format('[PLAYER] Interacted with: %s (url=%s)',
        tostring(candidate and candidate.label or "unknown"),
        candidate and tostring(candidate.url) or "nil"))
      return true
    else
      player_log('[PLAYER] No interactable found nearby')
    end
  else
    print('[PLAYER] WARNING: InteractionManager not loaded!')
  end

  -- Ask the main trigger registry to resolve zone-authored manual interactions.
  pcall(msg.post, "main:/main_go#script", zone_interact_msg or hash("request_zone_interact"), {
    position = pos
  })
  return false
end

function M.do_potion(self)
  local cooldown = (ACTIONS.potion and ACTIONS.potion.cooldown) or 0.1
  if (self._cd_potion or 0) > 0 then
    player_log(string.format('[PLAYER] Potion on cooldown (%.2fs remaining)', self._cd_potion or 0))
    return false
  end

  local current_hp = self.health or 0
  local max_hp = self.max_health or current_hp
  if current_hp >= max_hp then
    player_log('[PLAYER] Health already full; potion not consumed')
    if _Audio and _Audio.sfx then
      _Audio.sfx("error")
    end
    return false
  end

  if not Inventory then
    player_log('[PLAYER] Inventory system unavailable; cannot use potion')
    return false
  end

  local cfg = ACTIONS.potion or {}
  local candidates = {}
  if cfg.item_id then table.insert(candidates, cfg.item_id) end
  if cfg.alternate_item then table.insert(candidates, cfg.alternate_item) end
  if #candidates == 0 then table.insert(candidates, "potion_small") end

  local consumed_id = nil
  for _, item_id in ipairs(candidates) do
    if Inventory.consume(item_id, 1) then
      consumed_id = item_id
      break
    end
  end

  if not consumed_id then
    player_log('[PLAYER] No potions available')
    if _Audio and _Audio.sfx then
      _Audio.sfx("error")
    end
    return false
  end

  local heal_amount = cfg.heal_amount or 1
  if Items and Items[consumed_id] and Items[consumed_id].heal then
    heal_amount = Items[consumed_id].heal
  end

  local before = self.health or 0
  local new_health = math.min((self.health or 0) + heal_amount, self.max_health or before)
  self.health = new_health
  require("mvtk.player.resources").clamp_health(self)
  local actual_heal = self.health - before

  if actual_heal > 0 then
    player_log(string.format('[PLAYER] Used %s potion (+%.1f HP)', consumed_id, actual_heal))
  else
    player_log(string.format('[PLAYER] Used %s potion but health is already full', consumed_id))
  end

  pcall(msg.post, msg.url("main:/mode_hud#mode_hud"), hash("hud_health"), {
    hp = self.health,
    hp_max = self.max_health
  })

  if actual_heal > 0 then
    if Gamefeel and Gamefeel.damage_number then
      pcall(Gamefeel.damage_number, -actual_heal, go.get_position(), { dtype = 'heal', target = 'player' })
    end
  end

  self._cd_potion = math.max(cooldown, 0)

  if Inventory.count then
    local remaining = Inventory.count(consumed_id)
    pcall(msg.post, msg.url("main:/mode_hud#mode_hud"), hash("hud_consumable"), {
      item = consumed_id,
      count = remaining
    })
  end

  return true
end

function M.do_map_marker(self)
  local pos = self.pos or go.get_position()

  -- Use screenshot marker system if available
  if ScreenshotMarkers then
    -- Get current room ID from room manager
    local room_id = "unknown"
    if RoomManager and RoomManager.get_current_room then
      room_id = RoomManager.get_current_room() or "unknown"
    end

    -- Capture screenshot and create marker
    local success = ScreenshotMarkers.capture(pos, room_id, nil, function(marker)
      player_log(string.format('[PLAYER] Screenshot marker #%d placed at (%.0f, %.0f) in room %s',
        marker.id, pos.x, pos.y, room_id))
    end)

    if not success then
      player_log('[PLAYER] Failed to capture screenshot marker (limit reached or capture pending)')
    end
    return
  end

  player_log('[PLAYER] Screenshot marker system not available')
end

return M
