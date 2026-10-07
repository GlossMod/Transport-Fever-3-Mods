local collision = {}

local buildingRoots = {
    buildings = true,
    depots = true,
    industries = true,
    landmarks = true,
    stations = true,
    warehouses = true,
}

-- Match TF3 resource paths, including building assets used by constructions.
-- Do not remove boundingInfo: the renderer and selection still need it.
function collision.isBuildingModel(name, model)
    if type(name) ~= "string" or type(model) ~= "table" then return false end
    local metadata = model.metadata or {}
    if metadata.transportVehicle or metadata.car or metadata.person
        or metadata.animal or metadata.tree or metadata.rock then
        return false
    end
    local path = name:gsub("\\", "/"):gsub("^[^:]*::/?", ""):gsub("^/", "")
    path = path:gsub("^assets/", "")
    return buildingRoots[path:match("^([^/]+)/")] == true
end

function collision.removeModelCollider(model)
    if type(model.collider) == "table" and model.collider.type == "NONE" then
        return false
    end
    model.collider = {
        type = "NONE",
        params = {},
        transf = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1},
    }
    return true
end

-- Run after constructWithModules, including its terminateConstructionHook:
-- modules and late hooks can append colliders after the main update function.
function collision.clearConstruction(result)
    if type(result) ~= "table" then return result end
    if result.colliders ~= nil then result.colliders = {} end
    for _, sub in pairs(result.subconstructions or {}) do
        if type(sub) == "table" then sub.colliders = {} end
    end

    if result.slots or result.slotConfig then
        result.slotConfig = result.slotConfig or {}
        for _, config in pairs(result.slotConfig) do
            if type(config) == "table" then config.skipCollisionCheck = true end
        end
        for _, slot in pairs(result.slots or {}) do
            if type(slot) == "table" and type(slot.type) == "string" then
                local config = result.slotConfig[slot.type]
                if config == nil then
                    config = {}
                    result.slotConfig[slot.type] = config
                end
                config.skipCollisionCheck = true
            end
        end
    end
    return result
end

return collision
