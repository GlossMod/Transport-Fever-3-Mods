"""Execute the shipped Lua planner, native adapter and queue with engine doubles.

These checks do not claim C++ payment/cargo or native rendering validation.
"""
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".agents/tools/line_naming_test_runtime"))
from lupa.lua54 import LuaRuntime

MOD = ROOT / "staging_area/xiaom_vehicle_upgrade"

FIXTURE = r'''
function clone(v)
    if type(v)~="table" then return v end
    local r={};for k,x in pairs(v) do r[k]=clone(x) end;return r
end
function debugPrint() end
function _(s) return s end
gameLanguage = "zh_CN"
app = {getUserProfile = function()
    return {getLanguage = function() return {code = gameLanguage} end}
end}
models, names, mus, muNames, entities, lines = {}, {}, {}, {}, {}, {}
year, balance, gameTime = 2000, 1000000, 10000
commands, callbacks, events, protected, restrictions = {}, {}, {}, {}, {}
missionMessage, commandFails, throwCommand = nil, false, false
api={type={enum={Carrier={ROAD="ROAD",RAIL="RAIL",TRAM="TRAM",WATER="WATER",AIR="AIR"},
    VehicleEngineType={DIESEL="DIESEL",ELECTRIC="ELECTRIC"},
    TransportMode={TRAIN="TRAIN",ELECTRIC_TRAIN="ELECTRIC_TRAIN",TRAM="TRAM",ELECTRIC_TRAM="ELECTRIC_TRAM"}},
    ComponentType={TRANSPORT_VEHICLE="tv",GAME_TIME="time",LINE="line",PLAYER_OWNED="owner"},
    TransportVehicleConfig={new=function() return {vehicles={},vehicleGroups={},muFileNames={}} end},
    TransportVehiclePart={new=function() return {part={color={x=1,y=1,z=1}},autoLoadConfig={}} end},
    LoadConfig={new=function() return {loadConfigIndex=0,cargoTypeId=-1} end},
    Vec3f={new=function(x,y,z) return {x=x,y=y,z=z} end}},
    res={},engine={util={vehicle={},finance={}},system={simEntityAtVehicleSystem={}}},gui={},cmd={}}
local function rep(resources, paths)
    return {get=function(id) assert(resources[id],"missing resource "..id);return resources[id] end,
        getName=function(id) return paths[id] end,
        getAll=function() local r={};for id in pairs(resources) do r[id]=paths[id] end;return r end,
        find=function(path) for id,p in pairs(paths) do if p==path then return id end end;return -1 end,
        isVisible=function(id) return not resources[id].hidden end,
        forEachModelWithMetadata=function(key,fn)
            for id,m in pairs(resources) do if m.metadata and m.metadata[key] then fn(paths[id]) end end
        end}
end
api.res.modelRep=rep(models,names);api.res.multipleUnitRep=rep(mus,muNames)
api.res.cargoTypeRep={forEachCargoType=function(set,fn) for _,id in ipairs(set.ids) do fn(id) end end}
api.engine.util.getPlayer=function() return 99 end
api.engine.util.getWorld=function() return 0 end
api.engine.util.getYear=function() return year end
api.engine.util.getEntityName=function(id) return entities[id] and entities[id].name or lines[id].name end
api.engine.util.finance.getPlayersBalance=function() return balance end
api.engine.entityExists=function(id) return entities[id]~=nil or lines[id]~=nil end
api.engine.getEntitiesWithComponent=function(_,filter)
    assert(filter.requireOwnedByPlayer==99)
    local r={};for id,item in pairs(entities) do if item.owner==99 then r[#r+1]=id end end;return r
end
api.engine.getComponent=function(id,kind)
    if kind=="time" then return {gameTime=gameTime} end
    if kind=="line" then return lines[id] end
    if kind=="owner" then return entities[id] and {player=entities[id].owner} end
    return entities[id] and entities[id].tv
end
api.engine.util.vehicle.getPartPrice=function(part) return part.value or math.floor(models[part.part.modelId].metadata.cost.price/2) end
api.engine.util.vehicle.getDepreciatedValue=function(id)
    if entities[id].refund then return entities[id].refund end
    local total=0;for _,p in ipairs(entities[id].tv.transportVehicleConfig.vehicles) do total=total+api.engine.util.vehicle.getPartPrice(p) end;return total
end
api.engine.system.simEntityAtVehicleSystem.getVehicleSimEntitiesCountForCargoType=function(id,cargo)
    return entities[id].loaded[cargo] or 0
end
api.gui.fireGuiScriptEvent=function(_,name,param)
    events[#events+1]=clone(param);return missionMessage
end
api.cmd.makeVehicleReplaceCmd=function(entity,config) return {entity=entity,config=config} end
api.cmd.sendCommand=function(cmd,cb)
    if throwCommand then error("send failed") end
    commands[#commands+1]=cmd;callbacks[#callbacks+1]=cb
end
function finishCommand(success)
    local cb=table.remove(callbacks,1);cb({},success)
end
function model(id,cargos,capacity,opts)
    opts=opts or {};names[id]=opts.path or "::/vehicle/"..id..".mdl"
    local compartments={}
    for _=1,opts.compartments or 1 do
        if #cargos>0 then compartments[#compartments+1]={loadConfigs={{cargoEntry={capacity=capacity,cargoTypeSet={ids=cargos}}}}} end
    end
    local engines=opts.unpowered and {} or {{power=opts.power or 100,tractiveEffort=opts.traction or 50,type=opts.electric and "ELECTRIC" or "DIESEL"}}
    models[id]={hidden=opts.hidden,metadata={extent={bbMax={x=opts.length or 10},bbMin={x=0}},
        transportVehicle={carrier=opts.carrier or "ROAD",compartments=compartments,filterTags=opts.tags or {"standard"},
            transportModes={opts.electric and "ELECTRIC_TRAIN" or "TRAIN"},groupFileName=opts.group or ""},
        landVehicle={engines=engines,topSpeed=opts.speed or 20},
        cost={price=opts.price or 1000},availability={yearFrom=opts.year or 1900,yearTo=opts.untilYear or 0},
        description={name="Vehicle "..id}}}
end
function part(id,cargo,auto,opts)
    opts=opts or {};local loads,autos={},{}
    for _ in ipairs(models[id].metadata.transportVehicle.compartments) do
        loads[#loads+1]={loadConfigIndex=0,cargoTypeId=cargo or -1};autos[#autos+1]=auto~=false
    end
    return {part={modelId=id,reversed=opts.reversed or false,color={x=.2,y=.3,z=.4},compartment2loadConfig=loads},
        purchaseTime=opts.purchaseTime or 500,maintenanceChange=7,maintenanceState=.6,autoLoadConfig=autos,value=opts.value}
end
function vehicle(id,parts,opts)
    opts=opts or {};local groups,muFiles=opts.groups or {},opts.muFiles or {}
    if not opts.groups then for _ in ipairs(parts) do groups[#groups+1]=1;muFiles[#muFiles+1]="" end end
    local capacities={0,0,0}
    for _,p in ipairs(parts) do
        for _,lc in ipairs(p.part.compartment2loadConfig) do if lc.cargoTypeId>=0 then capacities[lc.cargoTypeId+1]=10 end end
    end
    entities[id]={owner=opts.owner or 99,name="Vehicle instance "..id,loaded=opts.loaded or {},refund=opts.refund,
        tv={carrier=opts.carrier or models[parts[1].part.modelId].metadata.transportVehicle.carrier,
            line=opts.line or -1,depot=opts.depot or -1,config={capacities=capacities},
            transportVehicleConfig={vehicles=parts,vehicleGroups=groups,muFileNames=muFiles}}}
end
function makeMu(id,ids)
    local parts={};for _,modelId in ipairs(ids) do parts[#parts+1]={name=names[modelId],forward=true} end
    mus[id]={vehicles=parts,filterTags={"standard"},name="Multiple unit "..id};muNames[id]="::/vehicle/"..id..".mu"
end
storeMock={}
storeMock.makeVehicleData=function(id,mu)
    local ids=mu and {} or {id}
    if mu then for _,p in ipairs(mus[id].vehicles) do ids[#ids+1]=api.res.modelRep.find(p.name) end end
    local r={allCargoTypes={},yearFrom=0,yearTo=0,speed=math.huge,power=0,tractiveEffort=0,length=0,totalCapacity=0,price=0}
    for _,mid in ipairs(ids) do
        local m=models[mid].metadata;r.yearFrom=math.max(r.yearFrom,m.availability.yearFrom)
        if m.availability.yearTo>0 then r.yearTo=r.yearTo==0 and m.availability.yearTo or math.min(r.yearTo,m.availability.yearTo) end
        r.speed=math.min(r.speed,m.landVehicle.topSpeed);r.price=r.price+m.cost.price;r.length=r.length+m.extent.bbMax.x
        for _,engine in ipairs(m.landVehicle.engines) do r.power=r.power+engine.power;r.tractiveEffort=r.tractiveEffort+engine.tractiveEffort end
        for _,compartment in ipairs(m.transportVehicle.compartments) do
            local maximum=0
            for _,lc in ipairs(compartment.loadConfigs) do
                maximum=math.max(maximum,lc.cargoEntry.capacity)
                for _,cargo in ipairs(lc.cargoEntry.cargoTypeSet.ids) do r.allCargoTypes[cargo]=(r.allCargoTypes[cargo] or 0)+lc.cargoEntry.capacity end
            end
            r.totalCapacity=r.totalCapacity+maximum
        end
    end
    return r
end
storeMock.getVehicleNameAndIcons=function(id,mu) return {name=mu and mus[id].name or models[id].metadata.description.name,icons={}} end
vehicleUtilMock={makePart=function(id,forward,color)
    local p=part(id,-1,true,{purchaseTime=0,reversed=not forward});p.part.color=color;p.value=nil;p.maintenanceState=0;p.maintenanceChange=0;return p
end}
cargoMock={getPassengerCargoTypeId=function() return 0 end,getCargoNameById=function(id) return ({[0]="Passengers",[1]="Oil",[2]="Goods"})[id] end}
gameCtx={filters={get=function() return {vehicleFilter=restrictions,protectedEntities=protected} end}}
externals={['::/gui/line_vehicle_mgmt/vehicle_store_util.tl']=storeMock,
    ['::/gui/line_vehicle_mgmt/vehicle_util.tl']=vehicleUtilMock,['::/gui/main/cargo_util.tl']=cargoMock}
'''


def runtime(language="zh_CN"):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FIXTURE)
    lua.globals().gameLanguage = language
    cache = {}

    def require(name):
        if name.startswith("::/"):
            module = lua.globals().externals[name]
            if module is None:
                raise AssertionError(f"Unexpected external module: {name}")
            return module
        filename = name.split("::/")[-1]
        if filename not in cache:
            cache[filename] = lua.execute((MOD / "content" / filename).read_text(encoding="utf-8"))
        return cache[filename]

    lua.globals().ug_require = require
    for name in ("core", "native", "controller"):
        lua.globals()[name] = require(f"upgrade_{name}.lua")
    lua.execute('''
        function catalogReady() native.resetCatalog();while not native.catalogStep(50) do end end
        function scan() controller.open(gameCtx);for _=1,100 do controller.step();if not controller.busy() then return end end;error("scan did not finish") end
        function preflight() controller.confirm();for _=1,100 do
            local s=controller.read();if s.phase~="checking" then return end;controller.step()
        end;error("preflight did not finish") end
        function row(i) return controller.read().rows[i or 1] end
    ''')
    return lua


class UpgradeTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime()

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_confirmation_logs_price_increases_and_proceeds_at_current_quote(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950})
            vehicle(10,{part(1,1)},{refund=500});scan()
            local messages={};debugPrint=function(s) messages[#messages+1]=s end
            entities[10].refund=400;preflight()
            local session=controller.read()
            assert(session.phase=="applying" and #commands==0 and not session.reviewMessage)
            assert(row().quote.net==600 and controller.totals().net==600)
            local function logged(fragment)
                for _,s in ipairs(messages) do if s:find(fragment,1,true) then return true end end
                return false
            end
            assert(logged("confirm received phase=idle") and logged("preflight started count=1"))
            assert(logged("quote increased phase=preflight entity=10 before=500 after=600 delta=100 accepted=true"))
            assert(not logged("preflight deferred") and logged("preflight passed"))
            entities[10].refund=350;controller.step()
            assert(#commands==1 and row().quote.net==650 and not session.reviewMessage)
            assert(logged("quote increased phase=apply entity=10 before=600 after=650 delta=50 accepted=true"))
            assert(logged("replace entity=10 net=650"))''')

    def test_configuration_deferral_identifies_automatic_cargo_and_preserves_reason(self):
        self.run_lua('''model(1,{1,2},10);model(2,{1,2},20,{year=1950})
            vehicle(10,{part(1,1,true)});scan()
            local messages={};debugPrint=function(s) messages[#messages+1]=s end
            entities[10].tv.transportVehicleConfig.vehicles[1].part.compartment2loadConfig[1].cargoTypeId=2
            preflight();local session=controller.read()
            assert(session.phase=="idle" and #commands==0 and session.reviewMessage:find("自动装载货物",1,true))
            local found=false;for _,s in ipairs(messages) do
                if s:find("field=unit[1].part[1].compartment[1].cargo 1 -> 2",1,true) then found=true end
            end;assert(found)
            local warning=session.reviewMessage
            entities[10].tv.transportVehicleConfig.vehicles[1].purchaseTime=501
            for _=1,3 do controller.refresh() end
            assert(session.reviewMessage==warning and session.message==warning)
            preflight();assert(session.phase=="applying" and not session.reviewMessage)''')

    def test_snapshot_diagnostics_distinguish_manual_setting_and_ordinary_consist_edit(self):
        self.run_lua('''model(1,{1,2},10);vehicle(10,{part(1,1,false)})
            catalogReady();local before=native.snapshot(10)
            entities[10].tv.transportVehicleConfig.vehicles[1].part.compartment2loadConfig[1].cargoTypeId=2
            local after=native.snapshot(10);local field,label,detail=core.snapshotChange(before,after)
            assert(field=="unit[1].part[1].compartment[1].cargo" and label:find("手动装载货物",1,true) and detail=="1 -> 2")
            before=after;entities[10].tv.transportVehicleConfig.vehicles[1].autoLoadConfig[1]=true
            after=native.snapshot(10);field,label,detail=core.snapshotChange(before,after)
            assert(field:find(".auto",1,true) and label:find("开关",1,true) and detail=="false -> true")
            before=after;entities[10].tv.transportVehicleConfig.vehicles[1].purchaseTime=501
            field,label,detail=core.snapshotChange(before,native.snapshot(10))
            assert(field=="unit[1].part[1].purchaseTime" and label:find("购买时间",1,true) and detail=="500 -> 501")''')

    def test_purchase_event_exception_blocks_and_recovery_refreshes_paused_preview(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)})
            local messages={};debugPrint=function(s) messages[#messages+1]=s end
            api.gui.fireGuiScriptEvent=function() error("native GUI service unavailable") end
            scan();assert(row().selected and row().config and row().error and controller.totals().blocked==1)
            assert(not controller.confirm() and #commands==0)
            local found=false;for _,s in ipairs(messages) do if s:find("native GUI service unavailable",1,true) then found=true end end
            assert(found)
            local _,before=controller.read()
            api.gui.fireGuiScriptEvent=function() return nil end
            for _=1,3 do controller.refresh() end
            local _,after=controller.read()
            assert(not row().error and controller.totals().blocked==0 and after>before)
            api.gui.fireGuiScriptEvent=function() return "mission denied" end
            for _=1,3 do controller.refresh() end
            assert(row().error=="mission denied" and not controller.confirm() and #commands==0)''')

    def test_gui_read_only_repository_loads_catalog_and_current_vehicles_without_get_as_table(self):
        self.run_lua('''assert(api.res.modelRep.getAsTable==nil and api.res.multipleUnitRep.getAsTable==nil)
            model(1,{1},10,{path="test_mod::/vehicle/old_oil.mdl"})
            model(2,{1},20,{path="test_mod::/vehicle/new_oil.mdl",year=1950})
            model(3,{},0,{carrier="RAIL"});model(4,{1},10,{carrier="RAIL",unpowered=true})
            model(5,{},0,{carrier="RAIL",year=1950});model(6,{1},20,{carrier="RAIL",unpowered=true,year=1950})
            makeMu(1,{3,4});makeMu(2,{5,6})
            vehicle(10,{part(1,1,false)},{loaded={[1]=4}})
            vehicle(11,{part(3,-1),part(4,1)},{groups={2},muFiles={muNames[1]},loaded={[1]=4}})
            local baseline=clone(models)
            -- Native repository resources are read-only in the UI context.
            local function readonly(value)
                if type(value)~="table" then return value end
                return setmetatable({}, {__index=function(_,key) return readonly(value[key]) end,
                    __len=function() return #value end,
                    __newindex=function() error("attempt to mutate repository resource") end})
            end
            api.res.modelRep.get=function(id) assert(models[id]);return readonly(models[id]) end
            api.res.multipleUnitRep.get=function(id) assert(mus[id]);return readonly(mus[id]) end
            scan();local catalog,byKey=native.catalog()
            assert(#catalog==8 and byKey["model:2"] and byKey["mu:2"])
            assert(#controller.read().rows==2)
            for _,r in ipairs(controller.read().rows) do
                assert(r.snapshot and r.config and not r.error and r.selected)
                assert(r.snapshot.loaded[1]==4)
                if r.entity==10 then assert(r.changes[1]=="model:2" and r.quote.purchase==1000)
                else assert(r.changes[1]=="mu:2" and r.quote.purchase==2000) end
            end
            assert(controller.totals().count==2 and #commands==0)
            assert(models[1].metadata.cost.price==baseline[1].metadata.cost.price)
            assert(models[1].metadata.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.capacity==10)''')

    def test_oil_dedicated_matches_new_oil_and_not_goods(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});model(3,{2},100,{year=1990})
            vehicle(10,{part(1,1)});scan();assert(row().changes[1]=="model:2")''')

    def test_empty_generic_preserves_explicit_oil_configuration(self):
        self.run_lua('''model(1,{1,2},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1,false)})
            scan();assert(row().changes[1]=="model:2" and row().snapshot.units[1].purpose[1])''')

    def test_unconfigured_generic_preserves_all_supported_cargo(self):
        self.run_lua('''model(1,{1,2},10);model(2,{1},20,{year=1950});model(3,{1,2},20,{year=1940})
            vehicle(10,{part(1,-1)});scan();assert(row().changes[1]=="model:3")''')

    def test_line_filters_resolve_empty_automatic_truck(self):
        self.run_lua('''model(1,{1,2},10);model(2,{1},20,{year=1950});lines[20]={name="oil route",customFilters=true,stops={{stopConfig={load={false,true,false}}}}}
            vehicle(10,{part(1,-1)},{line=20});scan();assert(row().changes[1]=="model:2")''')

    def test_newest_regression_is_manual_only(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});model(3,{1},5,{year=1990})
            vehicle(10,{part(1,1)});scan();assert(row().changes[1]=="model:2" and #row().candidates[1]==2)
            controller.target(10,1,"model:3");assert(row().changes[1]=="model:3" and row().selected)''')

    def test_same_or_future_or_retired_models_excluded(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1900});model(3,{1},20,{year=2001});model(4,{1},20,{year=1950,untilYear=2000})
            vehicle(10,{part(1,1)});scan();assert(not row().changes[1] and #row().candidates[1]==0)''')

    def test_ranking_ties_speed_capacity_price_and_stable_key(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950,price=2000});model(3,{1},20,{year=1950,price=1500})
            model(4,{1},30,{year=1950,price=2500});model(5,{1},20,{year=1950,speed=25})
            vehicle(10,{part(1,1)});scan();assert(row().changes[1]=="model:5" and row().candidates[1][3].key=="model:3")''')

    def test_mod_namespace_candidate_and_player_ownership(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950,path="other_mod::/oil.mdl"})
            vehicle(10,{part(1,1)});vehicle(11,{part(1,1)},{owner=88});scan();assert(#controller.read().rows==1 and row().changes[1]=="model:2")''')

    def test_purchase_filters_enforced(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});restrictions.disabledVehicles={names[2]}
            vehicle(10,{part(1,1)});scan();assert(not row().changes[1])''')

    def test_locomotive_keeps_power_and_traction(self):
        self.run_lua('''model(1,{},0,{carrier="RAIL"});model(2,{},0,{carrier="RAIL",year=1950,speed=30,power=90})
            model(3,{},0,{carrier="RAIL",year=1940,speed=25,power=110,traction=60})
            vehicle(10,{part(1,-1)});scan();assert(row().changes[1]=="model:3")''')

    def test_electric_conversion_allowed_and_warned(self):
        self.run_lua('''model(1,{},0,{carrier="RAIL"});model(2,{},0,{carrier="RAIL",year=1950,electric=true,speed=30})
            vehicle(10,{part(1,-1)});scan();assert(row().changes[1]=="model:2")
            local c,b=native.catalog();local warnings=core.warnings(b["model:1"],b["model:2"],{})
            assert(table.concat(warnings):find("接触网"))''')

    def test_mixed_train_each_wagon_preserves_order_and_direction(self):
        self.run_lua('''model(1,{},0,{carrier="RAIL"});model(2,{1},10,{carrier="RAIL",unpowered=true})
            model(3,{2},10,{carrier="RAIL",unpowered=true});model(4,{1},20,{carrier="RAIL",unpowered=true,year=1950})
            model(5,{2},20,{carrier="RAIL",unpowered=true,year=1950})
            vehicle(10,{part(1),part(2,1,true,{reversed=true}),part(3,2)});scan()
            assert(row().config.vehicles[1].part.modelId==1 and row().config.vehicles[2].part.modelId==4 and row().config.vehicles[3].part.modelId==5)
            assert(row().config.vehicles[2].part.reversed and #row().config.vehicleGroups==3)''')

    def test_partial_quote_retained_age_maintenance_and_rounding(self):
        self.run_lua('''model(1,{},0,{carrier="RAIL",price=1000});model(2,{1},10,{carrier="RAIL",unpowered=true,price=500})
            model(3,{},0,{carrier="RAIL",year=1950,price=2000,speed=30})
            vehicle(10,{part(1),part(2,1,false,{value=251})},{refund=752});scan()
            assert(row().quote.purchase==2000 and row().quote.refund==501 and row().quote.net==1499)
            local retained=row().config.vehicles[2];assert(retained.purchaseTime==500 and retained.maintenanceState==.6 and retained.maintenanceChange==7)
            assert(retained.autoLoadConfig[1]==false and retained.part.compartment2loadConfig[1].cargoTypeId==1)''')

    def test_fixed_multiple_unit_replaced_as_whole_even_different_length(self):
        self.run_lua('''model(1,{0},10,{carrier="RAIL"});model(2,{0},20,{carrier="RAIL",year=1950})
            makeMu(100,{1,1});makeMu(101,{2,2,2})
            vehicle(10,{part(1,0),part(1,0)},{groups={2},muFiles={muNames[100]}});scan()
            assert(row().changes[1]=="mu:101" and #row().config.vehicles==3 and row().config.vehicleGroups[1]==3 and row().config.muFileNames[1]==muNames[101])''')

    def test_reversed_multiple_unit_with_opposite_facing_ends_stays_reversed(self):
        self.run_lua('''model(1,{0},10,{carrier="RAIL"});model(2,{0},10,{carrier="RAIL"})
            model(3,{0},20,{carrier="RAIL",year=1950});model(4,{0},20,{carrier="RAIL",year=1950})
            makeMu(100,{1,2});mus[100].vehicles[2].forward=false
            makeMu(101,{3,4});mus[101].vehicles[2].forward=false
            vehicle(10,{part(2,0),part(1,0,true,{reversed=true})},{groups={2},muFiles={muNames[100]}});scan()
            local p=row().config.vehicles;assert(p[1].part.modelId==4 and not p[1].part.reversed)
            assert(p[2].part.modelId==3 and p[2].part.reversed)''')

    def test_fixed_group_with_changed_internal_parts_is_not_silently_rebuilt(self):
        self.run_lua('''model(1,{0},10,{carrier="RAIL"});model(2,{0},20,{carrier="RAIL",year=1950})
            makeMu(100,{1,1});makeMu(101,{2,2})
            vehicle(10,{part(1,0),part(2,0)},{groups={2},muFiles={muNames[100]}});scan()
            assert(not row().snapshot and row().error:find("固定编组") and #commands==0)''')

    def test_capacity_is_not_double_counted_for_two_shared_cargos(self):
        self.run_lua('''local slots={{options={{cargo=1,capacity=10,loadIndex=0},{cargo=2,capacity=10,loadIndex=0}}}}
            assert(not core.allocate(slots,{[1]=8,[2]=8}));assert(core.allocate(slots,{[1]=8}))''')

    def test_allocation_backtracks_to_preserve_two_cargos(self):
        self.run_lua('''local slots={{options={{cargo=1,capacity=10,loadIndex=0},{cargo=2,capacity=10,loadIndex=1}}},
            {options={{cargo=1,capacity=10,loadIndex=0}}}}
            local a=core.allocate(slots,{[1]=10,[2]=10});assert(a and a[1].cargo==2 and a[2].cargo==1)''')

    def test_manual_target_below_current_load_is_blocked(self):
        self.run_lua('''model(1,{1},10);model(2,{1},5,{year=1950});vehicle(10,{part(1,1)},{loaded={[1]=8}})
            scan();controller.target(10,1,"model:2");assert(row().error and not controller.confirm() and #commands==0)''')

    def test_cargo_load_index_remapped_by_actual_cargo(self):
        self.run_lua('''model(1,{1},10);model(2,{2},20,{year=1950})
            table.insert(models[2].metadata.transportVehicle.compartments[1].loadConfigs,{cargoEntry={capacity=20,cargoTypeSet={ids={1}}}})
            vehicle(10,{part(1,1)},{loaded={[1]=7}});scan();assert(row().config.vehicles[1].part.compartment2loadConfig[1].loadConfigIndex==1)''')

    def test_no_command_on_scan_or_cancel_or_duplicate_confirm(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan();assert(#commands==0)
            assert(controller.confirm());assert(not controller.confirm());controller.step();assert(#commands==0)
            controller.step();assert(#commands==1);controller.step();assert(#commands==1)''')

    def test_insufficient_funds_blocks_before_any_command(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950,price=10000});vehicle(10,{part(1,1)});balance=1
            scan();assert(not controller.confirm() and #commands==0)''')

    def test_free_mode_nil_balance_is_supported(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});balance=nil
            scan();preflight();assert(controller.read().phase=="applying")''')

    def test_preflight_price_increase_continues_without_another_confirmation(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)},{refund=500});scan()
            entities[10].refund=400;preflight();assert(controller.read().phase=="applying" and row().quote.net==600)
            controller.step();assert(#commands==1 and commands[1].entity==10)''')

    def test_individual_quote_increase_with_unchanged_total_continues_in_updated_cost_order(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)},{refund=500})
            vehicle(11,{part(1,1)},{refund=500});scan();entities[10].refund=400;entities[11].refund=600
            preflight();assert(controller.read().phase=="applying" and controller.totals().net==1000)
            controller.step();assert(#commands==1 and commands[1].entity==11)
            finishCommand(true);controller.step();assert(#commands==2 and commands[2].entity==10)''')

    def test_accepted_price_increase_still_checks_batch_and_per_vehicle_balance(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950})
            vehicle(10,{part(1,1)},{refund=500});balance=550;scan()
            entities[10].refund=400;preflight()
            assert(controller.read().phase=="idle" and #commands==0 and row().quote.net==600)
            assert(controller.read().reviewMessage:find("余额不足",1,true))
            balance=650;preflight();assert(controller.read().phase=="applying")
            entities[10].refund=300;controller.step()
            assert(#commands==0 and controller.read().phase=="result" and row().quote.net==700)
            assert(row().error:find("余额不足",1,true))''')

    def test_later_quote_increase_stops_only_when_remaining_balance_is_insufficient(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950})
            vehicle(10,{part(1,1)},{refund=500});vehicle(11,{part(1,1)},{refund=400})
            balance=1200;scan();preflight()
            entities[10].refund=350;controller.step();assert(#commands==1 and commands[1].entity==10)
            balance=balance-row(1).quote.net;finishCommand(true)
            entities[11].refund=300;controller.step()
            local session=controller.read()
            assert(#commands==1 and session.phase=="result" and session.results.success==1 and session.results.failed==1)
            assert(row(1).status=="success" and row(2).status=="failed" and row(2).error:find("余额不足",1,true))''')

    def test_catalog_rebuilt_after_closing_window_and_loading_another_game(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan()
            assert(row().changes[1]=="model:2");controller.close();models[2].hidden=true
            gameCtx={filters={get=function() return {} end}};scan();assert(not row().changes[1])''')

    def test_preflight_config_change_updates_preview_without_execution(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan()
            entities[10].tv.transportVehicleConfig.vehicles[1].purchaseTime=501;preflight()
            assert(controller.read().phase=="idle" and #commands==0)''')

    def test_deleted_vehicle_and_mission_purchase_denied(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan();entities[10]=nil
            preflight();assert(controller.read().phase=="idle" and #commands==0)''')

    def test_protected_vehicle_rejected_in_preflight(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan();protected[10]=true
            preflight();assert(controller.read().phase=="idle" and row().error and #commands==0)''')

    def test_queue_negative_net_first_then_stops_at_first_failure(self):
        self.run_lua('''model(1,{1},10,{price=4000});model(2,{1},20,{year=1950,price=1000})
            vehicle(10,{part(1,1)},{refund=3000});vehicle(11,{part(1,1)},{refund=200});vehicle(12,{part(1,1)},{refund=100})
            scan();preflight();controller.step();assert(commands[1].entity==10)
            finishCommand(true);controller.step();assert(commands[2].entity==11)
            finishCommand(false);controller.step();assert(#commands==2 and controller.read().phase=="result")
            assert(row(1).status=="success" and row(2).status=="failed" and row(3).status=="skipped")''')

    def test_runtime_cargo_increase_stops_queue_before_command(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan();preflight()
            entities[10].loaded[1]=30;controller.step();assert(#commands==0 and controller.read().phase=="result")''')

    def test_group_choice_then_individual_override_and_keep(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});model(3,{1},15,{year=1960});vehicle(10,{part(1,1)});vehicle(11,{part(1,1)})
            scan();controller.groupTarget(row().snapshot.units[1].groupKey,"model:2")
            assert(row(1).changes[1]=="model:2" and row(2).changes[1]=="model:2")
            controller.target(10,1,"keep");assert(not row().selected and not row().changes[1] and row(2).selected)''')

    def test_filters_limit_select_all_without_losing_hidden_selections(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});vehicle(11,{part(1,1)})
            scan();controller.filter("search","instance 10");controller.selectAll(false)
            assert(not row(1).selected and row(2).selected)''')

    def test_queue_progress_and_success_callback_ignores_result_shape(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan();preflight();controller.step()
            callbacks[1]({},true,{10});table.remove(callbacks,1);controller.step()
            assert(controller.read().phase=="result" and controller.read().results.success==1)''')

    def test_upgraded_manual_cargo_keeps_manual_mode(self):
        self.run_lua('''model(1,{1,2},10);model(2,{1,2},20,{year=1950});vehicle(10,{part(1,1,false)})
            scan();local p=row().config.vehicles[1];assert(p.autoLoadConfig[1]==false and p.part.compartment2loadConfig[1].cargoTypeId==1)''')

    def test_empty_manual_multi_cargo_keeps_each_compartment_purpose(self):
        self.run_lua('''model(1,{1,2},10,{compartments=2});model(2,{1,2},20,{year=1950,compartments=2})
            local p=part(1,1,false);p.part.compartment2loadConfig[2].cargoTypeId=2;vehicle(10,{p});scan()
            local configs=row().config.vehicles[1].part.compartment2loadConfig
            assert(configs[1].cargoTypeId~=configs[2].cargoTypeId)
            assert(not row().config.vehicles[1].autoLoadConfig[1] and not row().config.vehicles[1].autoLoadConfig[2])''')

    def test_recommendation_skips_newer_shared_tank_that_loses_manual_mix(self):
        self.run_lua('''model(1,{1,2},10,{compartments=2});model(2,{1,2},30,{year=1990})
            model(3,{1,2},20,{year=1950,compartments=2})
            local p=part(1,1,false);p.part.compartment2loadConfig[2].cargoTypeId=2;vehicle(10,{p});scan()
            assert(row().changes[1]=="model:3" and #row().candidates[1]==1 and not row().error)
            controller.target(10,1,"model:2");assert(row().changes[1]=="model:3")''')

    def test_manual_coverage_is_per_group_and_counts_alongside_current_load(self):
        self.run_lua('''local slots={{scope=1,options={{cargo=1,capacity=10,loadIndex=0},{cargo=2,capacity=10,loadIndex=1}}},
            {scope=1,options={{cargo=1,capacity=10,loadIndex=0},{cargo=2,capacity=10,loadIndex=1}}},
            {scope=2,options={{cargo=2,capacity=10,loadIndex=0}}}}
            local a=core.allocate(slots,{[1]=10,[2]=20},nil,{[1]={[1]=true,[2]=true},[2]={[2]=true}})
            assert(a and a[1].cargo~=a[2].cargo and a[3].cargo==2)
            assert(not core.allocate({slots[1],slots[3]},{},nil,{[1]={[1]=true,[2]=true}}))''')

    def test_owner_change_blocks_upgrade(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan();entities[10].owner=88
            preflight();assert(#commands==0 and row().error:find("公司"))''')

    def test_idle_external_config_refresh_recovers_without_dead_end(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan()
            entities[10].tv.transportVehicleConfig.vehicles[1].purchaseTime=501;controller.refresh()
            assert(not row().error and row().snapshot.units[1].parts[1].purchaseTime==501 and controller.confirm())''')

    def test_idle_balance_refresh_updates_ui_without_a_price_change(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan()
            controller.selectAll(false);local _,before=controller.read();balance=5;controller.refresh()
            local _,after=controller.read();assert(after>before and controller.totals().balance==5)''')

    def test_only_rail_traction_is_a_recommendation_requirement(self):
        self.run_lua('''model(1,{1},10,{power=100});model(2,{1},20,{year=1950,power=90});vehicle(10,{part(1,1)})
            scan();assert(row().changes[1]=="model:2")''')

    def test_mission_denial_and_transport_type_mismatch(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950,carrier="WATER"});model(3,{1},20,{year=1950})
            vehicle(10,{part(1,1)});missionMessage="mission denied";scan()
            assert(#row().candidates[1]==1 and row().error=="mission denied" and not controller.confirm())''')

    def test_large_scan_is_incremental(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});for i=1,120 do vehicle(i,{part(1,1)}) end
            controller.open(gameCtx);controller.step();controller.step()
            assert(#controller.read().rows==6 and controller.busy())
            for _=1,30 do controller.step() end;assert(#controller.read().rows==120 and not controller.busy())''')

    def test_syntax_json_resource_index_and_encoding(self):
        loader = self.lua.eval("function(code,name) return load(code,name) end")
        for file in MOD.rglob("*.lua"):
            data = file.read_bytes()
            self.assertFalse(data.startswith(b"\xef\xbb\xbf"), file)
            result = loader(data.decode("utf-8"), str(file))
            self.assertFalse(isinstance(result, tuple), (file, result))
        for file in MOD.rglob("*.json"):
            json.loads(file.read_text(encoding="utf-8"))
        index = json.loads((MOD / "_content.json").read_text(encoding="utf-8"))
        self.assertEqual(set(index["files"]), {p.relative_to(MOD / "content").as_posix() for p in (MOD / "content").rglob("*") if p.is_file()})


if __name__ == "__main__":
    unittest.main(verbosity=2)
