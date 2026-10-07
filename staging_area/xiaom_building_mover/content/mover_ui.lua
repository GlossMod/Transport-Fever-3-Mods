local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local globals = ug_require "::/gui/main/game_react_globals.tl"
local core = ug_require "xiaom_building_mover::/mover_core.lua"
local placement = ug_require "xiaom_building_mover::/mover_placement.lua"
local ui = {}
local windowId = "xiaom_building_mover_window"
local previewKey = "xiaom_building_mover_module_preview"
local openSerial = 0

local function text(value)
    return builtin.TextView {text = value, useUnicodeCompatibilityFont = true}
end
local function button(label, onClick, enabled)
    return builtin.Button {meta = {enabled = enabled ~= false}, content = text(label), onClick = onClick}
end

local Preview = react.RegisterWrapperRecipe("XiaomBuildingMoverPreview", builtin.ActionDescriptor, function(param)
    return builtin.ActionDescriptor {children = {builtin.ProposalViewer {
        simpleProposal = param.proposal,
        proposalId = previewKey .. tostring(param.serial),
        entityForRefundableContext = param.snapshot.entity,
        onCreateProposalData = param.onData,
    }}}
end)
local PreviewTool = react.RegisterTool {
    name = "xiaom_building_mover_module_preview_tool",
    push = function(ctx, param) ctx.setActionFn(function() return Preview(param) end, previewKey) end,
    pop = function(ctx, param) param.onStop() end,
    shelve = function(ctx, param, shelved) if shelved then param.onStop() end end,
}

local Window
Window = react.RegisterWrapperRecipe("XiaomBuildingMoverWindow", builtin.Window, function(param)
    local selection = react.useState({})
    local source = react.useState(-1)
    local target = react.useState(-1)
    local message = react.useState("正在读取模块……")
    local readiness = react.useState(false)
    local pending = react.useState(false)
    local preview = react.useRef({serial = 0})
    local waiting = react.useRef(false)
    local request = react.useRef(-1)

    local function stopPreview()
        preview:set({serial = preview:get().serial + 1})
        readiness:set(false)
        local tools = globals.getDefaultToolStackApi()
        if tools then tools.pop(PreviewTool, previewKey) end
    end
    local function close()
        if waiting:get() then return end
        stopPreview()
        local container = globals.getDefaultWindowContainer()
        if container and not container:hasExpired() then container:get():getApi().removeAllWindows(Window) end
    end
    local function select(entity)
        if waiting:get() then return end
        stopPreview()
        local info, err = core.inspect(entity)
        selection:set(info or {})
        source:set(info and info.modules[1] and info.modules[1].id or -1)
        target:set(-1)
        message:set(err or "选择已建模块和同类空插槽，预览后确认。搬移费用：0。")
    end
    react.onStep(function()
        if param.request ~= request:get() and not waiting:get() then
            select(param.entity); request:set(param.request)
        end
    end)
    react.onUnmount(stopPreview)
    react.onStepTimer(function()
        local info = selection:old()
        if info.entity and not waiting:get() and not core.unchanged(info.entity, info.revision) then select(info.entity) end
    end, 0.5, false)

    local function beginPreview()
        if waiting:get() then return end
        stopPreview()
        local info = selection:old()
        if not info.entity then return end
        local proposal, err, snapshot = core.proposal(info.entity, {kind = "module", source = source:old(), target = target:old()})
        if not proposal then message:set(err); return end
        local tools = globals.getDefaultToolStackApi()
        if not tools then message:set("游戏工具尚未就绪，请稍后重试。"); return end
        local serial = preview:get().serial
        preview:set({serial = serial, snapshot = snapshot})
        message:set("正在生成模块移动预览……")
        tools.push(PreviewTool, previewKey, {
            proposal = proposal, snapshot = snapshot, serial = serial,
            onData = function(data, generated)
                if readiness:hasExpired() or preview:hasExpired() or preview:get().serial ~= serial then return end
                local receipt = core.capturePreview(snapshot, data, generated, proposal)
                preview:set({serial = serial, snapshot = snapshot, receipt = receipt, proposal = proposal})
                readiness:set(receipt.valid); message:set(receipt.message .. "  搬移费用：0。")
            end,
            onStop = function()
                if readiness:hasExpired() or preview:hasExpired() then return end
                if preview:get().serial == serial then
                    preview:set({serial = serial + 1}); readiness:set(false); message:set("预览已取消。")
                end
            end,
        }, true)
    end
    local function apply()
        if waiting:get() or not readiness:old() then return end
        local current = preview:get()
        waiting:set(true); pending:set(true); readiness:set(false); message:set("正在移动模块……")
        local sent, err = core.apply(current.snapshot, current.receipt, current.proposal, function(success, entity)
            if pending:hasExpired() then return end
            waiting:set(false); pending:set(false); stopPreview()
            if success then select(entity); message:set("模块移动完成，搬移费用：0。")
            else message:set("移动未成功，原模块保留。请重新预览。") end
        end)
        if not sent then waiting:set(false); pending:set(false); message:set(err) end
    end

    local info = selection:old()
    local enabled = info.entity ~= nil and not pending:old()
    local modules, items = {}, {}
    for _, module in ipairs(info.modules or {}) do
        modules[#modules + 1] = builtin.ComboBoxItem {value = module.id,
            content = text((module.name or "模块") .. " · 插槽 " .. tostring(module.id))}
    end
    local targets = info.entity and core.targets(info.entity, source:old()) or {}
    for _, id in ipairs(targets) do
        local position = info.slots[id].transf:getTransl()
        items[#items + 1] = builtin.ComboBoxItem {value = id,
            content = text(string.format("插槽 %d · 相对位置 %.1f / %.1f m", id, position.x, position.y))}
    end
    return builtin.Window {
        id = windowId, title = "移动单个模块 · 免费", movable = true, closable = not pending:old(), onClose = close,
        initialX = 20, initialY = 100,
        content = builtin.BoxLayout {orientation = builtin.type.Orientation.Vertical, children = {
            text(info.name or "正在读取建筑……"),
            button("移动整栋建筑", function() close(); ui.open(info.entity) end, enabled),
            text("选择已建模块"),
            builtin.ComboBox {meta = {enabled = enabled}, value = source:old(), items = modules,
                onValueChange = function(id) stopPreview(); source:set(id); target:set(-1) end},
            text(#targets > 0 and "选择同类空插槽" or "该模块当前没有同类空插槽。"),
            builtin.ComboBox {meta = {enabled = enabled and #targets > 0}, value = target:old(), items = items,
                onValueChange = function(id) stopPreview(); target:set(id) end},
            builtin.BoxLayout {orientation = builtin.type.Orientation.Horizontal, children = {
                button("预览移动", beginPreview, enabled), button("确认移动", apply, readiness:old() and not pending:old()),
                button("取消预览", function() stopPreview(); message:set("预览已取消。") end, not pending:old()),
            }},
            text(message:old()), text("搬移费用：0。整栋建筑可直接在地图上选择新位置。"),
        }},
    }
end)

function ui.openModules(entity)
    if not core.inspect(entity) then return false end
    local container = globals.getDefaultWindowContainer()
    if not container or container:hasExpired() then return false end
    openSerial = openSerial + 1
    container:get():getApi().addSingletonWindow(Window, {entity = entity, request = openSerial})
    api.gui.byId.setVisible(windowId, true)
    return true
end
function ui.open(entity)
    -- The detail action enters map placement immediately; no coordinate editor.
    return placement.open(entity, ui.openModules)
end
return ui
