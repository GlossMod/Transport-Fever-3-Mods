local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local globals = ug_require "::/gui/main/game_react_globals.tl"
local lang = ug_require "::/scripts/lang_util.tl"
local core = ug_require "xiaom_connected_network_upgrade::/network_core.lua"
local controller = ug_require "xiaom_connected_network_upgrade::/network_controller.lua"
local ui = {}
local Window, Action
local windowId = "xiaom-connected-network-upgrade-window"
local toolKey = "xiaom-connected-network-upgrade"
local popupParamsRef, toolbarParamsRef

function ui.captureParamSources(popup, toolbar)
    popupParamsRef, toolbarParamsRef = popup, toolbar
end

-- CustomAction.getCurrentParams supplies the popup parameters only. Read the
-- live native toolbar API as well, including while the native action is unbound.
-- Keep React references, never a stale copy of the selected toolbar values.
function ui.getParams(param)
    local values = {}
    local function merge(source)
        for key, value in pairs(source or {}) do values[key] = value end
    end
    for _, spec in ipairs(param.definition.params or {}) do
        if spec.defaultIndex then values[spec.key] = spec.numbers and spec.numbers[spec.defaultIndex] or spec.defaultIndex end
    end
    local ok, popup = pcall(param.getCurrentParams)
    if ok then merge(popup) end
    local function read(ref)
        if not ref or ref:hasExpired() then return nil end
        local component = ref:get()
        if not component or not component:getIdentity() then return nil end
        local nativeApi = component:getApi()
        return nativeApi and nativeApi.getCurrentParams()
    end
    local popupOk, popupValues = pcall(read, popupParamsRef)
    if popupOk then merge(popupValues) end
    local toolbarOk, toolbarValues = pcall(read, toolbarParamsRef)
    if toolbarOk then merge(toolbarValues) end
    return values
end

local function tr(key) return _("xiaom_network_" .. key) end
local function text(value)
    return builtin.TextView {meta = {class = "network-upgrade-text"}, text = value or "", useUnicodeCompatibilityFont = true}
end
local function fmt(key, ...) return string.format(tr(key), ...) end
local function money(value)
    local prefix = api.util.getAppConfig().moneyPrefix or "$"
    return prefix .. lang.formatInt(math.floor((value or 0) + 0.5))
end
local function windowApi()
    local ref = globals.getDefaultWindowContainer()
    if ref and not ref:hasExpired() and ref:get() then return ref:get():getApi() end
end

function ui.close(session)
    if not controller.clear(session) then return end
    local windows = windowApi()
    if windows then windows.removeAllWindows(Window) end
end

local function resolveEdge(entity, details)
    if core.component(entity, "BASE_EDGE") then return entity end
    local selection = details and details.data
    if selection and selection.kind == api.gui.SelectionDetails.Type.TransportNetworkEdge then
        local candidate = selection.snap.edgeId.entity
        if core.component(candidate, "BASE_EDGE") then return candidate end
    end
end

-- Estimate the closest point and side on the Hermite curve. Do not assume that
-- a straight chord is the road direction on a curved or S-shaped segment.
local function clickSide(entity)
    local edge = core.component(entity, "BASE_EDGE")
    if not edge or not api.gui.mouse.hasTerrainPosition() then return false end
    local mouse = api.gui.mouse.getTerrainPosition()
    local bestD, bestX, bestY, bestDx, bestDy
    local function point(t)
        local t2, t3 = t * t, t * t * t
        local h0, h1, h2, h3 = 2*t3-3*t2+1, t3-2*t2+t, -2*t3+3*t2, t3-t2
        local d0, d1, d2, d3 = 6*t2-6*t, 3*t2-4*t+1, -6*t2+6*t, 3*t2-2*t
        local p0, p1, v0, v1 = edge.position0, edge.position1, edge.tangent0, edge.tangent1
        return h0*p0.x+h1*v0.x+h2*p1.x+h3*v1.x, h0*p0.y+h1*v0.y+h2*p1.y+h3*v1.y,
            d0*p0.x+d1*v0.x+d2*p1.x+d3*v1.x, d0*p0.y+d1*v0.y+d2*p1.y+d3*v1.y
    end
    for i = 0, 32 do
        local x, y, dx, dy = point(i / 32)
        local d = (x-mouse.x)^2+(y-mouse.y)^2
        if not bestD or d < bestD then bestD, bestX, bestY, bestDx, bestDy = d, x, y, dx, dy end
    end
    return bestDx*(mouse.y-bestY)-bestDy*(mouse.x-bestX) > 0
end

local function readTarget(param)
    local params = ui.getParams(param)
    if not core.enabled(param.definition, params) then return nil end
    return core.intent(param.definition, params, false, false).key
end

function ui.select(owner, param, entity, details, readSource)
    local resolved = resolveEdge(entity, details)
    local params = ui.getParams(param)
    if not resolved or not core.enabled(param.definition, params) or controller.busy() then return end
    local intent = core.intent(param.definition, params,
        api.gui.inputAction.modifierOnlyActionIsActive("IA_SECONDARY_MODE"), clickSide(resolved))
    local key = readTarget(param)
    local windows = windowApi()
    if not windows then return end
    local session = controller.begin(owner, resolved, intent, key, readSource or function() return readTarget(param) end)
    if not session then return end
    -- The window owns the timer, so cancellation and callbacks continue even
    -- when a newly selected native tool unmounts this map action.
    windows.removeAllWindows(Window)
    windows.addSingletonWindow(Window, session)
    api.gui.byId.setVisible(windowId, true)
end

local function issueLines(session)
    local children = {}
    local keys = {}
    for reason in pairs(session.reasons) do keys[#keys + 1] = reason end
    table.sort(keys)
    for _, reason in ipairs(keys) do children[#children + 1] = text(fmt("reason_count", tr("reason_" .. reason), session.reasons[reason])) end
    if #session.details > 0 then
        local shown = 0
        for _, item in ipairs(session.details) do
            if item.message ~= "" then
                children[#children + 1] = text(fmt("detail", item.entity or -1, item.message))
                shown = shown + 1
                if shown >= 8 then break end
            end
        end
        if #session.details > 8 then children[#children + 1] = text(tr("details_hint")) end
    end
    return children
end

Window = react.RegisterWrapperRecipe("XiaomConnectedNetworkUpgradeWindow", builtin.Window, function(session)
    local state = react.useState(0)
    local tickQueued = react.useRef(false)
    react.onStep(function()
        if state:old() ~= session.version then state:set(session.version) end
    end)
    react.onStepTimer(function()
        if tickQueued:hasExpired() or tickQueued:get() then return end
        tickQueued:set(true)
        react.enqueueJoin(function()
            if tickQueued:hasExpired() then return end
            tickQueued:set(false)
            controller.step(session)
        end, "XiaomConnectedNetworkUpgrade:step")
    end, 0.05, false)
    react.onEvent("constructionMenuPop", function() controller.invalidate(session.owner, "target_changed") end)
    react.onEvent("constructionMenuQuit", function() controller.invalidate(session.owner, "target_changed") end)
    react.onEvent("constructionMenuActive", function(_, event)
        if event and event.active == false then controller.invalidate(session.owner, "target_changed") end
    end)
    local progressing = session.phase == "scanning" or session.phase == "checking" or session.phase == "verifying" or session.phase == "applying"
    local children = {
        text(fmt("target", session.intent.name or "")),
        text(fmt("network_kind", tr(session.intent.network))),
        session.intent.invert and text(tr(session.intent.action == "ACTION_STREET_BUILDER_UPGRADER" and "reverse" or "inverse")) or nil,
        text(tr("status_" .. session.message)),
        text(fmt("counts", session.total, #session.ready, session.unchanged, session.skipped, session.failed)),
        text(fmt("estimate", money(session.estimate))),
        text(tr("estimate_hint")),
    }
    -- Keep a dense child array; a nil optional item truncates ipairs/native lists.
    local dense = {}
    for i = 1, 7 do if children[i] then dense[#dense + 1] = children[i] end end
    children = dense
    if #(session.intent.labels or {}) > 0 then
        table.insert(children, 2, text(table.concat(session.intent.labels, " · ")))
    end
    if session.phase == "checking" then children[#children + 1] = text(fmt("checked", session.preflightIndex - 1, session.total)) end
    if session.phase == "applying" or session.phase == "done" then
        children[#children + 1] = text(fmt("progress", session.processed, #session.ready, session.succeeded, money(session.actualCost)))
    end
    local reasonChildren = issueLines(session)
    if #reasonChildren > 0 then
        children[#children + 1] = builtin.ScrollArea {
            meta = {class = "network-upgrade-reasons"},
            content = builtin.Component {layout = builtin.BoxLayout {
                orientation = builtin.type.Orientation.Vertical, children = reasonChildren,
            }},
        }
    end
    children[#children + 1] = builtin.BoxLayout {
        orientation = builtin.type.Orientation.Horizontal,
        children = {
            builtin.Button {
                meta = {class = "primary", enabled = session.phase == "ready" and #session.ready > 0},
                content = text(tr("confirm")),
                onClick = function() controller.confirm(session) end,
            },
            builtin.Button {
                meta = {enabled = progressing and not session.cancelled},
                content = text(tr("cancel")),
                onClick = function() controller.cancel(session) end,
            },
            builtin.Button {
                meta = {enabled = not progressing and not session.pending},
                content = text(tr("close")),
                onClick = function() ui.close(session) end,
            },
        },
    }
    return builtin.Window {
        id = windowId, title = tr("title"), initialX = 20, initialY = 100, movable = true,
        closable = not progressing and not session.pending,
        onClose = function() ui.close(session) end,
        content = builtin.BoxLayout {meta = {class = "network-upgrade-body"}, orientation = builtin.type.Orientation.Vertical, children = children},
    }
end)

Action = react.RegisterWrapperRecipe("XiaomConnectedNetworkUpgradeAction", builtin.ActionDescriptor, function(param)
    local owner = react.useRef({}):get()
    local targetRef = react.useRef(param)
    targetRef:set(param)
    local hovered = react.useRef(nil)
    local state = react.useState(0)
    react.onStep(function()
        local session = controller.current()
        if session and session.owner == owner then
            if not targetRef:hasExpired() and session.phase ~= "done" and session.phase ~= "stale"
                and readTarget(targetRef:get()) ~= session.sourceKey then
                react.enqueueJoin(function() controller.invalidate(owner, "target_changed") end, "XiaomConnectedNetworkUpgrade:target")
            end
            if state:old() ~= session.version then state:set(session.version) end
        end
    end)
    react.onUnmount(function()
        react.enqueueJoin(function() controller.invalidate(owner, "target_changed") end, "XiaomConnectedNetworkUpgrade:unmount")
    end)
    local function select(entity, details)
        ui.select(owner, targetRef:get(), entity, details, function()
            if targetRef:hasExpired() then return nil end
            return readTarget(targetRef:get())
        end)
        return true
    end
    react.useInputAction("IA_APPLY", react.iaHandler(function()
        local hover = hovered:get()
        if hover then select(hover.entity, nil) end
    end, function() return hovered:get() ~= nil and not controller.busy() end, tr("select")))
    react.useInputAction("IA_MENU_BACK", react.iaHandler(function()
        local session = controller.current()
        if session and session.owner == owner then controller.cancel(session) else param.abort() end
    end, nil, tr("cancel")))
    local children = {builtin.Selector {
        filter = function(entity) return core.matches(core.component(entity, "BASE_EDGE"), core.network(param.definition)) end,
        onHover = function(entity, _, details)
            local edge = resolveEdge(entity, details)
            hovered:set(edge and {entity = edge} or nil)
        end,
        onSelect = function(entity, _, details) return select(entity, details) end,
        onSelectSecondary = function()
            local session = controller.current()
            if session and session.owner == owner then controller.cancel(session) else param.abort() end
            return true
        end,
        lineViewerSupport = false,
    }}
    local params = ui.getParams(param)
    local layer = param.gameCtx.preferredLayerConfig:get()
    if layer then layer = api.type.LayerConfig.new(layer) else layer = api.type.LayerConfig.new() end
    layer.undergroundMode = params.undergroundMode == 1
    children[#children + 1] = builtin.LayerConfig {config = layer}
    local session = controller.current()
    local highlights = {}
    if session and session.owner == owner and session.phase ~= "done" and session.phase ~= "stale" then
        for _, entry in ipairs(session.entries or {}) do highlights[#highlights + 1] = entry.entity end
        if session.previewProposal then
            children[#children + 1] = builtin.ProposalViewer {
                proposal = session.previewProposal,
                proposalId = toolKey .. ":" .. tostring(session.id) .. ":" .. tostring(session.previewVersion),
            }
        end
    end
    return builtin.ActionDescriptor {tool = toolKey, highlightedEntities = highlights,
        onBack = param.abort, children = children}
end)

ui.CustomAction = react.RegisterRecipe("XiaomConnectedNetworkUpgradeCustomAction", function(param)
    local bound = react.useRef(nil)
    local paramRef = react.useRef(param)
    paramRef:set(param)
    local actionFn = react.useRef(function() return Action(paramRef:get()) end)
    local function updateBinding()
        if paramRef:hasExpired() then return end
        local current = paramRef:get()
        local enabled = current.isActive and core.enabled(current.definition, ui.getParams(current))
        if bound:get() ~= enabled then
            bound:set(enabled)
            local key = toolKey .. ":" .. current.definition.action .. ":" .. tostring(current.definition.resName)
            current.setActionFn(enabled and actionFn:get() or nil, enabled and key or nil)
        end
    end
    updateBinding()
    react.onStep(updateBinding)
    -- This ordinary component renders no native layout or world action of its
    -- own. The construction list mounts Action only for the selected definition.
end)

return ui
