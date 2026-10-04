"""Execute the shipped Lua against a state-copying TF3 API test double.

Run: py -X utf8 .agents/tests/test_auto_line_names.py
The Lua test runtime is isolated in .agents/tools/line_naming_test_runtime.
This does not emulate the game resource loader or engine scheduling.
"""
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".agents/tools/line_naming_test_runtime"))
from lupa.lua54 import LuaRuntime

MOD = ROOT / "staging_area/xiaom_auto_line_names"
SCRIPT = MOD / "content/auto_line_names.script.lua"

MOCK = r'''
function deepcopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = deepcopy(item) end
    return copy
end
world = {
    components = {}, names = {}, lines = {}, vehicles = {}, towns = {},
    stationKinds = {}, sent = {}, queued = {}, delayed = false, fail = false,
    passenger = 0,
    cargo = {
        [0] = { name = "旅客", order = 0 },
        [1] = { name = "煤炭", order = 2 },
        [2] = { name = "铁矿石", order = 1 },
        [3] = { name = "食品", order = 3 },
        [8] = { name = "自定义货物", order = 4 },
    },
}
logs = {}
function debugPrint(message) logs[#logs + 1] = message end
api = {
    type = { ComponentType = {
        LINE = "line", STATION_GROUP = "group", TRANSPORT_VEHICLE = "vehicle",
        PLAYER_OWNED = "owner",
    } },
    engine = {
        entityExists = function(entity) return world.names[entity] ~= nil end,
        getComponent = function(entity, kind)
            return world.components[entity] and world.components[entity][kind]
        end,
        util = {
            getPlayer = function() return 99 end,
            getEntityName = function(entity) return world.names[entity] end,
            station = { isStationOfType = function(entity, cargo)
                local kind = world.stationKinds[entity]
                return kind == "mixed" or kind == (cargo and "cargo" or "passenger")
            end },
        },
        system = {
            lineSystem = { getLinesForPlayer = function(player)
                local result = {}
                for _, entity in ipairs(world.lines) do
                    if world.components[entity].owner.player == player then result[#result + 1] = entity end
                end
                return result
            end },
            stationSystem = { getStation2TownMap = function() return world.towns end },
            transportVehicleSystem = { getLineVehicles = function(entity)
                return world.vehicles[entity] or {}
            end },
        },
    },
    res = { cargoTypeRep = {
        getAll = function()
            local ids = {}
            for id in pairs(world.cargo) do ids[id] = "cargo/" .. id end
            return ids
        end,
        get = function(id) assert(world.cargo[id]); return world.cargo[id] end,
        getPassengerCargoTypeId = function() return world.passenger end,
    } },
    cmd = {
        makeEntitySetNameCmd = function(entity, name) return { entity = entity, name = name } end,
        sendCommand = function(command)
            if world.fail then return end -- Engine refuses a command without applying it.
            world.sent[#world.sent + 1] = command
            if world.delayed then
                world.queued[#world.queued + 1] = command
            else
                world.names[command.entity] = command.name
            end
        end,
    },
}
state = { value = {} }
function state:get() return deepcopy(self.value) end
function state:set(value) self.value = deepcopy(value) end
function reload() state.value = deepcopy(state.value) end
function flush()
    for _, command in ipairs(world.queued) do world.names[command.entity] = command.name end
    world.queued = {}
end
function station(id, townId, townName, name, kind)
    world.names[id] = name
    world.names[id + 1000] = "station " .. id
    world.components[id] = { group = { stations = { id + 1000 } } }
    world.stationKinds[id + 1000] = kind or "passenger"
    if townId then
        world.names[townId] = townName
        world.towns[id + 1000] = townId
    end
end
function stop(id, ids, maximum)
    local load, maxLoad = {}, {}
    for cargoId in pairs(world.cargo) do load[cargoId + 1] = false; maxLoad[cargoId + 1] = 1 end
    for _, cargoId in ipairs(ids or {}) do load[cargoId + 1] = true end
    if maximum then for cargoId, value in pairs(maximum) do maxLoad[cargoId + 1] = value end end
    return { stationGroup = id, station = 0, terminal = 0, stopConfig = { load = load, maxLoad = maxLoad } }
end
function line(id, stops, name, player)
    world.names[id] = name or "线路 " .. id
    world.components[id] = { line = { stops = stops }, owner = { player = player or 99 } }
    world.lines[#world.lines + 1] = id
end
function vehicle(id, lineId, caps)
    world.names[id] = "vehicle " .. id
    local capacities = {}
    for cargoId, count in pairs(caps) do capacities[cargoId + 1] = count end
    world.components[id] = { vehicle = { config = { capacities = capacities } } }
    world.vehicles[lineId] = world.vehicles[lineId] or {}
    table.insert(world.vehicles[lineId], id)
end
function run(count, dt)
    for i = 1, count or 15 do
        local operations = script.update({}, state, dt or 0.016)
        script.postUpdate({}, state, dt or 0.016, operations)
    end
end
station(10, 100, "北京", "北京站", "passenger")
station(20, 200, "天津", "天津站", "passenger")
station(30, 300, "唐山", "唐山站", "cargo")
station(40, 100, "北京", "北京西", "passenger")
station(50, nil, nil, "矿山", "cargo")
station(60, nil, nil, "钢厂", "cargo")
'''


class NamingTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.execute(SCRIPT.read_text(encoding="utf-8"))
        self.lua.execute("script = data()")
        self.lua.execute("run(1)")

    def execute(self, code):
        self.lua.execute(code)

    def name(self, entity=1):
        return self.lua.eval(f"world.names[{entity}]")

    def test_new_passenger_line(self):
        self.execute("line(1, { stop(10,{0}), stop(20,{0}) }); run()")
        self.assertEqual(self.name(), "[客运] 北京-天津")

    def test_existing_line_preserved(self):
        self.execute('state.value = {}; line(1,{stop(10,{0}),stop(20,{0})},"旧线路"); run(46)')
        self.assertEqual(self.name(), "旧线路")

    def test_empty_and_single_stop_wait(self):
        self.execute("line(1,{}); run(); world.components[1].line.stops = {stop(10,{0})}; run()")
        self.assertEqual(self.name(), "线路 1")
        self.execute("table.insert(world.components[1].line.stops,stop(20,{0})); run()")
        self.assertEqual(self.name(), "[客运] 北京-天津")

    def test_same_town_station_names(self):
        self.execute("line(1,{stop(10,{0}),stop(40,{0})}); run()")
        self.assertEqual(self.name(), "[客运] 北京站-北京西")

    def test_rural_station_names(self):
        self.execute("line(1,{stop(50,{1}),stop(60,{})}); run()")
        self.assertEqual(self.name(), "[货运] 煤炭-矿山-钢厂")

    def test_loop_skips_closing_first_stop(self):
        self.execute("line(1,{stop(10,{0}),stop(20,{0}),stop(10,{0})}); run()")
        self.assertEqual(self.name(), "[客运] 北京-天津")

    def test_no_second_distinct_stop(self):
        self.execute("line(1,{stop(10,{0}),stop(10,{0})}); run()")
        self.assertEqual(self.name(), "线路 1")

    def test_freight_without_vehicles(self):
        self.execute("line(1,{stop(30,{1}),stop(20,{})}); run()")
        self.assertEqual(self.name(), "[货运] 煤炭-唐山-天津")

    def test_multi_goods_stable_order(self):
        self.execute("line(1,{stop(50,{1,2}),stop(60,{2,1})}); run(45)")
        self.assertEqual(self.name(), "[货运] 铁矿石、煤炭-矿山-钢厂")
        self.assertEqual(self.lua.eval("#world.sent"), 1)

    def test_zero_maximum_not_named(self):
        self.execute("line(1,{stop(50,{1,2},{[2]=0}),stop(60,{})}); run()")
        self.assertEqual(self.name(), "[货运] 煤炭-矿山-钢厂")

    def test_sparse_mod_cargo_id(self):
        self.execute("line(1,{stop(50,{8}),stop(60,{})}); run()")
        self.assertEqual(self.name(), "[货运] 自定义货物-矿山-钢厂")

    def test_passenger_id_is_not_assumed_zero(self):
        self.execute("world.passenger=8; line(1,{stop(10,{8}),stop(20,{8})}); run()")
        self.assertEqual(self.name(), "[客运] 北京-天津")

    def test_vehicle_capacity_filters_goods(self):
        self.execute("line(1,{stop(50,{1,2}),stop(60,{})}); vehicle(500,1,{[1]=20}); run()")
        self.assertEqual(self.name(), "[货运] 煤炭-矿山-钢厂")

    def test_passenger_vehicle_on_mixed_stations(self):
        self.execute("world.stationKinds[1010]='mixed'; world.stationKinds[1020]='mixed'; line(1,{stop(10,{}),stop(20,{})}); vehicle(500,1,{[0]=20}); run()")
        self.assertEqual(self.name(), "[客运] 北京-天津")

    def test_pending_cargo_then_filter(self):
        self.execute("line(1,{stop(50,{}),stop(60,{})}); run()")
        self.assertEqual(self.name(), "[货运] 待定-矿山-钢厂")
        self.execute("world.components[1].line.stops[1]=stop(50,{1}); run()")
        self.assertEqual(self.name(), "[货运] 煤炭-矿山-钢厂")

    def test_unknown_mixed_line_waits(self):
        self.execute("world.stationKinds[1050]='mixed'; world.stationKinds[1060]='mixed'; line(1,{stop(50,{}),stop(60,{})}); run()")
        self.assertEqual(self.name(), "线路 1")

    def test_endpoint_updates(self):
        self.execute("line(1,{stop(10,{0}),stop(20,{0})}); run(); table.insert(world.components[1].line.stops,stop(40,{0})); run()")
        self.assertEqual(self.name(), "[客运] 北京站-北京西")

    def test_goods_change(self):
        self.execute("line(1,{stop(50,{1}),stop(60,{})}); run(); world.components[1].line.stops[1]=stop(50,{2}); run()")
        self.assertEqual(self.name(), "[货运] 铁矿石-矿山-钢厂")

    def test_manual_name_survives_updates_and_reload(self):
        self.execute('line(1,{stop(10,{0}),stop(20,{0})}); run(); world.names[1]="我的快线"; run(); reload(); table.insert(world.components[1].line.stops,stop(40,{0})); run(45)')
        self.assertEqual(self.name(), "我的快线")
        self.assertFalse(self.lua.eval('state.value.lines["1"].managed'))

    def test_reload_before_pending_acknowledged(self):
        self.execute("line(1,{stop(10,{0}),stop(20,{0})}); run(); reload(); table.insert(world.components[1].line.stops,stop(40,{0})); run()")
        self.assertEqual(self.name(), "[客运] 北京站-北京西")

    def test_delayed_command_not_manual(self):
        self.execute("world.delayed=true; line(1,{stop(10,{0}),stop(20,{0})}); run(45)")
        self.assertEqual(self.lua.eval("#world.sent"), 1)
        self.assertTrue(self.lua.eval('state.value.lines["1"].managed'))
        self.execute("flush(); run(); world.delayed=false; table.insert(world.components[1].line.stops,stop(40,{0})); run()")
        self.assertEqual(self.name(), "[客运] 北京站-北京西")

    def test_rejected_command_retries(self):
        self.execute("world.fail=true; line(1,{stop(10,{0}),stop(20,{0})}); run(60); world.fail=false; run(30)")
        self.assertEqual(self.name(), "[客运] 北京-天津")

    def test_other_player_not_renamed(self):
        self.execute("line(1,{stop(10,{0}),stop(20,{0})},'AI',101); run(45)")
        self.assertEqual(self.name(), "AI")

    def test_manual_change_between_update_and_postupdate(self):
        self.execute('line(1,{stop(10,{0}),stop(20,{0})}); run(14); operations=script.update({},state,0); world.names[1]="自定义"; script.postUpdate({},state,0,operations); run()')
        self.assertEqual(self.name(), "自定义")
        self.assertEqual(self.lua.eval("#world.sent"), 0)

    def test_deleted_line_cleanup_and_new_line(self):
        self.execute("line(1,{stop(10,{0}),stop(20,{0})}); run(); world.names[1]=nil; world.components[1]=nil; world.lines={}; run(); line(2,{stop(50,{1}),stop(60,{})}); run()")
        self.assertIsNone(self.lua.eval('state.value.lines["1"]'))
        self.assertEqual(self.name(2), "[货运] 煤炭-矿山-钢厂")

    def test_station_removed_while_line_exists(self):
        self.execute("line(1,{stop(10,{0}),stop(20,{0})}); world.names[20]=nil; run()")
        self.assertEqual(self.name(), "线路 1")

    def test_update_dt_zero(self):
        self.execute("line(1,{stop(10,{0}),stop(20,{0})}); run(15,0)")
        self.assertEqual(self.name(), "[客运] 北京-天津")

    def test_metadata_and_resource_references(self):
        for relative in ("mod.json", "_metadata/modinfo.json"):
            payload = (MOD / relative).read_bytes()
            self.assertFalse(payload.startswith(b"\xef\xbb\xbf"))
            self.assertIsInstance(json.loads(payload), dict)
        definition = json.loads((MOD / "mod.json").read_text(encoding="utf-8"))
        self.assertEqual(definition["modId"], "xiaom_auto_line_names")
        self.lua.execute((MOD / "content/auto_line_names.gs.lua").read_text(encoding="utf-8"))
        descriptor = self.lua.eval("data()")
        for hook in ("updateScript", "postUpdateScript"):
            reference = descriptor[hook]["fileName"]
            resource, function = reference.split("@")
            namespace, path = resource.split("::/")
            self.assertEqual(namespace, definition["modId"])
            self.assertTrue((MOD / "content" / (path + ".lua")).is_file())
            self.assertIsNotNone(self.lua.eval(f"script.{function}"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
