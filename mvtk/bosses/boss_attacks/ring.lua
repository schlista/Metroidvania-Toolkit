-- Fire full circles, rotating each volley by the authored angle increment.
local C = require "mvtk.bosses.boss_attacks.common"
local Telegraph = require "mvtk.bosses.boss_telegraph"

local M = {}

function M.execute(boss, pattern, instance)
    local settings = C.stationary_options(pattern)
    if not settings then return end
    instance = C.stationary_instance(boss, pattern, instance)
    local cue = Telegraph.take_stationary(boss, pattern, settings)
    Telegraph.cancel(cue)
    local fire = C.stationary_shots(boss, pattern, instance, settings)
    local separation = 2 * math.pi / settings.count
    local rotation = math.rad(settings.rotate_per_volley)
    for volley = 0, settings.volleys - 1 do
        local angle = volley * rotation
        local function fire_volley()
            local origin = go.get_position()
            for shot = 0, settings.count - 1 do
                fire(origin, angle + shot * separation)
            end
        end
        local delay = volley * settings.volley_delay
        if delay > 0 then instance:after(delay, fire_volley) else fire_volley() end
    end
end

return M
