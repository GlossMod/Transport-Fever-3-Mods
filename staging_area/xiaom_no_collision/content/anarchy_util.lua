local anarchy = {}

function anarchy.filterPreviewErrors(proposalData)
    -- Callback data is borrowed and read-only. Filter an owned Lua snapshot for
    -- the Anarchy button; leave the native preview and its apply rules intact.
    local errors = proposalData and proposalData.errorState
    if not errors then return false end
    local snapshot = {critical = errors.critical, messages = {}, warnings = {}, infos = {}}
    for _, message in ipairs(errors.messages or {}) do snapshot.messages[#snapshot.messages + 1] = message end
    for _, warning in ipairs(errors.warnings or {}) do snapshot.warnings[#snapshot.warnings + 1] = warning end
    for _, info in ipairs(errors.infos or {}) do snapshot.infos[#snapshot.infos + 1] = info end
    if snapshot.critical then return false, snapshot end
    local targets = {Collision = true, ["Too Much Curvature"] = true}
    targets[_("Collision")] = true
    targets[_("Too Much Curvature")] = true
    local messages, removed = {}, false
    for _, message in ipairs(snapshot.messages) do
        if targets[message] then removed = true
        else messages[#messages + 1] = message end
    end
    snapshot.messages = messages
    return removed, snapshot
end

function anarchy.installUI()
    local menu = ug_require "::/gui/construction/construction_react_util.tl"
    if menu.xiaomAnarchyInstalled then return end
    local original = menu.getActionParams
    assert(type(original) == "function", "[xiaom_no_collision] construction menu API unavailable")
    local build = ug_require "xiaom_no_collision::/anarchy_build.lua"
    local lastExtensionError
    local function extension(fn)
        local ok, err = pcall(fn)
        if not ok then
            -- Invalidate any stale force-build proposal before returning the
            -- native callback's result. Optional UI must not break normal tools.
            pcall(build.clear)
            local detail = tostring(err)
            if detail ~= lastExtensionError then
                lastExtensionError = detail
                debugPrint("[xiaom_no_collision] preview extension failed; native callback preserved: " .. detail)
            end
        end
        return ok
    end
    menu.getActionParams = function(...)
        local result = original(...)
        local definition, entity = select(1, ...), select(6, ...)
        extension(function()
            local action = result and result.constructionActionParams
            -- Native definitions may be recreated by React. Use their resource
            -- identity so rendering the same tool cannot invalidate its session.
            local key = tostring(definition and definition.action) .. ":"
                .. tostring(definition and definition.resName) .. ":"
                .. table.concat(definition and definition.constructions or {}, "|") .. ":"
                .. tostring(definition and definition.constructionTemplate) .. ":" .. tostring(entity)
            build.begin(key)
            -- Patch the standard menu, preserving custom tools' apply rules.
            if action and (action.streetEdgeBuilder or action.streetEdgeNodeModifier
                or action.constructionBuilder or action.moduleBuilder) then
                local previous = action.getProposalStringsFn
                action.getProposalStringsFn = function(proposal, proposalData)
                    local strings = previous and previous(proposal, proposalData) or {}
                    extension(function()
                        local filtered, errors = anarchy.filterPreviewErrors(proposalData)
                        build.capture(key, proposal, proposalData, filtered, errors)
                    end)
                    return strings
                end
            end
        end)
        return result
    end
    menu.xiaomAnarchyInstalled = true
    debugPrint("[xiaom_no_collision] Anarchy construction preview hook installed")
end

return anarchy
