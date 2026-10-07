local settings = ug_require "xiaom_global_tuning::/settings.lua"
local store = {}
store.directory = "mod_settings/xiaom_global_tuning"
store.fileName = "settings"
local cacheDirectory = "staging_area/xiaom_global_tuning/content"

local function liveFlags(value)
    value = type(value) == "table" and value or {}
    return {industryProduction = value.industryProduction == true, vehicleSpeed = value.vehicleSpeed == true}
end

local function equal(a, b)
    for key, value in pairs(a) do if b[key] ~= value then return false end end
    return true
end

local function cacheFallback(reason)
    local ok, data = pcall(function()
        local rep = api.res.genericRep
        local id = rep.find("xiaom_global_tuning::/local_settings.res")
        if not id or id < 0 then return nil end
        return (rep.getAsTable and rep.getAsTable(id) or rep.get(id)).data
    end)
    if ok and type(data) == "table" and data.version == 1 and type(data.params) == "table" then
        if reason and next(data.params) then debugPrint("[xiaom_global_tuning] config cache used: " .. reason) end
        return settings.normalize(data.params), next(data.params) ~= nil, nil, liveFlags(data.liveOverrides)
    end
    return settings.normalize({}), false, reason or "载入阶段未能读取配置缓存"
end

-- Native userdata is independent of game saves. Use the same reader in load
-- hooks and the UI; never execute config text or write Mod / GUI save data.
function store.read()
    if not app or not app.loadUserdata then
        return cacheFallback()
    end
    local ok, data = pcall(app.loadUserdata, store.directory, store.fileName)
    if not ok then return cacheFallback(tostring(data)) end
    if data == nil or (type(data) == "table" and next(data) == nil) then
        return cacheFallback()
    end
    if type(data) ~= "table" or data.version ~= 1 or type(data.params) ~= "table" then
        return cacheFallback("配置格式无效")
    end
    return settings.normalize(data.params), true, nil, liveFlags(data.liveOverrides)
end

function store.write(params, overrides)
    if not app or not app.saveUserdata then return false, "独立配置写入接口不可用" end
    local normalized = settings.normalize(params)
    local flags = liveFlags(overrides)
    if normalized.industryProduction ~= 1 then flags.industryProduction = true end
    if normalized.vehicleSpeed ~= 1 then flags.vehicleSpeed = true end
    local data = {version = 1, params = normalized, liveOverrides = flags}
    local ok, err = pcall(app.saveUserdata, store.directory, store.fileName, data)
    if not ok then return false, tostring(err) end
    local saved, found, readError = store.read()
    if not found or not equal(normalized, saved) then return false, readError or "配置写入后校验失败" end
    -- This workspace is the game's staging_area junction. Mirror the ten small
    -- values there so loader Lua states without `app` can read them next load.
    -- The authoritative file stays in mod_settings, outside the Mod package.
    local cacheData = {type = "xiaom-global-tuning-config", data = data}
    local cacheOk, cacheError = pcall(app.saveUserdata, cacheDirectory, "local_settings.res", cacheData)
    if not cacheOk then return false, "配置缓存更新失败：" .. tostring(cacheError) end
    local checked, cache = pcall(app.loadUserdata, cacheDirectory, "local_settings.res")
    if not checked or type(cache) ~= "table" or type(cache.data) ~= "table" or
        not equal(normalized, settings.normalize(cache.data.params)) then
        return false, "配置缓存写入后校验失败"
    end
    return true
end

function store.path()
    if app and app.getUserDataFolder then
        return app.getUserDataFolder() .. "/" .. store.directory .. "/" .. store.fileName .. ".lua"
    end
    return store.directory .. "/" .. store.fileName .. ".lua"
end

return store
