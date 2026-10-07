local settings = ug_require "xiaom_global_tuning::/settings.lua"
local core = ug_require "xiaom_global_tuning::/tuning_core.lua"
local store = ug_require "xiaom_global_tuning::/config_store.lua"
local controller = {}
local desired, committed, loaded
local runtimeTouched = {}
local message = "修改后自动保存配置；标注“实时”的项目立即应用。"
local initialized, dirty, dirtyAt = false, nil, 0
local queue, nextJob, inFlight, generation = {}, 1, {}, 0
local errors, auditAt, completed = 0, 0, true
local quietApply, submissions, configFailed = false, 0, false
local prefix = "[xiaom_global_tuning] "
local liveKeys = {industryProduction = true, vehicleSpeed = true, simulationSpeed = true, calendarSpeed = true}
local waitingKeys = {"freightCapacity", "freightWeight", "passengerCapacity", "freightLoading", "passengerLoading", "vehicleSpeed", "railTraction"}

local function now() return api.util.getApplicationTime() end
local function copy(t) local result = {}; for k, v in pairs(t) do result[k] = v end; return result end
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.000001 end
local function ensure()
    if desired then return end
    local found, err
    desired, found, err, runtimeTouched = store.read()
    runtimeTouched = runtimeTouched or {}
    loaded = settings.normalize({})
    local ok, snapshot = pcall(function()
        local rep = api.res.genericRep
        local id = rep.find("xiaom_global_tuning::/load_settings.res")
        return id and id >= 0 and rep.get(id).data or nil
    end)
    if ok and snapshot and snapshot.version == 1 and type(snapshot.params) == "table" and next(snapshot.params) then
        loaded = settings.normalize(snapshot.params)
    else
        -- The static cache is also a snapshot of the current load. Writing the
        -- cache file later does not mutate this already-loaded repository entry.
        local cacheOk, cache = pcall(function()
            local rep = api.res.genericRep
            local id = rep.find("xiaom_global_tuning::/local_settings.res")
            return id and id >= 0 and rep.get(id).data or nil
        end)
        if cacheOk and cache and cache.version == 1 then loaded = settings.normalize(cache.params) end
    end
    if not found and not err then desired = copy(loaded) end
    if desired.industryProduction ~= 1 then runtimeTouched.industryProduction = true end
    if desired.vehicleSpeed ~= 1 or loaded.vehicleSpeed ~= 1 then runtimeTouched.vehicleSpeed = true end
    committed = copy(desired)
    if err then configFailed = true; message = "配置读取失败：" .. err end
    if not found and not err then
        local saved, saveError = store.write(desired, runtimeTouched)
        if not saved then
            configFailed = true
            message = "配置未能保存：" .. tostring(saveError)
        end
    end
end

function controller.pending()
    ensure()
    local count = 0
    for _, key in ipairs(waitingKeys) do if desired[key] ~= loaded[key] then count = count + 1 end end
    return count
end

function controller.read()
    ensure()
    return copy(desired), message, false, controller.pending()
end

local function enqueue(kind, entity, value)
    queue[#queue + 1] = {kind = kind, entity = entity, value = value}
end

local function prepare(keys, timeToo, quiet)
    generation = generation + 1
    queue, nextJob, inFlight, errors, completed = {}, 1, {}, 0, false
    quietApply, submissions = quiet, 0
    -- Submit time controls first, even on maps with thousands of vehicles.
    if timeToo then
        if keys.simulationSpeed and committed.simulationSpeed >= 0 then enqueue("simulation", nil, committed.simulationSpeed) end
        if keys.calendarSpeed and committed.calendarSpeed >= 0 then
            enqueue("calendar", nil, core.dayDuration(committed.calendarSpeed, api.util.getDefaultDayDuration()))
        end
    end
    if keys.industryProduction and runtimeTouched.industryProduction then
        for _, entity in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY)) do
            enqueue("industry", entity, committed.industryProduction)
        end
    end
    if keys.vehicleSpeed and runtimeTouched.vehicleSpeed then
        -- Models are already scaled at load. Only apply the ratio to the load's
        -- scale, so 2 -> 3 -> 1 and reload never compound the multiplier.
        local factor = committed.vehicleSpeed / loaded.vehicleSpeed
        for _, entity in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE)) do
            enqueue("vehicle", entity, factor)
        end
    end
    if not quiet then message = "配置已保存，正在应用实时设置……" end
end

local function make(job)
    if job.kind == "simulation" then return api.cmd.makeGameSetSpeedCmd(job.value) end
    if job.kind == "calendar" then return api.cmd.makeGameSetCalendarSpeedCmd(job.value) end
    if not api.engine.entityExists(job.entity) then return nil end
    if job.kind == "industry" then
        local industry = api.engine.getComponent(job.entity, api.type.ComponentType.INDUSTRY)
        if not industry or not industry.stockList then return nil end
        local stock = api.engine.getComponent(industry.stockList, api.type.ComponentType.STOCK_LIST)
        if not stock or near(stock.modifiers.productivity, job.value) then return nil end
        local modifiers = api.type.StockList.Modifiers.new(stock.modifiers)
        modifiers.productivity = job.value
        return api.cmd.makeStockListSetModifiersCmd(job.entity, modifiers)
    end
    local vehicle = api.engine.getComponent(job.entity, api.type.ComponentType.TRANSPORT_VEHICLE)
    if not vehicle or near(vehicle.modifiers.topSpeedScale, job.value) then return nil end
    local modifiers = api.type.TransportVehicle.Modifiers.new(vehicle.modifiers)
    modifiers.topSpeedScale = job.value
    return api.cmd.makeVehicleSetModifiersCmd(job.entity, modifiers)
end

function controller.edit(key, value)
    ensure()
    if desired[key] == nil then return end
    local changed = copy(desired)
    changed[key] = value
    changed = settings.normalize(changed)
    if changed[key] == desired[key] then return end
    desired = changed
    if key == "industryProduction" or key == "vehicleSpeed" then runtimeTouched[key] = true end
    dirty = dirty or {}
    dirty[key] = true
    dirtyAt = now()
    message = "正在记录配置……"
end

function controller.reset()
    ensure()
    desired = settings.normalize({})
    dirty, dirtyAt = copy(liveKeys), now() - 1
    message = "正在恢复默认配置……"
end

function controller.retry()
    ensure()
    dirty, dirtyAt = copy(liveKeys), now() - 1
    message = "正在重新保存配置并应用实时设置……"
end

function controller.initialize(newSession)
    if newSession then
        desired, committed, loaded = nil, nil, nil
        runtimeTouched = {}
        initialized, dirty, configFailed = false, nil, false
        queue, nextJob, inFlight, completed = {}, 1, {}, true
        generation = generation + 1
        errors = 0
        message = "修改后自动保存配置；标注“实时”的项目立即应用。"
    end
    ensure()
    if initialized then return end
    initialized = true
    if not configFailed then prepare(liveKeys, true, false) end
    auditAt = now() + 3
    debugPrint(prefix .. "runtime initialized; independent config: " .. store.path())
end

function controller.update()
    if not initialized then return end
    local stamp = now()
    if dirty and stamp - dirtyAt >= 0.35 then
        local keys = dirty
        dirty = nil
        local ok, err = store.write(desired, runtimeTouched)
        if ok then
            -- Include edits whose previous disk write failed, especially time
            -- settings (which must never be retried by the periodic audit).
            for key, value in pairs(desired) do if committed[key] ~= value then keys[key] = true end end
            committed, configFailed = copy(desired), false
            prepare(keys, true, false)
            auditAt = stamp + 3
        else
            configFailed = true
            message = "配置保存失败，修改尚未应用；点击“重新应用”重试。"
            debugPrint(prefix .. "config write failed: " .. tostring(err))
        end
    end
    local active, timedOut = 0, false
    for index, item in pairs(inFlight) do
        if stamp - item.sentAt > 12 then
            inFlight[index] = nil
            errors = errors + 1
            timedOut = true
            if errors <= 8 then debugPrint(prefix .. "command callback timed out: " .. item.kind) end
        else active = active + 1 end
    end
    if timedOut then
        -- Stop this batch instead of waiting another 12 seconds for each group
        -- of vehicles. Late callbacks cannot complete a newer request.
        generation = generation + 1
        queue, nextJob, inFlight, active = {}, 1, {}, 0
    end
    -- Bound command submissions AND component reads per GUI frame. The window
    -- remains editable and closable even if engine callbacks never arrive.
    local inspected, sent = 0, 0
    while nextJob <= #queue and active < 8 and inspected < 32 and sent < 8 do
        local index, job, token = nextJob, queue[nextJob], generation
        nextJob, inspected = nextJob + 1, inspected + 1
        local ok, command = pcall(make, job)
        if not ok then
            errors = errors + 1
            if errors <= 8 then debugPrint(prefix .. "command unavailable: " .. tostring(command)) end
        elseif command then
            submissions = submissions + 1
            inFlight[index] = {sentAt = stamp, kind = job.kind}
            active, sent = active + 1, sent + 1
            local submitted, err = pcall(function()
                api.cmd.sendCommand(command, function(_result, success)
                    if generation ~= token or not inFlight[index] then return end
                    inFlight[index] = nil
                    if not success then errors = errors + 1 end
                end)
            end)
            if not submitted then
                inFlight[index] = nil
                errors = errors + 1
                if errors <= 8 then debugPrint(prefix .. "command submission failed: " .. tostring(err)) end
            end
        end
    end
    if not completed and nextJob > #queue and next(inFlight) == nil then
        completed = true
        local pending = controller.pending()
        if not dirty and not configFailed and (not quietApply or submissions > 0 or errors > 0) then
            message = errors > 0 and "配置已保存；部分实时设置未成功，可点击“重新应用”。" or
            (pending > 0 and "实时设置已应用 · " .. pending .. " 项资源设置将在下次载入生效。" or "配置已保存 · 实时设置已应用。")
        end
        if not quietApply or submissions > 0 or errors > 0 then
            debugPrint(prefix .. "runtime apply completed; errors=" .. errors .. "; pending=" .. pending)
        end
    end
    if completed and not dirty and not configFailed and errors == 0 and stamp >= auditAt then
        -- Newly built industries / purchased vehicles receive the setting too.
        -- Excluding time here lets players keep using the game's speed buttons.
        prepare({industryProduction = true, vehicleSpeed = true}, false, true)
        auditAt = stamp + 3
    end
end

return controller
