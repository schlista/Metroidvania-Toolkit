-- Debug-only page adapter. Selected snapshots belong to the menu context,
-- never to the active checkpoint or its runtime providers.
local Checkpoint = require "mvtk.core.checkpoint"
local Inspect = require "mvtk.debug.save_inspect"
local Config = require "developer.config.resolved_config"
local Debug = require "developer.config.debug_config"
local Prefab = require "mvtk.prefabs.prefab_utils"
local M = {}

function M.register_menu(menu)
    if not (Prefab.is_dev_build() and Debug.dev_tools and Debug.dev_tools.enabled == true) then return end
    menu.register("saves", "Saves", {
        rows = function(ctx)
            local selected = ctx.context.save_view
            if selected then
                local rows = {{id = "slots", label = "Slot " .. selected.slot .. " / Back to slots", hold = 0}}
                for _, row in ipairs(Inspect.rows(selected.data, selected.reason, selected.source, {
                    prefix = ctx.context.query, is_retired_provider = Checkpoint.is_retired_provider,
                })) do rows[#rows + 1] = row end
                return rows
            end
            local rows = {}
            for _, slot in ipairs(Checkpoint.list_slots(Config.progression.saves.max_slots)) do
                rows[#rows + 1] = {id = "slot:" .. slot.slot, slot = slot.slot, hold = 0,
                    label = "Slot " .. slot.slot .. " / " .. (slot.error or (slot.exists and "saved" or "missing"))}
            end
            return rows
        end,
        on_confirm = function(ctx, row)
            ctx.context.query = ""
            if row.slot then
                local data, reason, source = Checkpoint.inspect_slot(row.slot)
                ctx.context.save_view = {slot = row.slot, data = data, reason = reason, source = source}
            else ctx.context.save_view = nil end
            return {refresh = true, status = ""}
        end,
    })
end

return M
