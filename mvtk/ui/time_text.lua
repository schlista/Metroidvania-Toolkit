-- Pure h:mm:ss description. Resolve it only in the displaying GUI.
-- Integer arithmetic and %02d also work in the editor's LuaJ host.
local M = {}
function M.playtime(seconds, tenths)
    seconds = math.floor(math.max(0, seconds))
    if tenths ~= nil then
        return {key="trial.time", params={minutes=math.floor(seconds / 60),
            seconds=string.format("%02d", seconds % 60), tenths=math.floor(math.max(0, tenths)) % 10}}
    end
    return {key = "journal.playtime", params = {
        hours = math.floor(seconds / 3600),
        minutes = string.format("%02d", math.floor(seconds / 60) % 60),
        seconds = string.format("%02d", seconds % 60),
    }}
end
-- Minutes and whole seconds (m:ss), for clocks that show tenths only near zero.
function M.clock(seconds)
    seconds = math.floor(math.max(0, seconds))
    return {key="countdown.clock", params={minutes=math.floor(seconds / 60),
        seconds=string.format("%02d", seconds % 60)}}
end
return M
