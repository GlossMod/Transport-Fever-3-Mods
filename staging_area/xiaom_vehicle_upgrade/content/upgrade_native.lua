local core = ug_require "xiaom_vehicle_upgrade::/upgrade_core.lua"
local store = ug_require "::/gui/line_vehicle_mgmt/vehicle_store_util.tl"
local vehicleUtil = ug_require "::/gui/line_vehicle_mgmt/vehicle_util.tl"
local cargoUtil = ug_require "::/gui/main/cargo_util.tl"
local native = {}
local catalog, byKey, byModel, byMu, pending, cursor
local lastPurchaseError

local function set(array)
    local result = {}
    for _, value in ipairs(array or {}) do result[value] = true end
    return result
end

local function enumContains(map, group, key)
    local value = api.type.enum[group][key]
    return value ~= nil and map[value] == true
end

local function modelParts(repId, multipleUnit)
    if not multipleUnit then return {{modelId = repId, forward = true}} end
    local result = {}
    for _, part in ipairs(api.res.multipleUnitRep.get(repId).vehicles) do
        local id = api.res.modelRep.find(part.name)
        if id < 0 then error("Missing multiple unit part: " .. part.name) end
        result[#result + 1] = {modelId = id, forward = part.forward}
    end
    return result
end

local function describe(repId, multipleUnit, path)
    local parts = modelParts(repId, multipleUnit)
    local data = store.makeVehicleData(repId, multipleUnit)
    local image = store.getVehicleNameAndIcons(repId, multipleUnit, true)
    local first = api.res.modelRep.get(parts[1].modelId)
    local firstTv = first.metadata.transportVehicle
    if not firstTv then return nil end
    local modes, tags, hasEngine, electric = {}, {}, false, false
    for _, part in ipairs(parts) do
        -- The native UI exposes the read-only get API, like the original store.
        local m = api.res.modelRep.get(part.modelId)
        local tv = m.metadata.transportVehicle
        if not tv or tv.carrier ~= firstTv.carrier then return nil end
        for _, tag in ipairs(tv.filterTags or {}) do tags[tag] = true end
        for _, mode in ipairs(tv.transportModes or {}) do modes[mode] = true end
        local lv = m.metadata.landVehicle
        if lv then
            for _, engine in ipairs(lv.engines or {}) do
                hasEngine = true
                if engine.type == api.type.enum.VehicleEngineType.ELECTRIC then electric = true end
            end
        else
            hasEngine = true
        end
    end
    if multipleUnit then tags = set(api.res.multipleUnitRep.get(repId).filterTags) end
    electric = electric or enumContains(modes, "TransportMode", "ELECTRIC_TRAIN") or enumContains(modes, "TransportMode", "ELECTRIC_TRAM")
    local physicalType = "standard"
    if first.metadata.airVehicle then
        physicalType = first.metadata.airVehicle.isHelicopter and "helicopter" or "aircraft"
    elseif data.isLightrail then physicalType = "lightrail" end
    local cargo, passenger = false, false
    local passengerId = cargoUtil.getPassengerCargoTypeId()
    local capacities = {}
    for id, amount in pairs(data.allCargoTypes or {}) do
        if amount > 0 then
            capacities[id] = amount
            if id == passengerId then passenger = true else cargo = true end
        end
    end
    local purpose = passenger and (cargo and "mixed" or "passenger") or (cargo and "freight" or "engine")
    local role = purpose .. (hasEngine and ":powered" or ":unpowered")
    return {
        key = (multipleUnit and "mu:" or "model:") .. tostring(repId),
        repId = repId, path = path, multipleUnit = multipleUnit,
        parts = parts, name = image.name or path, icons = image.icons or {},
        carrier = firstTv.carrier, role = role, physicalType = physicalType,
        physicalModes = core.key(modes), tags = tags, capacities = capacities,
        hasEngine = hasEngine, electric = electric,
        compareTraction = hasEngine and (firstTv.carrier == api.type.enum.Carrier.RAIL or firstTv.carrier == api.type.enum.Carrier.TRAM),
        yearFrom = data.yearFrom or 0, yearTo = data.yearTo or 0,
        speed = data.speed or 0, power = data.power or 0,
        traction = data.tractiveEffort or 0, length = data.length or 0,
        capacity = data.totalCapacity or 0, price = data.price or 0,
    }
end

function native.resetCatalog()
    catalog, byKey, byModel, byMu, pending, cursor = {}, {}, {}, {}, {}, 1
    lastPurchaseError = nil
    -- getAll defaults to visible resources, excluding abstract variant parents.
    api.res.modelRep.forEachModelWithMetadata("transportVehicle", function(path)
        local id = api.res.modelRep.find(path)
        if id >= 0 and api.res.modelRep.isVisible(id) then
            pending[#pending + 1] = {id = id, path = path, mu = false}
        end
    end)
    for id, path in pairs(api.res.multipleUnitRep.getAll()) do
        pending[#pending + 1] = {id = id, path = path, mu = true}
    end
    table.sort(pending, function(a, b)
        if a.mu ~= b.mu then return not a.mu end
        return a.id < b.id
    end)
end

function native.catalogStep(amount)
    if not pending then native.resetCatalog() end
    for _ = 1, amount or 32 do
        local item = pending[cursor]
        if not item then return true end
        cursor = cursor + 1
        local ok, data = pcall(function()
            if not item.mu then
                local tv = api.res.modelRep.get(item.id).metadata.transportVehicle
                if not tv then return nil end
                -- Same exclusion as the native store for variant parent models.
                if tv.groupFileName and tv.groupFileName ~= "" and #(tv.filterTags or {}) == 0 then return nil end
            end
            return describe(item.id, item.mu, item.path)
        end)
        if ok and data then
            catalog[#catalog + 1] = data; byKey[data.key] = data
            if item.mu then byMu[item.path] = data else byModel[item.id] = data end
        elseif not ok then debugPrint("[xiaom_vehicle_upgrade] catalog skipped " .. item.path .. ": " .. tostring(data)) end
    end
    return cursor > #pending
end

function native.catalog() return catalog or {}, byKey or {} end
function native.catalogReady() return pending ~= nil and cursor > #pending end
function native.catalogProgress() return math.min((cursor or 1) - 1, #(pending or {})), #(pending or {}) end
function native.year() return api.engine.util.getYear() end
function native.balance() return api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer()) end
function native.entities()
    local result = api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE,
        {requireOwnedByPlayer = api.engine.util.getPlayer()})
    table.sort(result)
    return result
end

function native.restrictions(gameCtx)
    local filters = gameCtx and gameCtx.filters and gameCtx.filters:get() or {}
    local vf = filters.vehicleFilter or {}
    return {enabled = set(vf.enabledVehicles), disabled = set(vf.disabledVehicles)}, filters.protectedEntities or {}
end

local function copyPart(part)
    local result = {
        modelId = part.part.modelId, reversed = part.part.reversed, purchaseTime = part.purchaseTime,
        maintenanceChange = part.maintenanceChange, maintenanceState = part.maintenanceState,
        color = {part.part.color.x, part.part.color.y, part.part.color.z}, loads = {}, auto = {},
        value = api.engine.util.vehicle.getPartPrice(part),
    }
    for i, config in ipairs(part.part.compartment2loadConfig) do
        result.loads[i] = {index = config.loadConfigIndex, cargo = config.cargoTypeId}
        result.auto[i] = part.autoLoadConfig[i] == true
    end
    return result
end

local function lookupModel(id)
    if not byModel[id] then
        byModel[id] = describe(id, false, api.res.modelRep.getName(id))
        if byModel[id] then byKey[byModel[id].key] = byModel[id] end
    end
    return byModel[id]
end

local function groupReversed(unit)
    local specifications = unit.old.parts
    if #specifications ~= #unit.parts then return nil end
    local normal, reversed = true, true
    for index, part in ipairs(unit.parts) do
        local forward = specifications[index]
        local backward = specifications[#specifications - index + 1]
        normal = normal and part.modelId == forward.modelId and part.reversed == (not forward.forward)
        reversed = reversed and part.modelId == backward.modelId and part.reversed == backward.forward
    end
    if normal then return false end
    if reversed then return true end
end

function native.snapshot(entity)
    if not api.engine.entityExists(entity) then return nil, "载具已被出售或删除" end
    local owned = api.engine.getComponent(entity, api.type.ComponentType.PLAYER_OWNED)
    if not owned or owned.player ~= api.engine.util.getPlayer() then return nil, "载具已不属于当前公司" end
    local tv = api.engine.getComponent(entity, api.type.ComponentType.TRANSPORT_VEHICLE)
    if not tv then return nil, "找不到载具" end
    local lineEntity = tv.line
    local filtered, line = {}, nil
    if lineEntity >= 0 and api.engine.entityExists(lineEntity) then
        line = api.engine.getComponent(lineEntity, api.type.ComponentType.LINE)
        if line and line.customFilters then
            for _, stop in ipairs(line.stops) do
                for i, allow in ipairs(stop.stopConfig.load) do
                    if allow then filtered[i - 1] = true end
                end
            end
        end
    end
    local result = {
        entity = entity, name = api.engine.util.getEntityName(entity), carrier = tv.carrier,
        line = lineEntity, depot = tv.depot, lineName = line and api.engine.util.getEntityName(lineEntity) or "未分配线路",
        units = {}, loaded = {}, filterSignature = core.key(filtered),
        depreciated = api.engine.util.vehicle.getDepreciatedValue(entity),
    }
    -- The engine exposes cargo IDs through a 1-based array, with ID = index-1.
    for i in ipairs(tv.config.capacities) do
        local cargo = i - 1
        local count = api.engine.system.simEntityAtVehicleSystem.getVehicleSimEntitiesCountForCargoType(entity, cargo)
        if count > 0 then result.loaded[cargo] = count end
    end
    local config = tv.transportVehicleConfig
    local groups = {}
    for _, count in ipairs(config.vehicleGroups) do groups[#groups + 1] = count end
    if #groups == 0 then for _ in ipairs(config.vehicles) do groups[#groups + 1] = 1 end end
    local offset = 1
    for index, count in ipairs(groups) do
        if count < 1 or offset + count - 1 > #config.vehicles then return nil, "原编组数据无效" end
        local muName = config.muFileNames[index]
        local old
        if muName and muName ~= "" then
            old = byMu[muName]
            if not old then
                local id = api.res.multipleUnitRep.find(muName)
                if id >= 0 then old = describe(id, true, muName); byMu[muName] = old; byKey[old.key] = old end
            end
            if not old then return nil, "找不到原固定编组车型" end
        elseif count == 1 then old = lookupModel(config.vehicles[offset].part.modelId)
        else return nil, "未命名组合不能安全逐节升级" end
        if not old then return nil, "原车型缺少载具元数据" end
        local unit = {index = index, offset = offset, count = count, old = old, parts = {}, muName = muName or "", manualCargos = {}}
        local active = {}
        for i = offset, offset + count - 1 do
            local part = copyPart(config.vehicles[i]); unit.parts[#unit.parts + 1] = part
            for compartmentIndex, lc in ipairs(part.loads) do
                if lc.cargo >= 0 then
                    active[lc.cargo] = true
                    if not part.auto[compartmentIndex] then unit.manualCargos[lc.cargo] = true end
                end
            end
        end
        unit.reversed = groupReversed(unit)
        if unit.reversed == nil then return nil, "原固定编组的部件或朝向与车型定义不一致，无法安全升级" end
        -- A loaded cargo without a resolved per-compartment config is still
        -- relevant. Normal mixed trains use their own current compartment IDs.
        if next(active) == nil then for cargo in pairs(result.loaded) do active[cargo] = true end end
        unit.purpose, unit.uncertain = core.purpose(old, unit.parts, {active = active, filtered = filtered})
        unit.groupKey = old.key .. "/" .. core.key(unit.purpose)
        result.units[#result.units + 1] = unit
        offset = offset + count
    end
    if offset ~= #config.vehicles + 1 then return nil, "原编组数量不一致" end
    result.signature = core.signature(result)
    return result
end

local function makeRetained(part)
    local result = api.type.TransportVehiclePart.new()
    result.part.modelId = part.modelId; result.part.reversed = part.reversed
    result.part.color = api.type.Vec3f.new(part.color[1], part.color[2], part.color[3])
    local configs = {}
    for _, value in ipairs(part.loads) do
        local lc = api.type.LoadConfig.new(); lc.loadConfigIndex = value.index; lc.cargoTypeId = value.cargo
        configs[#configs + 1] = lc
    end
    result.part.compartment2loadConfig = configs; result.autoLoadConfig = core.copy(part.auto)
    result.purchaseTime = part.purchaseTime; result.maintenanceState = part.maintenanceState
    result.maintenanceChange = part.maintenanceChange
    return result
end

local function compartmentOptions(compartment, purpose)
    local options = {}
    for index, load in ipairs(compartment.loadConfigs) do
        api.res.cargoTypeRep.forEachCargoType(load.cargoEntry.cargoTypeSet, function(id)
            if purpose[id] then options[#options + 1] = {cargo = id, capacity = load.cargoEntry.capacity, loadIndex = index - 1} end
        end)
    end
    return options
end

function native.preservesManual(unit, target)
    if not next(unit.manualCargos or {}) then return true end
    local slots = {}
    for _, specification in ipairs(target.parts) do
        local tv = api.res.modelRep.get(specification.modelId).metadata.transportVehicle
        for _, compartment in ipairs(tv.compartments) do
            slots[#slots + 1] = {scope = unit.index, options = compartmentOptions(compartment, unit.purpose)}
        end
    end
    return core.allocate(slots, {}, nil, {[unit.index] = unit.manualCargos}) ~= nil
end

function native.build(snapshot, changes)
    local config = api.type.TransportVehicleConfig.new()
    local parts, groups, muNames, slots, quantities, coverage = {}, {}, {}, {}, {}, {}
    local time = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
    local hasEngine = false
    for _, unit in ipairs(snapshot.units) do
        local target = changes[unit.index] and byKey[changes[unit.index]] or unit.old
        if not target then return nil, "目标车型已不可用" end
        hasEngine = hasEngine or target.hasEngine
        local replaced = target.key ~= unit.old.key
        if replaced then coverage[unit.index] = unit.manualCargos end
        local groupParts = {}
        if replaced then
            local reverse = unit.reversed
            for targetIndex = 1, #target.parts do
                local sourceIndex = reverse and (#target.parts - targetIndex + 1) or targetIndex
                local specification = target.parts[sourceIndex]
                local color = unit.parts[math.min(targetIndex, #unit.parts)].color
                local forward = specification.forward
                if reverse then forward = not forward end
                local part = vehicleUtil.makePart(specification.modelId, forward, api.type.Vec3f.new(color[1], color[2], color[3]))
                part.purchaseTime = time
                local auto = {}; for i in ipairs(part.part.compartment2loadConfig) do auto[i] = true end
                part.autoLoadConfig = auto
                groupParts[#groupParts + 1] = part
                quantities[specification.modelId] = (quantities[specification.modelId] or 0) + 1
            end
        else
            for _, part in ipairs(unit.parts) do groupParts[#groupParts + 1] = makeRetained(part) end
        end
        groups[#groups + 1] = #groupParts
        muNames[#muNames + 1] = target.multipleUnit and target.path or ""
        for _, part in ipairs(groupParts) do
            parts[#parts + 1] = part
            local tv = api.res.modelRep.get(part.part.modelId).metadata.transportVehicle
            for compartmentIndex, compartment in ipairs(tv.compartments) do
                local options
                if replaced then
                    local required = core.copy(unit.purpose)
                    for id in pairs(snapshot.loaded) do if target.capacities[id] then required[id] = true end end
                    options = compartmentOptions(compartment, required)
                    -- Retain a useful empty cargo configuration, not just load 0.
                    if #options > 0 then
                        table.sort(options, function(a, b)
                            if a.capacity ~= b.capacity then return a.capacity > b.capacity end
                            if a.cargo ~= b.cargo then return a.cargo < b.cargo end
                            return a.loadIndex < b.loadIndex
                        end)
                        local lc = part.part.compartment2loadConfig[compartmentIndex]
                        lc.loadConfigIndex = options[1].loadIndex
                        lc.cargoTypeId = unit.uncertain and -1 or options[1].cargo
                        local configs = part.part.compartment2loadConfig; configs[compartmentIndex] = lc
                        part.part.compartment2loadConfig = configs
                    end
                else
                    local lc = part.part.compartment2loadConfig[compartmentIndex]
                    options = {}
                    local metadata = compartment.loadConfigs[lc.loadConfigIndex + 1]
                    if metadata and lc.cargoTypeId >= 0 then
                        options[1] = {cargo = lc.cargoTypeId, capacity = metadata.cargoEntry.capacity, loadIndex = lc.loadConfigIndex}
                    elseif metadata then
                        options = compartmentOptions({loadConfigs = {metadata}}, snapshot.loaded)
                        for _, option in ipairs(options) do option.loadIndex = lc.loadConfigIndex end
                    end
                end
                slots[#slots + 1] = {options = options, part = part, compartmentIndex = compartmentIndex,
                    replaced = replaced, manualCargos = unit.manualCargos, scope = replaced and unit.index or nil}
            end
        end
    end
    if not hasEngine then return nil, "编组必须包含动力载具" end
    local allocation, errorMessage = core.allocate(slots, snapshot.loaded, nil, coverage)
    if not allocation then return nil, errorMessage end
    for index, option in pairs(allocation) do
        local slot = slots[index]
        if slot.replaced then
            local loads = slot.part.part.compartment2loadConfig
            local lc = loads[slot.compartmentIndex]
            lc.loadConfigIndex = option.loadIndex; lc.cargoTypeId = option.cargo
            loads[slot.compartmentIndex] = lc; slot.part.part.compartment2loadConfig = loads
        end
    end
    for _, slot in ipairs(slots) do
        if slot.replaced then
            local lc = slot.part.part.compartment2loadConfig[slot.compartmentIndex]
            local auto = slot.part.autoLoadConfig
            auto[slot.compartmentIndex] = not (slot.manualCargos or {})[lc.cargoTypeId]
            slot.part.autoLoadConfig = auto
        end
    end
    config.vehicles = parts; config.vehicleGroups = groups; config.muFileNames = muNames
    return config, nil, quantities
end

function native.missionError(quantities, actuallyBuy)
    local ok, value = pcall(function()
        return api.gui.fireGuiScriptEvent("vehicleStore", "mission.buyVehicle",
            {modelId2quantity = quantities, actuallyBuy = actuallyBuy == true})
    end)
    if not ok then
        local detail = "actuallyBuy=" .. tostring(actuallyBuy == true) .. ": " .. tostring(value)
        if detail ~= lastPurchaseError then
            debugPrint("[xiaom_vehicle_upgrade] purchase restriction check failed " .. detail)
            lastPurchaseError = detail
        end
        return "购买限制检查暂时失败，请重新扫描（具体原因已记录到游戏日志）"
    end
    lastPurchaseError = nil
    if type(value) == "string" and value ~= "" then return value end
end

function native.send(entity, config, callback)
    -- Use native payment semantics; no separate sell/buy or manual refunds.
    local cmd = api.cmd.makeVehicleReplaceCmd(entity, config)
    api.cmd.sendCommand(cmd, function(_, success) callback(success == true) end)
end

function native.cargoName(id) return cargoUtil.getCargoNameById(id) end
function native.carrierName(carrier)
    for _, entry in ipairs({{"ROAD", "道路"}, {"RAIL", "列车"}, {"TRAM", "电车"}, {"WATER", "船舶"}, {"AIR", "航空"}}) do
        if carrier == api.type.enum.Carrier[entry[1]] then return entry[2] end
    end
    return "其他"
end

return native
