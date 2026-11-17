-- hooks/core/boot_env.lua
--
-- Tiny boot-time handoff for values discovered by hooks.editor_script before
-- the split hook chunks are loaded.

local M = {}

local project_root = nil

function M.set_project_root(value)
    project_root = value
end

function M.get_project_root()
    return project_root
end

function M.is_project_root(path, open_file)
    if type(path) ~= "string" or path == "" then return false end
    open_file = open_file or io.open
    local ok, file = pcall(open_file, path:gsub("[/\\]+$", "") .. "/game.project", "rb")
    if not ok or not file then return false end
    if type(file.close) == "function" then file:close() end
    return true
end

-- Headless only: a probe distinguishes folders even when their contents match.
-- nil means the current folder is not writable, so callers can compare bytes.
function M.same_folder(path, io_lib, os_lib)
    if type(path) ~= "string" or path == "" then return false end
    io_lib, os_lib = io_lib or io, os_lib or os
    local probe = ".mvtk_root_probe_" .. os_lib.time() .. "_" .. math.random(1, 2147483646) .. ".txt"
    local ok, file = pcall(io_lib.open, probe, "wb")
    if not ok or not file then return nil end

    local wrote, result = pcall(file.write, file, probe)
    local closed, close_result = pcall(file.close, file)
    local visible = false
    if wrote and result and closed and close_result then
        local opened, candidate = pcall(io_lib.open, path:gsub("[/\\]+$", "") .. "/" .. probe, "rb")
        if opened and candidate then
            visible = true
            pcall(candidate.close, candidate)
        end
    end

    -- Some hosts delete successfully yet return nil. Inspect the path instead.
    pcall(os_lib.remove, probe)
    local opened, remaining = pcall(io_lib.open, probe, "rb")
    if opened and remaining then
        pcall(remaining.close, remaining)
        error("Cannot remove project-root probe: " .. probe)
    end
    if not wrote or not result or not closed or not close_result then return nil end
    return visible
end

-- Read-only fallback for a headless host that cannot create a probe.
function M.same_project(path, open_file)
    if type(path) ~= "string" or path == "" then return false end
    open_file = open_file or io.open
    local function read_bytes(filename)
        local ok, file = pcall(open_file, filename, "rb")
        if not ok or not file then return nil end
        local read, bytes = pcall(file.read, file, "*a")
        pcall(file.close, file)
        if read and type(bytes) == "string" then return bytes end
        return nil
    end
    for _, filename in ipairs({ "game.project", "developer/config/persistence_settings.lua" }) do
        local current = read_bytes(filename)
        local candidate = read_bytes(path:gsub("[/\\]+$", "") .. "/" .. filename)
        if current == nil or candidate == nil or current ~= candidate then return false end
    end
    return true
end

return M
