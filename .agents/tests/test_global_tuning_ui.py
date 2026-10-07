"""Revision 7 regression cases. Updated, but deliberately not executed per AGENTS.md."""
import unittest
from test_global_tuning import MOD, runtime

FIXTURE = r'''
industries, stocks, vehicles = {[10]={stockList=11}}, {[11]={modifiers={productivity=1}}}, {
    [20]={modifiers={topSpeedScale=1,noiseScale=0.7,pollutionScale=0.8,comfortScale=1.3}},
}
api.type.ComponentType.INDUSTRY="industry"
api.type.ComponentType.STOCK_LIST="stock"
api.type.ComponentType.TRANSPORT_VEHICLE="vehicle"
api.type.StockList={Modifiers={new=clone}}
api.type.TransportVehicle={Modifiers={new=clone}}
api.engine.getComponent=function(entity,kind)
    if kind=="GAME_SPEED" then return ready and {speedup=0,millisPerDay=2000} or nil end
    if kind=="industry" then return industries[entity] end
    if kind=="stock" then return stocks[entity] end
    if kind=="vehicle" then return vehicles[entity] end
end
api.engine.getEntitiesWithComponent=function(kind)
    local source=kind=="industry" and industries or kind=="vehicle" and vehicles or {}
    local result={};for entity in pairs(source) do result[#result+1]=entity end;table.sort(result);return result
end
api.cmd.makeStockListSetModifiersCmd=function(entity,modifiers) return {kind="industry",entity=entity,modifiers=clone(modifiers)} end
api.cmd.makeVehicleSetModifiersCmd=function(entity,modifiers) return {kind="vehicle",entity=entity,modifiers=clone(modifiers)} end
callbacks, holdCallbacks, commandSuccess, throwWrite = {}, false, true, false
api.cmd.sendCommand=function(command,callback)
    commands[#commands+1]=command
    if commandSuccess then
        if command.kind=="industry" then stocks[industries[command.entity].stockList].modifiers=clone(command.modifiers) end
        if command.kind=="vehicle" then vehicles[command.entity].modifiers=clone(command.modifiers) end
    end
    if holdCallbacks then callbacks[#callbacks+1]=callback else callback({},commandSuccess) end
end
local nativeWrite=app.saveUserdata
app.saveUserdata=function(...) if throwWrite then error("disk write failed") end;nativeWrite(...) end
function tick(duration) clock=clock+(duration or 0.5);controller.update() end
recipes, timers, windows, visible = {}, {}, {}, {}
local function state(initial)
    return {value=initial,old=function(self) return self.value end,get=function(self) return self.value end,
        set=function(self,v) self.value=v end,hasExpired=function() return false end}
end
reactMock={
    RegisterRecipe=function(name,fn) recipes[name]=fn;return fn end,
    RegisterWrapperRecipe=function(name,base,fn)
        assert(base~=builtinMock.Button, "Native Button has no Lua recipe ID in this build")
        local wrapped=function(params)
            local result=fn(params)
            assert(base==builtinMock.Window and result.kind=="Window", "Wrapper must return its declared child")
            return result
        end
        recipes[name]=wrapped;return wrapped
    end,
    CallOriginalRecipe=function(recipe,params) return recipe(params) end,
    useState=function(value) return state(value) end,
    useStateLazy=function(fn) return state(fn()) end,
    onStepTimer=function(fn) timers[#timers+1]=fn end,
    setMouseTransparent=function(value) mouseTransparent=value end,
}
builtinMock={type={Orientation={Horizontal="horizontal",Vertical="vertical"},
    ScrollBarPolicy={AlwaysOff="off",Simple="simple"},ImageViewScaling={AutoFit="auto-fit"}}}
for _,name in ipairs({"TextView","ImageView","Button","ComboBoxItem","BoxLayout","ComboBox","Window","ScrollArea","FloatingLayout","FloatingLayoutChild","Component"}) do
    builtinMock[name]=function(params) return {kind=name,params=params} end
end
builtinMock.ScrollArea=function(params)
    assert(params.content and params.content.kind=="Component", "ScrollArea does not accept a Layout as content")
    assert(params.content.params.layout and params.content.params.layout.kind=="BoxLayout")
    return {kind="ScrollArea",params=params}
end
windowApi={
    addSingletonWindow=function(recipe,params) windows[recipe]=recipe(params) end,
    moveSingletonWindowToFront=function(recipe) front=recipe end,
    removeAllWindows=function(recipe) windows[recipe]=nil end,
}
globalsMock={getDefaultWindowApi=function() return windowApi end}
gameBarMock={GameBar=function(params) return {kind="OriginalGameBar",params=params} end}
api.gui.byId={setVisible=function(id,value) visible[id]=value end}
externalModules={['::/gui/main/react.lua']=reactMock,['::/gui/main/builtin.lua']=builtinMock,
    ['::/gui/main/game_react_globals.tl']=globalsMock,['::/gui/game_bar/game_bar.tl']=gameBarMock}
function findNode(node,id)
    if type(node)~="table" then return nil end
    if node.params and ((node.params.meta and node.params.meta.id==id) or node.params.id==id) then return node.params end
    for _,value in pairs(node) do
        if type(value)=="table" then local found=findNode(value,id);if found then return found end end
    end
end
function windowCount() local n=0;for _ in pairs(windows) do n=n+1 end;return n end
function getWindow() for _,v in pairs(windows) do return v end end
'''


class UiTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime()
        self.lua.execute(FIXTURE)
        original = self.lua.globals().ug_require
        def require(name):
            if name.startswith("::/"):
                module = self.lua.globals().externalModules[name]
                if module is None:
                    raise AssertionError(f"Unexpected external module: {name}")
                return module
            return original(name)
        self.lua.globals().ug_require = require
        self.lua.globals().controller = require("tuning_controller.lua")
        self.lua.globals().ui = require("tuning_ui.lua")

    def run_lua(self, code):
        return self.lua.execute(code)

    def test_launcher_singleton_closes_and_reopens(self):
        self.run_lua(r"""
            ui.Launcher().params.onClick();assert(windowCount()==1)
            ui.open();assert(windowCount()==1 and visible["xiaom-global-tuning-window"])
            local window=getWindow().params;assert(window.title=="内置修改器" and window.closable)
            window.onClose();assert(windowCount()==0);ui.open();assert(windowCount()==1)
        """)

    def test_ten_fields_record_actual_values_with_no_reload_button(self):
        self.run_lua(r"""
            controller.initialize();tick();ui.open()
            local keys={"industryProduction","freightCapacity","freightWeight","passengerCapacity",
                "freightLoading","passengerLoading","vehicleSpeed","railTraction","simulationSpeed","calendarSpeed"}
            for _,key in ipairs(keys) do
                local field=findNode(getWindow(),"xiaom-tuning-"..key)
                assert(field and #field.items>=10);field.onValueChange(2)
            end
            tick()
            local params=userdata["mod_settings/xiaom_global_tuning/settings"].params
            for _,key in ipairs(keys) do assert(params[key]==2) end
            assert(not findNode(getWindow(),"xiaom-tuning-reload") and not next(guiSaveData))
        """)

    def test_debounce_batches_storage_and_applies_factory_and_vehicle_live(self):
        self.run_lua(r"""
            controller.initialize();tick();local before=userdataWrites
            controller.edit("industryProduction",2);controller.edit("vehicleSpeed",3)
            tick(0.1);assert(userdataWrites==before)
            tick(0.3);assert(userdataWrites==before+2)
            assert(stocks[11].modifiers.productivity==2 and vehicles[20].modifiers.topSpeedScale==3)
            assert(vehicles[20].modifiers.noiseScale==0.7 and vehicles[20].modifiers.comfortScale==1.3)
            assert(controller.pending()==1)
        """)

    def test_scaling_uses_load_snapshot_and_does_not_stack(self):
        self.run_lua(r"""
            snapshots[1].data.params={vehicleSpeed=2};setConfig({vehicleSpeed=2})
            controller.initialize();tick()
            controller.edit("vehicleSpeed",3);tick();assert(vehicles[20].modifiers.topSpeedScale==1.5)
            controller.edit("vehicleSpeed",1);tick();assert(vehicles[20].modifiers.topSpeedScale==0.5)
            controller.retry();tick();assert(vehicles[20].modifiers.topSpeedScale==0.5)
        """)

    def test_new_entities_receive_settings_without_resending_time(self):
        self.run_lua(r"""
            setConfig({industryProduction=2,vehicleSpeed=3,simulationSpeed=4,calendarSpeed=2})
            controller.initialize();tick()
            industries[30]={stockList=31};stocks[31]={modifiers={productivity=1}}
            vehicles[40]={modifiers={topSpeedScale=1,noiseScale=1,pollutionScale=1,comfortScale=1}}
            tick(4);tick()
            assert(stocks[31].modifiers.productivity==2 and vehicles[40].modifiers.topSpeedScale==3)
            local timeCalls=0;for _,command in ipairs(commands) do
                if command.kind=="simulation" or command.kind=="calendar" then timeCalls=timeCalls+1 end
            end
            assert(timeCalls==2)
        """)

    def test_paused_time_and_unrelated_edit_do_not_reapply_time(self):
        self.run_lua(r"""
            controller.initialize();tick()
            controller.edit("simulationSpeed",0);controller.edit("calendarSpeed",0);tick()
            local count=#commands
            assert(commands[count-1].kind=="simulation" and commands[count-1].value==0)
            assert(commands[count].kind=="calendar" and commands[count].value==0)
            controller.edit("freightCapacity",2);tick();tick(4);tick()
            assert(#commands==count and controller.pending()==1)
        """)

    def test_missing_callbacks_never_lock_ui_and_timeout(self):
        self.run_lua(r"""
            controller.initialize();tick();holdCallbacks=true
            controller.edit("simulationSpeed",8);tick();ui.open()
            assert(getWindow().params.closable and not select(3,controller.read()))
            getWindow().params.onClose();assert(windowCount()==0)
            tick(13);local _,message=controller.read();assert(message:find("未成功"))
            holdCallbacks=false;controller.retry();tick()
            assert(not select(3,controller.read()))
        """)

    def test_disk_failure_is_visible_and_never_applied_by_background_audit(self):
        self.run_lua(r"""
            controller.initialize();tick();throwWrite=true
            controller.edit("vehicleSpeed",3);controller.edit("simulationSpeed",8);tick();tick(5)
            assert(vehicles[20].modifiers.topSpeedScale==1)
            assert(select(2,controller.read()):find("保存失败"))
            throwWrite=false;controller.edit("freightCapacity",2);tick()
            assert(vehicles[20].modifiers.topSpeedScale==3)
            local found=false;for _,c in ipairs(commands) do if c.kind=="simulation" and c.value==8 then found=true end end
            assert(found)
        """)

    def test_command_work_is_bounded_per_frame(self):
        self.run_lua(r"""
            for entity=21,90 do vehicles[entity]={modifiers={topSpeedScale=1,noiseScale=1,pollutionScale=1,comfortScale=1}} end
            setConfig({vehicleSpeed=2});holdCallbacks=true
            controller.initialize();tick()
            assert(#commands==8 and getWindow()==nil and not select(3,controller.read()))
        """)

    def test_resource_options_are_persisted_without_runtime_resource_writes(self):
        self.run_lua(r"""
            controller.initialize();tick();local count=#commands
            controller.edit("freightCapacity",100);controller.edit("railTraction",0.1);tick()
            assert(#commands==count and writes==0 and controller.pending()==2)
            local config=userdata["mod_settings/xiaom_global_tuning/settings"].params
            assert(config.freightCapacity==100 and config.railTraction==0.1)
            assert(userdata["staging_area/xiaom_global_tuning/content/local_settings.res"].data.params.freightCapacity==100)
        """)

    def test_stored_config_beats_legacy_save_settings(self):
        self.run_lua(r"""
            rawParams=settings.toModParams({passengerCapacity=100,simulationSpeed=32})
            setConfig({passengerCapacity=3,simulationSpeed=2})
            controller.initialize();tick();local params=controller.read()
            assert(params.passengerCapacity==3 and params.simulationSpeed==2 and not next(guiSaveData))
        """)

    def test_loader_without_app_reads_resource_cache(self):
        self.run_lua(r"""
            snapshots[2].data.params={freightCapacity=5,vehicleSpeed=2}
            local store=ug_require("xiaom_global_tuning::/config_store.lua")
            app=nil;local params,found,err=store.read()
            assert(found and not err and params.freightCapacity==5 and params.vehicleSpeed==2)
        """)

    def test_game_bar_preserves_native_recipe_and_installs_once(self):
        self.run_lua(r"""
            local installs=0
            local replacementApi={ReplaceRecipe=function(original,replacement)
                assert(original==gameBarMock.GameBar);installs=installs+1;wrappedBar=replacement
            end}
            ui.install(replacementApi);ui.install(replacementApi);assert(installs==1)
            local params={gameCtx="game",gameSpeedHelper="speed"}
            local result=wrappedBar(params)
            assert(mouseTransparent and result.kind=="FloatingLayout")
            assert(result.params.children[1].params.item.params==params)
            assert(findNode(result,"xiaom-global-tuning-launcher"))
        """)


if __name__ == "__main__":
    unittest.main(verbosity=2)
