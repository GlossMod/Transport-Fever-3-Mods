"""Naming UI interactions and the installed TF3 React registration contracts."""
import unittest
from zipfile import ZipFile
import test_line_names_v3 as upgrade_tests
from test_vehicle_upgrade_ui import UI_FIXTURE, GUI

FIXTURE = r'''
externals={}; api.gui={}; local originalModuleLoader=ug_require
function ug_require(path) return externals[path] or originalModuleLoader(path) end
function native(t)
    return {find=function(_,k) local v=t[k];return type(v)=='table' and native(v) or v end,
        size=function() return #t end,asTable=function() return deepcopy(t) end}
end
api.type.ComponentType.GAME_SCRIPT='gamescript'
world.names[900000]='script'
api.engine.system.gameScriptSystem={getEntityForGameScript=function(name)
    assert(name=='xiaom_auto_line_names::/auto_line_names.gs');return 900000 end}
local get=api.engine.getComponent
api.engine.getComponent=function(id,kind)
    if id==900000 and kind=='gamescript' then return {state_native=native(state.value)} end
    return get(id,kind)
end
'''


class NamingUiTest(unittest.TestCase):
    def setUp(self):
        upgrade_tests.UpgradeTest.setUp(self)
        self.lua.execute(FIXTURE)
        # The simulation's state must retain its name when the shared UI fixture declares a helper.
        self.lua.execute('simulationState=state')
        self.lua.execute(UI_FIXTURE)
        self.lua.execute('reactState=state;state=simulationState;reactMock.useState=reactState')
        self.lua.execute('''managerMock={ManagerWindowContent=function(p) return {kind='OriginalManager',params=p} end}
            externals['::/gui/line_vehicle_mgmt/manager_window.tl']=managerMock
            ui=ug_require 'xiaom_auto_line_names::/naming_ui.lua'
            control=ug_require 'xiaom_auto_line_names::/naming_controller.lua'
            function renderNamingWindow() return recipes.XiaomLineNamingPreview() end
            function finish() for i=1,4 do local ops=script.update({},state,0);script.postUpdate({},state,0,ops) end end''')

    def test_manager_keeps_native_content_and_selected_entities(self):
        self.lua.execute('''local count=0;local replace
            local api={ReplaceRecipe=function(old,new) assert(old==managerMock.ManagerWindowContent);replace=new;count=count+1 end}
            ui.install(api);ui.install(api);assert(count==1)
            line(1,{stop(10,{0}),stop(20,{0})},'Manual')
            local p={toolParam={lineManagerStateRef={get=function() return {lineListEntitiesSelected={{entity=1}}} end}}}
            local tree=replace(p)
            assert(tree.params.children[2].params.layout.kind=='BoxLayout')
            assert(tree.params.children[2].params.layout.params.children[1].kind=='OriginalManager')
            find(tree,'xiaom-line-naming-bulk').onClick();finish()
            assert(not control.read().session.all and #control.read().session.ids==1)
            assert(#world.sent==0)''')

    def test_checkbox_uses_native_integer_contract_and_takeover(self):
        self.lua.execute('''line(1,{stop(10,{0}),stop(20,{0})},'Manual');ui.open({1});finish()
            assert(find(renderNamingWindow(),'xiaom-line-naming-include').value==0)
            assert(find(renderNamingWindow(),'xiaom-line-naming-confirm').meta.enabled==false)
            find(renderNamingWindow(),'xiaom-line-naming-include').onValueChange(1);finish()
            assert(find(renderNamingWindow(),'xiaom-line-naming-include').value==1)
            find(renderNamingWindow(),'xiaom-line-naming-confirm').onClick();finish()
            assert(world.names[1]=='[铁路客运] 北京-天津-001' and state.value.lines['1'].managed)''')

    def test_checkbox_zero_restores_protection(self):
        self.lua.execute('''line(1,{stop(10,{0}),stop(20,{0})},'Manual');ui.open({1});finish()
            find(renderNamingWindow(),'xiaom-line-naming-include').onValueChange(1);finish()
            find(renderNamingWindow(),'xiaom-line-naming-include').onValueChange(0);finish()
            assert(not control.read().session.include and control.read().eligible==0 and #world.sent==0)''')

    def test_window_close_cancels_without_rename(self):
        self.lua.execute('''line(1,{stop(10,{0}),stop(20,{0})},'Manual');ui.open({1});finish()
            find(renderNamingWindow(),'xiaom-line-naming-preview').onClose()
            assert(not control.read() and not state.value.preview and #world.sent==0)''')


class NativeNamingUiTest(NamingUiTest):
    # Run only the contracts below with TF3's actual React implementation.
    test_manager_keeps_native_content_and_selected_entities = None
    test_checkbox_uses_native_integer_contract_and_takeover = None
    test_checkbox_zero_restores_protection = None
    test_window_close_cancels_without_rename = None

    def setUp(self):
        NamingUiTest.setUp(self)
        self.lua.execute('''
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
        with ZipFile(GUI) as z:
            self.lua.globals().react = self.lua.execute(z.read('gui/main/react.lua').decode('utf-8'))
        self.lua.execute('''
            ug_require=moduleLoader;builtin={type=builtinMock.type}
            for id,name in ipairs({'BoxLayout','TextView','Button','Component','CheckBox','ComboBox','ComboBoxItem','Window','TableLayout','Row'}) do
                _react.builtin[name]=id+1;builtin[name]=react.DeclareBuiltin(name,function() end)
            end
            managerMock={ManagerWindowContent=react.RegisterRecipe('OriginalManager',function(p) return builtin.BoxLayout{children={}} end)}
            externals['::/gui/main/react.lua']=react;externals['::/gui/main/builtin.lua']=builtin
            externals['::/gui/line_vehicle_mgmt/manager_window.tl']=managerMock
            loaded['xiaom_auto_line_names::/naming_ui.lua']=nil
            ui=ug_require 'xiaom_auto_line_names::/naming_ui.lua'
            ui.install({ReplaceRecipe=react.GloballyReplaceRecipeBeforeInitInternal})
            function transform(id,p)
                local ctx={}
                function ctx:makeNodeWithProps(recipeId,key,props)
                    local node=#nativeNodes+1;nativeNodes[node]={recipeId=recipeId,props=props};return node
                end
                function ctx:checkRecipeMatch(node,recipeId) assert(nativeNodes[node].recipeId==recipeId);return true end
                function ctx:setResult(v) self.result=v end
                function ctx:declareState(v) return reactState(v) end
                function ctx:onStepTimer(fn) timers[#timers+1]=fn end
                _react.recipes[id](ctx,{props=table.pack(p)});assert(#ctx.result==1)
                return nativeNodes[ctx.result[1]]
            end
        ''')

    def test_native_window_wrapper_is_a_window(self):
        self.lua.execute('''line(1,{stop(10,{0}),stop(20,{0})},'Manual');control.open({1});finish()
            local node=transform(nativeIds.XiaomLineNamingPreview,{})
            assert(node.recipeId==_react.builtin.Window and node.props.props[1].id=='xiaom-line-naming-preview')''')

    def test_native_manager_component_and_layout_contract(self):
        self.lua.execute('''local p={toolParam={lineManagerStateRef={get=function() return {lineListEntitiesSelected={}} end}}}
            local node=transform(nativeIds.XiaomLineNamingManager,p)
            assert(node.recipeId==_react.builtin.BoxLayout)
            assert(not _react.recipeMetas[nativeIds.XiaomLineNamingManager])
            local component=nativeNodes[node.props.props[1].children[2]]
            assert(component.recipeId==_react.builtin.Component)
            local layout=nativeNodes[component.props.props[1].layout]
            assert(layout.recipeId==_react.builtin.BoxLayout)
            assert(nativeNodes[layout.props.props[1].children[1]].recipeId==nativeIds.OriginalManager)''')


if __name__ == '__main__':
    unittest.main(verbosity=2)
