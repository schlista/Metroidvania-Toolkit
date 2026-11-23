--- Boss Attack Execution Module
-- Implements all boss attack types with actual damage application.
-- Used by boss.script to execute attack patterns.
--
-- This module is the boss-flavored entry point for attacks. As of Phase 5
-- step 27, each attack type lives in its own file under
-- `mvtk/bosses/boss_attacks/`. This file is now a thin shim that:
--   * imports each per-type executor,
--   * re-exports them on M as `M.execute_<type>` for back-compat,
--   * owns the `M._dispatch` table and `M.execute_pattern` entry point.
--
-- Geometry math (spread angles, aim vectors, beam/AOE hit-tests) lives in
-- mvtk/combat/attack_geometry.lua. Projectile factory spawning goes through
-- mvtk/combat/projectile_spawner.lua. All numeric defaults read from
-- developer/config/boss_defaults.lua — do not add magic numbers here.
--
-- Adding a new attack type:
--   1. Create mvtk/bosses/boss_attacks/<type>.lua exporting M.execute(boss, pattern, instance).
--   2. Import it below and add it to MODULES.
--   3. Add the entry to M._dispatch.
--
-- @module boss_attacks

local C = require "mvtk.bosses.boss_attacks.common"

local Melee         = require "mvtk.bosses.boss_attacks.melee"
local Projectile    = require "mvtk.bosses.boss_attacks.projectile"
local AOE           = require "mvtk.bosses.boss_attacks.aoe"
local Summon        = require "mvtk.bosses.boss_attacks.summon"
local Beam          = require "mvtk.bosses.boss_attacks.beam"
local Charge        = require "mvtk.bosses.boss_attacks.charge"
local Hazard        = require "mvtk.bosses.boss_attacks.hazard"
local HazardPulse   = require "mvtk.bosses.boss_attacks.hazard_pulse"
local Combo         = require "mvtk.bosses.boss_attacks.combo"
local Special       = require "mvtk.bosses.boss_attacks.special"
local Grab          = require "mvtk.bosses.boss_attacks.grab"
local Heal          = require "mvtk.bosses.boss_attacks.heal"
local Buff          = require "mvtk.bosses.boss_attacks.buff"
local Shield        = require "mvtk.bosses.boss_attacks.shield"
local ParryWindow   = require "mvtk.bosses.boss_attacks.parry_window"
local Environmental = require "mvtk.bosses.boss_attacks.environmental"
local Mine          = require "mvtk.bosses.boss_attacks.mine"
local Wave          = require "mvtk.bosses.boss_attacks.wave"
local Zone          = require "mvtk.bosses.boss_attacks.zone"
local GroundWave    = require "mvtk.bosses.boss_attacks.ground_wave"
local Sweep         = require "mvtk.bosses.boss_attacks.sweep"
local Rain          = require "mvtk.bosses.boss_attacks.rain"
local Ring          = require "mvtk.bosses.boss_attacks.ring"
local Leap          = require "mvtk.bosses.boss_attacks.leap"
local Dive          = require "mvtk.bosses.boss_attacks.dive"
local Reposition    = require "mvtk.bosses.boss_attacks.reposition"
local Telegraph     = require "mvtk.bosses.boss_telegraph"

local M = {}

-- Re-export per-type executors as M.execute_<type> for back-compat with any
-- caller that referenced them on the old monolithic module.
M.execute_melee         = Melee.execute
M.execute_projectile    = Projectile.execute
M.execute_aoe           = AOE.execute
M.execute_summon        = Summon.execute
M.execute_beam          = Beam.execute
M.execute_charge        = Charge.execute
M.execute_hazard        = Hazard.execute
M.execute_hazard_pulse  = HazardPulse.execute
M.execute_combo         = Combo.execute
M.execute_special       = Special.execute
M.execute_grab          = Grab.execute
M.execute_heal          = Heal.execute
M.execute_buff          = Buff.execute
M.execute_shield        = Shield.execute
M.execute_parry_window  = ParryWindow.execute
M.execute_environmental = Environmental.execute
M.execute_mine          = Mine.execute
M.execute_wave          = Wave.execute
M.execute_zone          = Zone.execute
M.execute_ground_wave   = GroundWave.execute
M.execute_sweep         = Sweep.execute
M.execute_rain          = Rain.execute
M.execute_ring          = Ring.execute
M.execute_leap          = Leap.execute
M.execute_dive          = Dive.execute
M.execute_reposition    = Reposition.execute

-- Pattern.type -> execute_* function. Keep entries in lowercase to match
-- pattern.type values produced by `developer/config/boss_*.lua` and the
-- attack-pattern schema. `special` aliases also land here so older
-- pattern definitions ("charge", "hazard", "combo") keep working.
M._dispatch = {
    melee         = M.execute_melee,
    projectile    = M.execute_projectile,
    aoe           = M.execute_aoe,
    summon        = M.execute_summon,
    beam          = M.execute_beam,
    grab          = M.execute_grab,
    heal          = M.execute_heal,
    buff          = M.execute_buff,
    shield        = M.execute_shield,
    parry_window  = M.execute_parry_window,
    environmental = M.execute_environmental,
    hazard_pulse  = M.execute_hazard_pulse,
    mine          = M.execute_mine,
    wave          = M.execute_wave,
    zone          = M.execute_zone,
    ground_wave   = M.execute_ground_wave,
    sweep         = M.execute_sweep,
    rain          = M.execute_rain,
    ring          = M.execute_ring,
    leap          = M.execute_leap,
    dive          = M.execute_dive,
    reposition    = M.execute_reposition,
    -- Legacy aliases routed through execute_special for back-compat.
    special       = M.execute_special,
    charge        = M.execute_special,
    hazard        = M.execute_special,
    combo         = M.execute_special,
}

local function execute_pattern(boss, pattern, opts)
    opts = opts or {}
    if not boss or not pattern or (boss.boss_data and boss.boss_data.defeated) then
        return
    end

    local fn = M._dispatch[pattern.type]
    if not fn then return end
    local instance = C.instance(boss, pattern, opts.instance)
    instance._defer = opts.defer_timers == true

    local function launch(active)
        if opts.play_animation ~= false then
            C.play_pattern_animation(boss, pattern)
        end
        fn(boss, pattern, active)
    end

    local warning_time = opts.warn and pattern.telegraph_time or 0
    if warning_time > 0 then
        local warning = Telegraph.begin(boss, pattern, warning_time, true)
        local launched = false
        instance.interruptible = true
        instance:on_cancel(function() Telegraph.cancel(warning) end)
        instance:after(warning_time, function(active)
            launched = true
            active:on_cancel(nil)
            Telegraph.with_child_warning(warning, launch, active)
        end)
        instance:each_frame(function()
            if launched then return false end
            Telegraph.refresh(boss, warning)
        end, warning_time)
    else
        launch(instance)
    end
    instance:finish()
    return instance
end

M.execute_pattern = execute_pattern

-- Combo re-enters the dispatcher; bind it on the common module so submodules
-- can call C.execute_pattern() without a circular require.
C.set_execute_pattern(execute_pattern)

return M
