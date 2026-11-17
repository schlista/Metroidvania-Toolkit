-- The cabin owns travel; this provider only presents landing identities.
local M = { pause = true }

function M.title()
    return { key = "list.choose_floor" }
end

function M.rows(ctx)
    local rows = {}
    local elevator_id = (ctx.context or {}).elevator_id
    for _, floor in ipairs(require("mvtk.elevators.elevator_manager").landings(elevator_id)) do
        rows[#rows + 1] = {
            id = floor.key,
            label = floor.label,
            enabled = not floor.current,
            selectable = not floor.current,
            value = floor.current and { key = "list.current_floor" } or nil,
        }
    end
    return rows
end

function M.on_confirm()
    return { delegate = true, close = true }
end

return M
