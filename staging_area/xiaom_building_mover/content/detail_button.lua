local react = ug_require "::/gui/main/react.lua"
local entityWindow = ug_require "::/gui/entity_window/entity_window_util.tl"
local core = ug_require "xiaom_building_mover::/mover_core.lua"
local ui = ug_require "xiaom_building_mover::/mover_ui.lua"
local details = {}
local installed = false
local configureEntities = setmetatable({}, {__mode = "k"})
local originalBar = entityWindow.ActionButtonBar

-- CallOriginalRecipe creates a recipe node, not a layout. Register its wrapper
-- so the renderer can resolve the original bar's layout through this node.
local ActionBar = react.RegisterWrapperRecipe("XiaomBuildingMoverActionBar", originalBar, function(param)
    -- Preserve the original bar's focus/navigation, secondary actions and styling.
    local updated = {}
    for key, value in pairs(param) do updated[key] = value end
    updated.primaryButtons = {}
    for _, action in ipairs(param.primaryButtons or {}) do
        updated.primaryButtons[#updated.primaryButtons + 1] = action
        local entity = action.onClick and configureEntities[action.onClick]
        if entity ~= nil and core.inspect(entity) then
            updated.primaryButtons[#updated.primaryButtons + 1] = {
                description = "移动",
                icon = "::/gui/line_vehicle_mgmt/icons/indicator_move_20@2x.tga",
                tag = "entityWindow.xiaomBuildingMover.move",
                onClick = function() ui.open(entity) end,
            }
        end
    end
    return react.CallOriginalRecipe(originalBar, updated)
end)

function details.install(replacementApi)
    if installed then return end
    -- ActionButtonBar has no entity argument. Capture the entity from the native
    -- configure callback factory, so pinned and merged windows target correctly.
    local makeConfigure = entityWindow.makeConfigureOnClickFunction
    entityWindow.makeConfigureOnClickFunction = function(entity)
        local callback = makeConfigure(entity)
        if callback then configureEntities[callback] = entity end
        return callback
    end
    replacementApi.ReplaceRecipe(originalBar, ActionBar)
    installed = true
    debugPrint("[xiaom_building_mover] detail move button registered")
end

return details
