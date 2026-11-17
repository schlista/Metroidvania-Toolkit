-- Shared presentation for authored message plates. Texture, slice-9 and font
-- stay on the scene nodes; creator configuration controls geometry and tint.
local HudLayout = require "mvtk.ui.hud_layout"
local Notices = require "mvtk.ui.notices"
local GeneratedText = require "mvtk.ui.generated_text"
local M = {}

function M.entry(layout, name, overrides)
    local entry = HudLayout.entry(layout, name, overrides)
    entry.plate_color = entry.plate_color or layout.message_plate
    return entry
end

-- Opt into the editor's node colour without letting subsequent fades replace
-- that original tint. Each GUI owner resolves this once, before hiding nodes.
function M.authored_plate(gui_api, plate, style)
    if style.plate_color=="authored" then
        local c=gui_api.get_color(plate)
        style.plate_color={r=c.x,g=c.y,b=c.z,a=c.w}
    end
end

function M.tint(gui_api, label, plate, style, alpha)
    local text, backing = style.text_color or {r=1,g=1,b=1,a=1}, style.plate_color or {r=0,g=0,b=0,a=0.75}
    gui_api.set_color(label, vmath.vector4(text.r, text.g, text.b, (text.a or 1) * (style.opacity or 1) * alpha))
    if plate then gui_api.set_color(plate, vmath.vector4(backing.r, backing.g, backing.b, (backing.a or 1) * alpha)) end
end

-- Width/height caps and padding are final design pixels, independent of HUD
-- scale. Shorten at UTF-8 boundaries rather than shrinking readable glyphs.
function M.fit(gui_api, resources, label, plate, text, style, hud_scale, reading_scale)
    local scale = (style.text_scale or 1) * (hud_scale or 1) * (reading_scale or 1)
    local padding = style.padding or {x=24,y=12}
    local width, height = style.max_width or 848, style.max_height or 160
    local text_width, text_height = width-padding.x*2, height-padding.y*2
    local font=gui_api.get_font_resource(gui_api.get_font(label))
    local leading,tracking=gui_api.get_leading(label),gui_api.get_tracking(label)
    -- An oversized creator font must still show a line. Only cap glyph scale
    -- when even one unwrapped line would exceed the reserved vertical band.
    local line=GeneratedText.metrics(font,(text:gsub("[\r\n]+"," ")),
        {line_break=false,leading=leading,tracking=tracking},resources)
    if line.height*scale>text_height then scale=text_height/math.max(1,line.height) end
    gui_api.set_scale(label, vmath.vector3(scale, scale, 1))
    gui_api.set_line_break(label, true)
    gui_api.set_size(label, vmath.vector3(text_width/scale, text_height/scale, 0))
    local function metrics(value)
        return GeneratedText.metrics(font, value,
            {width=text_width/scale,line_break=true,leading=leading,tracking=tracking}, resources)
    end
    local extent = metrics(text)
    -- At large HUD/reading sizes, joining authored lines often retains the
    -- whole short gate name and cost where a multi-line label would not fit.
    if extent.height*scale > text_height and text:find("\n",1,true) then
        text=text:gsub("[\r\n]+"," | ");extent=metrics(text)
    end
    if extent.height*scale > text_height or extent.width*scale > text_width then
        local count=0; for _ in text:gmatch("[^\128-\191]") do count=count+1 end
        local low, high, best = 0, count, ""
        while low<=high do
            local mid=math.floor((low+high)/2)
            local candidate=Notices.trim(text,mid)
            local measured=metrics(candidate)
            if measured.height*scale<=text_height and measured.width*scale<=text_width then
                best=candidate;low=mid+1
            else high=mid-1 end
        end
        text=best;extent=metrics(text)
    end
    gui_api.set_text(label, text)
    local size=vmath.vector3(math.min(width,extent.width*scale+padding.x*2),
        math.min(height,extent.height*scale+padding.y*2),0)
    if plate then
        gui_api.set_scale(plate,vmath.vector3(1,1,1))
        gui_api.set_size(plate,size)
    end
    return size
end

-- Unlike HUD bars, message entries centre their text and plate on the anchor
-- point. This keeps short labels and multi-line gate hints centred together.
function M.position(gui_api, label, plate, style, bounds)
    local x,y=HudLayout.position(style,bounds.max_x-bounds.min_x,bounds.max_y-bounds.min_y)
    local p=vmath.vector3(x+bounds.min_x,y+bounds.min_y,0)
    gui_api.set_pivot(label,gui_api.PIVOT_CENTER)
    gui_api.set_position(label,p)
    if plate then gui_api.set_pivot(plate,gui_api.PIVOT_CENTER);gui_api.set_position(plate,p) end
end

function M.rectangle(style, width, height)
    return HudLayout.message_rectangle(style,width,height)
end

function M.screen_position(gui_api, label, plate, style, rect)
    local x,y=HudLayout.screen_top_left(style,rect,0,0)
    if not x then return end
    for _,node in ipairs({plate,label}) do
        gui_api.set_pivot(node,gui_api.PIVOT_CENTER)
        gui_api.set_screen_position(node,vmath.vector3(x,y,0))
    end
end
return M
