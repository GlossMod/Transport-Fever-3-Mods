"""UI interactions plus TF3's real React registration/dispatch in Lua."""
import unittest
from zipfile import ZipFile
from test_vehicle_upgrade import MOD, runtime

GUI = r"E:\steam\steamapps\common\Transport Fever 3\base\content\gui.zip"

UI_FIXTURE = r'''
recipes, timers, windows, joins = {}, {}, {}, {}
function drainJoins()
    while #joins>0 do
        local pending=joins;joins={}
        for _,fn in ipairs(pending) do fn() end
    end
end
function state(value)
    return {value=value,old=function(self) return self.value end,set=function(self,v) self.value=v end,
        get=function(self) return self.value end,hasExpired=function() return false end}
end
reactMock={RegisterRecipe=function(name,fn) recipes[name]=fn;return fn end,
    RegisterWrapperRecipe=function(name,base,fn) recipes[name]=fn;return fn end,
    CallOriginalRecipe=function(fn,param) return fn(param) end,
    useState=function(v) return state(v) end,onStepTimer=function(fn) timers[#timers+1]=fn end,
    enqueueJoin=function(fn) joins[#joins+1]=fn end}
builtinMock={type={Orientation={Horizontal=1,Vertical=2},ScrollBarPolicy={AlwaysOff=0,Simple=1}}}
for _,name in ipairs({'Button','TextView','BoxLayout','Component','CheckBox','ImageView',
    'ComboBox','ComboBoxItem','Window','TextInputField','ScrollArea','TableLayout','Row'}) do
    builtinMock[name]=function(param) return {kind=name,params=param} end
end
windowApi={addSingletonWindow=function(recipe,param) windows[recipe]=recipe(param) end,
    moveSingletonWindowToFront=function() end,removeAllWindows=function(recipe) windows[recipe]=nil end}
globalsMock={getDefaultWindowApi=function() return windowApi end}
statsMock={StatisticsEntryPoint=function(param) return {kind="OriginalEntry",params=param} end}
originalVehicleMock=function(param) return {kind="OriginalVehicles",params=param} end
externals['::/gui/main/react.lua']=reactMock
externals['::/gui/main/builtin.lua']=builtinMock
externals['::/gui/main/game_react_globals.tl']=globalsMock
externals['::/gui/statistics/statistics.tl']=statsMock
externals['::/gui/statistics/statistic_vehicles.tl']=originalVehicleMock
api.gui.byId={setVisible=function(id,value) visibleId=id;visibleValue=value end}
function find(node,id)
    if type(node)~="table" then return nil end
    if node.params and (node.params.id==id or (node.params.meta or {}).id==id) then return node.params end
    for _,v in pairs(node) do if type(v)=="table" then local result=find(v,id);if result then return result end end end
end
function renderWindow() return recipes.XiaomVehicleUpgradeWindow() end
'''


class UiTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime()
        self.lua.execute(UI_FIXTURE)
        self.lua.execute('''ui=ug_require("xiaom_vehicle_upgrade::/upgrade_ui.lua")
            entry=ug_require("xiaom_vehicle_upgrade::/upgrade_entry.lua")''')

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_enabled_confirm_reports_configuration_deferral_prominently_and_can_confirm_again(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950})
            vehicle(10,{part(1,1)},{refund=500});scan()
            local confirm=find(renderWindow(),"xiaom-upgrade-confirm");assert(confirm.meta.enabled)
            entities[10].tv.transportVehicleConfig.vehicles[1].purchaseTime=501;confirm.onClick()
            assert(controller.read().phase=="checking" and not find(renderWindow(),"xiaom-upgrade-confirm").meta.enabled)
            for _=1,10 do controller.step() end
            assert(controller.read().phase=="idle" and #commands==0)
            local function warning(node)
                if type(node)~="table" then return false end
                local p=node.params
                if p and (p.meta or {}).class=="upgrade-footer-blocked" and p.text and
                    p.text:find("购买时间",1,true) and p.text:find("核对",1,true) then return true end
                for _,value in pairs(node) do if warning(value) then return true end end
                return false
            end
            local window=renderWindow();assert(warning(window))
            confirm=find(window,"xiaom-upgrade-confirm");assert(confirm.meta.enabled);confirm.onClick()
            controller.step();assert(controller.read().phase=="applying")
            controller.step();assert(#commands==1)''')

    def test_confirm_accepts_rising_quote_without_a_second_click_and_shows_current_cost(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950})
            vehicle(10,{part(1,1)},{refund=500});scan()
            local confirm=find(renderWindow(),"xiaom-upgrade-confirm");assert(confirm.meta.enabled)
            entities[10].refund=400;confirm.onClick();controller.step()
            assert(controller.read().phase=="applying" and row().quote.net==600 and not controller.read().reviewMessage)
            assert(not find(renderWindow(),"xiaom-upgrade-confirm").meta.enabled)
            entities[10].refund=300;controller.step()
            assert(#commands==1 and row().quote.net==700 and not controller.read().reviewMessage)
            local function contains(node,fragment)
                if type(node)~="table" then return false end
                local p=node.params
                if p and p.text and p.text:find(fragment,1,true) then return true end
                for _,value in pairs(node) do if contains(value,fragment) then return true end end
                return false
            end
            local window=renderWindow()
            assert(contains(window,"$700") and contains(window,"支出上涨也继续"))
            finishCommand(true);controller.step();assert(controller.read().results.success==1)''')

    def test_entry_keeps_original_tab_and_opens_full_company_preview(self):
        self.run_lua('''local replacements={};entry.install({ReplaceRecipe=function(old,new) replacements[old]=new end})
            local param={gameCtx=gameCtx};local original=replacements[statsMock.StatisticsEntryPoint](param)
            assert(original.kind=="OriginalEntry" and original.params==param)
            local tab=replacements[originalVehicleMock]({searchString="unrelated search"})
            local list=tab.params.children[2].params.layout
            assert(list.kind=="BoxLayout" and list.params.children[1].kind=="OriginalVehicles")
            assert(list.params.children[1].params.searchString=="unrelated search")
            find(tab,"xiaom-vehicle-upgrade-button").onClick()
            assert(controller.read().phase=="catalog" and visibleValue and #commands==0)''')

    def test_button_registration_is_idempotent(self):
        self.run_lua('''local count=0;local api={ReplaceRecipe=function() count=count+1 end}
            entry.install(api);entry.install(api);assert(count==2)''')

    def test_checkbox_and_target_update_actual_controller(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan()
            controller.toggleGroup(row().snapshot.units[1].groupKey);controller.toggleRow(row())
            local window=renderWindow();find(window,"upgrade-select-10").onValueChange(0);assert(not row().selected)
            find(window,"upgrade-target-10-1").onValueChange("model:2");assert(row().selected)
            find(window,"upgrade-target-10-1").onValueChange("keep");assert(not row().selected and not row().changes[1])''')

    def test_confirm_disabled_when_cash_or_current_load_insufficient(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950,price=100000});vehicle(10,{part(1,1)});scan();balance=1
            assert(find(renderWindow(),"xiaom-upgrade-confirm").meta.enabled==false)
            balance=1000000;assert(find(renderWindow(),"xiaom-upgrade-confirm").meta.enabled==true)''')

    def test_scan_timer_and_window_close_dont_send_commands(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)})
            ui.open(gameCtx);for _=1,30 do for _,timer in ipairs(timers) do timer() end;drainJoins() end
            assert(controller.read().phase=="idle" and #commands==0)
            local window=find(renderWindow(),"xiaom-vehicle-upgrade-window");window.onClose()
            assert(not controller.read() and next(windows)==nil);ui.open(gameCtx);assert(controller.read())''')

    def test_timer_purchase_checks_join_main_thread_before_native_gui_events(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)})
            local onMain=false
            api.gui.fireGuiScriptEvent=function(_,name,param)
                assert(onMain,"GUI event called outside main thread")
                events[#events+1]=clone(param)
            end
            ui.open(gameCtx)
            for _=1,30 do
                onMain=false;local before=#events
                for _,timer in ipairs(timers) do timer() end
                assert(#events==before)
                onMain=true;drainJoins()
            end
            assert(not row().error and row().config and controller.totals().blocked==0 and #commands==0)
            assert(find(renderWindow(),"xiaom-upgrade-confirm").meta.enabled)
            assert(#events>0)''')

    def test_cash_format_and_electric_warning_visible(self):
        self.run_lua('''model(1,{},0,{carrier="RAIL"});model(2,{},0,{carrier="RAIL",year=1950,electric=true,price=1234567})
            vehicle(10,{part(1,-1)});scan()
            function contains(node,pattern)
                if type(node)~="table" then return false end
                if node.params and node.params.text and node.params.text:find(pattern,1,true) then return true end
                for _,v in pairs(node) do if type(v)=="table" and contains(v,pattern) then return true end end
                return false
            end
            local window=renderWindow();assert(contains(window,"接触网") and contains(window,"1,234,567"))''')

    def test_failed_fleet_details_expand_and_paginate_without_enabling_upgrade(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950})
            for i=1,94 do vehicle(i,{part(1,1)},{muFiles={"missing.mu"}}) end;scan()
            local saved,cursor={},0
            reactMock.useState=function(v)
                cursor=cursor+1;if not saved[cursor] then saved[cursor]=state(v) end;return saved[cursor]
            end
            local function redraw() cursor=0;return renderWindow() end
            local function errorRows(node)
                if type(node)~="table" then return 0 end
                local count=node.params and (node.params.meta or {}).class=="upgrade-error-row" and 1 or 0
                for _,v in pairs(node) do if type(v)=="table" then count=count+errorRows(v) end end
                return count
            end
            local function nextBatch(node)
                if type(node)~="table" then return nil end
                if node.kind=="Button" and node.params.content.params.text=="下一批" then return node.params end
                for _,v in pairs(node) do if type(v)=="table" then local result=nextBatch(v);if result then return result end end end
            end
            local window=redraw();assert(errorRows(window)==0 and not find(window,"xiaom-upgrade-confirm").meta.enabled)
            find(window,"upgrade-errors-toggle").onClick();window=redraw();assert(errorRows(window)==8)
            for _=1,11 do local next=nextBatch(window);assert(next.meta.enabled);next.onClick();window=redraw() end
            assert(errorRows(window)==6 and not nextBatch(window).meta.enabled)
            find(window,"upgrade-errors-toggle").onClick();assert(errorRows(redraw())==0)
            assert(controller.totals().count==0 and #commands==0)''')


class NativeReactTests(unittest.TestCase):
    """Use the shipped registration implementation; only C++ context is doubled."""

    def setUp(self):
        self.lua = runtime()
        self.lua.execute(UI_FIXTURE)
        self.lua.execute(r'''
            _react={builtin={WithComponentParams=1},recipes={},recipeMetas={},originalRecipeFn={},recipeReplace={},
                tools={},extensionPoints={},recipeReplacementAllowed=true}
            nativeIds={};nativeNodes={};local nextRecipe=100
            log={verbose=function() end,warning=function() end,error=error}
            require=function() return {format=function(s) return s end} end
            moduleLoader=ug_require;ug_require=function() return {} end
            api.gui.react={params={builtin={WithComponentParams={new=function() return {} end}}},
                detail={IAHandle={new=function() return {} end},makeRecipeId=function(name)
                    nextRecipe=nextRecipe+1;nativeIds[name]=nextRecipe;return nextRecipe end},fireEvent=function() end}
        ''')
        with ZipFile(GUI) as archive:
            self.lua.globals().react = self.lua.execute(archive.read("gui/main/react.lua").decode("utf-8"))
        self.lua.execute(r'''
            ug_require=moduleLoader
            builtin={type=builtinMock.type}
            for id,name in ipairs({'BoxLayout','TextView','Button','Component','CheckBox','ImageView',
                'ComboBox','ComboBoxItem','Window','TextInputField','ScrollArea','TableLayout','Row'}) do
                _react.builtin[name]=id+1;builtin[name]=react.DeclareBuiltin(name,function() end)
            end
            statsMock={StatisticsEntryPoint=react.RegisterRecipe('StatisticsEntryPoint',function(p)
                return builtin.BoxLayout{children={}} end)}
            originalVehicleMock=react.RegisterRecipe('VehiclesStatistic',function(p)
                return builtin.BoxLayout{children={}} end)
            externals['::/gui/main/react.lua']=react;externals['::/gui/main/builtin.lua']=builtin
            externals['::/gui/statistics/statistics.tl']=statsMock
            externals['::/gui/statistics/statistic_vehicles.tl']=originalVehicleMock
            ui=ug_require('xiaom_vehicle_upgrade::/upgrade_ui.lua')
            entry=ug_require('xiaom_vehicle_upgrade::/upgrade_entry.lua')
            entry.install({ReplaceRecipe=react.GloballyReplaceRecipeBeforeInitInternal})
            function transform(id,param)
                local ctx={}
                function ctx:makeNodeWithProps(recipeId,key,props)
                    local node=#nativeNodes+1;nativeNodes[node]={recipeId=recipeId,props=props};return node
                end
                function ctx:checkRecipeMatch(node,recipeId)
                    assert(nativeNodes[node].recipeId==recipeId,'Wrapper child mismatch');return true
                end
                function ctx:setResult(result) self.result=result end
                function ctx:declareState(v) return state(v) end
                function ctx:onStepTimer(fn) timers[#timers+1]=fn end
                _react.recipes[id](ctx,{props=table.pack(param)})
                assert(#ctx.result==1)
                return nativeNodes[ctx.result[1]]
            end
            function validateNativeContainers(node)
                local visited={}
                local layouts={[_react.builtin.BoxLayout]=true,[_react.builtin.TableLayout]=true}
                local function isLayout(child)
                    if layouts[child.recipeId] then return true end
                    local meta=_react.recipeMetas[child.recipeId]
                    return meta and layouts[meta.innerRecipeId]==true or false
                end
                local function visit(current)
                    if visited[current] then return end;visited[current]=true
                    local p=current.props.props[1] or {}
                    if current.recipeId==_react.builtin.Component and p.layout then
                        assert(isLayout(nativeNodes[p.layout]),'Item of Component must be a layout')
                    end
                    if current.recipeId==_react.builtin.ScrollArea then
                        assert(p.content and nativeNodes[p.content],'ScrollArea must have content')
                        assert(not isLayout(nativeNodes[p.content]),
                            'ScrollArea does not accept a Layout as content')
                    end
                    for _,field in ipairs({'layout','content','item'}) do
                        if nativeNodes[p[field]] then visit(nativeNodes[p[field]]) end
                    end
                    for _,field in ipairs({'children','rows','cells','items'}) do
                        for _,id in ipairs(p[field] or {}) do if nativeNodes[id] then visit(nativeNodes[id]) end end
                    end
                end
                visit(node)
            end
            function nativeKind(recipeId)
                local meta=_react.recipeMetas[recipeId]
                if meta and meta.innerRecipeId then return nativeKind(meta.innerRecipeId) end
                if recipeId==_react.builtin.BoxLayout or recipeId==_react.builtin.TableLayout then return 'layout' end
                return 'component'
            end
        ''')

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_tab_body_and_context_wrapper_resolve_correct_native_nodes(self):
        self.run_lua('''local entry=transform(nativeIds.XiaomUpgradeStatisticsEntryPoint,{gameCtx=gameCtx})
            assert(entry.recipeId==nativeIds.StatisticsEntryPoint)
            local tab=transform(nativeIds.XiaomUpgradeVehicleTab,{searchString="test"})
            assert(tab.recipeId==_react.builtin.BoxLayout)
            assert(_react.recipeReplace[nativeIds.VehiclesStatistic] and _react.recipeReplace[nativeIds.StatisticsEntryPoint])
            assert(not _react.recipeMetas[nativeIds.XiaomUpgradeVehicleTab])''')

    def test_preview_wrapper_matches_window_and_original_table_is_deferred(self):
        self.run_lua('''model(1,{1},10);model(2,{1},20,{year=1950});vehicle(10,{part(1,1)});scan()
            local window=transform(nativeIds.XiaomVehicleUpgradeWindow,{})
            assert(window.recipeId==_react.builtin.Window)
            assert(window.props.props[1].id=="xiaom-vehicle-upgrade-window")
            assert(_react.recipeMetas[nativeIds.XiaomVehicleUpgradeWindow].innerRecipeId==_react.builtin.Window)
            local tab=transform(nativeIds.XiaomUpgradeVehicleTab,{})
            local list=nativeNodes[tab.props.props[1].children[2]]
            assert(list.recipeId==_react.builtin.Component)
            local layout=nativeNodes[list.props.props[1].layout]
            assert(layout.recipeId==_react.builtin.BoxLayout)
            local original=nativeNodes[layout.props.props[1].children[1]]
            assert(original.recipeId==nativeIds.VehiclesStatistic)''')

    def test_vehicle_tab_obeys_native_component_layout_contract(self):
        self.run_lua('''local tab=transform(nativeIds.XiaomUpgradeVehicleTab,{})
            validateNativeContainers(tab)''')

    def test_vehicle_tab_replacement_preserves_original_native_component_kind(self):
        self.run_lua('''local originalId=react.GetRecipeId(originalVehicleMock)
            local replacement=_react.recipeReplace[originalId]
            assert(nativeKind(originalId)=='component')
            assert(nativeKind(react.GetRecipeId(replacement))=='component',
                'A native layout wrapper cannot replace this component recipe')''')

    def test_generic_recipe_is_a_component_even_when_its_body_returns_a_layout(self):
        self.run_lua('''react.RegisterRecipe('InvalidVehicleListContainer',function()
                return builtin.Component{layout=react.CallOriginalRecipe(originalVehicleMock,{})}
            end)
            local invalid=transform(nativeIds.InvalidVehicleListContainer,{})
            local ok,reason=pcall(validateNativeContainers,invalid)
            assert(not ok and reason:find('Item of Component must be a layout',1,true))''')

    def test_preview_native_containers_during_scan_and_expanded_train_and_empty_filter(self):
        self.run_lua('''model(1,{},0,{carrier="RAIL"});model(2,{},0,{carrier="RAIL",year=1950})
            model(3,{1},10,{carrier="RAIL",unpowered=true})
            model(4,{1},20,{carrier="RAIL",unpowered=true,year=1950})
            vehicle(10,{part(1,-1),part(3,1)})
            controller.open(gameCtx)
            validateNativeContainers(transform(nativeIds.XiaomVehicleUpgradeWindow,{}))
            scan();assert(#row().snapshot.units==2)
            for _,unit in ipairs(row().snapshot.units) do controller.toggleGroup(unit.groupKey) end
            controller.toggleRow(row())
            validateNativeContainers(transform(nativeIds.XiaomVehicleUpgradeWindow,{}))
            controller.filter("search","no-matching-vehicle")
            validateNativeContainers(transform(nativeIds.XiaomVehicleUpgradeWindow,{}))
            controller.filter("search","");row().snapshot=nil;row().error="Vehicle no longer exists"
            validateNativeContainers(transform(nativeIds.XiaomVehicleUpgradeWindow,{}))
            assert(#commands==0)''')

    def test_native_scroll_area_guard_rejects_direct_layout_content(self):
        self.run_lua('''react.RegisterRecipe('InvalidScrollContent',function()
                return builtin.ScrollArea{content=builtin.BoxLayout{children={builtin.TextView{text="test"}}}}
            end)
            local invalid=transform(nativeIds.InvalidScrollContent,{})
            local ok,reason=pcall(validateNativeContainers,invalid)
            assert(not ok and reason:find('ScrollArea does not accept a Layout as content',1,true))''')


if __name__ == "__main__":
    unittest.main(verbosity=2)
