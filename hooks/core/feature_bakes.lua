-- Static registry; gen_collection retains a literal branch for each type.
local grapple_point = require "hooks.core.bakes.grapple_point_bake"
local boss_add_spawner = require "hooks.core.bakes.boss_add_spawner_bake"
local cutscene = require "hooks.core.bakes.cutscene_trigger_bake"
local hazard_return_zone = require "hooks.core.bakes.hazard_return_zone_bake"
local strike_switch = require "hooks.core.bakes.strike_switch_bake"
local wind_current = require "hooks.core.bakes.wind_current_bake"
local ice_floor = require "hooks.core.bakes.ice_floor_bake"
local pendulum = require "hooks.core.bakes.pendulum_bake"
local warp_statue = require "hooks.core.bakes.warp_statue_bake"
local zip_line = require "hooks.core.bakes.zip_line_bake"
local breakable_prop = require "hooks.core.bakes.breakable_prop_bake"
local hazard = require "hooks.core.bakes.hazard_bake"
local water_volume = require "hooks.core.bakes.water_volume_bake"
local air_pocket = require "hooks.core.bakes.air_pocket_bake"
local launch_cannon = require "hooks.core.bakes.launch_cannon_bake"
local movement_zone = require "hooks.core.bakes.movement_zone_bake"
local socket = require "hooks.core.bakes.socket_bake"
local carryable = require "hooks.core.bakes.carryable_bake"
local encounter = require "hooks.core.bakes.encounter_bake"
local trade_station = require "hooks.core.bakes.trade_station_bake"
local combat_trial = require "hooks.core.bakes.combat_trial_bake"
local quest_trigger = require "hooks.core.bakes.quest_trigger_bake"
local countdown_zone = require "hooks.core.bakes.countdown_zone_bake"
local M = {}

for _, module in ipairs({combat_trial, quest_trigger, countdown_zone, trade_station, encounter, socket, carryable, movement_zone, grapple_point, boss_add_spawner, cutscene, hazard_return_zone, strike_switch, wind_current, ice_floor, pendulum, warp_statue, zip_line, breakable_prop, hazard, water_volume, air_pocket, launch_cannon}) do
    for _, object_type in ipairs(module.TYPES) do
        assert(M[object_type] == nil, "duplicate bake type: " .. object_type)
        M[object_type] = module
    end
end

return M
