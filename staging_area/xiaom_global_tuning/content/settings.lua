local settings = {}
settings.modId = "xiaom_global_tuning"
settings.multipliers = {0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 5, 10, 20, 50, 100}
settings.simulationSpeeds = {-1, 0, 1, 2, 4, 8, 16, 32, 64, 100}
settings.calendarSpeeds = {-1, 0, 0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 5, 10, 20, 50, 100}
settings.multiplierKeys = {
    "industryProduction", "freightCapacity", "freightWeight", "passengerCapacity",
    "freightLoading", "passengerLoading", "vehicleSpeed", "railTraction",
}

local function choice(value, choices, fallback)
    if type(value) == "number" then
        for _, candidate in ipairs(choices) do
            if value == candidate then return candidate end
        end
    end
    return fallback
end

function settings.normalize(params)
    params = type(params) == "table" and params or {}
    local result = {}
    for _, key in ipairs(settings.multiplierKeys) do
        result[key] = choice(params[key], settings.multipliers, 1)
    end
    result.simulationSpeed = choice(params.simulationSpeed, settings.simulationSpeeds, -1)
    result.calendarSpeed = choice(params.calendarSpeed, settings.calendarSpeeds, -1)
    return result
end

local function choicesFor(key)
    if key == "simulationSpeed" then return settings.simulationSpeeds end
    if key == "calendarSpeed" then return settings.calendarSpeeds end
    return settings.multipliers
end

-- Build 25533170's Mod settings UI deliberately omits ScriptParam.numbers.
-- Native modParams therefore store one-based option indices; GUI drafts and
-- resource transforms use the actual multiplier values instead.
function settings.fromModParams(params)
    local result = settings.normalize({})
    if type(params) ~= "table" then return result end
    for key in pairs(result) do
        local index = params[key]
        local choices = choicesFor(key)
        if type(index) == "number" and index >= 1 and index <= #choices and index % 1 == 0 then
            result[key] = choices[index]
        end
    end
    return result
end

function settings.toModParams(params)
    local result = {}
    for key, value in pairs(settings.normalize(params)) do
        for index, candidate in ipairs(choicesFor(key)) do
            if value == candidate then result[key] = index + 0.0; break end
        end
    end
    return result
end

return settings
