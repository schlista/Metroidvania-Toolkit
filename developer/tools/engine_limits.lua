-- Apply Recommended Engine Limits (G8-04b): raises game.project's engine pool
-- limits that the last world budget report (developer/tools/world_budget.lua)
-- found too small. Offered from Project > Preparation Status only.
-- Pure Lua for the editor (LuaJ) and headless tests: no frontier patterns, no
-- %.Nf formats, integers only in string.format.
--
-- A recommended value is max(current, ceil(worst * margin)), capped at the
-- engine's ceiling for that key. Ceilings, read from the Defold 1.14.0 source:
--   collection.max_instances   1 << 20 (gameobject.cpp:66 MAX_INSTANCE_COUNT;
--                              NewCollection rejects more, :812-815)
--   tilemap.max_tile_count     the vertex buffer holds 6 * max_tile_count
--                              vertices in a uint32_t (comp_tilegrid.cpp:153)
--   every other pool           dmConfigFile::GetInt reads an int32_t; the pools
--                              size uint32_t arrays (comp_sprite.cpp:265,
--                              comp_label.cpp:156, comp_factory.cpp:135, ...)
-- The rewrite changes only the recommended key lines inside their [section],
-- adds a missing key at the end of its section, adds a missing section at the
-- end of the file, and keeps every other byte, line ending included.
local Budget = require "developer.tools.world_budget"
local M = {}

M.TITLE = "Apply Recommended Engine Limits"
M.INT32_MAX = 2147483647
M.CEILINGS = {
    ["collection.max_instances"] = 1048576,
    ["tilemap.max_tile_count"] = 715827882, -- floor(0xFFFFFFFF / 6)
}

local function default_of(section, key)
    for _, pool in ipairs(Budget.POOLS) do
        if pool.section == section and pool.name == key then return pool.default end
    end
end

function M.ceiling(section, key)
    return M.CEILINGS[section .. "." .. key] or M.INT32_MAX
end

-- Recommendations for `overflows` (world_budget summary.overflows:
-- {section, key, current, worst, margin}) against the game.project text as it
-- is now. The cached `current` may be stale, so it is read again here. Keys
-- that already meet the recommendation are left out.
function M.recommend(overflows, project_text)
    local project = Budget.parse_project(project_text or "")
    local out, seen = {}, {}
    for _, o in ipairs(type(overflows) == "table" and overflows or {}) do
        local section, key = tostring(o.section or ""), tostring(o.key or "")
        local id = section .. "." .. key
        local worst = math.floor(tonumber(o.worst) or 0)
        if section ~= "" and key ~= "" and worst > 0 and not seen[id] then
            seen[id] = true
            local raw = (project[section] or {})[key]
            local current = tonumber(raw)
            current = current and math.floor(current) or default_of(section, key) or tonumber(o.current) or 0
            local margin = tonumber(o.margin) or 1
            if margin < 1 then margin = 1 end
            local wanted = math.ceil(worst * margin)
            local ceiling = M.ceiling(section, key)
            local new = math.min(math.max(current, wanted), ceiling)
            if new > current then
                out[#out+1] = {section=section, key=key, current=current, new=new, worst=worst,
                    present=raw ~= nil, capped=wanted > ceiling}
            end
        end
    end
    return out
end

-- game.project text with each change applied. `changes` items carry
-- {section, key, new}. Every other byte is kept.
function M.apply(text, changes)
    text = text or ""
    local nl = text:find("\r\n", 1, true) and "\r\n" or "\n"
    local wanted = {}
    for _, c in ipairs(changes or {}) do
        wanted[c.section] = wanted[c.section] or {}
        wanted[c.section][c.key] = string.format("%d", math.floor(c.new))
    end
    -- Split keeping each line's own ending.
    local lines = {}
    local pos = 1
    while pos <= #text do
        local s, e = text:find("\r?\n", pos)
        if not s then lines[#lines+1] = {body=text:sub(pos), ending=""}; break end
        lines[#lines+1] = {body=text:sub(pos, s - 1), ending=text:sub(s, e)}
        pos = e + 1
    end
    local done, section, last_in = {}, nil, {}
    for i, line in ipairs(lines) do
        local name = line.body:match("^%s*%[([^%]]+)%]%s*$")
        if name then
            section = name; last_in[section] = last_in[section] or i
        elseif section then
            if line.body:match("%S") then last_in[section] = i end
            local keys = wanted[section]
            if keys then
                local prefix, key = line.body:match("^(%s*([%w_%.#]+)%s*=%s*)")
                if key and keys[key] then
                    line.body = prefix .. keys[key]
                    done[section .. "." .. key] = true
                end
            end
        end
    end
    -- Missing keys go after the last non-blank line of their section, in the
    -- order the changes were given.
    local inserts, appended = {}, {}
    for _, c in ipairs(changes or {}) do
        local id = c.section .. "." .. c.key
        if not done[id] then
            done[id] = true
            local row = c.key .. " = " .. wanted[c.section][c.key]
            local at = last_in[c.section]
            if at then
                inserts[at] = inserts[at] or {}
                table.insert(inserts[at], row)
            else
                if not appended[c.section] then
                    appended[c.section] = {}
                    appended[#appended+1] = c.section
                end
                table.insert(appended[c.section], row)
            end
        end
    end
    local out = {}
    for i, line in ipairs(lines) do
        out[#out+1] = line.body
        if inserts[i] then
            -- A last line without an ending keeps none after the added rows.
            local ending = line.ending ~= "" and line.ending or nl
            out[#out+1] = ending .. table.concat(inserts[i], ending) .. line.ending
        else
            out[#out+1] = line.ending
        end
    end
    local result = table.concat(out)
    if #appended > 0 then
        if result ~= "" and not result:match("\n$") then result = result .. nl end
        for _, name in ipairs(appended) do
            result = result .. nl .. "[" .. name .. "]" .. nl
            for _, row in ipairs(appended[name]) do result = result .. row .. nl end
        end
    end
    return result
end

-- Confirmation text: one line per change, old and new value.
function M.describe(changes)
    local lines = {"Apply Recommended Engine Limits changes only these game.project settings:"}
    for _, c in ipairs(changes) do
        local line = string.format("[%s] %s: %d -> %d (the last world budget report needs %d)",
            c.section, c.key, math.floor(c.current), math.floor(c.new), math.floor(c.worst))
        if c.capped then line = line .. "; capped at the engine maximum, so this pool still overflows" end
        if not c.present then line = line .. "; the key is added" end
        lines[#lines+1] = line
    end
    lines[#lines+1] = "Every other line of game.project stays as it is."
    return lines
end

M.DONE_LINES = {
    "game.project now has the recommended engine limits.",
    "Run Project > Prepare & Check again before Build.",
}

-- The confirmation flow. The caller (hooks/editor_commands.lua, through
-- deps.apply_limits) has already refused a running game, checked the editor
-- scripts are current and saved the editor's buffers.
-- deps: root, overflows, dialog(title, lines, opts), ui (dialog_button),
-- read(path), commit(root, files) (project_transaction.commit by default),
-- refresh() (reload changed resources), info(text).
-- Returns "applied", "cancelled" or "current".
function M.run(deps)
    local root = tostring(deps.root or "."):gsub("\\", "/"):gsub("/$", "")
    local Transaction = require "mvtk.editor.project_transaction"
    local read = deps.read or Transaction.read
    local path = root .. "/game.project"
    local text = read(path)
    assert(type(text) == "string", "Cannot read game.project")
    local changes = M.recommend(deps.overflows, text)
    if #changes == 0 then
        deps.dialog(M.TITLE, {"game.project already has the recommended engine limits. Nothing was changed."})
        return "current"
    end
    local answer = deps.dialog(M.TITLE, M.describe(changes), {cancel_text="Cancel", cancel_result="cancel",
        extra_buttons={deps.ui.dialog_button({text="Apply", result="apply"})}})
    if answer ~= "apply" then return "cancelled" end
    assert(read(path) == text, "game.project changed since review. Choose Project > Preparation Status again.")
    local commit = deps.commit or Transaction.commit
    commit(root, {{path="game.project", content=M.apply(text, changes)}})
    if deps.info then
        local keys = {}
        for _, c in ipairs(changes) do keys[#keys+1] = c.section .. "." .. c.key end
        deps.info("[PREPARE] Applied recommended engine limits: " .. table.concat(keys, ", "))
    end
    if deps.refresh then deps.refresh() end
    deps.dialog(M.TITLE, M.DONE_LINES)
    return "applied"
end

return M
