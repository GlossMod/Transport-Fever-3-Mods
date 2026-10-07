local U=ug_require "xiaom_auto_line_names::/naming_util.lua"
local M={}
local catalog, townMap, industries
function M.name(entity)
    if not entity or entity < 0 or not api.engine.entityExists(entity) then return nil end
    return U.clean(api.engine.util.getEntityName(entity))
end
function M.station(stop)
    if not M.name(stop.stationGroup) then return nil end
    local g=api.engine.getComponent(stop.stationGroup,api.type.ComponentType.STATION_GROUP)
    return g and g.stations and g.stations[(stop.station or 0)+1]
end
function M.refresh()
    townMap=api.engine.system.stationSystem.getStation2TownMap()
    industries=nil
    if not catalog then
        catalog={}
        for id,resName in pairs(api.res.cargoTypeRep.getAll(true)) do
            local cargo=api.res.cargoTypeRep.get(id)
            catalog[#catalog+1]={id=id,name=U.clean(cargo.name),order=cargo.order or id,
                resource=resName,key=tostring(resName):match("([^/:]+)%.cargo") or tostring(resName):match("([^/:]+)$")}
        end
        table.sort(catalog,function(a,b) return a.order == b.order and a.id < b.id or a.order < b.order end)
    end
end
local function position(entity)
    local c=entity and api.engine.getComponent(entity,api.type.ComponentType.CONSTRUCTION)
    return c and c.transf and c.transf:getTransl()
end
local function industryName(station)
    local cs=api.engine.system.constructionSystem
    local catches=api.engine.system.catchmentAreaSystem.getStationCatchables(station,true)
    if not industries then
        industries={}
        for _,id in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY)) do
            local c=api.engine.getComponent(id,api.type.ComponentType.INDUSTRY)
            industries[c.stockList]={id=id,construction=c.construction}
            industries[id]=industries[c.stockList]
        end
    end
    local pos=position(cs.getConstructionEntityForStation(station))
    local best, distance
    for _,entity in ipairs(catches) do
        local candidate=industries[entity]
        if candidate then
            local p=position(candidate.construction)
            local d=pos and p and ((pos.x-p.x)^2+(pos.y-p.y)^2) or math.huge
            if not best or d < distance or d == distance and candidate.id < best.id then best=candidate; distance=d end
        end
    end
    return best and (M.name(best.id) or M.name(best.construction))
end
local function places(line,config)
    if not line.stops or #line.stops < 2 then return nil end
    local first,last=line.stops[1]
    for i=#line.stops,2,-1 do if line.stops[i].stationGroup ~= first.stationGroup then last=line.stops[i]; break end end
    if not last then return nil end
    local a,b=M.station(first),M.station(last)
    if not a or not b or not api.engine.entityExists(a) or not api.engine.entityExists(b) then return nil end
    local ta,tb=townMap[a],townMap[b]
    local function label(stop,station,town)
        if config.place == "industry" then return industryName(station) or M.name(stop.stationGroup) end
        if config.place == "station" or ta == tb then return M.name(stop.stationGroup) end
        local townName=M.name(town)
        if townName and config.place == "short" then townName=U.short(townName,config.shortLength) end
        return townName or M.name(stop.stationGroup)
    end
    local pa,pb=label(first,a,ta),label(last,b,tb)
    if not pa or not pb then return nil end
    local towns={}; for _,stop in ipairs(line.stops) do local s=M.station(stop); local t=s and townMap[s]; if t and M.name(t) then towns[t]=true end end
    local count=0; for _ in pairs(towns) do count=count+1 end
    return pa,pb,count == 1 and "LO" or count == 2 and "IC" or count >= 3 and "RE" or ""
end
local function modeClasses(modes)
    local e=api.type["enum"].TransportMode
    local classes={}
    for _,pair in ipairs({{"BUS","bus"},{"TRUCK","truck"},{"TRAM","tram"},{"ELECTRIC_TRAM","tram"},
        {"TRAIN","train"},{"ELECTRIC_TRAIN","train"},{"AIRCRAFT","aircraft"},{"SMALL_AIRCRAFT","aircraft"},
        {"SHIP","ship"},{"SMALL_SHIP","ship"},{"HELICOPTER","helicopter"}}) do
        if e[pair[1]] and modes[e[pair[1]]] then classes[pair[2]]=true end
    end
    return classes
end
function M.info(entity,config)
    if not catalog or not townMap then M.refresh() end
    local line=api.engine.getComponent(entity,api.type.ComponentType.LINE)
    if not line then return nil end
    local pa,pb,region=places(line,config); if not pa then return nil end
    local passenger=api.res.cargoTypeRep.getPassengerCargoTypeId()
    local allowed,caps,modes={},{},{}
    for _,stop in ipairs(line.stops) do
        local sc=stop.stopConfig
        if sc and sc.load then for _,cargo in ipairs(catalog) do
            local ix=cargo.id+1
            if sc.load[ix] and (not sc.maxLoad or sc.maxLoad[ix] == nil or sc.maxLoad[ix] > 0) then allowed[cargo.id]=true end
        end end
    end
    local vehicles=api.engine.system.transportVehicleSystem.getLineVehicles(entity)
    local vp,vg=false,false
    for _,id in ipairs(vehicles) do
        local v=api.engine.getComponent(id,api.type.ComponentType.TRANSPORT_VEHICLE)
        local c=v and v.config
        if c then
            for mode,value in pairs(c.transportModes or {}) do if value then modes[mode]=true end end
            for _,cargo in ipairs(catalog) do if c.capacities and (c.capacities[cargo.id+1] or 0)>0 then
                caps[cargo.id]=true; if cargo.id == passenger then vp=true else vg=true end
            end end
        end
    end
    local cargoItems={}
    for _,cargo in ipairs(catalog) do
        if cargo.id ~= passenger and allowed[cargo.id] and (#vehicles == 0 or caps[cargo.id]) then cargoItems[#cargoItems+1]=cargo end
    end
    local kind
    if vp and vg then kind="mixed" elseif vg then kind="goods" elseif vp then kind="passengers"
    elseif #cargoItems>0 and allowed[passenger] then kind="mixed"
    elseif #cargoItems>0 then kind="goods" elseif allowed[passenger] then kind="passengers"
    else
        local p,g=false,false
        for _,stop in ipairs(line.stops) do local station=M.station(stop); if station then
            p=p or api.engine.util.station.isStationOfType(station,false); g=g or api.engine.util.station.isStationOfType(station,true)
        end end
        if p and not g then kind="passengers" elseif g and not p then kind="goods" end
    end
    if not kind then return nil end
    local classes=modeClasses(modes)
    if next(classes) == nil then classes=modeClasses(api.engine.util.line.getLineTransportModesUnion(entity)) end
    if classes.bus and classes.truck then classes.bus=nil; classes.truck=nil; classes[kind == "goods" and "truck" or "bus"]=true end
    local transport,count=nil,0; for k in pairs(classes) do transport=k; count=count+1 end
    if count ~= 1 then return nil end
    return {transport=transport,kind=kind,category=transport .. ":" .. kind,cargo=cargoItems,placeA=pa,placeB=pb,region=region}
end
function M.defaultName(name)
    if not name then return false end
    if name == _("New Line") then return true end
    local template=_("Line {lineNumber}")
    local escaped=template:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1")
    escaped=escaped:gsub("{lineNumber}","%%d+")
    return name:match("^" .. escaped .. "$") ~= nil
end
function M.reset() catalog=nil; townMap=nil; industries=nil end
return M
