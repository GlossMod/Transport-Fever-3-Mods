"""Upgrade and crash regression tests against the shipped Lua; Python 3.11."""
import json
import unittest
from test_auto_line_names import MOCK, MOD, SCRIPT, LuaRuntime


class UpgradeTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().content_root = (MOD / "content").as_posix()
        self.lua.execute(MOCK)
        self.lua.execute('world.legacyTicks=false; world.params={language=2};')
        self.lua.execute(SCRIPT.read_text(encoding="utf-8"))
        self.lua.execute('script=data(); run(1)')

    def execute(self, s):
        self.lua.execute(s)

    def value(self, s):
        return self.lua.eval(s)

    def name(self, id=1):
        return self.value(f'world.names[{id}]')

    def pulse(self, code='', review=True):
        self.execute(code + f'; event("tick",{{review={str(review).lower()}}}); '
                     'operations=script.update({},state,0); script.postUpdate({},state,0,operations)')

    def steps(self, count=1):
        self.execute(f'for i=1,{count} do local ops=script.update({{}},state,0); script.postUpdate({{}},state,0,ops) end')

    def preview(self, include=False, all=True):
        self.execute(f'event("preview",{{request="test",ids={{1}},all={str(all).lower()},include={str(include).lower()}}})')
        self.steps(2)

    def commit(self):
        self.execute('event("commit",{request="test"})')
        self.steps(3)

    def test_full_default_and_categories(self):
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})}); line(2,{stop(50,{1}),stop(60,{})})')
        self.assertEqual(self.name(), '[铁路客运] 北京-天津-001')
        self.assertEqual(self.name(2), '[铁路货运] 煤炭-矿山-钢厂-001')

    def test_all_transport_modes(self):
        for index, (mode, label, cargo) in enumerate([
            ('BUS','公交客运',False), ('TRUCK','卡车货运',True), ('TRAM','电车客运',False),
            ('ELECTRIC_TRAM','电车客运',False), ('TRAIN','铁路客运',False), ('ELECTRIC_TRAIN','铁路客运',False),
            ('SHIP','水运客运',False), ('SMALL_SHIP','水运客运',False), ('AIRCRAFT','航空客运',False),
            ('SMALL_AIRCRAFT','航空客运',False), ('HELICOPTER','直升机客运',False)], start=4000):
            with self.subTest(mode=mode):
                self.pulse(f'line({index},{{stop(10,{{{1 if cargo else 0}}}),stop(20,{{}})}}); world.modes[{index}]={{ {mode}=true }}')
                self.assertTrue(self.name(index).startswith('[' + label + '] '))

    def test_vehicle_modes_override_stop_modes(self):
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})}); vehicle(500,1,{[0]=10}); world.components[500].vehicle.config.transportModes={BUS=true}')
        self.assertEqual(self.name(), '[公交客运] 北京-天津-001')

    def test_ambiguous_modes_wait(self):
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})}); world.modes[1]={HELICOPTER=true,AIRCRAFT=true}')
        self.assertEqual(self.name(), '线路 1')

    def test_mixed_service(self):
        self.pulse('line(1,{stop(10,{0,1}),stop(20,{})}); vehicle(500,1,{[0]=10,[1]=20})')
        self.assertEqual(self.name(), '[铁路客货混运] 煤炭-北京-天津-001')

    def test_number_stable_on_endpoint_and_goods_change(self):
        self.pulse('line(1,{stop(50,{1}),stop(60,{})})')
        self.pulse('world.components[1].line.stops={stop(30,{2}),stop(60,{})}')
        self.assertEqual(self.name(), '[铁路货运] 铁矿石-唐山-钢厂-001')

    def test_category_change_allocates_new_number(self):
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})}); line(2,{stop(10,{0}),stop(20,{0})}); world.modes[2]={BUS=true}')
        self.pulse('world.modes[1]={BUS=true}')
        self.assertEqual(self.name(), '[公交客运] 北京-天津-002')

    def test_deleted_number_not_reused(self):
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})})')
        self.pulse('world.names[1]=nil; world.components[1]=nil; world.lines={}; line(2,{stop(10,{0}),stop(20,{0})})')
        self.assertEqual(self.name(2), '[铁路客运] 北京-天津-002')

    def test_early_manual_name_is_preserved(self):
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})},"我的快线")')
        self.assertEqual(self.name(), '我的快线')
        self.assertFalse(self.value('state.value.lines["1"].managed'))

    def test_native_default_name_pattern_is_exact(self):
        self.execute('collect=ug_require "xiaom_auto_line_names::/naming_collect.lua"')
        for name in ['线路 1','线路 999','新线路']:
            self.assertTrue(self.lua.globals().collect.defaultName(name))
        for name in ['线路 1 快线','线路 甲','线路 1a','我的线路 1']:
            self.assertFalse(self.lua.globals().collect.defaultName(name))

    def test_cst_protection_and_reload_command(self):
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})},"Cst Express")')
        self.assertEqual(self.name(), 'Cst Express')
        self.pulse('world.names[1]="reload"')
        self.assertEqual(self.name(), '[铁路客运] 北京-天津-001')

    def test_refresh_off_still_protects_manual_names(self):
        self.execute('world.params.refresh=2; reload()')
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})})', review=False)
        self.pulse('world.components[1].line.stops={stop(10,{0}),stop(40,{0})}', review=False)
        self.assertEqual(self.name(), '[铁路客运] 北京-天津-001')
        self.pulse('world.names[1]="Custom"', review=False)
        self.assertFalse(self.value('state.value.lines["1"].managed'))

    def test_english_and_other_language_fallback(self):
        for locale in ['en','fr','de']:
            with self.subTest(locale=locale):
                self.execute(f'world.locale="{locale}"; world.params.language=1; reload()')
                self.pulse(f'line(1,{{stop(10,{{0}}),stop(20,{{0}})}},"Line 1");')
                self.assertEqual(self.name(), '[Train Passenger] 北京-天津-001')
                self.pulse('world.names[1]=nil; world.lines={}; state.value.lines={}; state.value.numbers={}; reload()')

    def test_refresh_off_preserves_name_after_save_reload(self):
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})})')
        self.pulse()
        self.execute('world.params.refresh=2; world.components[1].line.stops={stop(10,{0}),stop(40,{0})}; reload()')
        self.pulse(review=False)
        self.assertEqual(self.name(), '[铁路客运] 北京-天津-001')

    def test_foreign_events_do_not_change_names_or_configuration(self):
        self.execute('script.handleEvent({},state,"another_mod","xiaom_auto_line_names","reloadConfig",{request="x"})')
        self.assertIsNone(self.value('state.value.status'))

    def test_migration_number_order_is_deterministic(self):
        self.execute('''line(2,{stop(10,{0}),stop(20,{0})},"Old 2"); line(1,{stop(10,{0}),stop(20,{0})},"Old 1");
            state.value={version=1,initialized=true,lines={["2"]={managed=true,lastName="Old 2"},["1"]={managed=true,lastName="Old 1"}}}; restart_runtime();''')
        self.pulse()
        self.assertTrue(self.name(1).endswith('-001'))
        self.assertTrue(self.name(2).endswith('-002'))

    def test_loading_options_handle_invalid_values(self):
        self.execute('config=ug_require "xiaom_auto_line_names::/naming_config.lua"; options=config.fromParams({format=100,refresh=999,language=-1})')
        self.assertEqual(self.value('options.format'),'full')
        self.assertEqual(self.value('options.language'),'auto')
        self.assertEqual(self.value('options.refresh'),60)

    def test_place_station_and_unicode_short(self):
        self.execute('world.params.place=3; reload()')
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})})')
        self.assertEqual(self.name(), '[铁路客运] 北京站-天津站-001')
        self.execute('world.params.place=2; world.names[100]="北京市中心"; reload()')
        self.pulse()
        self.assertEqual(self.name(), '[铁路客运] 北京市-天津-001')

    def test_industry_uses_catchment_and_nearest_then_id(self):
        self.execute('world.params.place=4; reload()')
        self.pulse('''line(1,{stop(50,{1}),stop(60,{})});
            local function transform(x) return {getTransl=function() return {x=x,y=0} end} end
            world.components[1050]={construction={transf=transform(0)}};
            for id,x in pairs({[700]=9,[701]=2,[702]=2,[703]=0}) do
                world.names[id]="产业" .. id; world.names[id+100]="厂";
                world.components[id]={industry={stockList=id+200,construction=id+100}};
                world.components[id+100]={construction={transf=transform(x)}};
            end
            world.catchables[1050]={900,901,902};''')
        self.assertEqual(self.name(), '[铁路货运] 煤炭-产业701-钢厂-001')

    def test_cargo_limit_and_mod_cargo_fallback(self):
        self.pulse('line(1,{stop(50,{1,2,3,8}),stop(60,{})})')
        self.assertEqual(self.name(), '[铁路货运] 铁矿石、煤炭、食品+1-矿山-钢厂-001')

    def test_cargo_overrides_and_number_width(self):
        self.execute('world.userConfig={numberWidth=4,cargoOverrides={["1"]={code="COAL"}}}; event("reloadConfig",{request="cfg"}); world.params.cargoStyle=3; reload()')
        self.pulse('line(1,{stop(50,{1,8}),stop(60,{})})')
        self.assertEqual(self.name(), '[铁路货运] COAL、自定义货物-矿山-钢厂-0001')

    def test_compact_format(self):
        self.execute('world.params.format=3; reload()')
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})})')
        self.assertEqual(self.name(), '[TP001] 北京-天津')

    def test_custom_template_and_persisted_configuration(self):
        self.execute('world.userConfig={passengerTemplate="{lineType}/{transportType}{serviceType}/{placeA}/{placeB}/{lineNumber}"}; event("reloadConfig",{request="cfg"}); world.params.format=4; reload(); world.userConfig={}; reload()')
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})})')
        self.assertEqual(self.name(), 'IC/铁路客运/北京/天津/001')

    def test_invalid_configuration_preserves_previous(self):
        before=self.value('ug_require("xiaom_auto_line_names::/naming_util.lua").signature(state.value.config)')
        for raw in ['{passengerTemplate="{bogus}"}','{numberWidth=0}','{cargoLimit=1.5}','{labels={fr={train="Rail"}}}']:
            with self.subTest(raw=raw):
                self.execute(f'world.userConfig={raw}; event("reloadConfig",{{request="cfg"}})')
                self.assertEqual(self.value('state.value.status.key'), 'error')
                self.assertEqual(self.value('ug_require("xiaom_auto_line_names::/naming_util.lua").signature(state.value.config)'), before)

    def test_region_classification(self):
        self.execute('world.params.region=2; reload()')
        self.pulse('line(1,{stop(10,{0}),stop(20,{0}),stop(30,{0})})')
        self.assertTrue(self.name().startswith('[RE 铁路客运]'))
        self.pulse('world.components[1].line.stops={stop(10,{0}),stop(40,{0})}')
        self.assertTrue(self.name().startswith('[LO 铁路客运]'))

    def test_preview_is_read_only_and_cancel_does_not_allocate(self):
        self.execute('line(1,{stop(10,{0}),stop(20,{0})},"Old")')
        self.preview(include=True)
        self.assertEqual(self.name(), 'Old')
        self.assertIsNone(self.value('state.value.numbers["train:passengers"]'))
        self.execute('event("cancel")')
        self.assertIsNone(self.value('state.value.preview'))
        self.assertIsNone(self.value('state.value.numbers["train:passengers"]'))

    def test_bulk_protection_then_explicit_takeover(self):
        self.execute('line(1,{stop(10,{0}),stop(20,{0})},"Old")')
        self.preview()
        self.assertEqual(self.value('state.value.preview.rows[1].reason'), 'protected')
        self.preview(include=True)
        self.commit()
        self.assertEqual(self.name(), '[铁路客运] 北京-天津-001')
        self.pulse('world.components[1].line.stops={stop(10,{0}),stop(40,{0})}')
        self.assertEqual(self.name(), '[铁路客运] 北京站-北京西-001')

    def test_bulk_stale_manual_edit_rejected(self):
        self.execute('line(1,{stop(10,{0}),stop(20,{0})},"Old")')
        self.preview(include=True)
        self.execute('world.names[1]="New custom"')
        self.commit()
        self.assertEqual(self.name(), 'New custom')
        self.assertEqual(self.value('state.value.status.key'), 'changed')
        self.assertIsNone(self.value('state.value.numbers["train:passengers"]'))

    def test_bulk_stale_counter_rejected(self):
        self.execute('line(1,{stop(10,{0}),stop(20,{0})},"Old")')
        self.preview(include=True,all=False)
        self.pulse('line(2,{stop(10,{0}),stop(20,{0})})')
        self.commit()
        self.assertEqual(self.name(), 'Old')
        self.assertEqual(self.value('state.value.status.key'), 'changed')

    def test_postupdate_manual_edit_is_rechecked(self):
        self.execute('line(1,{stop(10,{0}),stop(20,{0})}); event("tick",{review=true}); ops=script.update({},state,0); world.names[1]="Manual"; script.postUpdate({},state,0,ops)')
        self.assertEqual(self.name(), 'Manual')
        self.assertEqual(self.value('#world.sent'),0)

    def test_old_save_migration_and_pending_command(self):
        self.execute('''line(1,{stop(10,{0}),stop(20,{0})},"[客运] 北京-天津"); line(2,{stop(10,{0}),stop(20,{0})},"Manual");
            state.value={version=1,initialized=true,lines={["1"]={managed=true,lastName="线路 1",pendingName="[客运] 北京-天津"},["2"]={managed=false}}}; restart_runtime();''')
        self.pulse()
        self.assertEqual(self.value('state.value.version'),2)
        self.assertEqual(self.name(), '[铁路客运] 北京-天津-001')
        self.assertEqual(self.name(2),'Manual')

    def test_idle_does_not_copy_entire_state(self):
        before=self.value('world.reads')
        self.steps(120)
        self.assertEqual(self.value('world.reads'),before)

    def test_5000_lines_have_bounded_work_and_complete(self):
        self.execute('''
            for id=10000,14999 do line(id,{stop(10,{0}),stop(20,{0})}) end
            event("tick",{review=true})
            maxBatch=0
            for i=1,85 do local ops=script.update({},state,0); script.postUpdate({},state,0,ops); maxBatch=math.max(maxBatch,state.value.stats.processed) end
        ''')
        self.assertLessEqual(self.value('maxBatch'),64)
        self.assertEqual(self.value('#world.sent'),5000)
        self.assertEqual(self.name(14999),'[铁路客运] 北京-天津-5000')
        self.assertEqual(self.value('world.reads'),1)
        self.assertEqual(self.value('world.nativeCalls'),0)

    def test_tick_does_not_write_state_or_call_native_storage(self):
        before=self.value('world.writes')
        self.execute('for i=1,100 do event("tick",{review=false}) end')
        self.assertEqual(self.value('world.writes'),before)
        self.assertEqual(self.value('world.nativeCalls'),0)

    def test_plain_storage_survives_commands_events_and_reload(self):
        self.pulse('line(1,{stop(10,{0}),stop(20,{0})})')
        self.pulse()  # Acknowledge the command before reopening the save.
        self.execute('reload()')
        self.steps()
        self.assertEqual(self.value('state.value.lines["1"].number'),1)
        self.execute('world.userConfig={numberWidth=4};event("reloadConfig",{request="cfg"})')
        self.preview()
        self.commit()
        self.assertEqual(self.name(), '[铁路客运] 北京-天津-0001')
        self.execute('reload()')
        self.steps()
        self.assertEqual(self.value('state.value.config.numberWidth'),4)
        self.assertEqual(self.value('world.nativeCalls'),0)

    def test_pending_intent_is_saved_before_delayed_dispatch(self):
        self.execute('''line(1,{stop(10,{0}),stop(20,{0})});world.delayed=true
            local send=api.cmd.sendCommand
            api.cmd.sendCommand=function(cmd)
                if not cmd.event then
                    assert(state.value.lines[tostring(cmd.entity)].pendingName==cmd.name)
                    assert(state.value.numbers["train:passengers"]==1)
                end
                return send(cmd)
            end''')
        self.pulse()
        self.assertEqual(self.name(),'线路 1')
        self.execute('reload();flush()')
        self.pulse()
        self.assertEqual(self.name(),'[铁路客运] 北京-天津-001')
        self.assertIsNone(self.value('state.value.lines["1"].pendingName'))
        self.assertEqual(self.value('world.nativeCalls'),0)

    def test_resources_json_and_lua_syntax(self):
        for file in MOD.rglob('*.json'):
            self.assertFalse(file.read_bytes().startswith(b'\xef\xbb\xbf'))
            json.loads(file.read_text(encoding='utf-8'))
        for file in (MOD/'content').glob('*.lua'):
            self.lua.execute('assert(loadfile(...))', file.as_posix())
        definition=json.loads((MOD/'mod.json').read_text(encoding='utf-8'))
        self.assertEqual(definition['revision'],4)
        self.assertTrue(definition['cosmetic'])
        self.assertEqual((MOD/'_metadata/mod.io_fileid.txt').read_text().strip(),'6426466')


if __name__ == '__main__':
    unittest.main(verbosity=2)
