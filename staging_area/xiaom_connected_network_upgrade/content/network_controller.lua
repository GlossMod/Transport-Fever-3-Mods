local core = ug_require "xiaom_connected_network_upgrade::/network_core.lua"
local controller = {}
local active, serial = nil, 0

local function bump(session) session.version = session.version + 1 end
local function issue(session, reason, message, entity, failed)
    local key = reason or "rejected"
    session.reasons[key] = (session.reasons[key] or 0) + 1
    if failed then session.failed = session.failed + 1 else session.skipped = session.skipped + 1 end
    if #session.details < 100 then session.details[#session.details + 1] = {entity = entity, reason = key, message = message or ""} end
    if message and message ~= "" then debugPrint("[xiaom_connected_network_upgrade] " .. tostring(entity) .. " " .. key .. ": " .. message) end
end

local function done(session, message)
    session.phase, session.message = "done", message or "complete"
    session.previewProposal = nil
    bump(session)
end

function controller.current() return active end
function controller.busy() return active and (active.phase == "applying" or active.pending) end

function controller.invalidate(owner, reason)
    local s = active
    if not s or s.owner ~= owner or s.phase == "done" or s.phase == "stale" then return end
    s.previewProposal = nil
    if s.phase == "applying" then
        s.cancelled, s.stopReason = true, reason or "target_changed"
        if not s.pending then done(s, s.stopReason) end
    else
        s.phase, s.message = "stale", reason or "target_changed"
        bump(s)
    end
end

function controller.cancel(session)
    if session ~= active then return end
    session.cancelled, session.stopReason = true, "cancelled"
    if not session.pending then done(session, "cancelled") else session.message = "cancelling"; bump(session) end
end

function controller.clear(session)
    if session and session ~= active then return false end
    if controller.busy() then controller.cancel(active); return false end
    active = nil
    return true
end

function controller.begin(owner, entity, intent, sourceKey, readSource)
    if controller.busy() then return nil end
    local edge = core.component(entity, "BASE_EDGE")
    if not core.matches(edge, intent.network) then return nil end
    serial = serial + 1
    active = {
        id = serial, owner = owner, intent = intent, sourceKey = sourceKey, readSource = readSource,
        phase = "scanning", message = "scanning", version = 0, seed = entity,
        queue = {entity}, head = 1, visited = {[entity] = true}, nodes = {}, entries = {},
        preflightIndex = 1, applyIndex = 1, ready = {}, total = 0, unchanged = 0,
        skipped = 0, failed = 0, succeeded = 0, processed = 0, estimate = 0, actualCost = 0,
        reasons = {}, details = {}, entityMap = {}, pending = false, cancelled = false,
    }
    return active
end

local function sourceValid(s)
    if not s.readSource then return true end
    local ok, key = pcall(s.readSource)
    return ok and key == s.sourceKey
end

local function scan(s)
    for _ = 1, 128 do
        local entity = s.queue[s.head]
        if not entity then
            s.phase, s.message = "checking", "checking"
            bump(s)
            return
        end
        s.head = s.head + 1
        local edge = core.component(entity, "BASE_EDGE")
        if core.matches(edge, s.intent.network) then
            s.total = s.total + 1
            s.entries[#s.entries + 1] = core.snapshot(entity)
            -- Expand first, including through already-matching/locked edges.
            for _, node in ipairs({edge.node0, edge.node1}) do
                if not s.nodes[node] then
                    s.nodes[node] = core.revision(node)
                    for _, adjacent in ipairs(core.neighbors(node, s.intent.network) or {}) do
                        if not s.visited[adjacent] then
                            s.visited[adjacent] = true
                            s.queue[#s.queue + 1] = adjacent
                        end
                    end
                end
            end
        else issue(s, "changed", nil, entity) end
    end
    bump(s)
end

local function preflight(s)
    -- Native geometry/error checks are intentionally spread across frames.
    for _ = 1, 4 do
        local snapshot = s.entries[s.preflightIndex]
        if not snapshot then
            s.phase, s.message = "ready", #s.ready > 0 and "ready" or "nothing"
            s.queue, s.visited = nil, nil
            bump(s)
            return
        end
        s.preflightIndex = s.preflightIndex + 1
        if not core.unchanged(snapshot.entity, snapshot.revision) then
            issue(s, "changed", nil, snapshot.entity)
        else
            local ok, entry, reason, detail, proposal = pcall(core.preflight, snapshot.entity, s.intent)
            if not ok then issue(s, "api", tostring(entry), snapshot.entity)
            elseif entry then
                entry.snapshot = snapshot
                s.ready[#s.ready + 1] = entry
                s.estimate = s.estimate + entry.cost
                if not s.previewProposal then s.previewProposal = proposal; s.previewVersion = s.version + 1 end
            elseif reason == "unchanged" then s.unchanged = s.unchanged + 1
            else issue(s, reason, detail, snapshot.entity) end
        end
    end
    bump(s)
end

function controller.confirm(session)
    if session ~= active or session.phase ~= "ready" or #session.ready == 0 or not sourceValid(session) then return false end
    session.phase, session.message, session.previewProposal = "verifying", "verifying", nil
    session.verifyIndex, session.verifyNodeIndex = 1, 1
    session.nodeKeys = {}
    for node in pairs(session.nodes) do session.nodeKeys[#session.nodeKeys + 1] = node end
    bump(session)
    return true
end

local function verify(s)
    -- Catch a changed graph or target before starting any world command.
    for _ = 1, 128 do
        local snapshot = s.entries[s.verifyIndex]
        if snapshot then
            if not core.unchanged(snapshot.entity, snapshot.revision) then controller.invalidate(s.owner, "world_changed"); return end
            s.verifyIndex = s.verifyIndex + 1
        else
            local node = s.nodeKeys[s.verifyNodeIndex]
            if not node then
                s.phase, s.message = "applying", "applying"
                s.entries, s.nodes, s.nodeKeys = nil, nil, nil
                bump(s)
                return
            end
            if not core.unchanged(node, s.nodes[node]) then controller.invalidate(s.owner, "world_changed"); return end
            s.verifyNodeIndex = s.verifyNodeIndex + 1
        end
    end
    bump(s)
end

local function resultError(result)
    local data = result and result.resultProposalData
    return data and data.errorState and table.concat(data.errorState.messages or {}, "; ") or ""
end

-- Borrowed command results are inspected only inside the completion callback.
local function resultMapping(result, oldEntity, shape)
    local found = {}
    local function consider(entity)
        local edge = core.component(entity, "BASE_EDGE")
        if core.sameGeometry(shape, edge) then found[entity] = true end
    end
    for _, entry in ipairs(result and result.resultEntities or {}) do
        consider(type(entry) == "number" and entry or entry[1])
    end
    for _, segment in ipairs(result and result.proposal and result.proposal.proposal.addedSegments or {}) do consider(segment.entity) end
    local entity, count = nil, 0
    for candidate in pairs(found) do entity, count = candidate, count + 1 end
    if count == 1 then return {[oldEntity] = entity} end
    return {}
end

local function applyNext(s)
    if s.pending then return end
    if s.cancelled then done(s, s.stopReason or "cancelled"); return end
    local entry = s.ready[s.applyIndex]
    if not entry then done(s); return end
    s.applyIndex = s.applyIndex + 1
    local snapshot, entity = entry.snapshot, entry.snapshot.entity
    if not core.unchanged(entity, snapshot.revision) then
        issue(s, "changed", nil, entity)
        s.processed = s.processed + 1; bump(s); return
    end
    local ok, fresh, reason, detail, proposal = pcall(core.preflight, entity, s.intent)
    if not ok then issue(s, "api", tostring(fresh), entity, true); s.processed = s.processed + 1; bump(s); return end
    if not fresh then
        if reason == "unchanged" then s.unchanged = s.unchanged + 1 else issue(s, reason, detail, entity, true) end
        s.processed = s.processed + 1; bump(s); return
    end
    local balance = api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer())
    if balance ~= nil and fresh.cost > math.max(0, balance) then
        s.applyIndex = s.applyIndex - 1
        done(s, "funds")
        return
    end
    local command = api.cmd.makeWorldBuildProposalCmd(proposal, core.context(), false, true, true)
    s.pending = true
    bump(s)
    local sent, errorMessage = pcall(api.cmd.sendCommand, command, function(result, success)
        s.pending = false
        s.processed = s.processed + 1
        if success then
            s.succeeded = s.succeeded + 1
            local data = result and result.resultProposalData
            s.actualCost = s.actualCost + (data and data.costs or fresh.cost)
            local mapped, map = pcall(resultMapping, result, entity, snapshot.shape)
            if not mapped then
                debugPrint("[xiaom_connected_network_upgrade] result mapping unavailable: " .. tostring(map))
                map = {}
            end
            for old, new in pairs(map) do s.entityMap[old] = new end
            -- Apply only proven result mappings, never a nearest road guess.
            for i = s.applyIndex, #s.ready do
                local nextSnapshot = s.ready[i].snapshot
                local replacement = map[nextSnapshot.entity]
                if replacement and core.sameGeometry(nextSnapshot.shape, core.component(replacement, "BASE_EDGE")) then
                    nextSnapshot.entity, nextSnapshot.revision = replacement, core.revision(replacement)
                end
            end
        else
            issue(s, "rejected", resultError(result), entity, true)
            local currentBalance = api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer())
            if currentBalance ~= nil and fresh.cost > math.max(0, currentBalance) then
                s.cancelled, s.stopReason = true, "funds"
            end
        end
        debugPrint("[xiaom_connected_network_upgrade] result entity=" .. tostring(entity) .. " success=" .. tostring(success)
            .. " completed=" .. tostring(s.processed) .. "/" .. tostring(#s.ready))
        if s.cancelled then done(s, s.stopReason or "cancelled") else bump(s) end
    end)
    if not sent then
        s.pending = false
        s.processed = s.processed + 1
        issue(s, "api", tostring(errorMessage), entity, true)
        bump(s)
    end
end

function controller.step(session)
    if session ~= active or session.phase == "done" or session.phase == "stale" then return end
    if not sourceValid(session) then controller.invalidate(session.owner, "target_changed"); return end
    local ok, message = pcall(function()
        if session.phase == "scanning" then scan(session)
        elseif session.phase == "checking" then preflight(session)
        elseif session.phase == "verifying" then verify(session)
        elseif session.phase == "applying" then applyNext(session) end
    end)
    if not ok then
        debugPrint("[xiaom_connected_network_upgrade] controller error: " .. tostring(message))
        issue(session, "api", tostring(message), session.seed, true)
        if session.pending then session.cancelled, session.stopReason = true, "error"
        else done(session, "error") end
    end
end

return controller
