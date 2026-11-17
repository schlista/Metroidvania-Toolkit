-- Pure sound-caption throttle. Shared for the singleton audio controller's
-- lifetime; callers supply seconds and opaque ids (including Defold hashes).
-- One live line, no queue. Only accepted lines consume their per-id repeat gap.
local M = {}
local last = {}
local live_until = -math.huge

function M.note(id, caption, now, cfg)
    cfg = cfg or {}
    if cfg.sound ~= true or id == nil or type(caption) ~= "string"
        or not caption:match("%S") or type(now) ~= "number" then return nil end
    local gap = math.max(0, tonumber(cfg.sound_repeat_gap) or 4)
    if now < live_until or (last[id] and now - last[id] < gap) then return nil end
    last[id] = now
    live_until = now + math.max(0, tonumber(cfg.sound_seconds) or 2.5)
    return caption
end

return M
