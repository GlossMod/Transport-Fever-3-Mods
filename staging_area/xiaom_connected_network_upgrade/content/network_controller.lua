local core = ug_require "xiaom_connected_network_upgrade::/network_core.lua"
local controller = {}
local active, serial = nil, 0

local function bump(session) session.version = session.version + 1 end
local function log(session, event, message)
    debugPrint("[xiaom_connected_network_upgrade] session=" .. tostring(session.id)
        .. " phase=" .. tostring(session.phase) .. " event=" .. event .. " " .. (message or ""))
end
local function summary(session)
    return "found=" .. tostring(session.total) .. " checked=" .. tostring(session.checked)
        .. " planned=" .. tostring(#session.ready) .. " unchanged=" .. tostring(session.unchanged)
        .. " succeeded=" .. tostring(session.succeeded) .. " skipped=" .. tostring(session.skipped)
        .. " failed=" .. tostring(session.failed) .. " processed=" .. tostring(session.processed)
        .. " estimate=" .. tostring(session.estimate) .. " charged=" .. tostring(session.actualCost)
        .. " reasons=" .. core.errorText(session.reasons)
end
local function issue(session, reason, message, entity, failed, diagnostic)
    local key = reason or "rejected"
    session.reasons[key] = (session.reasons[key] or 0) + 1
    if not diagnostic then
        if failed then session.failed = session.failed + 1 else session.skipped = session.skipped + 1 end
    end
    if message and message ~= "" then
        local normalized = message:gsub("0x%x+", "<address>"):gsub("table: %x+", "<table>"):gsub("userdata: %x+", "<userdata>")
        local detailKey = key .. "|" .. normalized
        local previous = session.detailKeys[detailKey]
        if previous then previous.count = previous.count + 1
        else
            local item = {entity = entity, reason = key, message = message, count = 1}
            session.detailKeys[detailKey] = item
            if #session.details < 100 then session.details[#session.details + 1] = item end
            log(session, "issue", "entity=" .. tostring(entity) .. " stage=" .. key .. "\n" .. message)
        end
    end
end

local function done(session, message)
    session.finishedPhase = session.finishedPhase or session.phase
    session.phase, session.message = "done", message or "complete"
    session.previewProposal = nil
    session.quote = nil
    log(session, "stop", "from=" .. tostring(session.finishedPhase) .. " reason=" .. session.message .. " " .. summary(session))
    bump(session)
end

function controller.current() return active end
function controller.busy() return active and (active.phase == "applying" or active.pending) end

function controller.invalidate(owner, reason)
    local s = active
    if not s or s.owner ~= owner or s.phase == "done" or s.phase == "stale" then return end
    s.previewProposal = nil
    s.quote = nil
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
        reasons = {}, details = {}, detailKeys = {}, entityMap = {}, pending = false, cancelled = false,
        checked = 0, quoteSerial = 0,
    }
    log(active, "begin", "seed=" .. tostring(entity) .. " network=" .. tostring(intent.network)
        .. " source=" .. tostring(edge.roadTemplate) .. " structure=" .. tostring(edge.type)
        .. "/" .. tostring(edge.typeIndex) .. " target=" .. intent.key)
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
            log(s, "scan_complete", "found=" .. tostring(s.total))
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
                    s.nodes[node] = core.nodeSnapshot(node, s.intent.network)
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

local function requestQuote(s, entry, proposal, purpose)
    s.quoteSerial = s.quoteSerial + 1
    s.quote = {id = s.quoteSerial, entry = entry, entity = entry.snapshot.entity,
        proposal = proposal, purpose = purpose, waitSteps = 0}
    bump(s)
end

function controller.acceptQuote(s, id, receipt)
    if s ~= active or not s.quote or s.quote.id ~= id or s.quote.receipt then return end
    s.quote.receipt = receipt
    bump(s)
end

local function preflight(s)
    -- Skip simple classifications in small batches. Native checks run through
    -- ProposalViewer, one owned request at a time, in the construction context.
    for _ = 1, 16 do
        local snapshot = s.entries[s.preflightIndex]
        if not snapshot then
            s.phase, s.message = "ready", #s.ready > 0 and "ready" or "nothing"
            s.queue, s.visited = nil, nil
            log(s, "preview_complete", summary(s))
            bump(s)
            return
        end
        s.preflightIndex = s.preflightIndex + 1
        if not core.snapshotMatches(snapshot) then
            issue(s, "changed", nil, snapshot.entity)
            s.checked = s.checked + 1
        else
            local ok, entry, reason, detail, proposal = core.protect(core.prepare, snapshot.entity, s.intent)
            if not ok then
                issue(s, "api", entry, snapshot.entity)
                s.checked = s.checked + 1
                done(s, "error")
                return
            elseif reason == "native" then
                issue(s, reason, detail, snapshot.entity)
                s.checked = s.checked + 1
                done(s, "native_error")
                return
            elseif entry then
                entry.snapshot = snapshot
                requestQuote(s, entry, proposal, "preview")
                return
            elseif reason == "unchanged" then s.unchanged = s.unchanged + 1
            else issue(s, reason, detail, snapshot.entity) end
            s.checked = s.checked + 1
        end
    end
    bump(s)
end

function controller.confirm(session)
    if session ~= active or session.phase ~= "ready" or session.quote or #session.ready == 0 or not sourceValid(session) then return false end
    log(session, "confirm", "ready=" .. tostring(#session.ready) .. " estimate=" .. tostring(session.estimate))
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
            if not core.snapshotMatches(snapshot) then controller.invalidate(s.owner, "world_changed"); return end
            s.verifyIndex = s.verifyIndex + 1
        else
            local node = s.nodeKeys[s.verifyNodeIndex]
            if not node then
                s.phase, s.message = "applying", "applying"
                s.entries, s.nodes, s.nodeKeys = nil, nil, nil
                bump(s)
                return
            end
            if not core.nodeMatches(s.nodes[node]) then controller.invalidate(s.owner, "world_changed"); return end
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

local function submit(s, entry, proposal, receipt)
    local snapshot, entity = entry.snapshot, entry.snapshot.entity
    if not core.snapshotMatches(snapshot) then
        issue(s, "changed", nil, entity)
        s.processed = s.processed + 1; bump(s); return
    end
    local cost = receipt.cost
    local balance = api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer())
    if balance ~= nil and cost > math.max(0, balance) then
        s.applyIndex = s.applyIndex - 1
        done(s, "funds")
        return
    end
    local command = api.cmd.makeWorldBuildProposalCmd(proposal, core.context(), false, true, true)
    log(s, "submit", "entity=" .. tostring(entity) .. " quote=" .. tostring(cost) .. " balance=" .. tostring(balance))
    s.pending = true
    bump(s)
    local completed = false
    local sent, errorMessage = core.protect(api.cmd.sendCommand, command, function(result, success)
        if completed then return end
        completed = true
        s.pending = false
        s.processed = s.processed + 1
        if success then s.succeeded = s.succeeded + 1 else s.failed = s.failed + 1 end
        -- The native result is borrowed and must be read before returning.
        -- Guard the asynchronous callback independently from sendCommand.
        local handled, callbackError = core.protect(function()
          if success then
            local data = result and result.resultProposalData
            s.actualCost = s.actualCost + (data and data.costs or cost)
            local mapped, map = core.protect(resultMapping, result, entity, snapshot.shape)
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
                    s.ready[i].snapshot = core.snapshot(replacement)
                end
            end
            if result and result.proposal then
                -- Match the native replacement UI's refundable-entity updates.
                local validEntities = {}
                for _, entityRevision in ipairs(result.resultEntities or {}) do
                    local current = type(entityRevision) == "number" and entityRevision or entityRevision[1]
                    local revision = type(entityRevision) ~= "number" and entityRevision[2] or nil
                    if revision and core.unchanged(current, revision.num) or not revision and api.engine.entityExists(current) then
                        validEntities[#validEntities + 1] = current
                    end
                end
                api.gui.construction.updateRefundableEntities(validEntities, result.proposal.proposal)
            end
          else
            issue(s, "rejected", resultError(result), entity, true, true)
            local currentBalance = api.engine.util.finance.getPlayersBalance(api.engine.util.getPlayer())
            if currentBalance ~= nil and cost > math.max(0, currentBalance) then
                s.cancelled, s.stopReason = true, "funds"
            end
          end
        end)
        if not handled then
            -- A successful world command must never be retried due to a UI or
            -- mapping error. Stop the queue and keep the completed upgrade.
            issue(s, "api", "command callback: " .. callbackError, entity, true, true)
            s.cancelled, s.stopReason = true, "error"
        end
        log(s, "result", "entity=" .. tostring(entity) .. " success=" .. tostring(success)
            .. " completed=" .. tostring(s.processed) .. "/" .. tostring(#s.ready))
        if s.cancelled then done(s, s.stopReason or "cancelled") else bump(s) end
    end)
    if not sent and not completed then
        completed = true
        s.pending = false
        s.processed = s.processed + 1
        issue(s, "api", tostring(errorMessage), entity, true)
        done(s, "error")
    end
end

local function resolveQuote(s)
    local request = s.quote
    local receipt = request.receipt
    if not receipt then
        request.waitSteps = request.waitSteps + 1
        if request.waitSteps < 600 then return end
        issue(s, "preview_timeout", "ProposalViewer callback did not return for request=" .. tostring(request.id)
            .. " purpose=" .. request.purpose, request.entity, request.purpose == "apply")
        -- A missing preview callback is not a per-segment rejection. Avoid
        -- waiting the same timeout for every remaining segment.
        done(s, "error")
        return
    end
    s.quote = nil
    local snapshot = request.entry.snapshot
    if not core.snapshotMatches(snapshot) then receipt = {valid = false, reason = "changed"} end
    if receipt.reason == "api" then
        issue(s, "api", receipt.detail, snapshot.entity, request.purpose == "apply")
        if request.purpose == "preview" then s.checked = s.checked + 1 else s.processed = s.processed + 1 end
        done(s, "error")
        return
    end
    if request.purpose == "preview" then
        s.checked = s.checked + 1
        if receipt.valid then
            request.entry.cost = receipt.cost
            s.ready[#s.ready + 1] = request.entry
            s.estimate = s.estimate + receipt.cost
            if not s.previewProposal then s.previewProposal = request.proposal; s.previewVersion = request.id end
        else issue(s, receipt.reason, receipt.detail, snapshot.entity) end
    elseif receipt.valid then
        submit(s, request.entry, request.proposal, receipt)
    else
        issue(s, receipt.reason, receipt.detail, snapshot.entity, receipt.reason ~= "changed")
        s.processed = s.processed + 1
    end
    bump(s)
end

local function applyNext(s)
    if s.pending then return end
    if s.cancelled then done(s, s.stopReason or "cancelled"); return end
    local entry = s.ready[s.applyIndex]
    if not entry then done(s); return end
    s.applyIndex = s.applyIndex + 1
    local snapshot = entry.snapshot
    if not core.snapshotMatches(snapshot) then
        issue(s, "changed", nil, snapshot.entity)
        s.processed = s.processed + 1; bump(s); return
    end
    local ok, fresh, reason, detail, proposal = core.protect(core.prepare, snapshot.entity, s.intent)
    if not ok then
        issue(s, "api", fresh, snapshot.entity, true)
        s.processed = s.processed + 1
        done(s, "error")
        return
    elseif reason == "native" then
        issue(s, reason, detail, snapshot.entity, true)
        s.processed = s.processed + 1
        done(s, "native_error")
        return
    elseif fresh then
        fresh.snapshot = snapshot
        requestQuote(s, fresh, proposal, "apply")
        return
    elseif reason == "unchanged" then s.unchanged = s.unchanged + 1
    else issue(s, reason, detail, snapshot.entity, true) end
    s.processed = s.processed + 1
    bump(s)
end

function controller.step(session)
    if session ~= active or session.phase == "done" or session.phase == "stale" then return end
    if not sourceValid(session) then controller.invalidate(session.owner, "target_changed"); return end
    local ok, message = core.protect(function()
        if session.quote then resolveQuote(session); return end
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
