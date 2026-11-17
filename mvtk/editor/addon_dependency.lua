-- Shared dependency-only transforms. Pure Lua; preserve unrelated bytes and indices.
local M = {}

local function lines(text)
    local out, pos = {}, 1
    while pos <= #text do
        local ending = text:find("\n", pos, true)
        local stop = ending or #text
        local raw = text:sub(pos, stop)
        out[#out+1] = { raw=raw, text=raw:gsub("[\r\n]+$", "") }
        pos = stop + 1
    end
    return out
end
local function newline(text) return text:find("\r\n", 1, true) and "\r\n" or "\n" end
function M.project_sections(text)
    local count = 0
    for _, line in ipairs(lines(text)) do
        if line.text:match("^%s*%[project%]%s*$") then count = count + 1 end
    end
    return count
end
function M.entries(text, marker)
    local section, entries, used = nil, {}, {}
    for index, line in ipairs(lines(text)) do
        local heading = line.text:match("^%s*%[([^%]]+)%]%s*$")
        if heading then section = heading end
        local number, url = line.text:match("^%s*dependencies#(%d+)%s*=%s*(.-)%s*$")
        if number and section == "project" then
            used[tonumber(number)] = true
            if url and url:find(marker, 1, true) ~= nil then entries[#entries+1] = { line=index, index=tonumber(number), url=url } end
        end
    end
    return entries, used
end
-- Preserve unrelated text, dependency indices and the input newline convention.
-- Canonical Off -> On -> Off is byte-identical. Arbitrary removed dependency
-- spacing/indices and ignore-line placement cannot be recovered without metadata.
function M.dependency_text(text, enabled, marker, supported_url)
    text = text or ""
    assert(M.project_sections(text) == 1, "game.project must contain exactly one [project] section")
    local entries = M.entries(text, marker)
    if enabled and #entries == 1 and entries[1].url == supported_url then return text end
    if not enabled and #entries == 0 then return text end
    local remove = {}; for _, entry in ipairs(entries) do remove[entry.line] = true end
    local kept = {}
    for index, line in ipairs(lines(text)) do if not remove[index] then kept[#kept+1] = line.raw end end
    local output = table.concat(kept)
    if not enabled then return output end
    local _, used = M.entries(output, marker)
    local index = 0; while used[index] do index = index + 1 end
    local source, section, insert_at = lines(output), nil, nil
    for i, line in ipairs(source) do
        local heading = line.text:match("^%s*%[([^%]]+)%]%s*$")
        if heading then
            if section == "project" then break end
            section = heading
            if section == "project" then insert_at = i + 1 end
        elseif section == "project" and line.text:match("^%s*dependencies#%d+%s*=") then insert_at = i + 1 end
    end
    assert(insert_at, "game.project is missing its [project] section")
    local eol = newline(text)
    if insert_at > 1 and source[insert_at-1].raw:sub(-1) ~= "\n" then
        source[insert_at-1].raw = source[insert_at-1].raw .. eol
    end
    table.insert(source, insert_at, {raw="dependencies#" .. index .. " = " .. supported_url .. eol})
    local result = {}; for _, line in ipairs(source) do result[#result+1] = line.raw end
    return table.concat(result)
end

return M
