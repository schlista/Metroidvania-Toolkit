-- Pure compact HUD labels from ability metadata and the current unlock flags.
local M = {}
local category_rank = { movement = 1, combat = 2, defensive = 3, utility = 4 }

-- Return metadata copies with ids; never depend on hash-table iteration order.
function M.list(abilities_cfg, is_unlocked)
    local shown = {}
    for id, definition in pairs(abilities_cfg) do
        if definition.show_on_hud ~= false and is_unlocked(id) then
            local entry = {}
            for key, value in pairs(definition) do entry[key] = value end
            entry.id = id
            shown[#shown + 1] = entry
        end
    end
    table.sort(shown, function(a, b)
        local ac, bc = a.category or "", b.category or ""
        local ar, br = category_rank[ac] or 5, category_rank[bc] or 5
        if ar ~= br then return ar < br end
        if ac ~= bc then return ac < bc end
        return a.id < b.id
    end)
    return shown
end

function M.short(entry, display)
    if entry.hud_short then return display and display.render(entry.hud_short) or entry.hud_short end
    if not entry.name then return display and display.ui("hud.unknown_ability") or "" end
    local name = display and display.render(entry.name) or entry.name
    local initials = {}
    for word in name:gmatch("%S+") do
        -- Keep the complete first UTF-8 codepoint, never a lone leading byte.
        local initial = word:match("^[%z\1-\127\194-\244][\128-\191]*") or ""
        initials[#initials + 1] = #initial == 1 and initial:upper() or initial
    end
    return table.concat(initials)
end

-- Labels only: the GUI owns the player-visible prefix and display rendering.
function M.text(list, display)
    local labels = {}
    for _, entry in ipairs(list) do labels[#labels + 1] = M.short(entry, display) end
    return table.concat(labels, display and display.ui("hud.ability_separator") or " ")
end

return M
