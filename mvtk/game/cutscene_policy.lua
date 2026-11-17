-- Pure playback policy shared by runtime and authoring checks (including LuaJ).
local M = {}
function M.steps(scene) return type(scene)=="table" and (scene.steps or scene) or {} end

function M.dialogue_outcomes(scene, dialogues)
    local visited = {}
    local function visit(id)
        if visited[id] then return false end
        visited[id] = true
        local lines
        if type(dialogues)=="function" then lines=dialogues(id)
        else lines=(dialogues or {})[id] end
        for _, line in ipairs(lines or {}) do
            if line.set_flag or (line.choices and #line.choices > 0) then return true end
            -- Quest actions run only when their line is shown, as flags do.
            if line.quest_start or line.quest_advance or line.quest_turn_in or line.quest_fail then return true end
            if line.next and visit(line.next) then return true end
        end
        return false
    end
    for _, step in ipairs(M.steps(scene)) do
        if step.type=="dialogue" and step.id and visit(step.id) then return true end
    end
    return false
end
function M.skippable(scene, dialogues)
    return type(scene)=="table" and scene.skippable~=false and not M.dialogue_outcomes(scene, dialogues)
end
return M
