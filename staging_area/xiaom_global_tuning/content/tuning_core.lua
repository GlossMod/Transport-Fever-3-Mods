-- Pure resource-table transforms. Engine cargo-set resolution is supplied by the caller.
local core = {}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end

local function positive(value)
    return type(value) == "number" and value > 0 and value < math.huge
end

local function scale(target, key, multiplier, integer)
    local old = target and target[key]
    if multiplier == 1 or not positive(old) then return false end
    local value = old * multiplier
    if integer then value = math.max(1, math.floor(value + 0.5)) end
    if value == old then return false end
    target[key] = value
    return true
end

local function passengerConfig(config, passengerName)
    local result = copy(config)
    result.cargoEntry.cargoTypeSet = {
        cargoClassesIncluded = {}, cargoClassesExcluded = {},
        cargoTypesIncluded = {passengerName}, cargoTypesExcluded = {},
    }
    return result
end

local function freightConfig(config, passengerName)
    local result = copy(config)
    local set = result.cargoEntry.cargoTypeSet
    set.cargoTypesExcluded = set.cargoTypesExcluded or {}
    for _, name in ipairs(set.cargoTypesExcluded) do
        if name == passengerName then return result end
    end
    set.cargoTypesExcluded[#set.cargoTypesExcluded + 1] = passengerName
    return result
end

function core.model(model, params, classify, passengerName)
    local metadata = model.metadata
    local tv = metadata and metadata.transportVehicle
    if not tv then return false end
    local changed, hasFreight = false, false
    for _, compartment in ipairs(tv.compartments or {}) do
        local configs = {}
        for _, config in ipairs(compartment.loadConfigs or {}) do
            local entry = config.cargoEntry
            local passengers, freight = false, false
            if entry and entry.cargoTypeSet then
                passengers, freight = classify(entry.cargoTypeSet)
            end
            hasFreight = hasFreight or freight
            if passengers and freight and positive(entry.capacity)
                and params.passengerCapacity ~= params.freightCapacity then
                -- These remain alternatives in ONE compartment, not two additional stocks.
                local passenger = passengerConfig(config, passengerName)
                local goods = freightConfig(config, passengerName)
                scale(passenger.cargoEntry, "capacity", params.passengerCapacity, true)
                scale(goods.cargoEntry, "capacity", params.freightCapacity, true)
                configs[#configs + 1] = passenger
                configs[#configs + 1] = goods
                changed = true
            else
                if entry then
                    local factor = passengers and params.passengerCapacity
                        or (freight and params.freightCapacity or 1)
                    changed = scale(entry, "capacity", factor, true) or changed
                end
                configs[#configs + 1] = config
            end
        end
        if changed then compartment.loadConfigs = configs end
    end
    for _, key in ipairs({"landVehicle", "waterVehicle", "airVehicle"}) do
        local vehicle = metadata[key]
        if vehicle then
            changed = scale(vehicle, "topSpeed", params.vehicleSpeed) or changed
            if hasFreight then
                changed = scale(vehicle, "weightMaxPayload", params.freightWeight) or changed
            end
        end
    end
    if tv.carrier == "RAIL" and metadata.landVehicle then
        for _, engine in ipairs(metadata.landVehicle.engines or {}) do
            changed = scale(engine, "power", params.railTraction) or changed
            changed = scale(engine, "tractiveEffort", params.railTraction) or changed
        end
    end
    return changed
end

local roadModes = {
    CAR = true, BUS = true, TRUCK = true, TRAM = true, ELECTRIC_TRAM = true,
    TRAIN = true, ELECTRIC_TRAIN = true, TRAM_TRACK = true, ELECTRIC_TRAM_TRACK = true,
}
local function hasMode(modes, allowed)
    for key, value in pairs(modes or {}) do
        if allowed[value] or (value == true and allowed[key]) then return true end
    end
    return false
end

function core.street(template, multiplier)
    if multiplier == 1 then return false end
    local changed, transportLane = false, false
    for _, lane in ipairs(template.laneConfigs or {}) do
        if hasMode(lane.transportModes, roadModes) then
            transportLane = true
            changed = scale(lane, "speed", multiplier) or changed
        end
    end
    if transportLane and template.roadType == "TRACK" and template.speedCoeffs then
        -- a * (radius + b)^c: only multiply a, preserving radius and exponent.
        changed = scale(template.speedCoeffs, 1, multiplier) or changed
    end
    return changed
end

function core.section(section, multiplier)
    local carriers = section.carriers
    if carriers and next(carriers) and not hasMode(carriers, {ROAD = true, RAIL = true, TRAM = true}) then
        return false
    end
    return scale(section, "speedLimit", multiplier)
end

function core.cargo(cargo, multiplier)
    return scale(cargo, "loadSpeedFactor", multiplier)
end

function core.dayDuration(factor, defaultDuration)
    if factor == 0 then return 0 end
    return math.max(1, math.floor(defaultDuration / factor + 0.5))
end

return core
