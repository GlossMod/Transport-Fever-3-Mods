local settings = ug_require "xiaom_global_tuning::/settings.lua"
local core = ug_require "xiaom_global_tuning::/tuning_core.lua"
local store = ug_require "xiaom_global_tuning::/config_store.lua"
local prefix = "[xiaom_global_tuning] "
local postApplied = false

local function report(message) debugPrint(prefix .. message) end

function data()
    return {
        preRunFn = function(_captureParams, _configDict, _allModParams, _baseConfig)
            postApplied = false
            -- Industry now uses a live modifier; multiplying baseConfig too
            -- would apply the same production factor twice.
        end,

        postRunFn = function(_captureParams, _configDict, _allModParams)
            if postApplied then return end
            postApplied = true
            local params, found, err = store.read()
            -- One-time migration from revision 5. Subsequent loads exclusively
            -- use the independent config; no parameters are written to saves.
            local legacy = _allModParams and _allModParams[settings.modId]
            if not found and not err and type(legacy) == "table" and next(legacy) then
                params = settings.fromModParams(legacy)
                report("first-load settings migrated from legacy parameters")
            end
            report("external config at load: " .. (found and "loaded" or "defaults") .. (err and "; " .. err or ""))
            local snapshotOk, snapshotError = pcall(function()
                local snapshotId = api.res.genericRep.find("xiaom_global_tuning::/load_settings.res")
                if not snapshotId or snapshotId < 0 then error("load snapshot resource unavailable") end
                local snapshot = api.res.genericRep.getAsTable(snapshotId)
                snapshot.data = {version = 1, params = params}
                if api.res.genericRep.setAsTable(snapshotId, snapshot) == false then error("load snapshot rejected") end
            end)
            if not snapshotOk then report("load snapshot: " .. tostring(snapshotError)) end
            local passengerId = api.res.cargoTypeRep.getPassengerCargoTypeId()
            local passengerName = api.res.cargoTypeRep.getName(passengerId)
            local count, failures = {}, 0
            local function transform(rep, id, kind, fn)
                local ok, err = pcall(function()
                    local resource = rep.getAsTable(id)
                    if fn(resource) then
                        if rep.setAsTable(id, resource) == false then error("setAsTable rejected resource") end
                        count[kind] = (count[kind] or 0) + 1
                    end
                end)
                if not ok then
                    failures = failures + 1
                    if failures <= 10 then report(kind .. " " .. tostring(rep.getName(id)) .. ": " .. tostring(err)) end
                end
            end
            local function classify(set)
                -- getAsTable returns a serialized table; cargo APIs require a native CargoTypeSet.
                local native = api.type.CargoTypeSet.new()
                native.cargoClassesIncluded = set.cargoClassesIncluded or {}
                native.cargoClassesExcluded = set.cargoClassesExcluded or {}
                native.cargoTypesIncluded = set.cargoTypesIncluded or {}
                native.cargoTypesExcluded = set.cargoTypesExcluded or {}
                return api.res.cargoTypeRep.hasCargoType(native, passengerId),
                    api.res.cargoTypeRep.hasCargoType(native, passengerId, true)
            end
            api.res.modelRep.forEachModelWithMetadata("transportVehicle", function(name)
                local id = api.res.modelRep.find(name)
                transform(api.res.modelRep, id, "vehicles", function(model)
                    return core.model(model, params, classify, passengerName)
                end)
            end)
            for id in pairs(api.res.cargoTypeRep.getAll(true)) do
                transform(api.res.cargoTypeRep, id, "cargo", function(cargo)
                    return core.cargo(cargo, id == passengerId and params.passengerLoading or params.freightLoading)
                end)
            end
            if params.vehicleSpeed ~= 1 then
                for id in pairs(api.res.streetTemplateRep.getAll(true)) do
                    transform(api.res.streetTemplateRep, id, "roads/tracks", function(template)
                        return core.street(template, params.vehicleSpeed)
                    end)
                end
                for _, item in ipairs({
                    {api.res.bridgeTypeRep, "bridges"}, {api.res.tunnelTypeRep, "tunnels"},
                    {api.res.railroadCrossingTypeRep, "crossings"},
                }) do
                    for id in pairs(item[1].getAll(true)) do
                        transform(item[1], id, item[2], function(section)
                            return core.section(section, params.vehicleSpeed)
                        end)
                    end
                end
            end
            report(string.format("loaded: vehicles=%d cargo=%d roads/tracks=%d bridges=%d tunnels=%d crossings=%d errors=%d",
                count.vehicles or 0, count.cargo or 0, count["roads/tracks"] or 0,
                count.bridges or 0, count.tunnels or 0, count.crossings or 0, failures))
        end,
    }
end
