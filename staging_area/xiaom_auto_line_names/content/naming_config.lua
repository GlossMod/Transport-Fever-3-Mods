local U = ug_require "xiaom_auto_line_names::/naming_util.lua"
local I = ug_require "xiaom_auto_line_names::/naming_i18n.lua"
local M = {modId="xiaom_auto_line_names"}
local fields = {transportType=true,serviceType=true,cargoTypes=true,placeA=true,placeB=true,lineType=true,lineNumber=true}
M.defaults = {passengerTemplate="[{transportType}{serviceType}] {placeA}-{placeB}-{lineNumber}",
    freightTemplate="[{transportType}{serviceType}] {cargoTypes}-{placeA}-{placeB}-{lineNumber}",
    numberWidth=3,shortLength=3,cargoLimit=3,labels={},cargoOverrides={}}
function M.validate(raw)
    if type(raw) ~= "table" then return nil,"configuration must return a table" end
    local r=U.copy(M.defaults)
    for k in pairs(raw) do if r[k] == nil then return nil,"unknown configuration key: " .. tostring(k) end end
    for _, k in ipairs({"passengerTemplate","freightTemplate"}) do
        if raw[k] ~= nil then
            if not U.clean(raw[k]) or #raw[k] > 512 then return nil,k .. " must be a nonempty string (max 512 bytes)" end
            local rest=raw[k]:gsub("{([%w_]+)}",function(key) if fields[key] then return "" end; return "{" .. key .. "}" end)
            if rest:find("[{}]") then return nil,"invalid placeholder in " .. k end
            r[k]=raw[k]
        end
    end
    for k,max in pairs({numberWidth=8,shortLength=32,cargoLimit=16}) do
        if raw[k] ~= nil then
            if type(raw[k]) ~= "number" or raw[k] < 1 or raw[k] > max or raw[k]%1 ~= 0 then return nil,k .. " must be an integer from 1 to " .. max end
            r[k]=raw[k]
        end
    end
    for _, k in ipairs({"labels","cargoOverrides"}) do
        if raw[k] ~= nil and type(raw[k]) ~= "table" then return nil,k .. " must be a table" end
    end
    for lang, map in pairs(raw.labels or {}) do
        if lang ~= "en" and lang ~= "zh_CN" or type(map) ~= "table" then return nil,"labels require en/zh_CN tables" end
        r.labels[lang]={}
        for key,v in pairs(map) do
            if not I.labels(lang)[key] or not U.clean(v) then return nil,"invalid label: " .. tostring(key) end
            r.labels[lang][key]=v
        end
    end
    for key, entry in pairs(raw.cargoOverrides or {}) do
        if type(key) ~= "string" or type(entry) ~= "table" then return nil,"cargo overrides require resource-name keys and tables" end
        r.cargoOverrides[key]={}
        for style,v in pairs(entry) do
            if (style ~= "full" and style ~= "short" and style ~= "code") or not U.clean(v) then return nil,"invalid cargo override: " .. key end
            r.cargoOverrides[key][style]=v
        end
    end
    return r
end
function M.fromParams(raw)
    raw=raw or {}
    local function choice(k,values,default) return values[raw[k] or 1] or default or values[1] end
    return {format=choice("format",{"full","classic","compact","custom"}),
        language=choice("language",{"auto","zh_CN","en"}),
        place=choice("place",{"town","short","station","industry"}),
        cargoStyle=choice("cargoStyle",{"full","short","code"}),
        region=raw.region == 2, refresh=choice("refresh",{60,0,30,120},60)}
end
function M.options()
    local all=api.engine.config.getModParams(); return M.fromParams(all and all[M.modId])
end
function M.file()
    local ok,raw=pcall(ug_require,"xiaom_auto_line_names::/user_config.lua")
    if not ok then return nil,tostring(raw) end
    return M.validate(raw)
end
function M.effective(saved,options)
    local r=U.copy(saved or M.defaults)
    for k,v in pairs(options or M.options()) do r[k]=v end
    r.language=I.language(r.language); r.label=I.labels(r.language,r.labels[r.language]); return r
end
return M
