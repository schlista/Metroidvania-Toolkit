-- Countdown Zones (WM09): entering a zone starts, finishes or cancels the
-- countdown it names. The countdown service owns every rule; a zone only asks.
local M = {}
local Ctx
function M.configure(ctx) Ctx = ctx or Ctx end

-- Room-local feet point at the zone's bottom centre. The arriving player
-- resolves its live collider; the trigger does not estimate a stand height.
function M.start_point(zone)
    local pos = zone.position or vmath.vector3(0, 0, 0)
    local ox, oy = Ctx.Geometry.compute_spawn_xy(Ctx.RoomManager.get_room_data(zone.room_id))
    local x = pos.x + (tonumber(zone.width) or 0) * 0.5
    local y = pos.y
    return x - ox, y - oy
end

function M.on_trigger(self, zone)
    assert(Ctx, "mvtk.game.triggers.countdown is not configured")
    local Countdown = Ctx.Countdown
    local id, role = zone.countdown_id or "", zone.role or "start"
    if id == "" then return false end
    if role == "start" then
        -- Re-entering the start zone of the run in progress changes nothing.
        if Countdown.running() == id then return false end
        local local_x, local_y = M.start_point(zone)
        local ok, why = Countdown.start(id, {source = "zone", room_id = zone.room_id,
            local_x = local_x, local_y = local_y, position_kind = "feet"})
        if not ok and why ~= "busy" and why ~= "finished" then
            print("[COUNTDOWN] Zone " .. tostring(zone.id) .. " could not start " .. id .. ": " .. tostring(why))
        end
        return ok == true
    end
    -- Finish and cancel act only on the countdown they name.
    if Countdown.running() ~= id then return false end
    if role == "finish" then return Countdown.finish(id) == true end
    if role == "cancel" then return Countdown.cancel(id) == true end
    return false
end
return M
