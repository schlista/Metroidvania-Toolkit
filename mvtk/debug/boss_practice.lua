-- English-only creator diagnostics, reachable solely from the debug overlay.
local Census = require "mvtk.world.census"
local Session = require "mvtk.game.fight_session"
local Cheats = require "mvtk.debug.dev_cheats"
local Warp = require "mvtk.debug.dev_warp"
local M = {}
local all_abilities = false

function M.update(dt) Session.update(dt) end

local function capabilities()
    local gives = {}
    for id in pairs(require("developer.config.abilities").abilities) do
        gives[#gives+1] = {kind="ability", id=id}
    end
    table.sort(gives, function(a,b) return a.id < b.id end)
    return {available=Cheats.available, warp=Warp.warp, abilities=gives}
end

function M.register_menu(menu)
    if not Cheats.available() then return end
    Session.attach()
    menu.register("boss_practice", "Boss practice", {
        rows = function(ctx)
            local bosses, rows = {}, {}
            for _, entry in ipairs(Census.entries()) do
                if entry.kind == "boss" then bosses[#bosses+1] = entry end
            end
            if #bosses == 0 and Session.state() == "idle" then
                return {{id="empty", label="No bosses found: run Prepare & Check", hold=0}}
            end
            rows[#rows+1] = {id="abilities",label="All abilities " .. (all_abilities and "[ON]" or "[OFF]"),hold=0,
                action=function() all_abilities=not all_abilities; return true end}
            if Session.kind() == "practice" then
                rows[#rows+1] = {id="end",label="End practice",hold=0,action=Session.finish}
            end
            for _, entry in ipairs(bosses) do
                local boss = entry
                local label = boss.room .. " - " .. (boss.preset and boss.preset ~= "" and boss.preset or boss.identity)
                    .. (Census.state(boss) and " [defeated]" or "")
                if label:lower():find((ctx.context.query or ""):lower(),1,true) then
                    rows[#rows+1] = {id=boss.id,label=label,entry=boss,hold=0,
                        action=function() return Session.start(boss,capabilities(),all_abilities) end}
                end
            end
            return rows
        end,
        on_confirm = function(_,row)
            if not row.action then return {} end
            local ok, err = row.action()
            return {close=ok and row.id~="abilities",refresh=true,
                status=err or (row.id=="abilities" and "Applies to the next practice." or "Saving off (boss practice)")}
        end,
    })
end
return M
