local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local statistics = ug_require "::/gui/statistics/statistics.tl"
local originalVehicles = ug_require "::/gui/statistics/statistic_vehicles.tl"
local ui = ug_require "xiaom_vehicle_upgrade::/upgrade_ui.lua"
local entry = {}
local gameCtx, installed
local originalEntry = statistics.StatisticsEntryPoint

local EntryPoint = react.RegisterWrapperRecipe("XiaomUpgradeStatisticsEntryPoint", originalEntry, function(param)
    gameCtx = param.gameCtx
    return react.CallOriginalRecipe(originalEntry, param)
end)

-- VehiclesStatistic is a normal component recipe. Keep that native root kind:
-- wrapping BoxLayout directly creates a layout root and causes a native
-- downcast failure when the statistics tab mounts or reuses the component.
local VehicleTab = react.RegisterRecipe("XiaomUpgradeVehicleTab", function(param)
    return builtin.BoxLayout {
        meta = {class = "upgrade-vehicle-tab"}, orientation = builtin.type.Orientation.Vertical,
        children = {
            builtin.BoxLayout {meta = {class = "upgrade-tab-toolbar"}, orientation = builtin.type.Orientation.Horizontal,
                children = {builtin.Button {
                    meta = {id = "xiaom-vehicle-upgrade-button", class = "primary", tooltip = "扫描全公司载具，预览并选择升级目标"},
                    content = builtin.TextView {text = "升级载具", useUnicodeCompatibilityFont = true},
                    onClick = function() ui.open(gameCtx) end,
                }},
            },
            -- A normal registered recipe materializes as a component, even
            -- when its body returns a layout. Component.layout requires a
            -- native layout node; embed the untouched recipe as its child.
            builtin.Component {meta = {class = "upgrade-original-list"}, layout = builtin.BoxLayout {
                orientation = builtin.type.Orientation.Vertical,
                children = {react.CallOriginalRecipe(originalVehicles, param)},
            }},
        },
    }
end)

function entry.install(replacementApi)
    if installed then return end
    replacementApi.ReplaceRecipe(originalEntry, EntryPoint)
    replacementApi.ReplaceRecipe(originalVehicles, VehicleTab)
    installed = true
    debugPrint("[xiaom_vehicle_upgrade] vehicle statistics upgrade button registered")
end

return entry
