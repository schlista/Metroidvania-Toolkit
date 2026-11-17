-- Shared currency syntax and integer formatting, also usable in editor LuaJ.
local M = {}

function M.valid(fmt)
    if type(fmt) ~= "string" then return false, "Currency format must be text." end
    if #fmt > 40 then return false, "Currency format must be at most 40 characters." end
    local count, i = 0, 1
    while true do
        local at = string.find(fmt, "{amount}", i, true)
        if not at then break end
        count, i = count + 1, at + 8
    end
    i = 1
    while true do
        local at = string.find(fmt, "%", i, true)
        if not at then break end
        local token = string.sub(fmt, at + 1, at + 1)
        if token == "d" then count = count + 1
        elseif token ~= "%" then
            return false, "Currency format accepts only {amount}, %d and %% (a literal percent)."
        end
        i = at + 2
    end
    if count ~= 1 then return false, "Currency format needs exactly one {amount} or %d placeholder." end
    return true
end

local function integer_text(n, separator)
    n = math.floor(n)
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    local digits, count = {}, 0
    repeat
        if count > 0 and count % 3 == 0 and separator ~= "" then
            table.insert(digits, 1, separator)
        end
        table.insert(digits, 1, string.char(48 + n % 10))
        count, n = count + 1, math.floor(n / 10)
    until n == 0
    return sign .. table.concat(digits)
end

function M.apply(fmt, n, opts)
    opts = opts or {}
    local valid, message = M.valid(fmt)
    if not valid then
        if opts.warn then opts.warn(message) end
        fmt = "$ %d"
    end
    local amount = integer_text(n, opts.thousands_separator or "")
    local out, i = {}, 1
    while i <= #fmt do
        if string.sub(fmt, i, i + 7) == "{amount}" then
            out[#out + 1], i = amount, i + 8
        elseif string.sub(fmt, i, i) == "%" then
            out[#out + 1] = string.sub(fmt, i + 1, i + 1) == "d" and amount or "%"
            i = i + 2
        else
            out[#out + 1], i = string.sub(fmt, i, i), i + 1
        end
    end
    return table.concat(out)
end

return M
