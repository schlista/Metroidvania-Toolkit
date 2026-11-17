-- Pure persistent identity rules shared by authoring and runtime.
local M = {}
local function text(value)
    if value == nil then return nil end
    local s=tostring(value):match("^%s*(.-)%s*$")
    return s~="" and s or nil
end
function M.runtime(boss, fallback_id)
    local cfg=boss and boss.config or {}
    return text(cfg.spawn_id) or text(cfg.boss_id) or text(cfg.boss_tag)
        or text(boss and boss.preset_id) or text(boss and boss.type) or fallback_id
end
function M.placed(props, instance_id)
    props=props or {}
    return text(props.boss_id) or text(props.boss_tag) or instance_id
end
return M
