-- Shared state for baked Tiled artwork. Keys include the collection socket and
-- instance path, so streamed copies never share presentation or trigger state.
local M = {}
local entries = {}
local function key(owner)
    local url = msg.url(owner or ".")
    return tostring(url.socket) .. ":" .. tostring(url.path)
end
local function entry(owner)
    local id = key(owner)
    entries[id] = entries[id] or { state = "default", removed = false }
    return entries[id]
end
-- A callback belongs to a holder script instance. If that instance was
-- destroyed without its final (an object whose room spawn failed is deleted
-- that way), the callback raises when the same owner path appears again, and
-- an error raised inside an owner's init makes the engine delete the whole
-- room. Drop such a callback and keep going: the new holder re-attaches.
local warned = {}
local function invoke(e, id, event)
    local ok, err = pcall(e.callback, e, event)
    if ok then return true end
    e.callback, e.bounds = nil, nil
    if not warned[id] then
        warned[id] = true
        print(string.format("WARNING:[OBJECT_ART] Dropped the stale presentation callback of %s: %s", id, tostring(err)))
    end
    return false
end
function M.attach(owner, callback, bounds, animation)
    local id = key(owner)
    local e = entry(owner)
    e.callback, e.bounds = callback, bounds
    e.animation = animation
    invoke(e, id)
end
-- A behavior can own the clock so damage and the displayed frame agree,
-- including after disabling, pausing, or streaming a room back in.
function M.animation(owner) return entry(owner).animation end
function M.animate(time, owner) entry(owner).animation_time = time end
-- callback, when given, must be the attached one: a late final of an older
-- holder never removes the entry of a newer holder at the same path.
function M.detach(owner, callback)
    local id = key(owner)
    local e = entries[id]
    if e and callback ~= nil and e.callback ~= nil and e.callback ~= callback then return end
    entries[id] = nil
end
function M.release_unbound(owner)
    local id = key(owner)
    if entries[id] and not entries[id].callback then entries[id] = nil end
end
-- Restoring state never produces feedback. Missing alternate art retains the
-- default artwork; availability and removal remain decisions of the behavior.
function M.restore(state, removed, owner)
    local e = entry(owner)
    if state then e.state = state end
    if removed ~= nil then e.removed = removed end
    if e.callback then invoke(e, key(owner)) end
end
function M.emit(event, state, removed, owner)
    local e = entry(owner)
    if e.removed then return false end
    if state then e.state = state end
    if removed then e.removed = true end
    if not (e.callback and invoke(e, key(owner), event)) then e.pending_event = event end
    return true
end
function M.visible(visible, owner)
    local e = entry(owner)
    e.visible = visible
    if e.callback then invoke(e, key(owner)) end
end
-- Optional transforms for the default image when a behavior state has no
-- dedicated artwork. Explicit art_state images always take precedence.
function M.set_state_fallbacks(fallbacks, owner)
    local e = entry(owner)
    e.fallbacks = fallbacks
    if e.callback then invoke(e, key(owner)) end
end
function M.take_pending(owner)
    local e = entry(owner)
    local event = e.pending_event
    e.pending_event = nil
    return event
end
function M.contains(owner, position)
    local id = key(owner)
    local e = entries[id]
    if not e or not e.bounds then return nil end
    if e.removed then return false end
    local ok, inside = pcall(e.bounds, position)
    if ok then return inside end
    e.callback, e.bounds = nil, nil
    return nil
end
function M.is_removed(owner)
    local e = entries[key(owner)]
    return e and e.removed == true or false
end
function M.is_authored(owner)
    local e = entries[key(owner)]
    return e and e.bounds ~= nil or false
end
return M
