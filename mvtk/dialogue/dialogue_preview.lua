-- Pure preview of what a conversation would show right now (WM12a).
-- No engine APIs and no requires at load: callers pass the sequence lookup
-- (DialogueRegistry.get) and the condition check (DialogueLogic.eval_condition),
-- so the editor, tests and npc_living share one walk.
--
-- The walk mirrors developer/ui/game/dialogue.gui_script: lines whose
-- condition fails are skipped, a shown line with `next` jumps to that sequence
-- (the rest of the current one is never reached), and a line with `choices`
-- ends the walk, its choice texts included. A sequence seen twice ends the
-- walk (cycle guard). Text is the authored source text, so the signature does
-- not change with the player's language.
--
--   Preview.lines(sequence_id, get, eval)  -- {{text=, line=, choice=true|nil}, ...}
--   Preview.signature(rows)                -- a number, or nil when nothing shows
--   Preview.offers_task(rows)              -- a shown line or choice starts or turns in a quest
local M = {}

-- A runaway authored chain stops here rather than freezing the game.
M.MAX_ROWS = 256

local function text_of(value)
    if value == nil then return "" end
    return tostring(value)
end

function M.lines(sequence_id, get, eval)
    local rows, visited = {}, {}
    if type(get) ~= "function" then return rows end
    local check = type(eval) == "function" and eval or function() return true end
    local id = sequence_id
    while id ~= nil and id ~= "" and not visited[id] and #rows < M.MAX_ROWS do
        visited[id] = true
        local sequence = get(id)
        id = nil
        if type(sequence) ~= "table" then break end
        for _, line in ipairs(sequence) do
            if type(line) == "table" and check(line.condition) then
                rows[#rows + 1] = { text = text_of(line.text), line = line }
                if type(line.choices) == "table" and #line.choices > 0 then
                    for _, choice in ipairs(line.choices) do
                        if type(choice) == "table" then
                            rows[#rows + 1] = { text = text_of(choice.text), line = choice, choice = true }
                        end
                    end
                    return rows
                end
                if line.next ~= nil then
                    id = line.next
                    break
                end
                if #rows >= M.MAX_ROWS then break end
            end
        end
    end
    return rows
end

function M.signature(rows)
    if type(rows) ~= "table" or #rows == 0 then return nil end
    local parts = {}
    for index, row in ipairs(rows) do
        parts[index] = tostring(index) .. ":" .. text_of(row.text)
    end
    return require("mvtk.core.adler32").checksum(table.concat(parts, "\n"))
end

function M.offers_task(rows)
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        local line = row.line
        if type(line) == "table" and (line.quest_start ~= nil or line.quest_turn_in ~= nil) then
            return true
        end
    end
    return false
end

return M
