-- Project-owned wizard overrides. Authored baseline files are never replaced.
local Model = require "mvtk.core.creator_settings_model"
local Transaction = require "mvtk.editor.project_transaction"
local PlayerScaleWriter = require "mvtk.editor.player_scale_writer"
local PlayerScale = require "mvtk.player.player_scale"
local M = {}

local function load_table(content, path)
    local chunk = assert((loadstring or load)(content, "@" .. path))
    local value = chunk()
    assert(type(value) == "table", path .. " must return a table")
    return value
end

local function config_loader(read, base)
    return function(name)
        local path = base .. "/config/" .. name:match("[^.]+$") .. ".lua"
        local text = read(path)
        if text then return load_table(text, path) end
        return require(name)
    end
end

local function project_root(base, opts)
    if opts and opts.project_root then return opts.project_root end
    if base == "developer" then return "." end
    return base:match("^(.*)/developer$")
end

function M.recover(base, opts)
    base = base or "developer"
    local recovered = Transaction.recover(base, opts)
    local root = project_root(base, opts)
    if root then recovered = Transaction.recover(root, opts) or recovered end
    return recovered
end

local function validate_player(baseline, effective, saved_overrides)
    local checked = Model.copy(effective)
    if saved_overrides then
        for _, field in pairs(Model.fields) do
            local path = field.allow_saved_out_of_range and field.path:match("^player%.(.+)$")
            local saved = path and Model.get(saved_overrides, path)
            if type(saved) == "number" and saved == Model.get(effective, path)
                and (saved < field.min or saved > field.max) then
                -- Check the authored value here. Keep the saved override in
                -- the effective settings used by the player and the writer.
                Model.put(checked, path, Model.get(baseline, path))
            end
        end
    end
    local errors = require("mvtk.core.config_validator").validate_config(checked,
        require("mvtk.core.config_schemas").player_settings)
    assert(#errors == 0, table.concat(errors, "; "))
end

-- Rebuild geometry from the saved effective settings without publishing drafts
-- or rewriting the wizard document. Called by Prepare & Check.
function M.prepare(opts)
    opts=opts or {}
    local base=(opts.base or "developer"):gsub("\\", "/"):gsub("/$", "")
    local ok,result=pcall(function()
        M.recover(base,opts)
        local read=opts.fs and opts.fs.read or Transaction.read
        local baseline=load_table(read(base.."/config/player_settings.lua"),"player_settings.lua")
        local text=read(base.."/config/creator_settings.lua")
        local doc=text and Model.load_document(load_table(text,"creator_settings.lua"),baseline,config_loader(read,base))
        local saved_overrides=doc and doc.published==true and doc.overrides.player
        local player=Model.merge(Model.copy(baseline),saved_overrides or {})
        validate_player(baseline,player,saved_overrides)
        local files=PlayerScaleWriter.stage({base=base,read=read,player=player,
            previous=Model.copy(player),force_geometry=true})
        return Transaction.commit(base,files,opts)
    end)
    if ok then return result end
    return nil,{error="player_settings_prepare_failed",message=tostring(result)}
end

function M.save(data, opts)
    opts = opts or {}
    local base = (opts.base or "developer"):gsub("\\", "/"):gsub("/$", "")
    local function run()
        M.recover(base, opts)
        -- Existing callback is now a preflight: failure cannot publish settings.
        if opts.validate_generated_configs then
            local valid, message = opts.validate_generated_configs()
            if not valid then error(message or "Configuration validation failed", 0) end
        end
        local read = opts.fs and opts.fs.read or Transaction.read
        local load_config = config_loader(read, base)
        local player_path = base .. "/config/player_settings.lua"
        local baseline = load_table(read(player_path) or data.player_settings, player_path)
        local creator_path = base .. "/config/creator_settings.lua"
        local previous_text = read(creator_path)
        local previous = previous_text and load_table(previous_text, creator_path)
            or { version = Model.VERSION, player_units = Model.baseline_units(baseline), overrides = {} }
        previous = Model.load_document(previous, baseline, load_config)
        if data.expected_document then
            local expected = Model.copy(Model.load_document(data.expected_document, baseline, load_config))
            -- Loading has normalized the timings. The disk marker can differ
            -- even when no settings value changed.
            expected.attack_recovery_version = previous.attack_recovery_version
            assert(Model.encode(previous) == Model.encode(expected),
                "Project settings changed since the wizard opened. Rebuild and reopen before saving.")
        end
        local values = Model.copy(data.player_preset or data.controls or {})
        if data.player_scale ~= nil then values.player_scale = data.player_scale end
        if data.scale_movement ~= nil then values.scale_movement = data.scale_movement end
        local doc = data.requested_document and Model.copy(Model.load_document(data.requested_document, baseline, load_config))
            or Model.from_controls(values, previous, baseline, load_config)
        doc.player_units = Model.baseline_units(baseline)
        doc.attack_recovery_version = Model.ATTACK_RECOVERY_VERSION
        -- A Save with no edits still retires runtime switches from older drafts.
        Model.prune_legacy(doc)
        doc.published = true
        local files = {}
        -- These compatibility outputs are only scaffolds for a missing baseline.
        for _, item in ipairs({
            { "config/player_settings.lua", data.player_settings },
            { "config/ability_defaults.lua", data.ability_defaults },
            { "config/combat_overrides.lua", data.combat_overrides },
        }) do
            if read(base .. "/" .. item[1]) == nil then
                assert(type(item[2]) == "string", "Missing baseline: " .. item[1])
                load_table(item[2], item[1])
                files[#files + 1] = { path = item[1], content = item[2] }
            end
        end
        local old_player = Model.merge(Model.copy(baseline), previous.overrides.player or {})
        local effective = Model.merge(Model.copy(baseline), doc.overrides.player or {})
        validate_player(baseline, effective, previous.overrides.player)
        local Validator = require "mvtk.core.config_validator"
        local Schemas = require "mvtk.core.config_schemas"
        -- Controls authoring uses this same pure contract in Stage 3. Validate
        -- the current defaults before publishing any Game Settings transaction.
        local bindings_text = read(base .. "/config/default_bindings.lua")
        if bindings_text then
            local Rules = require "mvtk.core.input_binding_rules"
            local merged, problems = Rules.apply_creator(load_table(bindings_text, "default_bindings.lua"),
                doc.overrides.default_bindings, require "mvtk.rooms.input_actions")
            local binding_errors = Rules.validate(merged)
            for _, problem in ipairs(problems) do binding_errors[#binding_errors + 1] = problem end
            assert(#binding_errors == 0, table.concat(binding_errors, "; "))
        end
        local ending_text=read(base.."/config/game_completion.lua")
        if ending_text then
            local ending=require("mvtk.game.endings").effective(load_table(ending_text,"game_completion.lua"),doc.overrides.game_completion or {})
            local ending_errors=Validator.validate_config(ending,Schemas.game_completion)
            assert(#ending_errors==0,table.concat(ending_errors,"; "))
        end
        for _, file in ipairs(PlayerScaleWriter.stage({ base=base, read=read,
            player=effective, previous=old_player, force_geometry=opts.force_geometry })) do
            files[#files+1] = file
        end
        if opts.art_import then
            local cfg=Model.merge(PlayerScale.convert_units(load_table(assert(read(base.."/config/player_art.lua")),"player_art.lua"),
                "player_art",effective),doc.overrides.player_art or {})
            assert(Model.encode(cfg)==Model.encode(opts.art_import.config),"Player art settings changed after preview; import/preview again before Save.")
            local remaps=Model.copy((require("developer.config.game_config").player or {}).animation_overrides or {})
            Model.merge(remaps,effective.animation_overrides or {})
            require("developer.tools.player_art_import").validate_runtime(opts.art_import,remaps)
            local staged={}; for _,file in ipairs(files) do staged[file.path]=file.content end
            local art_files=require("developer.tools.player_art_import").stage(opts.art_import,effective,function(path)
                if path:sub(1,10)=="developer/" then return staged[path:sub(11)] or read(base.."/"..path:sub(11)) end
                return read(path)
            end)
            local replacements={}; for _,file in ipairs(art_files) do replacements[file.path]=true end
            local combined={}; for _,file in ipairs(files) do if not replacements[file.path] then combined[#combined+1]=file end end
            for _,file in ipairs(art_files) do combined[#combined+1]=file end
            files=combined
            doc.overrides.player=doc.overrides.player or {}; doc.overrides.player.player_type="sprite"
        end
        files[#files + 1] = { path = "config/creator_settings.lua", content = Model.serialize(doc, baseline, load_config) }
        local root = project_root(base, opts)
        local identity
        if root and read(root .. "/game.project") and data.project_name then
            local Identity = require "developer.tools.project_identity"
            local identity_files
            identity_files, identity = Identity.stage(root, data.project_name, data.identity_proposal,
                {read=read, choice=data.identity_choice})
            if data.identity_choice == "copy" then
                require("developer.tools.player_data_migration").copy(data.identity_proposal, data.identity_review,
                    {ownership_confirmed=data.ownership_confirmed, sys=opts.sys, max_slots=opts.max_slots})
            end
            for _, file in ipairs(files) do file.path = "developer/" .. file.path end
            for _, file in ipairs(identity_files) do files[#files+1] = file end
        else root = nil end
        local written, cleanup_warning = Transaction.commit(root or base, files, opts)
        data.creator_document = doc
        data.identity = identity
        data.cleanup_warning = cleanup_warning
        return written
    end
    local ok, result = pcall(run)
    if ok then return result end
    return nil, { error = "creator_settings_save_failed", message = tostring(result) }
end

return M
