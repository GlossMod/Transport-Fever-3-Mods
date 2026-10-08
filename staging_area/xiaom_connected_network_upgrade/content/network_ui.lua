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
local function text(value, class)
    return builtin.TextView {meta = {class = "network-text" .. (class and "," .. class or "")},
        text = value or "", useUnicodeCompatibilityFont = true}
end
local function fmt(key, ...) return string.format(tr(key), ...) end
local function panel(class, children, horizontal)
    return builtin.Component {
        meta = {class = class},
        layout = builtin.BoxLayout {
            orientation = horizontal and builtin.type.Orientation.Horizontal or builtin.type.Orientation.Vertical,
            children = children,
        },
    }
end
local function metric(label, value, tone)
    return panel("network-metric", {
        text(lang.formatInt(value), "network-number," .. (tone or "network-ink")),
        text(tr(label), "network-caption"),
    })
end
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

local function issueLines(session, expanded)
    local children = {}
    local keys = {}
    for reason in pairs(session.reasons) do keys[#keys + 1] = reason end
    table.sort(keys, function(a, b)
        if session.reasons[a] == session.reasons[b] then return a < b end
        return session.reasons[a] > session.reasons[b]
    end)
    for _, reason in ipairs(keys) do
        children[#children + 1] = text(fmt("reason_count", tr("reason_" .. reason), session.reasons[reason]), "network-reason")
    end
    if expanded and #session.details > 0 then
        for _, item in ipairs(session.details) do
            local message = item.message:gsub("%s+", " ")
            -- Keep the full trace in the log. Bound UI text even for long engine errors.
            if #message > 540 then
                local cut = 540
                -- Avoid cutting a UTF-8 continuation byte; no extra library.
                while cut > 0 and message:byte(cut + 1) >= 128 and message:byte(cut + 1) < 192 do cut = cut - 1 end
                message = message:sub(1, cut) .. "…"
            end
            children[#children + 1] = panel("network-error-item", {
                text(fmt("detail_group", tr("reason_" .. item.reason), item.entity or -1, item.count), "network-warning"),
                text(message, "network-note"),
            })
            if #children >= #keys + 5 then break end
        end
        children[#children + 1] = text(tr("details_hint"), "network-note")
    end
    return children
end

local function progress(session)
    local phase = session.phase == "done" and session.finishedPhase or session.phase
    if phase == "scanning" then return 0, fmt("scanned", session.total) end
    if phase == "checking" then
        return session.checked / math.max(1, session.total), fmt("checked", session.checked, session.total)
    end
    if phase == "verifying" then
        local count = #(session.entries or {}) + #(session.nodeKeys or {})
        local checked = session.verifyIndex + session.verifyNodeIndex - 2
        return checked / math.max(1, count), tr("status_verifying")
    end
    if phase == "applying" then
        return session.processed / math.max(1, #session.ready), fmt("processed", session.processed, #session.ready)
    end
    return session.checked / math.max(1, session.total), fmt("checked", session.checked, session.total)
end

Window = react.RegisterWrapperRecipe("XiaomConnectedNetworkUpgradeWindow", builtin.Window, function(session)
    local state = react.useState(0)
    local expanded = react.useState(false)
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
    local target = {
        text(fmt("target_caption", tr(session.intent.network)), "network-caption,network-accent"),
        text(session.intent.name or "", "network-target-name"),
    }
    if #(session.intent.labels or {}) > 0 then target[#target + 1] = text(table.concat(session.intent.labels, " · "), "network-note") end
    if session.intent.invert then
        target[#target + 1] = text(tr(session.intent.action == "ACTION_STREET_BUILDER_UPGRADER" and "reverse" or "inverse"), "network-warning")
    end
    local value, label = progress(session)
    local tone = (session.message == "error" or session.message == "native_error") and "network-danger"
        or (session.message == "funds" or session.phase == "stale" or session.message == "nothing") and "network-warning"
        or (session.message == "complete" or session.message == "ready") and "network-success" or "network-accent"
    local status = {text(tr("status_" .. session.message), "network-status-text," .. tone)}
    status[#status + 1] = builtin.ProgressBar {
        meta = {class = "network-progress"}, value = math.min(1, math.max(0, value)), label = label,
    }
    local phase = session.phase == "done" and session.finishedPhase or session.phase
    local incomplete = phase == "scanning" or phase == "checking"
    local costCaption = incomplete and (session.phase == "done" and "cost_caption_incomplete" or "cost_caption_pending") or "cost_caption"
    local costs = {
        text(tr(costCaption), "network-caption"),
        text(incomplete and #session.ready == 0 and "—" or money(session.estimate), "network-price,network-accent"),
    }
    if phase == "applying" then
        costs[#costs + 1] = text(fmt("charged", money(session.actualCost)), "network-success")
    end
    costs[#costs + 1] = text(tr("estimate_hint"), "network-note")
    local children = {
        panel("network-target", target),
        panel("network-status", status),
        panel("network-metric-row", {
            metric("metric_found", session.total), metric("metric_planned", #session.ready, "network-accent"),
            metric("metric_matching", session.unchanged, "network-success"),
        }, true),
        panel("network-metric-row", {
            metric("metric_success", session.succeeded, "network-success"), metric("metric_skipped", session.skipped, "network-warning"),
            metric("metric_failed", session.failed, session.failed > 0 and "network-danger" or "network-muted"),
        }, true),
        panel("network-cost", costs),
    }
    local reasonChildren = issueLines(session, expanded:old())
    if #reasonChildren > 0 then
        local heading = {text(tr("reasons_title"), "network-section-title")}
        if #session.details > 0 then
            heading[#heading + 1] = builtin.Button {
                meta = {class = "network-detail-toggle"},
                content = text(tr(expanded:old() and "hide_details" or "show_details")),
                onClick = function() expanded:set(not expanded:old()) end,
            }
        end
        children[#children + 1] = panel("network-reasons", {
            panel("network-reason-heading", heading, true),
            panel("network-reason-content", reasonChildren),
        })
    end
    local actions = panel("network-actions", {
            builtin.Button {
                meta = {class = "primary,network-button", enabled = session.phase == "ready" and #session.ready > 0},
                content = text(tr("confirm")),
                onClick = function() controller.confirm(session) end,
            },
            builtin.Button {
                meta = {class = "secondary,network-button", enabled = progressing and not session.cancelled},
                content = text(tr("cancel")),
                onClick = function() controller.cancel(session) end,
            },
            builtin.Button {
                meta = {class = "network-button", enabled = not progressing and not session.pending},
                content = text(tr("close")),
                onClick = function() ui.close(session) end,
            },
    }, true)
    return builtin.Window {
        id = windowId, title = tr("title"), initialX = 20, initialY = 100, movable = true,
        closable = not progressing and not session.pending,
        onClose = function() ui.close(session) end,
        content = panel("network-content", {
            builtin.ScrollArea {meta = {class = "network-main-scroll"}, content = panel("network-body", children)},
            actions, text(tr("confirm_hint"), "network-note"),
        }),
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
        if session.quote then
            local request = session.quote
            children[#children + 1] = builtin.ProposalViewer {
                proposal = request.proposal,
                proposalId = toolKey .. ":" .. tostring(session.id) .. ":quote:" .. tostring(request.id),
                entityForRefundableContext = api.engine.util.getPlayer(),
                onCreateProposalData = function(data, generated)
                    -- Native callback values are borrowed. Read them here and
                    -- pass only a scalar receipt to the main-thread controller.
                    -- For a full Proposal, the native callback may supply only
                    -- ProposalData; our input is already an owned full proposal.
                    local ok, receipt = core.protect(core.capturePreview, request.entity, data, generated or request.proposal)
                    if not ok then receipt = {valid = false, reason = "api", detail = "native preview: " .. receipt} end
                    react.enqueueJoin(function() controller.acceptQuote(session, request.id, receipt) end,
                        "XiaomConnectedNetworkUpgrade:quote")
                end,
            }
        elseif session.previewProposal then
            children[#children + 1] = builtin.ProposalViewer {
                proposal = session.previewProposal,
                proposalId = toolKey .. ":" .. tostring(session.id) .. ":" .. tostring(session.previewVersion),
                entityForRefundableContext = api.engine.util.getPlayer(),
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
