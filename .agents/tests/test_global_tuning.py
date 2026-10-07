"""Execute the shipped Lua 5.4; mocks cover transforms, not TF3 simulation."""
import json
import sys
import unittest
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".agents/tools/line_naming_test_runtime"))
from lupa.lua54 import LuaRuntime

MOD = ROOT / "staging_area/xiaom_global_tuning"
GAME = Path(r"E:\steam\steamapps\common\Transport Fever 3")

FIXTURE = r'''
function clone(v)
    if type(v) ~= "table" then return v end
    local t = {}; for k, x in pairs(v) do t[k] = clone(x) end; return t
end
logs, commands, writes = {}, {}, 0
function debugPrint(v) logs[#logs+1] = tostring(v) end
function _(v) return v end
function getCurrentModId() return "xiaom_global_tuning" end
catalog = {
    [0] = {name="::/cargos/passengers/passengers.cargo", classes={PASSENGERS=true}, loadSpeedFactor=1},
    [1] = {name="::/cargos/coal/coal.cargo", classes={UNIVERSAL=true,BULK=true}, loadSpeedFactor=0.0625},
    [2] = {name="::/cargos/tools/tools.cargo", classes={UNIVERSAL=true,GOODS=true}, loadSpeedFactor=0.0625},
}
function inList(list, value) for _, v in ipairs(list or {}) do if v == value then return true end end return false end
function accepts(set, item)
    local included = inList(set.cargoTypesIncluded, item.name)
    local excluded = inList(set.cargoTypesExcluded, item.name)
    for class in pairs(item.classes) do
        included = included or inList(set.cargoClassesIncluded, class)
        excluded = excluded or inList(set.cargoClassesExcluded, class)
    end
    return included and not excluded
end
function classify(set)
    local passenger, freight = false, false
    for id, item in pairs(catalog) do
        if accepts(set, item) then
            if id == 0 then passenger = true else freight = true end
        end
    end
    return passenger, freight
end
function makeModel(classes, capacity, carrier)
    return {metadata={
        transportVehicle={carrier=carrier or "ROAD", compartments={{loadConfigs={{
            cargoEntry={capacity=capacity, cargoTypeSet={cargoClassesIncluded=classes,
                cargoClassesExcluded={},cargoTypesIncluded={},cargoTypesExcluded={}},seats={7},loadIndicator="test"},toHide={"door"}
        }}}}},
        landVehicle={topSpeed=20,weightEmpty=1000,weightMaxPayload=2000,
            engines={{power=100,tractiveEffort=50,type="DIESEL"}}},
        cost={price=123},maintenance={runningCosts=42},availability={yearFrom=1900}
    }}
end
function makeRep(resources, names)
    return {
        getAsTable=function(id) return clone(resources[id]) end,
        getAll=function() local r={}; for id in pairs(resources) do r[id]=names and names[id] or tostring(id) end; return r end,
        getName=function(id) return names and names[id] or tostring(id) end,
        setAsTable=function(id,v) writes=writes+1;resources[id]=clone(v);return true end,
    }
end
models={[1]=makeModel({"UNIVERSAL"},10),[2]=makeModel({"PASSENGERS"},11),[3]=makeModel({},0,"RAIL")}
modelNames={[1]="truck",[2]="bus",[3]="locomotive"}
streets={[1]={roadType="STREET",laneConfigs={{speed=10,transportModes={"CAR","BUS"}},{speed=1,transportModes={"PERSON"}}}},
    [2]={roadType="TRACK",laneConfigs={{speed=20,transportModes={"TRAIN"}}},speedCoeffs={0.9,15,0.63}}}
bridges={[1]={speedLimit=20,carriers={"ROAD","RAIL"}}}
tunnels={[1]={speedLimit=30}}
crossings={[1]={speedLimit=40}}
rawParams={}
guiSaveData={}
ready=true
api={type={CargoTypeSet={new=function() return {} end},ComponentType={GAME_SPEED="GAME_SPEED"}},res={},
    engine={util={getWorld=function() return 0 end},entityExists=function() return ready end,
        getComponent=function() return ready and {speedup=0,millisPerDay=2000} or nil end,
        config={getModParams=function() return {xiaom_global_tuning=rawParams} end}},
    util={getDefaultDayDuration=function() return 2000 end},
    cmd={makeGameSetSpeedCmd=function(v) return {kind="simulation",value=v} end,
        makeGameSetCalendarSpeedCmd=function(v) return {kind="calendar",value=v} end,
        sendCommand=function(c,callback) commands[#commands+1]=c;callback({},true) end}}
api.res.modelRep=makeRep(models,modelNames)
api.res.modelRep.find=function(name) for id,n in pairs(modelNames) do if n==name then return id end end return -1 end
api.res.modelRep.forEachModelWithMetadata=function(_,fn) for _,name in pairs(modelNames) do fn(name) end end
api.res.cargoTypeRep=makeRep(catalog)
api.res.cargoTypeRep.getName=function(id) return catalog[id].name end
api.res.cargoTypeRep.getPassengerCargoTypeId=function() return 0 end
api.res.cargoTypeRep.hasCargoType=function(set,id,inverse)
    if not inverse then return accepts(set,catalog[id]) end
    for other,item in pairs(catalog) do if other~=id and accepts(set,item) then return true end end
    return false
end
api.res.streetTemplateRep=makeRep(streets)
api.res.bridgeTypeRep=makeRep(bridges)
api.res.tunnelTypeRep=makeRep(tunnels)
api.res.railroadCrossingTypeRep=makeRep(crossings)
api.gui={game={
    getGuiSaveData=function() return clone(guiSaveData) end,
    setGuiSaveData=function(_,data) guiSaveData=clone(data) end,
}}

-- Revision 6: userdata IO and resource snapshots, never savegame IO.
userdata, userdataWrites, snapshotWrites, clock = {}, 0, 0, 0
app = {
    loadUserdata=function(dir,name) return clone(userdata[dir.."/"..name]) end,
    saveUserdata=function(dir,name,value) userdataWrites=userdataWrites+1;userdata[dir.."/"..name]=clone(value) end,
    getUserDataFolder=function() return "mock-userdata" end,
    saveGame=function() error("Mod must never save a game") end,
    loadGame=function() error("Mod must never load a game") end,
}
function setConfig(params)
    userdata["mod_settings/xiaom_global_tuning/settings"]={version=1,params=clone(params)}
end
snapshots={
    [1]={type="xiaom-global-tuning-load-settings",data={version=1,params={}}},
    [2]={type="xiaom-global-tuning-config",data={version=1,params={}}},
}
api.res.genericRep={
    find=function(name) return name:find("/load_settings.res",1,true) and 1 or name:find("/local_settings.res",1,true) and 2 or -1 end,
    get=function(id) return snapshots[id] end,
    getAsTable=function(id) return clone(snapshots[id]) end,
    setAsTable=function(id,value) snapshotWrites=snapshotWrites+1;snapshots[id]=clone(value);return true end,
}
api.engine.getEntitiesWithComponent=function() return {} end
api.util.getApplicationTime=function() return clock end
api.gui.game.setGuiSaveData=function() error("Mod must never write GUI save data") end

'''


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FIXTURE)
    modules = {}
    def require(name):
        key = name.split("::/")[-1]
        if key not in modules:
            modules[key] = lua.execute((MOD / "content" / key).read_text(encoding="utf-8"))
        return modules[key]
    lua.globals().ug_require = require
    lua.globals().settings = require("settings.lua")
    lua.globals().core = require("tuning_core.lua")
    return lua


class TuningTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime()

    def run_lua(self, source):
        return self.lua.execute(source)

    def hook(self):
        self.lua.execute((MOD / "content/mod.script.lua").read_text(encoding="utf-8"))
        return self.lua.globals().data()

    def test_json_and_parameter_contract(self):
        for file in MOD.rglob("*.json"):
            self.assertFalse(file.read_bytes().startswith(b"\xef\xbb\xbf"))
            json.loads(file.read_text(encoding="utf-8"))
        definition = json.loads((MOD / "mod.json").read_text(encoding="utf-8"))
        self.assertEqual(definition["params"], [], "Settings are independent of saves")
        self.assertEqual(definition["revision"], 7)
        index = json.loads((MOD / "_content.json").read_text(encoding="utf-8"))
        self.assertEqual(sorted(index["files"]), sorted(p.name for p in (MOD / "content").iterdir()))

    def test_all_lua_parses(self):
        check = self.lua.eval("function(s) local f,e=load(s); return f~=nil,e end")
        for file in (MOD / "content").glob("*.lua"):
            ok, err = check(file.read_text(encoding="utf-8"))
            self.assertTrue(ok, f"{file}: {err}")

    def test_invalid_parameters_use_defaults(self):
        self.run_lua('local p=settings.normalize({freightCapacity=0,freightWeight=math.huge,vehicleSpeed="2",railTraction=0/0,simulationSpeed=1.5}); assert(p.freightCapacity==1 and p.freightWeight==1 and p.vehicleSpeed==1 and p.railTraction==1 and p.simulationSpeed==-1)')

    def test_native_option_indices_roundtrip_and_invalid_values(self):
        self.run_lua('''
            for index,value in ipairs(settings.multipliers) do
                local p=settings.fromModParams({freightCapacity=index})
                assert(p.freightCapacity==value and settings.toModParams(p).freightCapacity==index)
            end
            for _,key in ipairs({"simulationSpeed","calendarSpeed"}) do
                local choices=key=="simulationSpeed" and settings.simulationSpeeds or settings.calendarSpeeds
                for index,value in ipairs(choices) do
                    local p=settings.fromModParams({[key]=index})
                    assert(p[key]==value and settings.toModParams(p)[key]==index)
                end
            end
            for _,index in ipairs({0,-1,0.1,1.5,100,math.huge,"5"}) do
                assert(settings.fromModParams({freightCapacity=index}).freightCapacity==1)
            end
            assert(settings.fromModParams({freightCapacity=9,passengerCapacity=10,simulationSpeed=1,calendarSpeed=1}).freightCapacity==5)
            assert(settings.fromModParams({simulationSpeed=1}).simulationSpeed==-1)
        ''')

    def test_multiplier_boundaries_and_rounding(self):
        self.run_lua('for _,factor in ipairs({0.1,1,2,100}) do local p=settings.normalize({freightCapacity=factor}); local m=makeModel({"UNIVERSAL"},11); core.model(m,p,classify,catalog[0].name); assert(m.metadata.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.capacity==math.max(1,math.floor(11*factor+0.5))) end')

    def test_positive_capacity_never_rounds_to_zero(self):
        self.run_lua('local m=makeModel({"UNIVERSAL"},1); core.model(m,settings.normalize({freightCapacity=0.1}),classify,catalog[0].name); assert(m.metadata.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.capacity==1)')

    def test_zero_and_negative_capacity_preserved(self):
        self.run_lua('for _,value in ipairs({0,-1}) do local m=makeModel({"UNIVERSAL"},value); core.model(m,settings.normalize({freightCapacity=100}),classify,catalog[0].name); assert(m.metadata.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.capacity==value) end')

    def test_passenger_capacity_independent(self):
        self.run_lua('local m=makeModel({"PASSENGERS"},10); core.model(m,settings.normalize({freightCapacity=100,passengerCapacity=2}),classify,catalog[0].name); assert(m.metadata.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.capacity==20)')

    def test_mixed_config_stays_one_compartment(self):
        self.run_lua('local m=makeModel({"PASSENGERS","UNIVERSAL"},10); core.model(m,settings.normalize({freightCapacity=3,passengerCapacity=2}),classify,catalog[0].name); local tv=m.metadata.transportVehicle; assert(#tv.compartments==1); local c=tv.compartments[1].loadConfigs; assert(#c==2 and c[1].cargoEntry.capacity==20 and c[2].cargoEntry.capacity==30); local p,g=classify(c[1].cargoEntry.cargoTypeSet); assert(p and not g); p,g=classify(c[2].cargoEntry.cargoTypeSet); assert(not p and g); assert(c[1].toHide[1]=="door" and c[2].cargoEntry.loadIndicator=="test"); c[1].toHide[1]="other"; assert(c[2].toHide[1]=="door")')

    def test_equal_factors_do_not_split(self):
        self.run_lua('local m=makeModel({"PASSENGERS","UNIVERSAL"},10); core.model(m,settings.normalize({freightCapacity=2,passengerCapacity=2}),classify,catalog[0].name); assert(#m.metadata.transportVehicle.compartments[1].loadConfigs==1)')

    def test_cargo_exclusions_respected(self):
        self.run_lua('local m=makeModel({"UNIVERSAL","PASSENGERS"},10); m.metadata.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.cargoTypeSet.cargoClassesExcluded={"PASSENGERS"}; core.model(m,settings.normalize({freightCapacity=2,passengerCapacity=100}),classify,catalog[0].name); assert(m.metadata.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.capacity==20)')

    def test_empty_cargo_set_not_treated_as_freight(self):
        self.run_lua('local m=makeModel({},4,"RAIL"); core.model(m,settings.normalize({freightCapacity=100,freightWeight=100}),classify,catalog[0].name); assert(m.metadata.landVehicle.weightMaxPayload==2000 and m.metadata.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.capacity==4)')

    def test_weight_does_not_change_capacity_or_empty_mass(self):
        self.run_lua('local m=makeModel({"UNIVERSAL"},10); core.model(m,settings.normalize({freightWeight=2}),classify,catalog[0].name); assert(m.metadata.landVehicle.weightMaxPayload==4000 and m.metadata.landVehicle.weightEmpty==1000 and m.metadata.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.capacity==10)')

    def test_passenger_weight_preserved(self):
        self.run_lua('local m=makeModel({"PASSENGERS"},10); core.model(m,settings.normalize({freightWeight=100}),classify,catalog[0].name); assert(m.metadata.landVehicle.weightMaxPayload==2000)')

    def test_traction_only_powered_rail(self):
        self.run_lua('for _,carrier in ipairs({"RAIL","TRAM","ROAD"}) do local m=makeModel({"PASSENGERS"},10,carrier); core.model(m,settings.normalize({railTraction=2}),classify,catalog[0].name); local e=m.metadata.landVehicle.engines[1]; assert(e.power==(carrier=="RAIL" and 200 or 100)); assert(e.tractiveEffort==(carrier=="RAIL" and 100 or 50)) end; local m=makeModel({},0,"RAIL");m.metadata.landVehicle.engines={};assert(not core.model(m,settings.normalize({railTraction=2}),classify,catalog[0].name))')

    def test_land_water_air_speed(self):
        self.run_lua('for _,kind in ipairs({"landVehicle","waterVehicle","airVehicle"}) do local m=makeModel({"UNIVERSAL"},10);local v=m.metadata.landVehicle;m.metadata.landVehicle=nil;m.metadata[kind]=v;core.model(m,settings.normalize({vehicleSpeed=2}),classify,catalog[0].name);assert(v.topSpeed==40) end')

    def test_cost_maintenance_and_availability_preserved(self):
        self.run_lua('local m=makeModel({"UNIVERSAL"},10); core.model(m,settings.normalize({freightCapacity=100,vehicleSpeed=100,freightWeight=100}),classify,catalog[0].name); assert(m.metadata.cost.price==123 and m.metadata.maintenance.runningCosts==42 and m.metadata.availability.yearFrom==1900)')

    def test_road_walk_and_airport_lanes(self):
        self.run_lua('local s={roadType="STREET",laneConfigs={{speed=10,transportModes={"CAR"}},{speed=2,transportModes={"PERSON","CARGO"}},{speed=8,transportModes={"AIRCRAFT"}}}};core.street(s,2);assert(s.laneConfigs[1].speed==20 and s.laneConfigs[2].speed==2 and s.laneConfigs[3].speed==8)')

    def test_native_style_mode_dictionary(self):
        self.run_lua('local s={roadType="STREET",laneConfigs={{speed=10,transportModes={CAR=true,PERSON=false}}}};core.street(s,2);assert(s.laneConfigs[1].speed==20)')

    def test_track_curve_formula_scaling(self):
        self.run_lua('local t={roadType="TRACK",laneConfigs={{speed=50,transportModes={"TRAIN"}}},speedCoeffs={0.9,15,0.63}};local before=t.speedCoeffs[1]*(100+t.speedCoeffs[2])^t.speedCoeffs[3];core.street(t,2);assert(t.speedCoeffs[2]==15 and t.speedCoeffs[3]==0.63);assert(math.abs(t.speedCoeffs[1]*(100+t.speedCoeffs[2])^t.speedCoeffs[3]-2*before)<1e-8)')

    def test_section_sentinels_and_carriers(self):
        self.run_lua('for _,value in ipairs({0,-1}) do local t={speedLimit=value}; assert(not core.section(t,100) and t.speedLimit==value) end; local t={speedLimit=10,carriers={"AIR"}};assert(not core.section(t,2)); t={speedLimit=10,carriers={"ROAD"}};assert(core.section(t,2) and t.speedLimit==20)')

    def test_full_hook_and_no_repeated_post_multiplication(self):
        hook = self.hook()
        self.run_lua('rawParams={industryProduction=2,freightCapacity=2,passengerCapacity=3,freightWeight=2,freightLoading=2,passengerLoading=3,vehicleSpeed=2,railTraction=2};base={locations={industry={industryProductivity=1.5}}}')
        g = self.lua.globals()
        all_params = self.lua.table_from({"xiaom_global_tuning": g.settings.toModParams(g.rawParams)})
        hook.preRunFn(None, None, all_params, g.base)
        hook.postRunFn(None, None, all_params)
        before = g.writes
        hook.postRunFn(None, None, all_params)
        self.assertEqual(g.writes, before)
        self.run_lua('assert(base.locations.industry.industryProductivity==1.5);assert(models[1].metadata.landVehicle.topSpeed==40 and models[1].metadata.landVehicle.weightMaxPayload==4000);assert(models[2].metadata.transportVehicle.compartments[1].loadConfigs[1].cargoEntry.capacity==33);assert(models[3].metadata.landVehicle.engines[1].power==200);assert(catalog[0].loadSpeedFactor==3 and catalog[1].loadSpeedFactor==0.125);assert(streets[1].laneConfigs[2].speed==1 and bridges[1].speedLimit==40)')

    def test_default_hook_does_not_rewrite_resources(self):
        hook = self.hook()
        hook.postRunFn(None, None, self.lua.table())
        self.assertEqual(self.lua.globals().writes, 0)

    def test_new_load_starts_from_fresh_resources(self):
        for _ in range(2):
            lua = runtime()
            lua.execute((MOD / "content/mod.script.lua").read_text(encoding="utf-8"))
            hook = lua.globals().data()
            params = lua.eval('{xiaom_global_tuning=settings.toModParams({vehicleSpeed=2})}')
            hook.postRunFn(None, None, params)
            self.assertEqual(lua.globals().models[1].metadata.landVehicle.topSpeed, 40)

    def time_hook(self):
        self.lua.execute((MOD / "content/time_control.script.lua").read_text(encoding="utf-8"))
        return self.lua.globals().data()

    def test_time_preserve_does_not_send_commands(self):
        hook = self.time_hook()
        hook.guiUpdate(None, None, None)
        self.assertEqual(len(self.lua.globals().commands), 0)

    def test_time_initializes_while_paused_and_only_once(self):
        self.run_lua('setConfig({simulationSpeed=4,calendarSpeed=2})')
        hook = self.time_hook()
        for _ in range(10):
            hook.guiUpdate(None, None, None)
        self.run_lua('assert(#commands==2 and commands[1].value==4 and commands[2].value==1000)')

    def test_time_waits_for_world(self):
        self.run_lua('ready=false;setConfig({simulationSpeed=2,calendarSpeed=0})')
        hook = self.time_hook()
        hook.guiUpdate(None, None, None)
        self.assertEqual(len(self.lua.globals().commands), 0)
        self.run_lua('ready=true')
        hook.guiUpdate(None, None, None)
        self.run_lua('assert(#commands==2 and commands[2].value==0)')

    def test_time_can_pause_simulation(self):
        self.run_lua('setConfig({simulationSpeed=0})')
        self.time_hook().guiUpdate(None, None, None)
        self.run_lua('assert(#commands==1 and commands[1].value==0)')

    def test_calendar_boundaries(self):
        self.run_lua('assert(core.dayDuration(0,2000)==0 and core.dayDuration(0.1,2000)==20000 and core.dayDuration(100,2000)==20)')

    def test_rejected_resource_reported(self):
        self.run_lua('api.res.modelRep.setAsTable=function() return false end')
        self.hook().postRunFn(None, None, self.lua.eval('{xiaom_global_tuning={vehicleSpeed=2}}'))
        self.run_lua('assert(logs[#logs]:find("errors=3",1,true))')


class InstalledResourceTests(unittest.TestCase):
    def test_original_vehicle_and_infrastructure_tables(self):
        if not GAME.exists():
            self.skipTest("Installed TF3 unavailable")
        lua = runtime()
        core = lua.globals().core
        params = lua.globals().settings.normalize(lua.eval('{freightCapacity=2,passengerCapacity=3,freightWeight=2,vehicleSpeed=2,railTraction=2}'))
        counts = {}
        # Use real .mdl data tables, without loading textures/meshes or emulating the engine.
        for kind in ["truck", "bus", "train", "waggon", "ship", "plane", "tram"]:
            tested = 0
            for archive in (GAME / "base/content/vehicle" / kind).glob("*.zip"):
                with ZipFile(archive) as z:
                    for name in z.namelist():
                        if not name.endswith(".mdl"):
                            continue
                        source = z.read(name).decode("utf-8")
                        try:
                            lua.execute(source)
                            model = lua.globals().data()
                        except Exception:
                            continue  # Some assets need additional game-specific model helpers.
                        metadata = model.metadata
                        if metadata is None or metadata.transportVehicle is None:
                            continue
                        old = lua.globals().clone(model)
                        core.model(model, params, lua.globals().classify, lua.globals().catalog[0].name)
                        for key in ["landVehicle", "waterVehicle", "airVehicle"]:
                            before, after = old.metadata[key], metadata[key]
                            if before is not None and before.topSpeed and before.topSpeed > 0:
                                self.assertAlmostEqual(after.topSpeed, before.topSpeed * 2, msg=name)
                                self.assertEqual(after.weightEmpty, before.weightEmpty, name)
                        tested += 1
            self.assertGreater(tested, 0, kind)
            counts[kind] = tested
        for archive_name in ["street", "track", "bridge", "tunnel", "railroad_crossing"]:
            tested = 0
            with ZipFile(GAME / "base/content/infrastructure" / f"{archive_name}.zip") as z:
                for name in z.namelist():
                    suffix = ".street_template.lua" if archive_name in {"street", "track"} else {"bridge": ".bridge.lua", "tunnel": ".tunnel.lua", "railroad_crossing": ".rcr.lua"}[archive_name]
                    if not name.endswith(suffix):
                        continue
                    try:
                        lua.execute(z.read(name).decode("utf-8"))
                        resource = lua.globals().data()
                    except Exception:
                        continue
                    before = lua.globals().clone(resource)
                    if archive_name in {"street", "track"}:
                        core.street(resource, 2)
                        if resource.roadType == "TRACK" and before.speedCoeffs:
                            self.assertAlmostEqual(resource.speedCoeffs[1], before.speedCoeffs[1]*2)
                            self.assertEqual(resource.speedCoeffs[2], before.speedCoeffs[2])
                    else:
                        core.section(resource, 2)
                        if before.speedLimit and before.speedLimit > 0:
                            self.assertAlmostEqual(resource.speedLimit, before.speedLimit * 2)
                    tested += 1
            self.assertGreater(tested, 0, archive_name)
            counts[archive_name] = tested
        print("Original resource tables checked:", json.dumps(counts, sort_keys=True))


if __name__ == "__main__":
    unittest.main(verbosity=2)
