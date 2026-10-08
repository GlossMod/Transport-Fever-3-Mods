local core = ug_require "xiaom_connected_network_upgrade::/network_core.lua"
local ui = ug_require "xiaom_connected_network_upgrade::/network_ui.lua"
local entry = {}

local function decorate(definition)
    if not core.network(definition) or definition.customAction then return end
    local params = {}
    for _, param in ipairs(definition.params or {}) do params[#params + 1] = param end
    local enum = api.type["enum"]
    params[#params + 1] = {
        key = "xiaom_connected_network",
        id = "xiaom.connected_network_upgrade.enabled",
        group = "xiaom_connected_network",
        name = _("xiaom_network_toggle"), tooltip = _("xiaom_network_toggle_hint"),
        values = {_("No"), _("Yes")}, defaultIndex = 1,
        uiType = enum.ScriptParamType.CheckBox,
        location = enum.ScriptParamLocation.Toolbar,
        displayMode = enum.ScriptParamDisplayMode.Horizontal,
        yearFrom = 0, yearTo = 0,
        preserveValueInAllCategories = true, resetOnCategoryChange = false,
        resetOnDefinitionChange = false, resetOnMenuClose = true,
        checkEnabledFn = function(values)
            if definition.action == "ACTION_STREET_BUILDER_UPGRADER" and values.mode_street ~= 3 then return "Hidden" end
            if definition.action == "ACTION_TRACK_BUILDER_UPGRADER" and values.mode ~= 2 then return "Hidden" end
            return "Enabled"
        end,
    }
    definition.params = params
    definition.customAction = {recipe = ui.CustomAction, customParam = {network = core.network(definition)}}
end

function entry.install(_replacementApi)
    local menu = ug_require "::/gui/construction/construction_react_util.tl"
    if menu.xiaomConnectedNetworkInstalled then return end
    local original = menu.forEachDefinition
    local originalActionParams = menu.getActionParams
    assert(type(original) == "function", "[xiaom_connected_network_upgrade] construction definition API unavailable")
    assert(type(originalActionParams) == "function", "[xiaom_connected_network_upgrade] construction parameter API unavailable")
    menu.getActionParams = function(definition, params, repository, gamepad, popup, entity, notifications, toolbar)
        ui.captureParamSources(popup, toolbar)
        return originalActionParams(definition, params, repository, gamepad, popup, entity, notifications, toolbar)
    end
    menu.forEachDefinition = function(callback, repository)
        return original(function(definition)
            decorate(definition)
            callback(definition)
        end, repository)
    end
    menu.xiaomConnectedNetworkInstalled = true
    debugPrint("[xiaom_connected_network_upgrade] connected road/track upgrade tools installed, revision=5")
    debugPrint("[xiaom_connected_network_upgrade] runtime API: " .. core.apiSummary())
end

return entry
