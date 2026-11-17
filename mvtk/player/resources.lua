-- mvtk/player/resources.lua
-- Player health, energy, stamina, and upgrade helper routines.

local M = {}
local HealthState = require "mvtk.player.health_state"
local C = require "mvtk.core.constants"

local EnergyState
local AbilityManager
local Gamefeel
local stat_binding

local function bonus_source() return require "mvtk.player.player_stats" end

function M.configure(opts)
  opts = opts or {}
  EnergyState = opts.EnergyState or EnergyState
  AbilityManager = opts.AbilityManager or AbilityManager
  Gamefeel = opts.Gamefeel or Gamefeel
end

function M.clamp_health(self)
  local max_health = tonumber(self.max_health) or 0
  if max_health <= 0 then
    HealthState.set(self.health, max_health)
    return
  end
  if (self.health or 0) > max_health then
    self.health = max_health
  elseif self.health < 0 then
    self.health = math.max(self.health, 0)
  end
  HealthState.set(self.health, max_health)
end

function M.post_resource_float(amount, dtype)
  if amount and amount ~= 0 and Gamefeel and Gamefeel.damage_number then
    pcall(Gamefeel.damage_number, amount, go.get_position(), { dtype = dtype, target = "player" })
  end
end

local function whole(value)
  value = tonumber(value) or 0
  return value < 0 and math.ceil(value) or math.floor(value)
end

local function stamina_source()
  return AbilityManager or require "mvtk.abilities.ability_manager"
end

local function refresh_stamina(self, reason, totals)
  local abilities = stamina_source()
  local current, old_max = abilities.get_stamina()
  local new_max = math.max(0, self._stat_base.max_stamina + whole(totals.max_stamina))
  local gain = math.max(0, new_max - old_max)
  -- A reset refills like a fresh bind, now including the ledger's bonus.
  if reason == "bind" or reason == "reset" then current = new_max
  elseif reason == "record" then current = current + gain end
  abilities.set_stamina(current, new_max)
  if reason == "record" and gain > 0 then
    pcall(msg.post, C.URL.PLAYER, "mvtk_stat_gain_feedback", { amount = gain, resource = "stamina" })
  end
end

function M.refresh(self, reason)
  local base = self._stat_base
  if not base then return end
  local totals = bonus_source().totals()
  for _, resource in ipairs({ "health", "energy" }) do
    local maximum = "max_" .. resource
    local old_max = self[maximum] or 0
    local new_max = math.max(resource == "health" and 1 or 0, base[maximum] + whole(totals[maximum]))
    local gain = math.max(0, new_max - old_max)
    local current = self[resource] or 0
    if reason == "bind" then
      current = new_max
    elseif reason == "record" then
      current = current + gain
    end
    self[maximum] = new_max
    self[resource] = math.max(0, math.min(current, new_max))
    if reason == "record" and gain > 0 then
      pcall(msg.post, C.URL.PLAYER, "mvtk_stat_gain_feedback", { amount = gain, resource = resource })
    end
  end
  M.clamp_health(self)
  EnergyState.set(self.energy, self.max_energy)
  pcall(msg.post, "main:/mode_hud#mode_hud", "hud_health", { hp = self.health, hp_max = self.max_health })
  -- A stats layer reset only clamps; AbilityManager's own reset listener below
  -- still refills the pool. Removing gear must not become a free refill.
  refresh_stamina(self, reason == "reset" and "stats_reset" or reason, totals)
end

function M.unbind_stat_bonuses(self)
  if stat_binding and stat_binding.self == self then
    stat_binding.source.unregister_listener(stat_binding.handle)
    stat_binding.abilities.unregister_listener(stat_binding.ability_handle)
    stat_binding = nil
  end
  self._stat_base = nil
end

function M.bind_stat_bonuses(self, base)
  if stat_binding then M.unbind_stat_bonuses(stat_binding.self) end
  self._stat_base = {
    max_health = base.max_health,
    max_energy = base.max_energy,
    max_stamina = base.max_stamina,
  }
  local source = bonus_source()
  stat_binding = { self = self, source = source, handle = source.register_listener(function(reason)
    M.refresh(self, reason)
  end) }
  stat_binding.abilities = stamina_source()
  stat_binding.ability_handle = stat_binding.abilities.register_listener(function(reason)
    if reason == "load" or reason == "reset" then
      refresh_stamina(self, reason, source.totals())
    end
  end)
  M.refresh(self, "bind")
end

return M
