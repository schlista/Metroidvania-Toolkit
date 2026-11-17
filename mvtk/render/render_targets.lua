-- Render-script context only. Keep all render APIs behind these call-time seams.
local M = {}

function M.scaled(w, h, scale)
    return math.max(1, math.floor(w * scale + 0.5)), math.max(1, math.floor(h * scale + 0.5))
end

local function unsupported(store, name, reason)
    store.unsupported[name] = true
    print("[render] Render target " .. name .. " unavailable; effects disabled: " .. tostring(reason))
    return nil
end

-- spec.depth opts into a depth attachment; colour-only targets support later passes.
function M.ensure(store, name, w, h, spec)
    store.unsupported = store.unsupported or {}
    if store.unsupported[name] then return nil end
    if not graphics.TEXTURE_FORMAT_RGBA then return unsupported(store, name, "RGBA format unsupported") end
    if spec.depth and not graphics.TEXTURE_FORMAT_DEPTH then return unsupported(store, name, "depth format unsupported") end
    local target = store[name]
    if target then
        if target.w ~= w or target.h ~= h then
            local ok, reason = pcall(render.set_render_target_size, target.handle, w, h)
            if not ok then return unsupported(store, name, reason) end
            target.w, target.h = w, h
        end
        return target.handle
    end
    local params = {
        [graphics.BUFFER_TYPE_COLOR0_BIT] = {
            format = graphics.TEXTURE_FORMAT_RGBA, width = w, height = h,
            min_filter = graphics.TEXTURE_FILTER_LINEAR, mag_filter = graphics.TEXTURE_FILTER_LINEAR,
            u_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE, v_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
        },
    }
    if spec.depth then
        params[graphics.BUFFER_TYPE_DEPTH_BIT] = { format = graphics.TEXTURE_FORMAT_DEPTH, width = w, height = h }
    end
    local ok, handle = pcall(render.render_target, params)
    if not ok or not handle then return unsupported(store, name, handle) end
    store[name] = { handle = handle, w = w, h = h }
    return handle
end

function M.composite(predicate, material, sampler, handle, constants)
    render.enable_material(material)
    render.enable_texture(sampler, handle, graphics.BUFFER_TYPE_COLOR0_BIT)
    -- render.draw raises on an explicit nil second argument, whatever its message says.
    if constants then render.draw(predicate, { constants = constants }) else render.draw(predicate) end
    render.disable_texture(sampler)
    render.disable_material()
end

return M
