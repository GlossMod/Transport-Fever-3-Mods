local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local globals = ug_require "::/gui/main/game_react_globals.tl"
local build = {}
local owner, current
local Window
local windowId = "xiaom_anarchy_build_window"

local function windows()
    local container = globals.getDefaultWindowContainer()
    if container and not container:hasExpired() then return container:get():getApi() end
end

function build.clear()
    -- Do not mutate the window container when no Anarchy window exists.
    -- getActionParams also runs during initial GUI rendering.
    if not current then return end
    current.active = false; current.proposal = nil
    current = nil
    local apiWindow = windows()
    if apiWindow then apiWindow.removeAllWindows(Window) end
end

function build.begin(key)
    if owner ~= key then build.clear(); owner = key end
end

function build.capture(key, proposal, data, filtered, filteredErrors)
    if owner ~= key or current and current.pending then return end
    -- Eligibility comes from the owned error snapshot. Native callback data
    -- keeps all of its original errors and never needs a writable accessor.
    local errors = filteredErrors or data.errorState
    if not errors or errors.critical or #(errors.messages or {}) > 0 then
        build.clear()
        return
    end
    if not filtered then
        -- Moving onto the button can hide the native terrain preview. Retain
        -- the owned last preview only while the pointer is outside the map.
        if current and not api.gui.mouse.hasTerrainPosition() then return end
        build.clear()
        return
    end
    -- Proposal/ProposalData are borrowed. The documented clone creates our
    -- owned proposal; neither callback argument is kept in a later closure.
    local owned = proposal:clone()
    if not current then
        current = {active=true,pending=false,version=0}
        local apiWindow = windows()
        if not apiWindow then current = nil; return end
        apiWindow.addSingletonWindow(Window, current)
        api.gui.byId.setVisible(windowId, true)
    end
    current.proposal = owned
    current.costs = data.costs
    current.message = _("xiaom_anarchy_ready")
    current.version = current.version + 1
end

function build.apply(session)
    if session ~= current or not session.active or session.pending or not session.proposal then return false end
    local proposal = session.proposal
    local context = api.type.Context.new()
    context.player = api.engine.util.getPlayer()
    local refundable = api.gui.construction.getRefundableEntities()
    if refundable ~= nil then context.refundableEntities = refundable end
    session.pending = true
    session.message = _("xiaom_anarchy_building")
    session.version = session.version + 1
    -- This is the actual world command, with normal payer/ownership and costs.
    -- It bypasses non-critical engine checks, not just the preview's messages.
    api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, context, true, true, true),
        function(result, success)
            session.pending = false
            debugPrint("[xiaom_no_collision] Anarchy force build completed success=" .. tostring(success))
            if success then
                session.proposal = nil
                build.clear()
                react.fireEvent(nil, "onProposalApply")
                react.fireEvent(nil, "constructionMenuQuit")
            elseif session == current and session.active then
                session.message = _("xiaom_anarchy_failed")
                session.proposal = nil
                session.version = session.version + 1
                -- Read the command result only in this completion callback.
                local errors = result and result.resultProposalData and result.resultProposalData.errorState
                if errors then
                    for _, message in ipairs(errors.messages or {}) do
                        debugPrint("[xiaom_no_collision] force build error: " .. tostring(message))
                    end
                end
            end
        end)
    return true
end

Window = react.RegisterWrapperRecipe("XiaomAnarchyBuildWindow", builtin.Window, function(session)
    local state = react.useState(0)
    react.onStep(function()
        if state:old() ~= session.version then state:set(session.version) end
    end)
    react.onEvent("onProposalApply", build.clear)
    react.onEvent("constructionMenuActive", function(_, params)
        if params and params.active == false then build.clear() end
    end)
    local function text(value)
        return builtin.TextView {text=value,useUnicodeCompatibilityFont=true}
    end
    return builtin.Window {
        id=windowId,title="Anarchy",initialX=20,initialY=100,movable=true,closable=not session.pending,
        onClose=build.clear,
        content=builtin.BoxLayout {orientation=builtin.type.Orientation.Vertical,children={
            text(session.message or _("xiaom_anarchy_ready")),
            text(_("xiaom_anarchy_preview_hint")),
            builtin.Button {meta={enabled=session.active and not session.pending and session.proposal ~= nil},
                content=text(_("xiaom_anarchy_build")),onClick=function() build.apply(session) end},
        }},
    }
end)

return build
