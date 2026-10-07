local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local globals = ug_require "::/gui/main/game_react_globals.tl"
local core = ug_require "xiaom_building_mover::/mover_core.lua"
local placement = {}
local active
local nextSession = 0
local toolKey = "xiaom_building_mover_placement"
local StatusWindow, PlacementTool

local function text(value)
    return builtin.TextView {text = value, useUnicodeCompatibilityFont = true}
end

local function changed(a, b)
    if not a or not b then return a ~= b end
    return math.abs(a.x - b.x) > 0.001
        or math.abs(a.y - b.y) > 0.001 or math.abs(a.z - b.z) > 0.001
end

local function cursorPosition()
    if not api.gui.mouse.hasTerrainPosition() then return nil end
    local p = api.gui.mouse.getTerrainPosition()
    return {x = p.x, y = p.y, z = p.z}
end

local function builderParams(construction)
    -- Match the official construction menu's filterToDefinitionParams. The
    -- native builder inserts seed/year/modules itself: passing a saved table
    -- with those fields triggers lua::Table::Put's duplicate-key assertion.
    local id = api.res.constructionRep.find(construction.fileName)
    local desc = id and id >= 0 and api.res.constructionRep.get(id)
    local params = {}
    for _, param in ipairs(desc and desc.params or {}) do
        local key = param.key
        if key ~= "seed" and key ~= "year" and key ~= "modules" and construction.params[key] ~= nil then
            params[key] = core.copy(construction.params[key])
        end
    end
    return params
end

local Action = react.RegisterWrapperRecipe("XiaomBuildingMoverPlacementAction", builtin.ActionDescriptor, function(session)
    local state = react.useState(0)
    react.onStep(function()
        if not session.active then return end
        if not session.pending then session.update(cursorPosition()) end
        if state:old() ~= session.version then state:set(session.version) end
    end)
    local function bind(id, fn, prompt)
        react.useInputAction(id, react.iaHandler(fn, function()
            return session.active and not session.pending
        end, prompt, true))
    end
    local function precise()
        return api.gui.inputAction.modifierOnlyActionIsActive("IA_PRECISION_MODE")
    end
    -- Use the same named actions as the native construction menu, respecting
    -- the player's remapped keys and precision modifier.
    local adjustments = {
        constructOpt1 = function() session.adjust("angle", precise() and -1 or -15) end,
        constructOpt2 = function() session.adjust("angle", precise() and 1 or 15) end,
        constructRaise = function() session.adjust("height", precise() and 0.1 or 1) end,
        constructLower = function() session.adjust("height", precise() and -0.1 or -1) end,
    }
    bind("IA_MENU_BACK", session.cancel, "取消移动")
    react.useInputAction("IA_APPLY", react.iaHandler(session.place, function()
        return session.active and not session.pending and session.valid
            and not changed(cursorPosition(), session.position)
    end, "放置建筑（免费）"))

    local children = {
        builtin.Selector {
            onSelect = function() session.place(); return true end,
            onSelectSecondary = function() session.cancel(); return true end,
            onProcessMouseEvent = function(event)
                if event.button == 2 and event.type == api.gui.mouse.Event.Type.Clicked then
                    session.cancel(); return true
                end
                return false
            end,
            lineViewerSupport = false,
        },
    }
    local construction = api.engine.getComponent(session.entity, api.type.ComponentType.CONSTRUCTION)
    if construction and session.active and not session.pending and core.unchanged(session.entity, session.revision) then
        local builder = builtin.type.ConstructionAction.ConstructionBuilder.new()
        builder.constructions = {construction.fileName}
        builder.constructionTemplate = -1
        builder.params = builderParams(construction)
        local source = construction.transf
        builder.rotation = math.atan(source[2], source[1]) + session.angle * math.pi / 180
        builder.height = source:getTransl().z - api.engine.terrain.getHeightAt(
            api.type.Vec2f.new(source:getTransl().x, source:getTransl().y)) + session.height
        builder.assetRandomize = false
        builder.onRotationChangeFn = function() end
        local request = session.request
        children[#children + 1] = builtin.ConstructionAction {
            constructionBuilder = builder,
            inputActions = {constructOpt1 = "rotation", constructOpt2 = "rotation",
                constructRaise = "raiseOrLower", constructLower = "raiseOrLower"},
            inputActionPrompts = {constructOpt1 = "旋转", constructOpt2 = "旋转",
                constructRaise = "升高", constructLower = "降低"},
            inputActionsHandler = function(id)
                if session.active and not session.pending and adjustments[id] then adjustments[id]() end
            end,
            getProposalStringsFn = function(proposal, data)
                -- Write the complete value back: nested record getters can
                -- return copies, so changing data.errorState.critical alone
                -- does not necessarily disable the native new-build command.
                local errors = data.errorState
                errors.critical = true
                data.errorState = errors
                if session.active and not session.pending and session.request == request and proposal.toAdd[1] then
                    session.snap(proposal.toAdd[1].transf:clone(), request)
                end
                -- This builder supplies native snapping only. Its new-build
                -- command must never run; the mapped free update is submitted
                -- by our Selector after a separate replacement validation.
                return {}
            end,
        }
    end
    if session.proposal and session.active then
        local serial = session.serial
        children[#children + 1] = builtin.ProposalViewer {
            simpleProposal = session.proposal,
            proposalId = toolKey .. tostring(session.id) .. ":" .. tostring(serial),
            entityForRefundableContext = session.entity,
            onCreateProposalData = function(data, generated)
                if not session.active or session.pending or session.serial ~= serial then return end
                session.preview = core.capturePreview(session.snapshot, data, generated, session.proposal)
                session.valid, session.message = session.preview.valid, session.preview.message
                session.version = session.version + 1
            end,
        }
    end
    return builtin.ActionDescriptor {
        tool = toolKey,
        onBack = session.cancel,
        children = children,
    }
end)

StatusWindow = react.RegisterWrapperRecipe("XiaomBuildingMoverPlacementWindow", builtin.Window, function(session)
    local state = react.useState(0)
    react.onStep(function()
        if state:old() ~= session.version then state:set(session.version) end
    end)
    return builtin.Window {
        id = "xiaom_building_mover_placement_window",
        title = "移动建筑 · 免费",
        movable = true,
        closable = not session.pending,
        onClose = session.cancel,
        initialX = 20, initialY = 100,
        content = builtin.BoxLayout {
            orientation = builtin.type.Orientation.Vertical,
            children = {
                text(session.name),
                text("移动鼠标选择位置；左键放置，右键或返回键取消。"),
                text("使用建造时的旋转、升降按键；精细模式可微调。"),
                text(string.format("旋转 %.1f° · 高度 %+.1f m", session.angle, session.height)),
                builtin.BoxLayout {
                    orientation = builtin.type.Orientation.Horizontal,
                    children = {
                        builtin.Button {meta = {enabled = not session.pending}, content = text("旋转 −15°"),
                            onClick = function() session.adjust("angle", -15) end},
                        builtin.Button {meta = {enabled = not session.pending}, content = text("旋转 +15°"),
                            onClick = function() session.adjust("angle", 15) end},
                        builtin.Button {meta = {enabled = not session.pending}, content = text("升高"),
                            onClick = function() session.adjust("height", 1) end},
                        builtin.Button {meta = {enabled = not session.pending}, content = text("降低"),
                            onClick = function() session.adjust("height", -1) end},
                    },
                },
                text("建筑及全部子模块一起移动。搬移费用：0。"),
                text(session.message),
                builtin.Button {
                    meta = {enabled = not session.pending},
                    content = text("移动单个模块"),
                    onClick = function()
                        if session.pending then return end
                        session.cancel()
                        session.openModules(session.entity)
                    end,
                },
                builtin.Button {
                    meta = {enabled = not session.pending},
                    content = text("取消移动"), onClick = session.cancel,
                },
            },
        },
    }
end)

PlacementTool = react.RegisterTool {
    name = "xiaom_building_mover_placement_tool",
    push = function(ctx, session)
        ctx.setActionFn(function() return Action(session) end, toolKey)
        local container = globals.getDefaultWindowContainer()
        container:get():getApi().addSingletonWindow(StatusWindow, session)
    end,
    pop = function(ctx, session) session.finish() end,
    shelve = function(ctx, session, shelved)
        if shelved and not session.pending then session.cancel() end
    end,
}

function placement.open(entity, openModules)
    local info = core.inspect(entity)
    local tools = globals.getDefaultToolStackApi()
    local container = globals.getDefaultWindowContainer()
    if not info or not tools or not container or container:hasExpired() then return false end
    if active and active.pending then return false end
    if active then active.cancel() end
    nextSession = nextSession + 1
    local session = {
        id = nextSession, entity = entity, name = info.name, revision = info.revision,
        active = true, pending = false, valid = false, serial = 0, request = 0, version = 0,
        angle = 0, height = 0, openModules = openModules,
        message = "请选择建筑的新位置。",
    }
    active = session
    function session.finish()
        if not session.active then return end
        session.active = false
        session.valid = false
        session.serial = session.serial + 1
        session.request = session.request + 1
        if active == session then active = nil end
        local wc = globals.getDefaultWindowContainer()
        if wc and not wc:hasExpired() then wc:get():getApi().removeAllWindows(StatusWindow) end
    end
    function session.cancel()
        if session.pending or not session.active then return end
        session.finish()
        tools.pop(PlacementTool, toolKey)
    end
    function session.update(position, force)
        if not session.active or session.pending then return end
        if not core.unchanged(entity, session.revision) then
            session.valid = false
            session.proposal = nil
            session.message = "建筑已改变，请取消后重新点击移动。"
            session.version = session.version + 1
            return
        end
        if not force and not changed(position, session.position) then return end
        session.position = position and {x = position.x, y = position.y, z = position.z} or nil
        session.serial = session.serial + 1
        session.request = session.request + 1
        session.valid = false
        session.preview = nil
        session.proposal, session.snapshot = nil, nil
        session.message = position and "正在检查道路连接……" or "将鼠标移到地图上选择位置。"
        session.version = session.version + 1
    end
    function session.adjust(key, amount)
        if session.pending or not session.active then return end
        session[key] = session[key] + amount
        debugPrint("[xiaom_building_mover] adjust " .. key .. "=" .. tostring(session[key]))
        session.update(cursorPosition() or session.position, true)
    end
    function session.snap(matrix, request)
        local position = cursorPosition()
        if not position or not session.active or session.pending or request ~= session.request
            or not core.unchanged(entity, session.revision) then return end
        local previous = session.snapped
        local different = not previous
        if previous then
            for i = 1, 16 do
                if math.abs(previous[i] - matrix[i]) > 0.001 then different = true; break end
            end
        end
        if not different and session.proposal then return end
        session.snapped = matrix
        session.serial = session.serial + 1
        session.valid, session.preview = false, nil
        local p, err, snapshot = core.proposal(entity, {kind = "nativeplacement", transf = matrix})
        session.proposal, session.snapshot = p, snapshot
        session.message = err or "正在检查道路连接……"
        session.version = session.version + 1
    end
    function session.place()
        if not session.active or session.pending then return end
        local position = cursorPosition()
        if changed(position, session.position) then session.update(position); return end
        if not session.valid or not position then return end
        session.pending = true
        session.valid = false
        session.message = "正在移动……"
        session.version = session.version + 1
        local sent, err = core.apply(session.snapshot, session.preview, session.proposal, function(success)
            session.pending = false
            if success then
                session.finish()
                tools.pop(PlacementTool, toolKey)
            elseif session.active then
                session.message = "移动未成功，原建筑保留。请调整位置。"
                session.update(cursorPosition(), true)
            end
        end)
        if not sent then
            session.pending = false
            session.message = err
            session.version = session.version + 1
        end
    end
    session.update(cursorPosition(), true)
    tools.push(PlacementTool, toolKey, session, true)
    return true
end

return placement
