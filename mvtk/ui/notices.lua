-- Milestone messages contain source text; rendering belongs to the GUI.
local Bus = require "mvtk.ui.hud_bus"
local Util = require "mvtk.core.util"
local RuntimeSettings = require "developer.config.runtime_settings"
local HudLayout = require "mvtk.ui.hud_layout"
local Layout = require "developer.config.hud_layout"
local M = {}
local pending, serial = {}, 0

-- Transport a small reference rather than truncating a translation lookup key
-- to fit msg.post's 2 KB limit. The receiving scene takes ownership of the
-- original source. Bound abandoned deliveries when no GUI is loaded.
function M.take(reference)
    local notice = pending[reference]
    pending[reference] = nil
    return notice
end

-- Count UTF-8 codepoints and never leave a partial sequence at either limit.
function M.trim(value, characters, bytes)
    local text = tostring(value or "")
    local pos, count = 1, 0
    while pos <= #text and count < characters do
        local lead = text:byte(pos)
        local length = lead < 128 and 1 or lead < 224 and 2 or lead < 240 and 3 or 4
        if pos + length - 1 > math.min(#text, bytes or #text) then break end
        pos, count = pos + length, count + 1
    end
    return text:sub(1, pos - 1)
end

-- Called only by the displaying notice/toast scene. Source lookup precedes
-- every character/byte cap, so long originals still match their translations.
function M.render(notice, display, short)
    local render = require("mvtk.ui.menu_text").render
    local title, body = render(notice.title or "", display), render(notice.text or "", display)
    if short then title, body = title:gsub("[\r\n]", " "), body:gsub("[\r\n]", " ") end
    return M.trim(title, short and 40 or 120, short and nil or 384),
        M.trim(body, short and 48 or 240, short and nil or 768)
end

function M.toast_text(notice, display)
    local title, body = M.render(notice, display, true)
    return display.ui("gameplay.title_body", {title=title, body=body})
end

function M.post(notice)
    notice = notice or {}
    -- Only metadata is capped here. Source text travels by reference below.
    local n = { title = notice.title or "", text = notice.text or "",
        kind = M.trim(notice.kind, 32, 32), key = M.trim(notice.key, 64, 64),
        sound = M.trim(notice.sound, 64, 64) }
    if type(notice.icon) == "table" then
        n.icon = { texture = M.trim(notice.icon.texture, 32, 32), anim = M.trim(notice.icon.anim, 64, 64) }
    end
    local layout = RuntimeSettings.section("hud_layout", Layout)
    local entry = HudLayout.entry(layout, "notices", (RuntimeSettings.load() or {}).hud_layout)
    serial = serial + 1
    pending[serial], pending[serial - 128] = n, nil
    if entry.enabled == false or entry.visible == false then
        -- Toast's 800-pixel label does not wrap. Keep each fallback line short.
        return Util.safe_post("main:/toast_gui#toast", "toast", { notice_ref = serial })
    end
    return Bus.post("notices", { notice_ref = serial })
end
return M
