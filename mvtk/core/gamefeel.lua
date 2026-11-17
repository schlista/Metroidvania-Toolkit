-- mvtk/core/gamefeel.lua
-- moved from modules/core/gamefeel.lua

local Util = require "mvtk.core.util"
local C = require "mvtk.core.constants"
local SafeRequire = require "mvtk.core.safe_require"
local RuntimeSettings = require "developer.config.runtime_settings"
local ZERO_POS = vmath.vector3(0, 0, 0)  -- Cached zero vector for damage_number fallback

local M = {
  _t = 0,
  _dur = 0,
  _mag = 0,
  _freq = 25,
  _offx = 0,
  _offy = 0,
  enabled = true,
  shake_scale = 1,
  damage_numbers = false,
  rumble_enabled = true,
  num_opts = { enemies = true, player = true, heal = true, crit = true },
}

local function noise(t)
  local x = math.sin(t * 12.9898) * 43758.5453
  return (x - math.floor(x)) * 2 - 1
end

function M.shake(mag, dur, freq)
  M._mag = math.max(M._mag or 0, (tonumber(mag) or 0) * M.shake_scale)
  M._dur = math.max(M._dur or 0, tonumber(dur) or 0)
  M._t = 0
  if freq then M._freq = freq end
end

function M.update(dt)
  if not M.enabled then M._offx, M._offy, M._dur, M._mag = 0, 0, 0, 0; return end
  if (M._dur or 0) <= 0 then M._offx, M._offy = 0, 0; return end
  M._t = (M._t or 0) + dt
  M._dur = math.max(0, (M._dur or 0) - dt)
  local decay = (M._dur > 0) and (M._dur / (M._dur + M._t)) or 0
  local m = (M._mag or 0) * decay
  local n = M._freq or 25
  M._offx = m * noise(M._t * n)
  M._offy = m * noise((M._t + 100) * n)
  if M._dur == 0 then M._offx, M._offy, M._mag = 0, 0, 0 end
end

function M.offset()
  return M._offx or 0, M._offy or 0
end

-- Extended: impact helpers (shake + hitstop + optional rumble).
-- Pause should normally exist in any game using gamefeel; Rumble is optional
-- (controllers may not be connected), so it gets the quiet variant.
local PauseOk, Pause = SafeRequire('mvtk.core.pause', 'mvtk.core.gamefeel')
-- Literal require so Bob bundles and registers it with Gamefeel; the named
-- load was never built (AUDIT_BUILD_BUNDLING row 12). Rumble no-ops off mobile.
local Rumble = require "mvtk.core.rumble"

-- Map damage to shake/hitstop defaults
local function profile_for(kind)
  if kind == 'melee' then return { shake_k = 6, stop_k = 0.02 }
  elseif kind == 'projectile' then return { shake_k = 4, stop_k = 0.015 }
  elseif kind == 'parry' then return { shake_k = 8, stop_k = 0.02 }
  elseif kind == 'hurt' then return { shake_k = 5, stop_k = 0.02 }
  else return { shake_k = 5, stop_k = 0.02 } end
end

function M.impact(damage, opts)
  opts = opts or {}
  local prof = profile_for(opts.kind)
  local mag = opts.shake or (prof.shake_k * (math.max(0.5, tonumber(damage) or 1)))
  local dur = opts.shake_dur or 0.08
  local stop = opts.hitstop or (prof.stop_k * math.max(1, (tonumber(damage) or 1)))
  if M.enabled then M.shake(mag, dur, 25) end
  if PauseOk and Pause and Pause.hitstop and stop and stop > 0 then Pause.hitstop(stop) end
  local r = opts.rumble or 0.25
  if M.rumble_enabled and Rumble and r and r > 0 then pcall(Rumble.play, r, math.floor((opts.rumble_ms or 90))) end
end

function M.enable_damage_numbers(on)
  M.damage_numbers = on and true or false
end

function M.set_number_options(opts)
  if type(opts) ~= 'table' then return end
  for k,v in pairs(opts) do if M.num_opts[k] ~= nil then M.num_opts[k] = v and true or false end end
end

function M.get_number_options()
  local out = {}
  for k,v in pairs(M.num_opts) do out[k] = v end
  return out
end

function M.damage_number(amount, world_pos, opts)
  if not M.damage_numbers then return end
  local amt = tonumber(amount) or 0
  opts = opts or {}
  -- Color by dtype/crit/heal
  local r,g,b = 1,1,1
  local dtype = tostring(opts.dtype or '')
  local crit = opts.crit and true or false
  local is_heal = (amt < 0) or (dtype == 'heal')
  -- Per-category visibility filters
  local target = tostring(opts.target or '') -- 'enemy' or 'player'
  if target == 'enemy' and not M.num_opts.enemies then return end
  if target == 'player' and not M.num_opts.player then return end
  if is_heal and not M.num_opts.heal then return end
  -- Colors
  if is_heal then r,g,b = 0.2,1.0,0.2 end
  local cfg = RuntimeSettings.section("damage_types", require "developer.config.damage_types")
  local feedback = cfg.feedback or {}
  local entry = (cfg.types or {})[dtype]
  if not is_heal and feedback.tint_numbers and entry then r,g,b = unpack(entry.color) end
  local scale = 1.0
  if crit and M.num_opts.crit then r,g,b = 1.0,0.9,0.2; scale = 1.3 end
  local label = type(opts.label) == "string" and opts.label or ""
  local label_key = type(opts.label_key) == "string" and opts.label_key or ""
  -- Actors opt into affinity feedback when they start supplying verdicts.
  -- Weak hits keep their element colour while using the critical size.
  if opts.verdict == "weak" and feedback.weak_as_critical and M.num_opts.crit then scale = 1.3 end
  if opts.verdict == "immune" then
    r,g,b = unpack(feedback.immune_color)
    if label == "" then label = feedback.immune_label end
  end

  -- Prefer world-space label if factory exists; else fallback to toast
  local f = msg.url("main:/fx_numbers#damage_number_factory")
  if Util.safe_exists(f) then
    -- Live cap (CP04d): surplus numbers are skipped; they are cosmetic.
    local SpawnBudget = require "mvtk.core.spawn_budget"
    if not SpawnBudget.allow("damage_number") then return end
    local props = { text = amt, label = label, label_key = label_key, color_r = r, color_g = g, color_b = b, scale = scale }
    local pos = world_pos or ZERO_POS
    local ok, id = pcall(factory.create, f, pos, nil, props, 1)
    -- Counted at once, so a burst in one frame cannot pass the cap before
    -- the numbers' init runs.
    if ok and id then SpawnBudget.enter("damage_number", id) end
  else
    Util.safe_post(msg.url("main:/toast_gui#toast"), C.MSG.TOAST, { text = label ~= "" and label or tostring(amt),
      key = label_key ~= "" and label_key or nil, duration = 0.6 })
  end
end

return M
