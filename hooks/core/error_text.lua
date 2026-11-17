-- Error text for re-raised editor failures.
--
-- The Defold editor runs LuaJ 3.0.1, which ignores error()'s level for string
-- messages: the closure that catches the raise always prepends its
-- "@source:line " (LuaClosure.processErrorHooks). Every pcall-and-re-raise
-- therefore adds another prefix, and a creator's first line becomes a chain of
-- internal paths. Re-raise sites strip the earlier prefixes, so a message
-- carries at most the one LuaJ adds at the final raise. Desktop Lua's
-- "source:line: " prefix is stripped the same way, except where it names a
-- file outside hooks/ and mvtk/: that is where the error is, such as a syntax
-- error in a developer/config file, and the creator needs it.
--
-- LuaJ-safe: plain lazy patterns only, no %f frontier.
local M = {}

-- One leading position: optional "@", a path without spaces ending in .lua or .editor_script,
-- ":" line digits, an optional ":" and one space.
local PREFIXES = { "^@?[^%s]-%.lua:%d+:? ", "^@?[^%s]-%.editor_script:%d+:? " }

-- A "path:line: " origin (no "@", so not a LuaJ re-raise) in a creator's file.
local function creator_origin(prefix)
    if prefix:sub(1, 1) == "@" or not prefix:find(":%d+: $") then return false end
    local path = prefix:gsub("\\", "/")
    return not (path:find("^%.?/?hooks/") or path:find("/hooks/", 1, true)
        or path:find("^%.?/?mvtk/") or path:find("/mvtk/", 1, true))
end

function M.strip(message)
    if type(message) ~= "string" then return message end
    local changed = true
    while changed do
        changed = false
        for _, pattern in ipairs(PREFIXES) do
            local prefix = message:match(pattern)
            if prefix and not creator_origin(prefix) then
                message, changed = message:sub(#prefix + 1), true
            end
        end
    end
    return message
end

-- Raise a caught failure again without keeping earlier position prefixes.
-- Non-string error values pass through unchanged.
function M.reraise(err)
    error(M.strip(err), 0)
end

return M
