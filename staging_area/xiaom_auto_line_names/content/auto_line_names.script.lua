-- TF3 Build 25533170: GameScriptState:get/set, update + postUpdate.
-- Persistent state records ownership of names, never commands or API userdata.
local SCAN_TICKS = 15
local COMMAND_GRACE_SCANS = 4
local PREFIX = "[xiaom_auto_line_names] "

local function report(message)
    debugPrint(PREFIX .. message)
end

local function clean(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[\r\n\t]", " "):match("^%s*(.-)%s*$")
    if value == "" then return nil end
    return value
end

local function entityName(entity)
    if not entity or entity < 0 or not api.engine.entityExists(entity) then return nil end
    return clean(api.engine.util.getEntityName(entity))
end

local function stationForStop(stop)
    if not stop.stationGroup or stop.stationGroup < 0 then return nil end
    if not api.engine.entityExists(stop.stationGroup) then return nil end
    local group = api.engine.getComponent(stop.stationGroup, api.type.ComponentType.STATION_GROUP)
    if not group or not group.stations then return nil end
    -- Station/terminal indices in Line.Stop are zero based; Lua arrays start at 1.
    if stop.station and stop.station >= 0 then
        return group.stations[stop.station + 1]
    end
    return group.stations[1]
end

local function endpoints(line, stationTowns)
    local stops = line.stops
    if not stops or #stops < 2 then return nil end
    local first = stops[1]
    local last
    -- A closing copy of the first stop on a loop is not another destination.
    for index = #stops, 2, -1 do
        if stops[index].stationGroup ~= first.stationGroup then
            last = stops[index]
            break
        end
    end
    if not last then return nil end
    local firstStation, lastStation = stationForStop(first), stationForStop(last)
    if not firstStation or not lastStation then return nil end
    local firstTown, lastTown = stationTowns[firstStation], stationTowns[lastStation]
    local a = entityName(firstTown) or entityName(first.stationGroup)
    local b = entityName(lastTown) or entityName(last.stationGroup)
    if firstTown == lastTown or a == b then
        a = entityName(first.stationGroup) or a
        b = entityName(last.stationGroup) or b
    end
    if not a or not b then return nil end
    return a, b
end

local function cargoCatalog()
    local catalog = {}
    for id in pairs(api.res.cargoTypeRep.getAll(true)) do
        local cargo = api.res.cargoTypeRep.get(id)
        catalog[#catalog + 1] = {
            id = id,
            name = clean(cargo.name),
            order = cargo.order or id,
        }
    end
    table.sort(catalog, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return catalog
end

local function service(lineEntity, line, catalog, passengerId)
    local allowed, capacities = {}, {}
    local vehicleHasPassengers, vehicleHasGoods = false, false
    for _, stop in ipairs(line.stops) do
        local config = stop.stopConfig
        if config and config.load then
            for _, cargo in ipairs(catalog) do
                local index = cargo.id + 1
                local maximum = config.maxLoad and config.maxLoad[index]
                if config.load[index] and (maximum == nil or maximum > 0) then
                    allowed[cargo.id] = true
                end
            end
        end
    end
    for _, vehicleEntity in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(lineEntity)) do
        local vehicle = api.engine.getComponent(vehicleEntity, api.type.ComponentType.TRANSPORT_VEHICLE)
        local config = vehicle and vehicle.config
        if config and config.capacities then
            for _, cargo in ipairs(catalog) do
                if (config.capacities[cargo.id + 1] or 0) > 0 then
                    capacities[cargo.id] = true
                    if cargo.id == passengerId then
                        vehicleHasPassengers = true
                    else
                        vehicleHasGoods = true
                    end
                end
            end
        end
    end
    local names, seenNames = {}, {}
    for _, cargo in ipairs(catalog) do
        if cargo.id ~= passengerId and allowed[cargo.id]
            and (not vehicleHasGoods or capacities[cargo.id]) then
            local name = cargo.name or "未知物品"
            if not seenNames[name] then
                names[#names + 1] = name
                seenNames[name] = true
            end
        end
    end
    if vehicleHasGoods then
        return "goods", #names > 0 and table.concat(names, "、") or "待定"
    end
    if vehicleHasPassengers then return "passengers" end
    if #names > 0 then return "goods", table.concat(names, "、") end
    if allowed[passengerId] then return "passengers" end

    -- Empty load filters on a new, incomplete line cannot reveal the item yet.
    local passengerStations, cargoStations = false, false
    for _, stop in ipairs(line.stops) do
        local station = stationForStop(stop)
        if station and api.engine.entityExists(station) then
            passengerStations = passengerStations or api.engine.util.station.isStationOfType(station, false)
            cargoStations = cargoStations or api.engine.util.station.isStationOfType(station, true)
        end
    end
    if cargoStations and not passengerStations then return "goods", "待定" end
    if passengerStations and not cargoStations then return "passengers" end
    return nil
end

local function makeName(entity, line, stationTowns, catalog, passengerId)
    local a, b = endpoints(line, stationTowns)
    if not a then return nil end
    local kind, items = service(entity, line, catalog, passengerId)
    if kind == "passengers" then return "[客运] " .. a .. "-" .. b end
    if kind == "goods" then return "[货运] " .. items .. "-" .. a .. "-" .. b end
    return nil
end

local function scan(state)
    local saved = state:get() or {}
    saved.lines = saved.lines or {}
    saved.version = 1
    local player = api.engine.util.getPlayer()
    if not player or player < 0 then return {} end
    local lines = api.engine.system.lineSystem.getLinesForPlayer(player)
    if not saved.initialized then
        -- First activation in an existing save is a baseline, not a bulk rename.
        for _, entity in ipairs(lines) do
            saved.lines[tostring(entity)] = { managed = false }
        end
        saved.initialized = true
        saved.ticks = 0
        state:set(saved)
        report("initialized; existing line names preserved")
        return {}
    end
    saved.ticks = (saved.ticks or 0) + 1
    if saved.ticks < SCAN_TICKS then
        state:set(saved)
        return {}
    end
    saved.ticks = 0
    local live, operations = {}, {}
    local catalog = cargoCatalog()
    local passengerId = api.res.cargoTypeRep.getPassengerCargoTypeId()
    local stationTowns = api.engine.system.stationSystem.getStation2TownMap()
    for _, entity in ipairs(lines) do
        local key = tostring(entity)
        live[key] = true
        local current = entityName(entity)
        local entry = saved.lines[key]
        if not entry and current then
            entry = { managed = true, lastName = current }
            saved.lines[key] = entry
        end
        if entry and entry.managed and current then
            if entry.pendingName then
                if current == entry.pendingName then
                    entry.lastName = current
                    entry.pendingName = nil
                    entry.pendingScans = nil
                elseif current == entry.lastName then
                    -- Command dispatch can be asynchronous; do not mistake a delay for a manual rename.
                    entry.pendingScans = (entry.pendingScans or 0) + 1
                    if entry.pendingScans >= COMMAND_GRACE_SCANS then
                        entry.pendingName = nil
                        entry.pendingScans = nil
                    end
                else
                    entry.managed = false
                    entry.pendingName = nil
                end
            elseif current ~= entry.lastName then
                entry.managed = false
            end
            if entry.managed and not entry.pendingName then
                local line = api.engine.getComponent(entity, api.type.ComponentType.LINE)
                if line then
                    local ok, name = pcall(makeName, entity, line, stationTowns, catalog, passengerId)
                    if ok then
                        entry.errorReported = nil
                        if name and name ~= current then
                            operations[#operations + 1] = { entity = entity, oldName = current, name = name }
                        end
                    elseif not entry.errorReported then
                        report("cannot name line " .. key .. ": " .. tostring(name))
                        entry.errorReported = true
                    end
                end
            end
        end
    end
    for key in pairs(saved.lines) do
        if not live[key] then saved.lines[key] = nil end
    end
    state:set(saved)
    return operations
end

local function apply(state, operations)
    if not operations or #operations == 0 then return end
    local saved = state:get()
    if not saved or not saved.lines then return end
    local ready = {}
    local player = api.engine.util.getPlayer()
    for _, operation in ipairs(operations) do
        local entry = saved.lines[tostring(operation.entity)]
        if entry and entry.managed and not entry.pendingName
            and api.engine.entityExists(operation.entity) then
            local owner = api.engine.getComponent(operation.entity, api.type.ComponentType.PLAYER_OWNED)
            local current = entityName(operation.entity)
            if owner and owner.player == player and current == operation.oldName then
                entry.pendingName = operation.name
                entry.pendingScans = 0
                ready[#ready + 1] = operation
            elseif current and current ~= entry.lastName then
                entry.managed = false
            end
        end
    end
    -- Commit intent before dispatch so saves and delayed commands stay consistent.
    state:set(saved)
    for _, operation in ipairs(ready) do
        local ok, errorMessage = pcall(function()
            api.cmd.sendCommand(api.cmd.makeEntitySetNameCmd(operation.entity, operation.name))
        end)
        if not ok then
            report("rename command failed for " .. tostring(operation.entity) .. ": " .. tostring(errorMessage))
        end
    end
end

function data()
    return {
        update = function(_captureParams, state, _dt)
            return scan(state)
        end,
        postUpdate = function(_captureParams, state, _dt, updateResult)
            apply(state, updateResult)
        end,
    }
end
