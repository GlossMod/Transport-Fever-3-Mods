"""Lua 5.4 behavior checks; these do not simulate TF3's native collision engine."""
import json
import sys
import unittest
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "staging_area/xiaom_no_collision"
GAME = Path(r"E:\steam\steamapps\common\Transport Fever 3")
sys.path.insert(0, str(ROOT / ".agents/tools/line_naming_test_runtime"))
from lupa.lua54 import LuaRuntime


class AnarchyPreviewTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().anarchy=self.lua.execute((MOD/'content/anarchy_util.lua').read_text('utf-8'))
        self.lua.execute('''
            logs={};debugPrint=function(s) logs[#logs+1]=s end
            _=function(key) return ({Collision="碰撞",["Too Much Curvature"]="曲率过大"})[key] or key end
            mockBuild={begin=function() end,capture=function() end,clear=function() end}
            function readonly(value)
                if type(value)~="table" then return value end
                return setmetatable({}, {
                    __index=function(_,key) return readonly(value[key]) end,
                    __len=function() return #value end,
                    __newindex=function(_,key) error("cannot write to read only member '"..key.."'") end,
                })
            end
            ug_require=function(name)
                if name:find('anarchy_util',1,true) then return anarchy end
                if name:find('anarchy_build',1,true) then return mockBuild end
                if name:find('construction_react_util',1,true) then return menu end
                error(name)
            end
        ''')
        self.lua.execute((MOD/'content/mod.script.lua').read_text('utf-8'))
        self.lua.execute('mod=data()')

    def check(self,code):
        self.lua.execute(code)

    def test_package_has_no_native_resource_writes(self):
        desc=json.loads((MOD/'mod.json').read_text('utf-8'))
        self.assertEqual(desc['modId'],'xiaom_no_collision')
        self.assertEqual(desc['revision'],3)
        self.assertNotIn('preRunScript',desc)
        self.assertNotIn('postRunScript',desc)
        info=json.loads((MOD/'_metadata/modinfo.json').read_text('utf-8'))
        self.assertEqual(info['name'],'Anarchy')
        self.assertEqual(info['localization']['zh_CN']['name'],'无碰撞')
        self.assertLessEqual(len(info['summary']),100)
        index=json.loads((MOD/'_content.json').read_text('utf-8'))
        self.assertEqual(index['files'],sorted(p.name for p in (MOD/'content').iterdir()))
        for p in MOD.rglob('*'):
            if p.is_file() and p.suffix in {'.lua','.json','.md'}:
                raw=p.read_bytes();self.assertFalse(raw.startswith(b'\xef\xbb\xbf'));raw.decode('utf-8')
        code=''.join(p.read_text('utf-8') for p in (MOD/'content').glob('*.lua'))
        self.assertNotIn('setAsTable',code)
        self.assertNotIn('constructionScript',code)

    def test_filters_exact_localized_errors_and_preserves_other_errors(self):
        self.check('''
            local warnings, infos = {"warning"}, {"info"}
            local d = {errorState={critical=false,
                messages={"碰撞","曲率过大","Collision","Too Much Curvature","Slope too high","Collision on unknown object"},
                warnings=warnings,infos=infos},costs=100}
            local filtered,errors=anarchy.filterPreviewErrors(d)
            assert(filtered and #errors.messages == 2 and errors.messages[1] == "Slope too high")
            assert(errors.messages[2] == "Collision on unknown object")
            assert(errors.warnings[1] == warnings[1] and errors.infos[1] == infos[1])
            assert(#d.errorState.messages == 6 and d.errorState.messages[1] == "碰撞" and d.costs == 100)
            errors.warnings[1]="private change";errors.infos[1]="private change"
            assert(warnings[1]=="warning" and infos[1]=="info")
            assert(anarchy.filterPreviewErrors(d))
        ''')


    def test_critical_errors_and_read_only_native_record_accessors(self):
        self.check('''
            local critical = {errorState={critical=true,messages={"Collision"}}}
            assert(not anarchy.filterPreviewErrors(critical) and #critical.errorState.messages == 1)
            local stored = {critical=false,messages={"碰撞"},warnings={"preserved"},infos={}}
            local native = readonly({errorState=stored,costs=123})
            local filtered,errors=anarchy.filterPreviewErrors(native)
            assert(filtered and #errors.messages==0 and errors.warnings[1]=="preserved")
            assert(#stored.messages == 1 and stored.messages[1]=="碰撞" and stored.warnings[1] == "preserved")
            assert(native.errorState.messages[1]=="碰撞" and native.costs==123)
            local blocked,criticalErrors=anarchy.filterPreviewErrors(readonly(critical))
            assert(not blocked and criticalErrors.critical and criticalErrors.messages[1]=="Collision")
        ''')


    def test_menu_hook_preserves_callbacks_and_does_not_wrap_track_tools(self):
        self.check('''
            local calls, previousCalls = 0, 0
            menu = {getActionParams=function(kind, extra)
                calls=calls+1; assert(extra == 77)
                local action = {[kind]={},getProposalStringsFn=function(proposal,data)
                    previousCalls=previousCalls+1; assert(proposal.id == 5)
                    return {"Reputation: -1%"}
                end}
                return {constructionActionParams=action,layerConfig={id=10}}
            end}
            mod.installAnarchyUI({})
            local installed=menu.getActionParams
            mod.installAnarchyUI({}); assert(menu.getActionParams == installed)
            mockBuild.capture=function(_,proposal,d,filtered,errors)
                assert(proposal.id==5 and filtered and #errors.messages==0 and d.errorState.messages[1]=="Collision")
            end
            for _,kind in ipairs({"streetEdgeBuilder","streetEdgeNodeModifier","constructionBuilder","moduleBuilder"}) do
                local r=menu.getActionParams(kind,77)
                local d={errorState={critical=false,messages={"Collision"}}}
                local strings=r.constructionActionParams.getProposalStringsFn({id=5},d)
                assert(#d.errorState.messages == 1 and strings[1] == "Reputation: -1%")
                assert(r.layerConfig.id == 10)
            end
            local track=menu.getActionParams("trackEdgeBuilder",77)
            local d={errorState={critical=false,messages={"Collision"}}}
            track.constructionActionParams.getProposalStringsFn({id=5},d)
            assert(#d.errorState.messages == 1 and calls == 5 and previousCalls == 5)
        ''')


    def test_menu_hook_keeps_an_existing_callback_submission_block(self):
        self.check('''
            menu={getActionParams=function()
                return {constructionActionParams={constructionBuilder={},getProposalStringsFn=function(_,d)
                    d.errorState={critical=true,messages={"Collision"}}; return {"custom tool"}
                end}}
            end}
            mod.installAnarchyUI({})
            local action=menu.getActionParams().constructionActionParams
            local d={errorState={critical=false,messages={}}}
            assert(action.getProposalStringsFn({},d)[1] == "custom tool")
            assert(d.errorState.critical and #d.errorState.messages == 1)
        ''')


    def test_recreated_definitions_keep_identity_but_different_buildings_do_not(self):
        self.check('''
            local keys={}
            mockBuild.begin=function(key) keys[#keys+1]=key end
            menu={getActionParams=function() return {} end}
            mod.installAnarchyUI({})
            for index=1,2 do
                menu.getActionParams({action="ACTION_CONSTRUCTION_BUILDER",
                    constructions={"::/warehouse.con"},constructionTemplate=1},nil,nil,nil,nil,77)
            end
            assert(keys[1]==keys[2])
            menu.getActionParams({action="ACTION_CONSTRUCTION_BUILDER",
                constructions={"::/station.con"},constructionTemplate=1},nil,nil,nil,nil,77)
            assert(keys[2]~=keys[3])
            menu.getActionParams({action="ACTION_CONSTRUCTION_BUILDER",
                constructions={"::/station.con"},constructionTemplate=2},nil,nil,nil,nil,77)
            assert(keys[3]~=keys[4])
            menu.getActionParams({action="ACTION_CONSTRUCTION_BUILDER",
                constructions={"::/station.con"},constructionTemplate=2},nil,nil,nil,nil,88)
            assert(keys[4]~=keys[5])
        ''')


    def test_extension_failure_preserves_normal_building_callback_and_invalidates_stale_preview(self):
        self.check('''
            local nativeCalls,cleared=0,0
            local strings={"original construction information"}
            menu={getActionParams=function()
                return {constructionActionParams={constructionBuilder={},getProposalStringsFn=function(_,d)
                    nativeCalls=nativeCalls+1
                    assert(#d.errorState.messages==0 and d.costs==205)
                    return strings
                end}}
            end}
            mockBuild.capture=function() error("force preview unavailable") end
            mockBuild.clear=function() cleared=cleared+1 end
            mod.installAnarchyUI({});local before=#logs
            local action=menu.getActionParams().constructionActionParams
            local d=readonly({errorState={critical=false,messages={}},costs=205})
            for _=1,3 do assert(action.getProposalStringsFn({},d)==strings) end
            assert(nativeCalls==3 and cleared==3 and #logs==before+1)
            assert(logs[#logs]:find("native callback preserved",1,true))
            assert(#d.errorState.messages==0 and d.costs==205)
        ''')

    def test_valid_read_only_building_preview_keeps_native_callback_and_does_not_force_build(self):
        self.check('''
            local captured=0
            menu={getActionParams=function()
                return {constructionActionParams={constructionBuilder={},getProposalStringsFn=function(_,d)
                    assert(#d.errorState.messages==0);return {"native valid preview"}
                end}}
            end}
            mockBuild.capture=function(_,proposal,d,filtered,errors)
                captured=captured+1;assert(not filtered and #errors.messages==0 and not errors.critical)
                assert(d.costs==123)
            end
            mod.installAnarchyUI({})
            local d=readonly({errorState={critical=false,messages={},warnings={"native warning"}},costs=123})
            local result=menu.getActionParams().constructionActionParams.getProposalStringsFn({},d)
            assert(result[1]=="native valid preview" and captured==1 and #d.errorState.messages==0)
            assert(d.errorState.warnings[1]=="native warning")
        ''')


class AnarchyBuildTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            _=function(key) return key end
            logs={};debugPrint=function(s) logs[#logs+1]=s end
            events={};commands={};removed=0
            react={RegisterWrapperRecipe=function(name,wrapped,fn)
                registered={name=name,wrapped=wrapped,fn=fn};return fn
            end,fireEvent=function(_,name) events[#events+1]=name end,
                useState=function(v) return {old=function() return v end,set=function(_,n) v=n end} end,
                onStep=function(fn) onStep=fn end,onEvent=function(name,fn) end}
            builtin={Window=function(p) return p end,BoxLayout=function(p) return p end,
                TextView=function(p) return p end,Button=function(p) return p end,
                type={Orientation={Vertical=1}}}
            windowApi={addSingletonWindow=function(recipe,session) currentSession=session end,
                removeAllWindows=function(recipe) removed=removed+1 end}
            globals={getDefaultWindowContainer=function()
                return {hasExpired=function() return false end,
                    get=function() return {getApi=function() return windowApi end} end}
            end}
            api={type={Context={new=function() return {} end}},engine={util={getPlayer=function() return 42 end}},
                gui={byId={setVisible=function(id,visible) assert(visible) end},
                    mouse={hasTerrainPosition=function() return true end},
                    construction={getRefundableEntities=function() return {{7,8}} end}},
                cmd={makeWorldBuildProposalCmd=function(proposal,context,ignore,player,dust)
                    return {proposal=proposal,context=context,ignore=ignore,player=player,dust=dust}
                end,sendCommand=function(command,callback) commands[#commands+1]=command; completion=callback end}}
            ug_require=function(path)
                if path:find('react.lua',1,true) then return react end
                if path:find('builtin.lua',1,true) then return builtin end
                if path:find('game_react_globals',1,true) then return globals end
                error(path)
            end
            owned={tag="owned clone",toAdd={{fileName="warehouse"}},proposal={addedSegments={}}}
            borrowed={clone=function() return owned end}
            preview={errorState={critical=false,messages={}},costs=123}
        ''')
        self.lua.globals().build = self.lua.execute((MOD / "content/anarchy_build.lua").read_text("utf-8"))

    def test_force_build_uses_owned_errors_with_unchanged_read_only_native_collision_preview(self):
        self.lua.globals().anarchy=self.lua.execute((MOD / "content/anarchy_util.lua").read_text("utf-8"))
        self.lua.execute('''
            function readonly(value)
                if type(value)~="table" then return value end
                return setmetatable({}, {
                    __index=function(_,key) return readonly(value[key]) end,
                    __len=function() return #value end,
                    __newindex=function(_,key) error("cannot write to read only member '"..key.."'") end,
                })
            end
            local native=readonly({errorState={critical=false,messages={"Collision"},warnings={},infos={}},costs=123})
            local filtered,errors=anarchy.filterPreviewErrors(native)
            assert(filtered and #errors.messages==0 and native.errorState.messages[1]=="Collision")
            build.begin("warehouse");build.capture("warehouse",borrowed,native,filtered,errors)
            assert(currentSession.proposal==owned and currentSession.costs==123)
            assert(build.apply(currentSession) and #commands==1 and commands[1].ignore)
            assert(native.errorState.messages[1]=="Collision" and native.costs==123)
        ''')

    def test_submits_owned_clone_with_ignore_errors_and_normal_cost_payer(self):
        self.lua.execute('''
            build.begin("road");build.capture("road",borrowed,preview,true)
            assert(currentSession.proposal == owned and currentSession.proposal ~= borrowed)
            borrowed.clone=function() error("expired borrowed proposal") end
            preview=setmetatable({}, {__index=function() error("expired preview data") end})
            assert(build.apply(currentSession))
            assert(#commands==1 and commands[1].proposal==owned)
            assert(commands[1].ignore and commands[1].player and commands[1].dust)
            assert(commands[1].context.player==42 and commands[1].context.refundableEntities[1][1]==7)
            assert(not build.apply(currentSession) and #commands==1)
            completion({resultEntities={55}},true)
            assert(not currentSession.active and not currentSession.proposal)
            assert(events[1]=="onProposalApply" and events[2]=="constructionMenuQuit")
        ''')

    def test_rejects_critical_unrelated_and_unfiltered_previews(self):
        self.lua.execute('''
            build.begin("road")
            for _,candidate in ipairs({
                {errorState={critical=true,messages={}}},
                {errorState={critical=false,messages={"Slope too high"}}},
            }) do
                build.capture("road",borrowed,candidate,true)
                assert(not currentSession and #commands==0)
            end
            build.capture("road",borrowed,preview,false)
            assert(not currentSession)
            build.capture("old road",borrowed,preview,true)
            assert(not currentSession)
        ''')

    def test_changing_tools_invalidates_the_force_build_button(self):
        self.lua.execute('''
            build.begin("warehouse");build.capture("warehouse",borrowed,preview,true)
            local old=currentSession
            build.begin("road")
            assert(not old.active and not old.proposal and not build.apply(old))
            assert(#commands==0)
        ''')

    def test_pointer_can_reach_button_without_preserving_a_new_valid_map_preview(self):
        self.lua.execute('''
            build.begin("road");build.capture("road",borrowed,preview,true)
            local session=currentSession
            api.gui.mouse.hasTerrainPosition=function() return false end
            build.capture("road",{},preview,false)
            assert(session.active and session.proposal==owned)
            api.gui.mouse.hasTerrainPosition=function() return true end
            build.capture("road",{},preview,false)
            assert(not session.active and not session.proposal and not build.apply(session))
            build.capture("road",borrowed,preview,true)
            local rejected=currentSession
            api.gui.mouse.hasTerrainPosition=function() return false end
            build.capture("road",{}, {errorState={critical=true,messages={}}},false)
            assert(not rejected.active and #commands==0)
        ''')

    def test_initial_menu_render_does_not_mutate_window_container(self):
        self.lua.execute('''
            for index=1,50 do
                build.begin("fresh native definition " .. index)
                build.clear()
            end
            assert(removed==0 and not currentSession and #commands==0)
        ''')

    def test_rejected_native_command_is_reported_and_not_claimed_successful(self):
        self.lua.execute('''
            build.begin("road");build.capture("road",borrowed,preview,true)
            assert(build.apply(currentSession))
            completion({resultProposalData={errorState={messages={"native geometry rejected"}}}},false)
            assert(not currentSession.pending and not currentSession.proposal)
            assert(currentSession.message=="xiaom_anarchy_failed" and #events==0)
            assert(logs[#logs]:find("native geometry rejected",1,true))
        ''')

    def test_force_build_window_uses_matching_native_wrapper_and_button(self):
        self.lua.execute('''
            assert(registered.wrapped==builtin.Window)
            build.begin("road");build.capture("road",borrowed,preview,true)
            local window=registered.fn(currentSession)
            assert(window.title=="Anarchy")
            local button=window.content.children[3]
            assert(button.meta.enabled and button.content.text=="xiaom_anarchy_build")
            button.onClick()
            assert(#commands==1 and currentSession.pending)
            assert(not registered.fn(currentSession).content.children[3].meta.enabled)
        ''')

    def test_window_registration_with_shipped_tf3_react_code(self):
        self.lua.execute('''
            _react={builtin={WithComponentParams=1},recipes={},recipeMetas={},
                originalRecipeFn={},recipeReplace={},recipeReplacementAllowed=true}
            nativeNodes={};nativeIds={};local nextId=100
            log={verbose=function() end,warning=function() end,error=error}
            require=function() return {format=function(s) return s end} end
            ug_require=function() return {} end
            api.gui.react={params={builtin={WithComponentParams={new=function() return {} end}}},
                detail={makeRecipeId=function(name) nextId=nextId+1;nativeIds[name]=nextId;return nextId end}}
        ''')
        with ZipFile(GAME / "base/content/gui.zip") as archive:
            self.lua.globals().react = self.lua.execute(archive.read("gui/main/react.lua").decode("utf-8"))
        self.lua.execute('''
            builtin={type={Orientation={Vertical=1}}}
            for id,name in ipairs({"Window","TextView","BoxLayout","Button"}) do
                _react.builtin[name]=id+1
                builtin[name]=react.DeclareBuiltin(name,function() end)
            end
            ug_require=function(path)
                if path:find('react.lua',1,true) then return react end
                if path:find('builtin.lua',1,true) then return builtin end
                if path:find('game_react_globals',1,true) then return globals end
                error(path)
            end
        ''')
        self.lua.globals().build = self.lua.execute((MOD / "content/anarchy_build.lua").read_text("utf-8"))
        self.lua.execute('''
            build.begin("road");build.capture("road",borrowed,preview,true)
            local id=nativeIds.XiaomAnarchyBuildWindow
            assert(_react.recipeMetas[id].innerRecipeId==_react.builtin.Window)
            local ctx={}
            function ctx:declareState(v) return {old=function() return v end,set=function(_,n) v=n end} end
            function ctx:onStep(fn) end
            function ctx:onEvent(fn,name) end
            function ctx:makeNodeWithProps(id,key,props)
                nativeNodes[#nativeNodes+1]={id=id,props=props};return #nativeNodes
            end
            function ctx:checkRecipeMatch(node,expected)
                assert(nativeNodes[node].id==expected,"wrong native wrapper root");return true
            end
            function ctx:setResult(value) self.result=value end
            _react.recipes[id](ctx,{props=table.pack(currentSession)})
            assert(#ctx.result==1)
            local root=nativeNodes[ctx.result[1]]
            assert(root.id==_react.builtin.Window)
            local window=root.props.props[1]
            assert(window.title=="Anarchy")
            local layout=nativeNodes[window.content].props.props[1]
            local component=nativeNodes[layout.children[3]].props.props[1]
            assert(component.enabled)
            local button=nativeNodes[component.item].props.props[1]
            button.onClick();assert(#commands==1 and commands[1].ignore)
        ''')


if __name__ == "__main__":
    unittest.main(verbosity=2)
