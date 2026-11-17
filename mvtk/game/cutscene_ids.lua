-- One identity and generation rule for authored cutscene volumes.
local M = {}

local function text(value)
    if value == nil then return nil end
    local s = tostring(value):match("^%s*(.-)%s*$")
    if s ~= "" then return s end
end

function M.resolve(props, room_id, object_id)
    props = props or {}
    return text(props.cutscene_id) or text(props.cutscene_name)
        or string.format("tiled_cutscene_%s_%d", tostring(room_id), math.floor(tonumber(object_id) or 0))
end

function M.generates(props)
    if type(props) ~= "table" then return false end
    if props.generate_cutscene == true then return true end
    return text(props.video_id) or text(props.video_uri) or text(props.video_editor_uri)
        or text(props.cutscene_dialogue_id) or text(props.dialogue_id)
end

-- Configured entries and generating object definitions share one namespace.
function M.known(id, configured, definitions)
    local bucket = (definitions or {})[id]
    return (configured or {})[id] ~= nil or (type(bucket)=="table" and #bucket > 0)
end

return M
