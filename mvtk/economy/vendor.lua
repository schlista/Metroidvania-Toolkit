-- Pure vendor rules; ids and greeting state stay as source strings in Flags.
local M = {}
local function optional(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" or value:lower() == "none" then return nil end
    return value
end
function M.catalog(props, preset)
    return optional((props or {}).vendor_shop) or optional((preset or {}).vendor_shop)
end
function M.is_active(props, preset, Flags)
    local flag = (props or {}).vendor_flag
    flag = type(flag) == "string" and flag:match("^%s*(.-)%s*$") or ""
    return M.catalog(props, preset) ~= nil and (flag == "" or Flags.has(flag))
end
function M.needs_greeting(mode, npc_id, has_dialogue, Flags)
    if not has_dialogue or mode == "never" then return false end
    if mode == "every_visit" then return true end
    return not Flags.has("npc_greeted:" .. npc_id)
end
function M.mark_greeted(npc_id, Flags)
    Flags.set("npc_greeted:" .. npc_id, true)
end
return M
