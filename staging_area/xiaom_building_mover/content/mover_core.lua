-- Geometry and module edits use the installed TF3 SimpleProposal API.
local core = {}

function core.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = core.copy(item) end
    return result
end

local function component(entity, kind)
    if entity == nil or entity < 0 or not api.engine.entityExists(entity) then return nil end
    return api.engine.getComponent(entity, api.type.ComponentType[kind])
end

function core.resolveEntity(entity)
    if component(entity, "CONSTRUCTION") then return entity end
    local group = component(entity, "STATION_GROUP")
    if group then
        local found
        for _, station in ipairs(group.stations) do
            local construction = core.resolveEntity(station)
            if construction then
                if found and found ~= construction then return nil, "请选择具体的车站建筑或子模块。" end
                found = construction
            end
        end
        return found
    end
    local system = api.engine.system.streetConnectorSystem
    local lookups = {
        {"SUBCONSTRUCTION", system.getConstructionEntityForSubconstruction},
        {"STATION", system.getConstructionEntityForStation},
        {"DEPOT", system.getConstructionEntityForDepot},
        {"INDUSTRY", system.getConstructionEntityForIndustry},
        {"TOWN_BUILDING", system.getConstructionEntityForTownBuilding},
    }
    for _, lookup in ipairs(lookups) do
        if component(entity, lookup[1]) then
            local construction = lookup[2](entity)
            if component(construction, "CONSTRUCTION") then return construction end
        end
    end
    return nil, "请在地图上选择一栋建筑或它的子模块。"
end

function core.revision(entity)
    if not api.engine.entityExists(entity) then return nil end
    local r = api.engine.getRevision(entity).num
    return {r[1], r[2], r[3]}
end

function core.unchanged(entity, revision)
    local current = core.revision(entity)
    return current ~= nil and revision ~= nil
        and current[1] == revision[1] and current[2] == revision[2] and current[3] == revision[3]
end

local function getSlots(construction)
    local slots = {}
    for _, slot in ipairs(construction.slots or {}) do slots[slot.id] = slot end
    return slots
end

function core.inspect(entity)
    local construction = component(entity, "CONSTRUCTION")
    if not construction then return nil, "建筑已不存在，请重新选择。" end
    local owner = component(entity, "PLAYER_OWNED")
    if owner and owner.player ~= api.engine.util.getPlayer() then
        return nil, "只能移动自己的建筑或无主建筑。"
    end
    local slots = getSlots(construction)
    local modules = {}
    for slotId, module in pairs(construction.params.modules or {}) do
        local slot = slots[slotId]
        local resourceName = type(module) == "table" and module.name or tostring(module)
        local label = resourceName and resourceName:match("([^/]+)$") or "模块"
        local moduleId = resourceName and api.res.moduleRep.find(resourceName) or -1
        if moduleId >= 0 then
            local desc = api.res.moduleRep.get(moduleId)
            if desc.description and desc.description.name ~= "" then label = desc.description.name end
        end
        modules[#modules + 1] = {
            id = slotId,
            type = slot and slot.type or "",
            name = label,
        }
    end
    table.sort(modules, function(a, b) return a.id < b.id end)
    return {
        entity = entity,
        name = api.engine.util.getEntityName(entity) or construction.fileName,
        revision = core.revision(entity),
        modules = modules,
        slots = slots,
    }
end

function core.targets(entity, source)
    local construction = component(entity, "CONSTRUCTION")
    if not construction then return {} end
    local slots = getSlots(construction)
    local origin = slots[source]
    if not origin or not (construction.params.modules or {})[source] then return {} end
    local targets = {}
    for id, slot in pairs(slots) do
        if id ~= source and slot.type == origin.type and not construction.params.modules[id] then
            targets[#targets + 1] = id
        end
    end
    table.sort(targets)
    return targets
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function core.proposal(entity, operation)
    local info, err = core.inspect(entity)
    if not info then return nil, err end
    local construction = component(entity, "CONSTRUCTION")
    local params = core.copy(construction.params)
    local matrix = construction.transf:clone()
    if operation.kind == "building" then
        for _, key in ipairs({"x", "y", "z", "angle"}) do
            if not finite(operation[key]) then return nil, "位移和角度必须是有限数值。" end
        end
        if operation.x == 0 and operation.y == 0 and operation.z == 0 and operation.angle == 0 then
            return nil, "先调整位置、高度或旋转角度。"
        end
        -- Rotate about the building's own origin, keeping tilt/scale intact.
        local origin = matrix:getTransl()
        matrix = api.type.Mat4f.rotZ(operation.angle * math.pi / 180) * matrix
        matrix:setTransl(api.type.Vec3f.new(origin.x + operation.x, origin.y + operation.y, origin.z + operation.z))
    elseif operation.kind == "placement" then
        local position = operation.position
        if not position or not finite(position.x) or not finite(position.y) or not finite(position.z)
            or not finite(operation.angle) or not finite(operation.height) then
            return nil, "请选择有效的地图位置。"
        end
        local origin = matrix:getTransl()
        -- Keep the existing elevation relative to the ground, including raised
        -- or sunken buildings, while the cursor follows the native terrain pick.
        local ground = api.engine.terrain.getHeightAt(api.type.Vec2f.new(origin.x, origin.y))
        local z = position.z + origin.z - ground + operation.height
        if math.abs(position.x - origin.x) < 0.001 and math.abs(position.y - origin.y) < 0.001
            and math.abs(z - origin.z) < 0.001 and operation.angle == 0 then
            return nil, "请选择新的位置或旋转建筑。"
        end
        matrix = api.type.Mat4f.rotZ(operation.angle * math.pi / 180) * matrix
        matrix:setTransl(api.type.Vec3f.new(position.x, position.y, z))
    elseif operation.kind == "nativeplacement" then
        local native = operation.transf
        if not native then return nil, "请选择有效的地图位置。" end
        for i = 1, 16 do
            if not finite(native[i]) then return nil, "请选择有效的地图位置。" end
        end
        local sourceAngle = math.atan(matrix[2], matrix[1])
        local targetAngle = math.atan(native[2], native[1])
        matrix = api.type.Mat4f.rotZ(targetAngle - sourceAngle) * matrix
        matrix:setTransl(native:getTransl())
        local different = false
        for i = 1, 16 do
            if math.abs(matrix[i] - construction.transf[i]) > 0.001 then different = true; break end
        end
        if not different then return nil, "请选择新的位置或旋转建筑。" end
    elseif operation.kind == "module" then
        if operation.source == operation.target then return nil, "请选择另一个插槽。" end
        local source, target = info.slots[operation.source], info.slots[operation.target]
        if not source or not target or source.type ~= target.type then
            return nil, "只能移动到同类插槽。"
        end
        if not params.modules or not params.modules[operation.source] then
            return nil, "原插槽已没有模块，请重新选择。"
        end
        if params.modules[operation.target] then return nil, "目标插槽已有模块。" end
        params.modules[operation.target] = params.modules[operation.source]
        params.modules[operation.source] = nil
    else
        return nil, "未知的移动方式。"
    end
    local entry = api.type.SimpleProposal.ConstructionEntity.new()
    entry.fileName = construction.fileName
    entry.params = params
    entry.transf = matrix
    entry.name = info.name
    local owner = component(entity, "PLAYER_OWNED")
    if owner then
        entry.playerEntity = owner.player
    else
        -- Ask the native replacement helper for neutral ownership rather than
        -- relying on undocumented defaults of ConstructionEntity.new().
        local reference = api.engine.util.proposal.createProposalReplaceConstruction(entity, core.copy(construction.params))
        local index = reference and reference.old2new[entity]
        local original = index ~= nil and reference.toAdd[index + 1]
        if not original then return nil, "游戏无法替换这栋无主建筑。" end
        entry.playerEntity = original.playerEntity
    end
    entry.autoFillSlots = false
    local proposal = api.type.SimpleProposal.new()
    proposal.constructionsToRemove = {entity}
    proposal.constructionsToAdd = {entry}
    -- Native Proposal indices are ZERO based (see company_util.getNeededPermitsForProposal).
    proposal.old2new = {[entity] = 0}
    return proposal, nil, {entity = entity, revision = info.revision, modules = core.copy(params.modules or {})}
end

local function moduleIdentity(module)
    if type(module) == "table" then return module.name, module.variant or 0 end
    return module, 0
end

function core.checkPreview(snapshot, data, proposal)
    if not core.unchanged(snapshot.entity, snapshot.revision) then return false, "建筑已改变，请重新预览。" end
    local errorState = data and data.errorState
    if not errorState or errorState.critical or #(errorState.messages or {}) > 0 then
        local message = errorState and table.concat(errorState.messages or {}, "\n") or ""
        return false, message ~= "" and message or "游戏未接受这个位置，请调整后重新预览。"
    end
    if not proposal or proposal.old2new[snapshot.entity] ~= 0 or not proposal.toAdd[1] then
        return false, "游戏没有返回有效的建筑替换提案。"
    end
    -- Re-slotting a parent can invalidate dependent slots. Never silently discard modules.
    local actual = proposal.toAdd[1].construction.params.modules or {}
    for slot, module in pairs(snapshot.modules) do
        local name, variant = moduleIdentity(module)
        local actualName, actualVariant = moduleIdentity(actual[slot])
        if name ~= actualName or variant ~= actualVariant then
            return false, "该位置会丢失或改变模块，请换一个插槽或位置。"
        end
    end
    for slot in pairs(actual) do
        if snapshot.modules[slot] == nil then return false, "提案改变了其他模块，请重新选择位置。" end
    end
    for _, entity in ipairs(proposal.toRemove or {}) do
        if entity ~= snapshot.entity and component(entity, "CONSTRUCTION") then
            return false, "该位置需要拆除其他建筑，请换一个位置。"
        end
        if component(entity, "SUBCONSTRUCTION") then
            local parent = api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(entity)
            if parent ~= snapshot.entity then return false, "该位置会移除其他建筑的模块，请换一个位置。" end
        end
    end
    return true, "可以移动。"
end

-- ProposalViewer lends its generated Proposal/ProposalData only for the callback.
-- Keep just the validation result; reading those userdata on a later click can
-- dereference a destroyed native map. The SimpleProposal is owned by this mod.
function core.capturePreview(snapshot, data, generated, simpleProposal)
    local valid, message = core.checkPreview(snapshot, data, generated)
    return {valid = valid, message = message, snapshot = snapshot, proposal = simpleProposal}
end

function core.apply(snapshot, preview, proposal, callback)
    if not preview or not preview.valid or preview.snapshot ~= snapshot or preview.proposal ~= proposal then
        return false, "请等待当前移动位置的预览检查完成。"
    end
    if not core.unchanged(snapshot.entity, snapshot.revision) then
        return false, "建筑已改变，请重新预览。"
    end
    local context = api.type.Context.new()
    local player = api.engine.util.getPlayer()
    local account = component(player, "ACCOUNT")
    local balanceBefore = account and account.balance
    local refundables = api.gui.construction.getRefundableEntities()
    if refundables ~= nil then context.refundableEntities = refundables end
    -- Leave the command context's payer unset, as shipped scripted world updates
    -- do. Ownership is explicitly retained by each ConstructionEntity instead.
    -- playerInitiated=false alone still bills an explicitly assigned payer.
    -- Keep error checks enabled and dust off.
    -- This is one mapped update, never a demolition followed by a second build.
    -- Rebuild from our owned input, as native tools do, instead of submitting a
    -- ProposalViewer result whose native lifetime ended with its callback.
    debugPrint("[xiaom_building_mover] submit owned SimpleProposal entity=" .. tostring(snapshot.entity)
        .. " payer=" .. tostring(context.player))
    api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, context, false, false, false),
        function(result, success)
            debugPrint("[xiaom_building_mover] placement completed success=" .. tostring(success))
            local updatedAccount = component(player, "ACCOUNT")
            local proposalData = result.resultProposalData
            debugPrint("[xiaom_building_mover] costs=" .. tostring(proposalData and proposalData.costs)
                .. " withCostRep=" .. tostring(result.withCostRep)
                .. " balance=" .. tostring(balanceBefore) .. " -> " .. tostring(updatedAccount and updatedAccount.balance))
            local newEntity
            if success then
                -- The installed engine returns numeric entity IDs here. Its
                -- type definition describes {entity, revision} pairs instead;
                -- accept both without indexing a number in the GUI callback.
                for _, entry in ipairs(result.resultEntities or {}) do
                    local entity = type(entry) == "number" and entry
                        or type(entry) == "table" and entry[1]
                    if type(entity) == "number" and component(entity, "CONSTRUCTION") then
                        newEntity = entity
                        break
                    end
                end
            end
            debugPrint("[xiaom_building_mover] result construction=" .. tostring(newEntity))
            callback(success, newEntity)
            debugPrint("[xiaom_building_mover] completion handler returned")
        end)
    return true
end

return core
