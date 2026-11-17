-- Pure ballistic integration. The host injects a world-space centre raycast;
-- sample box faces from interior centre lines so the whole body stops at terrain.
local M = {}

function M.vector(speed, angle, facing)
    local radians = math.rad(angle)
    return math.cos(radians) * speed * (facing < 0 and -1 or 1), math.sin(radians) * speed
end

function M.step(body, dt, gravity, raycast)
    local vy = body.vy + gravity * dt
    local dx, dy = body.vx * dt, (body.vy + vy) * 0.5 * dt
    if dx == 0 and dy == 0 then return body.x, body.y, body.vx, vy end
    local groups = {"solid", "world"}
    if dy < 0 then groups[#groups + 1] = "platform" end
    local fraction, impact = 1, nil
    local function cast(ox, oy, lead_x, lead_y, step)
        local from_x, from_y = body.x + ox, body.y + oy
        local rx, ry = dx * step + lead_x, dy * step + lead_y
        local hit = raycast(from_x, from_y, from_x + rx, from_y + ry, groups)
        if not hit then return end
        local nx, ny = hit.normal.x, hit.normal.y
        if hit.group == "platform" and (dy >= 0 or ny <= 0.5) then return end
        local dot = dx * nx + dy * ny
        if dot >= 0 then return end
        -- Intersect the moving leading face with the hit plane. Origins lie
        -- strictly inside our old box, so our own kinematic body is invisible.
        local t = ((rx * hit.fraction - lead_x) * nx + (ry * hit.fraction - lead_y) * ny) / dot
        if t <= fraction then fraction, impact = math.max(0,t), hit end
    end
    -- Intermediate faces close diagonal corner wedges. Each cast starts on an
    -- original centre line, never on a wall-touching edge or at the destination.
    local steps = math.max(1, math.ceil(math.max(math.abs(dx), math.abs(dy)) / math.min(body.half_w, body.half_h)))
    for i = 1, steps do
        local step = i / steps
        if dx ~= 0 then
            for _,offset in ipairs({-0.999,0,0.999}) do
                cast(0,body.half_h*offset,dx < 0 and -body.half_w or body.half_w,0,step)
            end
        end
        if dy ~= 0 then
            for _,offset in ipairs({-0.999,0,0.999}) do
                cast(body.half_w*offset,0,0,dy < 0 and -body.half_h or body.half_h,step)
            end
        end
    end
    if impact then
        local nx, ny = impact.normal.x, impact.normal.y
        local dot = body.vx * nx + vy * ny
        return body.x + dx * fraction, body.y + dy * fraction,
            body.vx - math.min(0,dot) * nx, vy - math.min(0,dot) * ny, impact
    end
    return body.x + dx, body.y + dy, body.vx, vy
end

return M
