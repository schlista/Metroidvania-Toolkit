-- Engine-free switch channels, saved state, payloads and authored orders.
-- A channel is the normalized text target_id (plates default to plate_id).
-- Levers/plates write Flags before the live TriggerBus signal. Timed doors,
-- tile platforms and hazards replay the channel when their baked room loads.
-- secret.script also listens on TriggerBus but restores its own secret_ flag.
-- Own states are booleans (Flags.has considers every string set); channel
-- states carry on|message or off|message. Stays-open doors also keep a boolean
-- own state with persist_key timed_door:<channel>, independent of sender off.
-- No save provider is needed.
local Util = require "mvtk.core.util"
local M = {}

function M.parse_order(value)
    local order = {}
    for token in tostring(value or ""):gmatch("[^,]+") do
        local id = Util.normalize_hash_string(token)
        if id then order[#order + 1] = id end
    end
    return order
end

function M.read_signal(message)
    if type(message) ~= "table" then return nil end
    local id = Util.normalize_hash_string(message.lever_id)
    if id and (message.state == "on" or message.state == "off") then
        return {kind = message.kind or "lever", id = id, on = message.state == "on", persist = message.persist == true}
    end
    id = Util.normalize_hash_string(message.plate_id)
    if id and type(message.pressed) == "boolean" then
        return {kind = "plate", id = id, on = message.pressed, persist = message.persist == true}
    end
    id = Util.normalize_hash_string(message.prop_id)
    if id and (message.state == "on" or message.state == "off") then
        return {kind = "prop", id = id, on = message.state == "on", persist = message.persist == true}
    end
    return nil
end

local function key(prefix, value)
    local text = Util.normalize_hash_string(Util.resolve_id(value))
    if text then return prefix .. text end
end

function M.channel_key(channel) return key("switch_channel_", channel) end
function M.own_key(persist_key) return key("switch_state_", persist_key) end

function M.write_channel(flags, channel, on, message_text)
    local channel_key = M.channel_key(channel)
    if channel_key then
        flags.set(channel_key, (on and "on|" or "off|") .. (message_text or ""))
    end
end

function M.read_channel(flags, channel)
    local channel_key = M.channel_key(channel)
    if not channel_key then return nil end
    local value = flags.get(channel_key)
    if type(value) ~= "string" then return nil end
    local split = string.find(value, "|", 1, true)
    if not split then return nil end
    local state = value:sub(1, split - 1)
    if state ~= "on" and state ~= "off" then return nil end
    return {on = state == "on", message = value:sub(split + 1)}
end

function M.write_own(flags, persist_key, on)
    local own_key = M.own_key(persist_key)
    if own_key then flags.set(own_key, on == true) end
end

function M.read_own(flags, persist_key)
    local own_key = M.own_key(persist_key)
    if not own_key then return nil end
    local value = flags.get(own_key)
    if type(value) == "boolean" then return value end
end

function M.replay(flags, channel, apply)
    local state = M.read_channel(flags, channel)
    if not state then return false end
    apply(state.on, state.message)
    return true
end

return M
