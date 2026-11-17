-- Run-scoped config reader. Project dependencies never use package.loaded.
local M = {}

function M.new(opts)
    local root = tostring(opts.root or "."):gsub("\\", "/"):gsub("/$", "")
    local cache, loading = {}, {}
    local loader = {}
    local function vector3(x, y, z) return { x=x or 0, y=y or 0, z=z or 0 } end
    local function vector4(x, y, z, w) return { x=x or 0, y=y or 0, z=z or 0, w=w or 0 } end
    local function evaluate(path)
        local source = opts.read(root .. "/" .. path)
        if source == nil then
            if opts.missing then
                local fallback = opts.missing(path, loader.require)
                if fallback ~= nil then return fallback end
            end
            return nil, "Missing " .. path
        end
        local env = setmetatable({ require=loader.require,
            vmath=opts.vmath or { vector3=vector3, vector4=vector4 } }, { __index=_G })
        env._G = env
        local chunk, err
        if loadstring then
            chunk, err = loadstring(source, "@" .. path)
            if chunk then setfenv(chunk, env) end
        else
            ---@diagnostic disable-next-line: redundant-parameter
            chunk, err = load(source, "@" .. path, "t", env)
        end
        if not chunk then return nil, "Cannot read " .. path .. ": " .. tostring(err) end
        local ok, value = pcall(chunk)
        if not ok then return nil, "Cannot read " .. path .. ": " .. tostring(value) end
        if type(value) ~= "table" then return nil, "Cannot read " .. path .. ": it returns no table" end
        return value
    end
    function loader.require(name)
        if not name:match("^developer%.config%.") then return require(name) end
        local value, err = loader.load_path(name:gsub("%.", "/") .. ".lua")
        if value == nil then error(err) end
        return value
    end
    function loader.load_path(path)
        -- Public disk loads retain the nullable contract used by bakers.
        if cache[path] ~= nil then return cache[path] end
        if loading[path] then return nil, "Circular config require: " .. path end
        loading[path] = true
        local ok, value, err = pcall(evaluate,path)
        loading[path] = nil
        if not ok then return nil, value end
        if value ~= nil then cache[path] = value end
        return value, err
    end
    return loader
end

return M
