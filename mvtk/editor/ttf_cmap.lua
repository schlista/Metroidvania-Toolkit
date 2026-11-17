-- Unicode coverage from sfnt TrueType/OpenType cmap tables. No bit/UTF-8 library.
-- https://learn.microsoft.com/en-us/typography/opentype/spec/cmap
local M = {}

local function parse(data)
    assert(type(data) == "string", "Font data is missing")
    local function bounds(at, count, limit)
        assert(at >= 0 and count >= 0 and at + count <= (limit or #data), "Truncated font/cmap")
    end
    local function u16(at)
        bounds(at, 2)
        local a,b = data:byte(at+1, at+2)
        return a*256+b
    end
    local function i16(at)
        local value = u16(at)
        return value >= 32768 and value-65536 or value
    end
    local function u32(at) return u16(at)*65536+u16(at+2) end
    bounds(0, 12)
    local signature = data:sub(1,4)
    assert(signature == "\0\1\0\0" or signature == "OTTO" or signature == "true", "Not a TrueType/OpenType font")
    local count = u16(4)
    bounds(12, count*16)
    local cmap, cmap_end
    for i=0,count-1 do
        local at = 12+i*16
        local offset, length = u32(at+8), u32(at+12)
        bounds(offset, length)
        if data:sub(at+1,at+4) == "cmap" then
            assert(not cmap, "Duplicate cmap table")
            cmap, cmap_end = offset, offset+length
        end
    end
    assert(cmap, "Font has no cmap table")
    bounds(cmap, 4, cmap_end)
    assert(u16(cmap) == 0, "Unsupported cmap version")
    count = u16(cmap+2)
    bounds(cmap+4, count*8, cmap_end)
    local tables, seen = {}, {}
    for i=0,count-1 do
        local record = cmap+4+i*8
        local platform, encoding = u16(record), u16(record+2)
        if platform == 0 or (platform == 3 and (encoding == 1 or encoding == 10)) then
            local at = cmap+u32(record+4)
            bounds(at, 2, cmap_end)
            local format = u16(at)
            if not seen[at] and (format == 4 or format == 12) then
                seen[at] = true
                local groups = {}
                if format == 4 then
                    bounds(at, 14, cmap_end)
                    local length, segments = u16(at+2), u16(at+6)/2
                    assert(segments >= 1 and segments == math.floor(segments), "Invalid format-4 segment count")
                    local limit = at+length
                    bounds(at, length, cmap_end)
                    bounds(at, 16+segments*8, limit)
                    local ends, starts = at+14, at+16+segments*2
                    local deltas, offsets = at+16+segments*4, at+16+segments*6
                    local previous = -1
                    for j=0,segments-1 do
                        local first, last = u16(starts+j*2), u16(ends+j*2)
                        local word, offset = offsets+j*2, u16(offsets+j*2)
                        assert(first <= last and first > previous, "Unsorted/overlapping format-4 segments")
                        if offset ~= 0 then
                            assert(offset%2 == 0 and word+offset >= offsets+segments*2, "Invalid format-4 glyph offset")
                            bounds(word+offset, (last-first+1)*2, limit)
                        end
                        groups[#groups+1] = {first=first,last=last,delta=i16(deltas+j*2),word=word,offset=offset}
                        previous = last
                    end
                    assert(previous == 65535, "Format-4 sentinel is missing")
                else
                    bounds(at, 16, cmap_end)
                    assert(u16(at+2) == 0, "Invalid format-12 reserved field")
                    local length, n = u32(at+4), u32(at+12)
                    bounds(at, length, cmap_end)
                    bounds(at+16, n*12, at+length)
                    local previous = -1
                    for j=0,n-1 do
                        local group = at+16+j*12
                        local first, last, glyph = u32(group), u32(group+4), u32(group+8)
                        assert(first <= last and last <= 0x10ffff and first > previous, "Invalid format-12 group")
                        assert(glyph+last-first <= 65535, "Invalid format-12 glyph index")
                        groups[#groups+1] = {first=first,last=last,glyph=glyph}
                        previous = last
                    end
                end
                tables[#tables+1] = {format=format,groups=groups}
            end
        end
    end
    assert(#tables > 0, "Font has no supported Unicode cmap (format 4 or 12)")
    local font = {}
    function font.has(codepoint)
        if type(codepoint) ~= "number" or codepoint%1 ~= 0 or codepoint < 0 or codepoint > 0x10ffff
            or (codepoint >= 0xd800 and codepoint <= 0xdfff) then return false end
        for _, subtable in ipairs(tables) do
            local lo, hi = 1, #subtable.groups
            while lo <= hi do
                local mid = math.floor((lo+hi)/2)
                local group = subtable.groups[mid]
                if codepoint < group.first then hi = mid-1
                elseif codepoint > group.last then lo = mid+1
                else
                    local glyph
                    if subtable.format == 12 then glyph = group.glyph+codepoint-group.first
                    elseif group.offset == 0 then glyph = (codepoint+group.delta)%65536
                    else
                        glyph = u16(group.word+group.offset+(codepoint-group.first)*2)
                        if glyph ~= 0 then glyph = (glyph+group.delta)%65536 end
                    end
                    if glyph ~= 0 then return true end
                    break
                end
            end
        end
        return false
    end
    return font
end

function M.parse(data)
    local ok, result = pcall(parse, data)
    if not ok then return nil, tostring(result) end
    return result
end

function M.read(path, read)
    local data = (read or require("mvtk.editor.file_utils").read_disk)(path)
    if not data then return nil, "Cannot read font: " .. tostring(path) end
    local font, err = M.parse(data)
    if not font then return nil, tostring(path) .. ": " .. err end
    return font
end

return M
