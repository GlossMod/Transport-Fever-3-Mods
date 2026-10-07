local core = ug_require "xiaom_vehicle_upgrade::/upgrade_core.lua"
local native = ug_require "xiaom_vehicle_upgrade::/upgrade_native.lua"
local controller = {}
local session, catalogContext
local revision = 0

local function touch() revision = revision + 1 end
local function report(message) session.message = message; touch() end
local function trace(message) debugPrint("[xiaom_vehicle_upgrade] " .. message) end
local function review(message)
    session.reviewMessage = message
    trace("review required phase=" .. session.phase .. ": " .. message)
    report(message)
end

local function changedSnapshot(row, snapshot, phase)
    local field, label, detail = core.snapshotChange(row.snapshot, snapshot)
    trace("configuration changed phase=" .. phase .. " entity=" .. row.entity .. " field=" .. field .. " " .. detail)
    return snapshot.name .. "：" .. label .. "变化"
end

local function recordQuoteIncrease(row, previousNet, phase)
    trace(string.format("quote increased phase=%s entity=%s before=%.17g after=%.17g delta=%.17g accepted=true",
        phase, tostring(row.entity), previousNet, row.quote.net, row.quote.net - previousNet))
end

local function noteReview(reason)
    session.refreshed = true
    session.reviewCount = session.reviewCount + 1
    session.reviewReason = session.reviewReason or reason
end

local function inspect(entity)
    local ok, snapshot, reason = pcall(native.snapshot, entity)
    if not ok then
        debugPrint("[xiaom_vehicle_upgrade] inspect failed: " .. tostring(snapshot))
        return nil, "无法读取载具数据，详情见游戏日志"
    end
    return snapshot, reason
end

local function planRow(snapshot, previous)
    local catalog, byKey = native.catalog()
    local restrictions = native.restrictions(session.gameCtx)
    local row = {entity = snapshot.entity, snapshot = snapshot, changes = {}, candidates = {}, reasons = {},
        selected = false, expanded = previous and previous.expanded or false, status = "待选择"}
    for _, unit in ipairs(snapshot.units) do
        local compatibleChoices = core.candidates(unit.old, catalog, unit.purpose, native.year(), restrictions)
        local choices, recommended = {}, nil
        for _, candidate in ipairs(compatibleChoices) do
            if native.preservesManual(unit, candidate) then
                choices[#choices + 1] = candidate
                if not recommended and core.nonRegressing(unit.old, candidate, unit.purpose) then recommended = candidate.key end
            end
        end
        row.candidates[unit.index] = choices
        local selected = recommended
        local prevUnit = previous and previous.snapshot and previous.snapshot.units[unit.index]
        if prevUnit and prevUnit.groupKey == unit.groupKey then
            local override = previous.changes[unit.index]
            -- Keeping an original unit is a meaningful user choice.
            selected = override
            if override and override ~= unit.old.key then
                local item = byKey[override]
                if not core.compatible(unit.old, item, unit.purpose, native.year(), restrictions) or not native.preservesManual(unit, item) then selected = nil end
            end
        end
        row.changes[unit.index] = selected
        row.reasons[unit.index] = #choices == 0 and "没有可购买且能保留货物配置的同用途更新车型" or
            (not recommended and "新车型存在性能下降，可手动选择" or "")
        if selected and selected ~= unit.old.key then row.selected = true end
    end
    if previous then row.selected = previous.selected end
    return row
end

local function quoteRow(row)
    if not row.snapshot then return end
    local _, byKey = native.catalog()
    row.quote, row.error = core.quote(row.snapshot, row.changes, byKey)
    row.config, row.quantities = nil, nil
    if row.quote and row.quote.changed > 0 then
        local ok, config, reason, quantities = pcall(native.build, row.snapshot, row.changes)
        if not ok then
            debugPrint("[xiaom_vehicle_upgrade] configuration failed: " .. tostring(config))
            row.error = "无法建立安全编组，详情见游戏日志"
        elseif not config then row.error = reason
        else
            row.config = config; row.quantities = quantities
            local checkOk, message = pcall(native.missionError, quantities, false)
            if not checkOk then
                debugPrint("[xiaom_vehicle_upgrade] purchase check failed entity=" .. row.entity .. ": " .. tostring(message))
                row.error = "无法检查购买限制，具体原因已记录到游戏日志"
            else row.error = message end
        end
    end
end

function controller.open(gameCtx)
    if session and (session.phase == "checking" or session.phase == "applying") then return end
    local cached = native.catalogReady() and catalogContext == gameCtx
    if not cached then native.resetCatalog() end
    catalogContext = gameCtx
    session = {gameCtx = gameCtx, phase = cached and "scan" or "catalog", rows = {}, entities = cached and native.entities() or {}, scanIndex = 1,
        message = "正在读取可用车型…", filters = {carrier = "all", line = "all", search = ""},
        refreshIndex = 1, results = {success = 0, failed = 0}, groupExpanded = {}, lastBalance = native.balance()}
    touch()
end

function controller.close()
    if session and (session.phase == "applying" or session.phase == "checking") then return false end
    session = nil; touch(); return true
end

function controller.read() return session, revision end
function controller.busy()
    return session and session.phase ~= "idle" and session.phase ~= "result"
end

function controller.totals()
    local result = {purchase = 0, refund = 0, net = 0, count = 0, blocked = 0, balance = native.balance()}
    for _, row in ipairs(session and session.rows or {}) do
        if row.selected and row.status ~= "成功" then
            if row.quote and row.quote.changed > 0 then
                result.purchase = result.purchase + row.quote.purchase
                result.refund = result.refund + row.quote.refund
                result.net = result.net + row.quote.net
                result.count = result.count + 1
            end
            if row.error or not row.quote or (row.quote.changed > 0 and not row.config) then result.blocked = result.blocked + 1 end
        end
    end
    result.enough = result.net <= 0 or result.balance == nil or result.balance >= result.net
    return result
end

function controller.matches(row)
    if not row.snapshot then return session.filters.carrier == "all" and session.filters.line == "all" end
    local filters = session.filters
    if filters.carrier ~= "all" and tostring(row.snapshot.carrier) ~= filters.carrier then return false end
    if filters.line ~= "all" and tostring(row.snapshot.line) ~= filters.line then return false end
    local text = string.lower(filters.search)
    if text == "" then return true end
    local haystack = row.snapshot.name .. " " .. row.snapshot.lineName
    for _, unit in ipairs(row.snapshot.units) do haystack = haystack .. " " .. unit.old.name end
    return string.find(string.lower(haystack), text, 1, true) ~= nil
end

function controller.filter(key, value)
    if controller.busy() then return end
    session.filters[key] = value; touch()
end

function controller.select(entity, value)
    if controller.busy() then return end
    for _, row in ipairs(session.rows) do
        if row.entity == entity and row.status ~= "成功" then row.selected = value == true; touch(); return end
    end
end

function controller.selectAll(value)
    if controller.busy() then return end
    for _, row in ipairs(session.rows) do
        if controller.matches(row) and row.status ~= "成功" then
            row.selected = value and row.quote and row.quote.changed > 0 and not row.error or false
        end
    end
    touch()
end

function controller.target(entity, unitIndex, targetKey)
    if controller.busy() then return end
    for _, row in ipairs(session.rows) do
        if row.entity == entity and row.snapshot and row.status ~= "成功" then
            local unit = row.snapshot.units[unitIndex]
            local _, byKey = native.catalog()
            local restrictions = native.restrictions(session.gameCtx)
            if targetKey ~= "keep" and not core.compatible(unit.old, byKey[targetKey], unit.purpose, native.year(), restrictions) then return end
            if targetKey ~= "keep" and not native.preservesManual(unit, byKey[targetKey]) then return end
            row.changes[unitIndex] = targetKey ~= "keep" and targetKey or nil
            row.status = "待选择"; quoteRow(row)
            if row.quote and row.quote.changed > 0 then row.selected = true else row.selected = false end
            touch(); return
        end
    end
end

function controller.groupTarget(groupKey, targetKey)
    if controller.busy() then return end
    -- Applying a group target affects the rows shown by the current filters.
    for _, row in ipairs(session.rows) do
        if controller.matches(row) and row.snapshot and row.status ~= "成功" then
            for _, unit in ipairs(row.snapshot.units) do
                if unit.groupKey == groupKey then controller.target(row.entity, unit.index, targetKey) end
            end
        end
    end
end

function controller.toggleGroup(key)
    session.groupExpanded[key] = not session.groupExpanded[key]; touch()
end

function controller.toggleRow(row) row.expanded = not row.expanded; touch() end

local function stop(message, failedRow)
    session.phase = "result"; session.pending = nil
    if failedRow then
        failedRow.status = "失败"; failedRow.error = message
        session.results.failed = session.results.failed + 1
    end
    for _, row in ipairs(session.queue or {}) do
        if row.status == "排队中" then row.status = "未执行" end
    end
    trace("queue stopped entity=" .. tostring(failedRow and failedRow.entity) .. " reason=" .. message)
    review(message .. "；成功 " .. session.results.success .. "，失败 " .. session.results.failed .. "，其余未执行。")
end

function controller.confirm()
    trace("confirm received phase=" .. tostring(session and session.phase or "closed"))
    if not session or controller.busy() then trace("confirm ignored: window closed or busy"); return false end
    local totals = controller.totals()
    trace(string.format("confirm selection count=%d blocked=%d net=%.17g balance=%s",
        totals.count, totals.blocked, totals.net, tostring(totals.balance)))
    if totals.count == 0 then review("请先选择有升级方案的载具"); return false end
    if totals.blocked > 0 then review("已选载具有无效方案，请展开查看原因"); return false end
    if not totals.enough then review("余额不足，请减少升级数量或修改目标车型"); return false end
    session.phase = "checking"; session.queue = {}; session.checkIndex = 1
    session.previewNet = totals.net; session.refreshed = false; session.quantities = {}
    session.reviewMessage = nil; session.reviewReason = nil; session.reviewCount = 0
    for _, row in ipairs(session.rows) do
        if row.selected and row.quote and row.quote.changed > 0 and row.status ~= "成功" then
            session.queue[#session.queue + 1] = row
        end
    end
    trace("preflight started count=" .. #session.queue)
    report("正在重新核对编组、载荷、价格和购买限制…")
    return true
end

local function checkStep()
    for _ = 1, 6 do
        local row = session.queue[session.checkIndex]
        if not row then
            local totals = controller.totals()
            if session.refreshed then
                trace(string.format("preflight deferred reasons=%d preview=%.17g current=%.17g",
                    session.reviewCount, session.previewNet, totals.net))
                session.phase = "idle"
                review("未开始升级：" .. (session.reviewReason or "载具配置变化") .. "。预览已更新；请核对后再次确认。")
                return
            end
            if totals.blocked > 0 or not totals.enough then
                session.phase = "idle"
                review(totals.blocked > 0 and "未开始升级：方案无法执行，请检查预览" or
                    "未开始升级：余额不足以支付最新报价，请减少升级数量或修改目标")
                return
            end
            local errorMessage = native.missionError(session.quantities, false)
            if errorMessage then session.phase = "idle"; review("未开始升级：" .. errorMessage); return end
            table.sort(session.queue, function(a, b)
                if a.quote.net ~= b.quote.net then return a.quote.net < b.quote.net end
                return a.entity < b.entity
            end)
            for _, item in ipairs(session.queue) do item.status = "排队中" end
            session.phase = "applying"; session.applyIndex = 1
            session.results = {success = 0, failed = 0}; session.startBalance = native.balance()
            session.actualNet = 0
            trace("preflight passed count=" .. #session.queue .. " net=" .. totals.net)
            report("已确认，开始逐辆升级…"); return
        end
        local snapshot, reason = inspect(row.entity)
        if not snapshot then
            row.error = reason; row.config = nil; session.phase = "idle"
            review("载具 " .. row.entity .. "：" .. reason .. "，请取消选择该载具或重新扫描"); return
        end
        local changed = snapshot.signature ~= row.snapshot.signature
        local previousNet = row.quote and row.quote.net
        if changed then
            noteReview(changedSnapshot(row, snapshot, "preflight"))
            local updated = planRow(snapshot, row)
            for key in pairs(row) do row[key] = nil end
            for key, value in pairs(updated) do row[key] = value end
        else row.snapshot = snapshot end
        local restrictions, protected = native.restrictions(session.gameCtx)
        if protected[row.entity] then row.error = "任务保护载具不能升级"; row.config = nil
        else
            for _, unit in ipairs(snapshot.units) do
                local key = row.changes[unit.index]
                local _, byKey = native.catalog()
                if key and not core.compatible(unit.old, byKey[key], unit.purpose, native.year(), restrictions) then
                    trace("target unavailable entity=" .. row.entity .. " unit=" .. unit.index .. " target=" .. key)
                    row.changes[unit.index] = nil; noteReview(snapshot.name .. "：目标车型已不可购买")
                end
            end
            quoteRow(row)
            -- Price changes are accepted by the player. Refresh the quote and
            -- retain the current-balance check instead of requiring a new click.
            if previousNet and row.quote and row.quote.net > previousNet then recordQuoteIncrease(row, previousNet, "preflight") end
        end
        if row.error then session.phase = "idle"; review("未开始升级：" .. row.snapshot.name .. "：" .. row.error); return end
        for id, quantity in pairs(row.quantities or {}) do
            session.quantities[id] = (session.quantities[id] or 0) + quantity
        end
        session.checkIndex = session.checkIndex + 1; touch()
    end
end

local function applyStep()
    if session.pending then return end
    local row = session.queue[session.applyIndex]
    if not row then
        session.phase = "result"
        local after = native.balance()
        local difference = after and session.startBalance and session.startBalance - after
        report("升级完成：成功 " .. session.results.success .. " 辆。" ..
            (difference and ("账户余额变化 " .. tostring(difference) .. "（运行中的经营收支也会影响余额）") or ""))
        return
    end
    -- Final per-row check prevents stale configs being applied while the rest
    -- of the batch runs. Use the current quote, including accepted price rises.
    local snapshot, reason = inspect(row.entity)
    if not snapshot then stop(reason, row); return end
    if snapshot.signature ~= row.snapshot.signature then stop(changedSnapshot(row, snapshot, "apply") .. "，请重新扫描", row); return end
    local previousNet = row.quote.net
    row.snapshot = snapshot; quoteRow(row)
    if row.error or not row.config then stop(row.error or "无有效升级方案", row); return end
    if row.quote.net > previousNet then recordQuoteIncrease(row, previousNet, "apply") end
    local restrictions, protected = native.restrictions(session.gameCtx)
    if protected[row.entity] then stop("载具已受到任务保护", row); return end
    local _, byKey = native.catalog()
    for _, unit in ipairs(snapshot.units) do
        local key = row.changes[unit.index]
        if key and not core.compatible(unit.old, byKey[key], unit.purpose, native.year(), restrictions) then
            stop("目标车型已不可购买，请重新选择", row); return
        end
    end
    local balance = native.balance()
    if row.quote.net > 0 and balance and balance < row.quote.net then stop("余额不足", row); return end
    local missionError = native.missionError(row.quantities, true)
    if missionError then stop(missionError, row); return end
    row.status = "执行中"; session.pending = row.entity; touch()
    local activeSession = session
    debugPrint("[xiaom_vehicle_upgrade] replace entity=" .. row.entity .. " net=" .. row.quote.net)
    local ok, err = pcall(native.send, row.entity, row.config, function(success)
        if session ~= activeSession or session.pending ~= row.entity then return end
        session.pending = nil
        if not success then stop("原版替换命令未成功", row); return end
        row.status = "成功"; row.selected = false
        session.results.success = session.results.success + 1
        session.actualNet = session.actualNet + row.quote.net
        session.applyIndex = session.applyIndex + 1
        debugPrint("[xiaom_vehicle_upgrade] replacement successful entity=" .. row.entity)
        report("已升级 " .. session.results.success .. " / " .. #session.queue .. " 辆")
    end)
    if not ok then
        debugPrint("[xiaom_vehicle_upgrade] send error: " .. tostring(err))
        stop("提交替换命令时出错，详情见游戏日志", row)
    end
end

function controller.step()
    if not session then return end
    local ok, err = pcall(function()
        if session.phase == "catalog" then
            if native.catalogStep(48) then
                session.entities = native.entities(); session.phase = "scan"
            end
            local current, total = native.catalogProgress()
            report("读取车型 " .. current .. " / " .. total)
        elseif session.phase == "scan" then
            for _ = 1, 6 do
                local entity = session.entities[session.scanIndex]
                if not entity then
                    session.phase = "idle"; report("扫描完成，共 " .. #session.rows .. " 辆；请查看目标、费用及供电提示后确认")
                    return
                end
                local snapshot, reason = inspect(entity)
                local row = snapshot and planRow(snapshot) or {entity = entity, selected = false, error = reason, status = "无法扫描"}
                quoteRow(row); session.rows[#session.rows + 1] = row
                session.scanIndex = session.scanIndex + 1
            end
            report("扫描载具 " .. (#session.rows) .. " / " .. #session.entities)
        elseif session.phase == "checking" then checkStep()
        elseif session.phase == "applying" then applyStep()
        end
    end)
    if not ok then
        debugPrint("[xiaom_vehicle_upgrade] step error: " .. tostring(err))
        if session.phase == "applying" then stop("升级流程出错，详情见游戏日志")
        else session.phase = "idle"; review("无法完成数据核对，详情见游戏日志；请重新扫描") end
    end
end

-- Refresh selected prices in small chunks while the preview is idle. Changes
-- to configuration stay visible as a warning until the player confirms again.
function controller.refresh()
    if not session or session.phase ~= "idle" then return end
    local balance = native.balance()
    if balance ~= session.lastBalance then session.lastBalance = balance; touch() end
    for _ = 1, 4 do
        local row = session.rows[session.refreshIndex]
        session.refreshIndex = session.refreshIndex + 1
        if not row then session.refreshIndex = 1; break end
        if row.selected and row.snapshot and row.status ~= "成功" then
            local snapshot, reason = inspect(row.entity)
            if not snapshot then row.error = reason; row.config = nil; touch()
            elseif snapshot.signature ~= row.snapshot.signature then
                local reason = changedSnapshot(row, snapshot, "idle")
                local updated = planRow(snapshot, row)
                for key in pairs(row) do row[key] = nil end
                for key, value in pairs(updated) do row[key] = value end
                quoteRow(row)
                -- Preserve the confirmation's specific rejection until the next
                -- click; idle updates must not overwrite it with a vague warning.
                if not session.reviewMessage then
                    report(reason .. "。预览已更新；确认前建议暂停游戏。")
                else touch() end
            else
                local previous = row.quote and row.quote.net
                local previousError, previousReady = row.error, row.config ~= nil
                row.snapshot = snapshot; quoteRow(row)
                if row.error or not row.quote or previous ~= row.quote.net or previousError ~= row.error or
                    previousReady ~= (row.config ~= nil) then touch() end
            end
        end
    end
end

return controller
