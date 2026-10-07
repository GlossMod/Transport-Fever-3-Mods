"""Run the shipped Lua using Lua 5.4; doubles do not emulate TF3's engine.

Run: py -X utf8 .agents/tests/test_building_mover.py
"""
import json
import re
import sys
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".agents/tools/line_naming_test_runtime"))
from lupa.lua54 import LuaRuntime

MOD = ROOT / "staging_area/xiaom_building_mover"
NATIVE_GUI = Path(r"E:\steam\steamapps\common\Transport Fever 3\base\content\gui.zip")
MOCK = r'''
world = {components = {}, revisions = {}, commands = {}, delayed = true, fail = false}
function debugPrint(message) end
function clone(v)
    if type(v) ~= "table" then return v end
    local t = {}; for k, x in pairs(v) do t[k] = clone(x) end; return setmetatable(t,getmetatable(v))
end
local matrixMeta = {}
matrixMeta.__index = {
    clone = function(m) return matrix(clone(m)) end,
    getTransl = function(m) return {x=m[13],y=m[14],z=m[15]} end,
    setTransl = function(m,v) m[13]=v.x;m[14]=v.y;m[15]=v.z end,
}
matrixMeta.__mul = function(a, b)
    local r = {}
    for c = 0, 3 do for row = 0, 3 do
        local sum = 0
        for k = 0, 3 do sum = sum + a[k*4+row+1]*b[c*4+k+1] end
        r[c*4+row+1] = sum
    end end
    return setmetatable(r, matrixMeta)
end
function matrix(values) return setmetatable(values, matrixMeta) end
function identity() return matrix({1,0,0,0, 0,1,0,0, 0,0,1,0, 100,200,30,1}) end
api = {
    type = {
        ComponentType = {},
        Vec2f = {new = function(x,y) return {x=x,y=y} end},
        Vec3f = {new = function(x,y,z) return {x=x,y=y,z=z} end},
        Mat4f = {
            rotZ = function(a) local c,s=math.cos(a),math.sin(a)
                return matrix({c,s,0,0, -s,c,0,0, 0,0,1,0, 0,0,0,1}) end,
        },
        SimpleProposal = {
            new = function() return {} end,
            ConstructionEntity = {new = function() return {playerEntity=-1} end},
        },
        Context = {new = function() return {player=-1} end},
    },
    engine = {
        terrain = {getHeightAt = function(p) return 30 end},
        entityExists = function(e) return world.components[e] ~= nil end,
        getComponent = function(e,k) return world.components[e] and clone(world.components[e][k]) end,
        getRevision = function(e) return {num=clone(world.revisions[e] or {1,0,0})} end,
        util = {
            getPlayer=function() return 99 end,
            getEntityName=function(e) return "Existing building" end,
            proposal={createProposalReplaceConstruction=function(e,p)
                return {old2new={[e]=0},toAdd={{playerEntity=88}}}
            end},
        },
        system = {streetConnectorSystem = {}},
    },
    gui = {
        mouse = {
            hasTerrainPosition = function() return world.cursor ~= nil end,
            getTerrainPosition = function() return clone(world.cursor) end,
            Event = {Type = {Clicked=1}},
        },
        inputAction = {modifierOnlyActionIsActive = function() return world.precision or false end},
        construction={getRefundableEntities=function() return {} end},
        byId={setVisible=function(id,visible) end},
    },
    res = {moduleRep={find=function(name) return -1 end},
        constructionRep={find=function(name) return 1 end,
            get=function(id) return {params={{key='length'},{key='cargo'}}} end}},
    util = {formatMoney=function(n) return tostring(n) end},
    cmd = {
        makeWorldBuildProposalCmd = function(p,c,ignore,player,dust)
            assert(ignore==false and player==false and dust==false)
            assert(p.constructionsToAdd and p.constructionsToRemove, 'submit the owned SimpleProposal')
            -- Actual rev.5 crash log proves entries are numeric, despite the
            -- shipped declaration describing entity/revision pairs.
            return {proposal=p,context=c,playerInitiated=player,doDust=dust,resultEntities={20}}
        end,
        sendCommand = function(cmd, cb) world.commands[#world.commands+1]={cmd=cmd,cb=cb} end,
    },
}
for _,k in ipairs({'CONSTRUCTION','SUBCONSTRUCTION','STATION','STATION_GROUP','INDUSTRY','DEPOT','TOWN_BUILDING','PLAYER_OWNED','ACCOUNT'}) do
    api.type.ComponentType[k]=k
end
for _,k in ipairs({'Subconstruction','Station','Industry','Depot','TownBuilding'}) do
    api.engine.system.streetConnectorSystem['getConstructionEntityFor'..k] = function(e) return world.parents[e] end
end
world.parents = {[11]=10,[12]=10,[13]=10,[14]=10,[15]=10}
world.components = {
    [99] = {ACCOUNT={balance=10000}},
    [10] = {
        PLAYER_OWNED = {player=99},
        CONSTRUCTION = {
            fileName='::/station.con', transf=identity(),
            params = {seed=42,year=1900,custom={level=3},modules={
                [0]={name='::/entrance.module',variant=-2,custom={cargo='coal'}},
                [10]={name='::/platform.module',variant=1},
            }},
            slots = {
                {id=0,type='entrance'},{id=1,type='entrance'},{id=2,type='track'},
                {id=10,type='platform'},{id=11,type='platform'},
            },
        },
    },
    [11]={SUBCONSTRUCTION={slotIds={0}}},[12]={STATION={}},[13]={DEPOT={}},
    [14]={INDUSTRY={}},[15]={TOWN_BUILDING={}},[16]={STATION_GROUP={stations={12}}},
    [20]={CONSTRUCTION={fileName='::/station.con',params={modules={}},slots={},transf=identity()}},
}
world.revisions[10]={1,2,3}
world.cursor={x=120,y=220,z=30}
for _,slot in ipairs(world.components[10].CONSTRUCTION.slots) do slot.transf=identity() end
function processed(simple)
    local entry = simple.constructionsToAdd[1]
    return {
        old2new=clone(simple.old2new),toRemove=clone(simple.constructionsToRemove),
        toAdd={{construction={params=clone(entry.params)}}},
    }
end
function previewData() return {errorState={critical=false,messages={}},costs=100} end
-- Model the native callback's borrowed userdata, which becomes invalid on return.
function borrowed(value)
    local live=true
    return setmetatable({}, {__index=function(_,k)
        assert(live, 'access to expired native preview userdata')
        return value[k]
    end}), function() live=false end
end
function deliverPreview(callback, simple)
    local data,expireData=borrowed(previewData())
    local generated,expireProposal=borrowed(processed(simple))
    callback(data,generated)
    expireData();expireProposal()
end
function receipt(snapshot, simple, data)
    return core.capturePreview(snapshot,data or previewData(),processed(simple),simple)
end
function complete(success)
    local sent=world.commands[#world.commands]
    sent.cb(sent.cmd, success)
end
'''

UI_MOCK = r'''
recipes, events, states, refs, timerFns, nodes, stepFns, inputActions = {}, {}, {}, {}, {}, {}, {}, {}
local stateCursor, refCursor = 0, 0
react = {
    RegisterRecipe = function(name,fn)
        local recipe=function(param)
            local result=fn(param)
            assert(result.nodeKind=='BoxLayout' or result.nodeKind=='FloatingLayout',
                'Recipe child must be a layout: '..name)
            return result
        end
        recipes[name]=recipe;return recipe
    end,
    RegisterWrapperRecipe = function(name,wrapped,fn)
        local recipe=function(param)
            local result=fn(param)
            assert(result.recipeFn==wrapped or result.builtinFn==wrapped,
                'Wrapper recipe child must match: '..name)
            return result
        end
        recipes[name]=recipe;return recipe
    end,
    RegisterTool = function(tool) return tool end,
    useState = function(initial)
        stateCursor=stateCursor+1
        if not states[stateCursor] then
            local s={value=initial}
            function s:old() return self.value end
            function s:set(v) self.value=v end
            function s:hasExpired() return false end
            states[stateCursor]=s
        end
        return states[stateCursor]
    end,
    useRef = function(initial)
        refCursor=refCursor+1
        if not refs[refCursor] then
            local r={value=initial}
            function r:get() return self.value end
            function r:set(v) self.value=v end
            function r:hasExpired() return false end
            refs[refCursor]=r
        end
        return refs[refCursor]
    end,
    onEvent=function(name,cb) events[name]=cb end,
    onStep=function(cb) stepFns={cb} end,
    onUnmount=function(cb) end,
    onStepTimer=function(cb) timerFns={cb} end,
    useInputAction=function(id,config) inputActions[id]=config end,
    iaHandler=function(fn,enabled) return {handlerFn=fn,isEnabledFn=enabled} end,
}
builtin={type={Orientation={Horizontal=1,Vertical=2},
    ConstructionAction={ConstructionBuilder={new=function() return {} end}}}}
for _,name in ipairs({'TextView','BoxLayout','Button','ActionDescriptor','ProposalViewer','Selector','Window','ComboBox','ComboBoxItem','ConstructionAction'}) do
    builtin[name]=function(p) p.nodeKind=name;p.builtinFn=builtin[name];nodes[#nodes+1]=p;return p end
end
local constructionActionNode=builtin.ConstructionAction
builtin.ConstructionAction=function(p)
    for id in pairs(p.inputActions or {}) do
        inputActions[id]={handlerFn=function() p.inputActionsHandler(id) end}
    end
    return constructionActionNode(p)
end
function nativeBuilderProposal(builder)
    -- The native builder inserts its own persistence fields. A full saved
    -- params table caused lua::Table::Put's duplicate-key assertion in r7.
    for _,key in ipairs({'seed','year','modules'}) do
        assert(builder.params[key]==nil, 'native builder duplicate key: '..key)
    end
    local m=world.nativeTransform and world.nativeTransform:clone() or api.type.Mat4f.rotZ(builder.rotation)
    if not world.nativeTransform then
        m:setTransl({x=world.cursor.x,y=world.cursor.y,z=world.cursor.z+builder.height})
    end
    return {toAdd={{transf=m}}}, previewData()
end
toolStack = {
    push=function(tool,key,param,stacking)
        toolStack.tool=tool;toolStack.param=param
        local ctx={setActionFn=function(fn) toolStack.action=fn end}
        tool.push(ctx,param)
    end,
    pop=function(tool,key)
        if toolStack.tool==tool then
            local param=toolStack.param
            toolStack.tool=nil;toolStack.action=nil;toolStack.param=nil
            tool.pop({},param)
        end
    end,
}
windowApi={
    addSingletonWindow=function(recipe,p)
        if windowApi.recipe~=recipe then states={};refs={} end
        windowApi.mounts=(windowApi.mounts or 0)+1;windowApi.params=p;windowApi.recipe=recipe
    end,
    removeAllWindows=function(recipe) windowApi.closed=true end,
}
local nativeNode={getApi=function() return windowApi end,getIdentity=function() return 100 end}
local container={hasExpired=function() return false end,get=function() return nativeNode end}
globals={getDefaultWindowContainer=function() return container end,getDefaultToolStackApi=function() return toolStack end}
function redraw()
    stateCursor=0;refCursor=0;nodes={}
    return recipes.XiaomBuildingMoverWindow(windowApi.params or {entity=10,request=0})
end
function openMover(entity)
    assert(ui.openModules(entity or 10))
    redraw()
    for _,fn in ipairs(stepFns) do fn() end
    redraw()
end
function chooseModuleTarget()
    for _,n in ipairs(nodes) do
        if n.nodeKind=='ComboBox' and #n.items==1 and n.items[1].value==1 then
            n.onValueChange(1);redraw();return
        end
    end
    error('target slot missing')
end
function click(label)
    for _,n in ipairs(nodes) do
        if n.nodeKind=='Button' and n.content.text==label then
            assert(n.meta.enabled~=false,'disabled button: '..label)
            n.onClick();return
        end
    end
    error('button missing: '..label)
end
function generate()
    local p=toolStack.param
    deliverPreview(p.onData,p.proposal)
end
'''


class MoverTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.globals().core = self.lua.execute((MOD / "content/mover_core.lua").read_text("utf-8"))

    def check(self, source):
        self.lua.execute(source)

    def ui(self):
        self.check(UI_MOCK)
        self.check('ug_require=function(path) if path:find("react.lua",1,true) then return react elseif path:find("builtin.lua",1,true) then return builtin elseif path:find("game_react_globals",1,true) then return globals elseif path:find("mover_placement",1,true) then return placement else return core end end')
        self.lua.globals().placement = self.lua.execute((MOD / "content/mover_placement.lua").read_text("utf-8"))
        self.lua.globals().ui = self.lua.execute((MOD / "content/mover_ui.lua").read_text("utf-8"))

    def test_translate_rotate_about_own_origin(self):
        self.check('''local p=assert(core.proposal(10,{kind='building',x=7,y=-8,z=2,angle=90}))
        local m=p.constructionsToAdd[1].transf
        assert(m[13]==107 and m[14]==192 and m[15]==32)
        assert(math.abs(m[1])<1e-8 and math.abs(m[2]-1)<1e-8)
        assert(world.components[10].CONSTRUCTION.transf[13]==100)
        assert(p.old2new[10]==0 and p.constructionsToRemove[1]==10)''')

    def test_move_preserves_custom_params_modules_and_owner(self):
        self.check('''local p=assert(core.proposal(10,{kind='building',x=1,y=0,z=0,angle=0}))
        local e=p.constructionsToAdd[1];assert(e.playerEntity==99 and e.autoFillSlots==false)
        assert(e.params.seed==42 and e.params.custom.level==3)
        e.params.modules[0].custom.cargo='changed'
        assert(world.components[10].CONSTRUCTION.params.modules[0].custom.cargo=='coal')''')

    def test_cursor_placement_keeps_modules_rotation_and_relative_elevation(self):
        self.check('''api.engine.terrain.getHeightAt=function() return 25 end
        local p=assert(core.proposal(10,{kind='placement',position={x=300,y=400,z=50},angle=90,height=2}))
        local e=p.constructionsToAdd[1]
        assert(e.transf[13]==300 and e.transf[14]==400 and e.transf[15]==57)
        assert(math.abs(e.transf[2]-1)<1e-8)
        assert(e.params.modules[0].variant==-2 and e.params.modules[10].variant==1)
        assert(e.autoFillSlots==false and p.old2new[10]==0)
        assert(world.components[10].CONSTRUCTION.transf[13]==100)''')

    def test_cursor_placement_rejects_invalid_and_unchanged_destination(self):
        self.check('''assert(core.proposal(10,{kind='placement',position={x=100,y=200,z=30},angle=0,height=0})==nil)
        assert(core.proposal(10,{kind='placement',position={x=0/0,y=200,z=30},angle=0,height=0})==nil)
        assert(core.proposal(10,{kind='placement',position={x=120,y=220,z=30},angle=math.huge,height=0})==nil)''')

    def test_relocate_module_with_zero_slot_and_variant(self):
        self.check('''local p=assert(core.proposal(10,{kind='module',source=0,target=1}))
        local m=p.constructionsToAdd[1].params.modules
        assert(m[0]==nil and m[1].variant==-2 and m[1].custom.cargo=='coal')
        assert(m[10].name=='::/platform.module')
        assert(world.components[10].CONSTRUCTION.params.modules[0]~=nil)''')

    def test_targets_require_type_and_vacancy(self):
        self.check('''local t=core.targets(10,0);assert(#t==1 and t[1]==1)
        assert(core.proposal(10,{kind='module',source=0,target=2})==nil)
        world.components[10].CONSTRUCTION.params.modules[1]={name='occupied'}
        assert(core.proposal(10,{kind='module',source=0,target=1})==nil)
        assert(#core.targets(10,0)==0)''')

    def test_bad_numbers_and_no_op_rejected(self):
        self.check('''assert(core.proposal(10,{kind='building',x=0,y=0,z=0,angle=0})==nil)
        for _,x in ipairs({math.huge,-math.huge,0/0,'bad'}) do
            assert(core.proposal(10,{kind='building',x=x,y=0,z=0,angle=0})==nil)
        end
        assert(core.proposal(10,{kind='module',source=0,target=0})==nil)''')

    def test_other_player_protected_neutral_owner_preserved(self):
        self.check('''world.components[10].PLAYER_OWNED.player=88
        assert(core.inspect(10)==nil)
        world.components[10].PLAYER_OWNED=nil
        local p=assert(core.proposal(10,{kind='building',x=1,y=0,z=0,angle=0}))
        assert(p.constructionsToAdd[1].playerEntity==88)''')

    def test_resolve_subentity_and_station_group(self):
        self.check('''for e=10,16 do assert(core.resolveEntity(e)==10) end
        world.components[17]={STATION={}};world.parents[17]=20
        world.components[16].STATION_GROUP.stations={12,17}
        assert(core.resolveEntity(16)==nil);assert(core.resolveEntity(777)==nil)''')

    def test_preview_refuses_dependent_module_loss(self):
        self.check('''local p,_,s=core.proposal(10,{kind='module',source=0,target=1})
        local g=processed(p);g.toAdd[1].construction.params.modules[10]=nil
        assert(core.checkPreview(s,previewData(),g)==false)
        g=processed(p);g.toAdd[1].construction.params.modules[10].variant=2
        assert(core.checkPreview(s,previewData(),g)==false)''')

    def test_preview_accepts_intact_module_configuration(self):
        self.check('''local p,_,s=core.proposal(10,{kind='module',source=0,target=1})
        assert(core.checkPreview(s,previewData(),processed(p))==true)''')

    def test_preview_collision_and_external_demolition_refused(self):
        self.check('''local p,_,s=core.proposal(10,{kind='module',source=0,target=1})
        local d=previewData();d.errorState.messages={'Collision'}
        assert(core.checkPreview(s,d,processed(p))==false)
        d=previewData();d.errorState.critical=true
        assert(core.checkPreview(s,d,processed(p))==false)
        local g=processed(p);g.toRemove[2]=20
        assert(core.checkPreview(s,previewData(),g)==false)''')

    def test_preview_external_child_module_removal_refused(self):
        self.check('''local p,_,s=core.proposal(10,{kind='module',source=0,target=1})
        local g=processed(p);g.toRemove[2]=11
        assert(core.checkPreview(s,previewData(),g)==true)
        world.parents[11]=20
        assert(core.checkPreview(s,previewData(),g)==false)''')

    def test_preview_requires_zero_based_mapping_and_moving_is_free(self):
        self.check('''local p,_,s=core.proposal(10,{kind='module',source=0,target=1})
        local g=processed(p);g.old2new[10]=1
        assert(core.checkPreview(s,previewData(),g)==false)
        local d=previewData();d.costs=20000
        world.components[99].ACCOUNT.balance=-500
        assert(core.checkPreview(s,d,processed(p))==true)
        assert(core.apply(s,receipt(s,p,d),p,function() end))
        local cmd=world.commands[1].cmd
        assert(cmd.playerInitiated==false and cmd.doDust==false)
        assert(cmd.context.player==-1,'setting the player payer still bills moves in the installed engine')
        assert(cmd.proposal.constructionsToAdd[1].playerEntity==99,'free moving must preserve ownership')''')

    def test_changed_or_deleted_building_never_applies(self):
        self.check('''local p,_,s=core.proposal(10,{kind='module',source=0,target=1})
        local checked=receipt(s,p);world.revisions[10][3]=4
        assert(core.apply(s,checked,p,function() error('sent') end)==false)
        world.components[10]=nil
        assert(core.apply(s,checked,p,function() error('sent') end)==false)
        assert(#world.commands==0)''')

    def test_command_success_failure_reported_and_errors_enabled(self):
        self.check('''local p,_,s=core.proposal(10,{kind='module',source=0,target=1})
        local done=false
        assert(core.apply(s,receipt(s,p),p,function(success,e) done=success;assert(e==20) end))
        assert(not done);complete(true);assert(done)
        assert(core.apply(s,receipt(s,p),p,function(success,e) assert(not success and e==nil) end))
        complete(false)''')

    def test_preview_receipt_cannot_authorize_another_destination(self):
        self.check('''local p,_,s=core.proposal(10,{kind='module',source=0,target=1})
        local checked=receipt(s,p)
        local other,_,otherSnapshot=core.proposal(10,{kind='module',source=10,target=11})
        assert(core.apply(otherSnapshot,checked,other,function() error('sent') end)==false)
        assert(core.apply(s,checked,other,function() error('sent') end)==false)
        checked.valid=false
        assert(core.apply(s,checked,p,function() error('sent') end)==false)
        assert(#world.commands==0)''')

    def test_success_result_skips_children_and_accepts_documented_pairs(self):
        self.check('''local p,_,s=core.proposal(10,{kind='module',source=0,target=1})
        local count=0
        for _,entities in ipairs({{11,12,20},{{11,{num={1,0,0}}},{20,{num={1,0,0}}}}}) do
            assert(core.apply(s,receipt(s,p),p,function(success,e)
                assert(success and e==20);count=count+1
            end))
            world.commands[#world.commands].cmd.resultEntities=entities
            complete(true)
        end
        assert(count==2)''')

    def test_success_without_construction_id_still_finishes_callback(self):
        self.check('''local p,_,s=core.proposal(10,{kind='module',source=0,target=1})
        local done=false
        assert(core.apply(s,receipt(s,p),p,function(success,e)
            assert(success and e==nil);done=true
        end))
        world.commands[1].cmd.resultEntities={11,12}
        complete(true);assert(done)''')

    def test_preview_userdata_expires_before_apply_and_refundables_can_be_nil(self):
        self.check('''local p,_,s=core.proposal(10,{kind='module',source=0,target=1})
        local checked
        deliverPreview(function(d,g) checked=core.capturePreview(s,d,g,p) end,p)
        api.gui.construction.getRefundableEntities=function() return nil end
        api.type.Context.new=function() return setmetatable({}, {__newindex=function(t,k,v)
            assert(v~=nil,'native setter must not receive nil');rawset(t,k,v)
        end}) end
        assert(core.apply(s,checked,p,function() end))
        assert(world.commands[1].cmd.proposal==p)''')

    def test_gui_lifecycle_preview_and_async_completion(self):
        self.ui()
        self.check('''assert(windowApi.mounts==nil)
        openMover(10);assert(windowApi.mounts==1)
        chooseModuleTarget()
        click('预览移动');generate();redraw();click('确认移动');redraw()
        assert(#world.commands==1)
        assert(states[6]:old()==true)
        complete(true);redraw();assert(states[1]:old().entity==20)''')

    def test_gui_cancel_and_late_preview_callback(self):
        self.ui()
        self.check('''openMover(10);chooseModuleTarget();click('预览移动')
        local old=toolStack.param
        redraw();click('取消预览');redraw()
        old.onData(previewData(),processed(old.proposal));redraw()
        assert(states[5]:old()==false and #world.commands==0)''')

    def test_gui_module_mode_filters_and_moves_selected_child(self):
        self.ui()
        self.check('''for _,slot in ipairs(world.components[10].CONSTRUCTION.slots) do slot.transf=identity() end
        openMover(10)
        assert(states[2]:old()==0)
        local combo
        for _,n in ipairs(nodes) do
            if n.nodeKind=='ComboBox' and #n.items==1 and n.items[1].value==1 then combo=n end
        end
        assert(combo);combo.onValueChange(1);redraw();click('预览移动')
        local modules=toolStack.param.proposal.constructionsToAdd[1].params.modules
        assert(modules[0]==nil and modules[1].variant==-2 and modules[10]~=nil)
        generate();redraw();click('确认移动');complete(true);redraw()
        assert(#world.commands==1)''')

    def test_localized_module_names(self):
        self.check('''api.res.moduleRep.find=function(name) return 7 end
        api.res.moduleRep.get=function(id) return {description={name='入口建筑'}} end
        assert(core.inspect(10).modules[1].name=='入口建筑')''')

    def test_gui_other_tool_shelves_and_invalidates_preview(self):
        self.ui()
        self.check('''openMover(10);chooseModuleTarget();click('预览移动');generate();redraw()
        assert(states[5]:old())
        toolStack.tool.shelve({},toolStack.param,true);redraw()
        assert(not states[5]:old())''')

    def test_gui_pending_failure_prevents_second_command(self):
        self.ui()
        self.check('''openMover(10);chooseModuleTarget();click('预览移动');generate();redraw()
        local applyFn
        for _,n in ipairs(nodes) do if n.nodeKind=='Button' and n.content.text=='确认移动' then applyFn=n.onClick end end
        applyFn();applyFn();assert(#world.commands==1)
        complete(false);redraw();assert(states[1]:old().entity==10 and not states[6]:old())''')

    def test_resource_structure_and_lua_syntax(self):
        for file in MOD.rglob("*.lua"):
            self.lua.execute("assert(load(...))", file.read_text("utf-8"))
            self.assertFalse(file.read_bytes().startswith(b"\xef\xbb\xbf"))
        for file in MOD.rglob("*.json"):
            json.loads(file.read_text("utf-8"))
        self.lua.execute((MOD / "content/detail_button.res.lua").read_text("utf-8"))
        self.assertEqual(self.lua.eval("data().type"), "react-replacement-config")
        self.assertEqual(self.lua.eval("data().data.filePath"),
                         "xiaom_building_mover::/building_mover.script")
        self.assertEqual(self.lua.eval("data().data.doReplaceFn"), "installDetailButton")
        self.lua.execute((MOD / "content/building_mover.script.lua").read_text("utf-8"))
        self.assertEqual(self.lua.eval("type(data().installDetailButton)"), "function")

    def detail(self):
        self.ui()
        self.check('''entityWindow={
            ActionButtonBar=function(param) return param end,
            makeConfigureOnClickFunction=function(entity)
                return function() world.lastConfigured=entity end
            end,
        }
        -- The engine creates a deferred node instead of calling the body.
        react.CallOriginalRecipe=function(fn,param) return {nodeKind='Recipe',recipeFn=fn,params=param} end
        function renderBar(param) return replacementApi.replacement(param).params end
        replacementApi={ReplaceRecipe=function(original,replacement)
            replacementApi.original=original;replacementApi.replacement=replacement
            replacementApi.count=(replacementApi.count or 0)+1
        end}
        ug_require=function(path)
            if path:find('entity_window_util',1,true) then return entityWindow
            elseif path:find('mover_ui',1,true) then return ui
            elseif path:find('react.lua',1,true) then return react
            else return core end
        end''')
        self.lua.globals().details = self.lua.execute((MOD / "content/detail_button.lua").read_text("utf-8"))
        self.check("details.install(replacementApi)")

    def test_detail_button_immediately_after_configure_preserves_native_bar(self):
        self.detail()
        self.check('''local configure=entityWindow.makeConfigureOnClickFunction(10)
        local original={primaryButtons={{description='Before'},{description='Configure',onClick=configure},{description='After'}},
            secondaryButtons={{description='secondary'}},nextUpFocusRef={marker=123}}
        local bar=renderBar(original)
        assert(#bar.primaryButtons==4 and bar.primaryButtons[3].description=='移动')
        assert(bar.primaryButtons[2].onClick==configure and bar.primaryButtons[4].description=='After')
        assert(#original.primaryButtons==3 and bar.secondaryButtons==original.secondaryButtons)
        assert(bar.nextUpFocusRef==original.nextUpFocusRef)
        configure();assert(world.lastConfigured==10)
        bar.primaryButtons[3].onClick();assert(windowApi.params.entity==10)''')

    def test_detail_buttons_bind_to_each_window_not_global_selection(self):
        self.detail()
        self.check('''local a=renderBar({primaryButtons={{onClick=entityWindow.makeConfigureOnClickFunction(10)}}})
        local b=renderBar({primaryButtons={{onClick=entityWindow.makeConfigureOnClickFunction(20)}}})
        a.primaryButtons[2].onClick();assert(windowApi.params.entity==10)
        b.primaryButtons[2].onClick();assert(windowApi.params.entity==20)
        a.primaryButtons[2].onClick();assert(windowApi.params.entity==10)''')

    def test_detail_install_once_and_skips_unrelated_or_unavailable_entities(self):
        self.detail()
        self.check('''details.install(replacementApi);assert(replacementApi.count==1)
        local bar=renderBar({primaryButtons={{description='Buy',onClick=function() end}}})
        assert(#bar.primaryButtons==1)
        world.components[10].PLAYER_OWNED.player=88
        local other=renderBar({primaryButtons={{onClick=entityWindow.makeConfigureOnClickFunction(10)}}})
        assert(#other.primaryButtons==1)
        world.components[10]=nil
        assert(ui.open(10)==false)''')

    def test_reopen_mover_changes_target_and_close_cancels_preview(self):
        self.ui()
        self.check('''openMover(10);chooseModuleTarget();click('预览移动');generate();redraw()
        openMover(20);assert(states[1]:old().entity==20 and not states[5]:old())
        assert(states[3]:old()==-1)
        local window=redraw();assert(window.closable)
        window.onClose();assert(windowApi.closed==true and toolStack.tool==nil)''')

    def placement_ui(self):
        self.ui()
        self.check('''function drawPlacement()
            local action=recipes.XiaomBuildingMoverPlacementAction(toolStack.param)
            for _,node in ipairs(action.children) do
                if node.nodeKind=='ConstructionAction' and world.cursor then
                    local proposal,data=nativeBuilderProposal(node.constructionBuilder)
                    node.getProposalStringsFn(proposal,data)
                    assert(data.errorState.critical, 'the native builder must not submit a new construction')
                end
            end
            return recipes.XiaomBuildingMoverPlacementAction(toolStack.param)
        end
        function placementViewer(action)
            for _,node in ipairs(action.children) do
                if node.nodeKind=='ProposalViewer' then return node end
            end
        end
        function acceptPlacement(viewer)
            deliverPreview(viewer.onCreateProposalData,viewer.simpleProposal)
        end''')

    def test_detail_enters_cursor_placement_with_complete_building(self):
        self.placement_ui()
        self.check('''assert(ui.open(10))
        assert(toolStack.param.entity==10 and windowApi.params==toolStack.param)
        local action=drawPlacement();local viewer=assert(placementViewer(action))
        local entry=viewer.simpleProposal.constructionsToAdd[1]
        assert(entry.transf[13]==120 and entry.params.modules[0].variant==-2)
        assert(entry.params.modules[10].variant==1)
        assert(inputActions.constructOpt1 and inputActions.constructRaise)
        acceptPlacement(viewer);action.children[1].onSelect()
        assert(#world.commands==1 and toolStack.param.pending)
        complete(true);assert(toolStack.tool==nil and windowApi.closed)''')

    def test_cursor_late_preview_cannot_place_at_previous_position(self):
        self.placement_ui()
        self.check('''ui.open(10)
        local old=assert(placementViewer(drawPlacement()))
        local session=toolStack.param
        world.cursor.x=130;session.update(world.cursor)
        acceptPlacement(old);assert(not session.valid)
        local latest=assert(placementViewer(drawPlacement()));acceptPlacement(latest)
        world.cursor.x=140;session.place()
        assert(#world.commands==0 and not session.valid)
        acceptPlacement(placementViewer(drawPlacement()));session.place()
        assert(#world.commands==1)
        assert(world.commands[1].cmd.proposal.constructionsToAdd[1].params.modules[0].variant==-2)''')

    def test_cursor_cancel_keeps_original_and_ignores_late_callbacks(self):
        self.placement_ui()
        self.check('''ui.open(10);local session=toolStack.param
        local action=drawPlacement();local old=placementViewer(action)
        action.children[1].onSelectSecondary()
        acceptPlacement(old);session.place()
        assert(not session.active and #world.commands==0 and toolStack.tool==nil)
        assert(world.components[10].CONSTRUCTION.transf[13]==100)''')

    def test_cursor_pending_blocks_repeated_click_and_target_switch(self):
        self.placement_ui()
        self.check('''ui.open(10);local session=toolStack.param
        acceptPlacement(placementViewer(drawPlacement()))
        session.place();session.place();session.cancel()
        assert(not ui.open(20) and #world.commands==1 and session.active)
        complete(false);assert(session.active and not session.pending)
        assert(world.components[10].CONSTRUCTION.transf[13]==100)''')

    def test_cursor_rotation_precision_height_and_source_change(self):
        self.placement_ui()
        self.check('''ui.open(10);local session=toolStack.param
        drawPlacement();inputActions.constructOpt2.handlerFn()
        assert(session.angle==15)
        world.precision=true;inputActions.constructOpt1.handlerFn()
        inputActions.constructRaise.handlerFn()
        assert(session.angle==14 and session.height==0.1)
        local viewer=placementViewer(drawPlacement());acceptPlacement(viewer)
        world.revisions[10][3]=4;session.place()
        assert(#world.commands==0 and not session.pending and not session.valid)''')

    def test_native_snap_pose_retains_original_modules_and_is_owned(self):
        self.placement_ui()
        self.check('''ui.open(10);local session=toolStack.param
        world.nativeTransform=api.type.Mat4f.rotZ(math.pi/2)
        world.nativeTransform:setTransl({x=135,y=225,z=33})
        local viewer=assert(placementViewer(drawPlacement()))
        local entry=viewer.simpleProposal.constructionsToAdd[1]
        assert(entry.transf[13]==135 and entry.transf[14]==225 and entry.transf[15]==33)
        assert(math.abs(entry.transf[2]-1)<1e-8)
        assert(entry.params.modules[0].variant==-2 and entry.params.modules[10].variant==1)
        assert(entry.playerEntity==99 and not entry.autoFillSlots)
        world.nativeTransform[13]=999
        assert(entry.transf[13]==135 and session.snapped[13]==135)
        acceptPlacement(viewer);session.place()
        assert(#world.commands==1 and world.commands[1].cmd.context.player==-1)
        assert(world.commands[1].cmd.proposal.old2new[10]==0)''')

    def test_native_builder_receives_only_declared_user_configuration(self):
        self.placement_ui()
        self.check('''world.components[10].CONSTRUCTION.params.length=4
        world.components[10].CONSTRUCTION.params.cargo=0
        api.res.constructionRep.get=function(id)
            return {params={{key='length'},{key='cargo'},{key='seed'}}}
        end
        ui.open(10);local action=drawPlacement();local builder=action.children[2].constructionBuilder
        assert(builder.params.length==4 and builder.params.cargo==0)
        assert(builder.params.seed==nil and builder.params.year==nil and builder.params.modules==nil)
        assert(builder.params.custom==nil)
        local entry=placementViewer(action).simpleProposal.constructionsToAdd[1]
        assert(entry.params.seed==42 and entry.params.year==1900 and entry.params.custom.level==3)
        assert(entry.params.modules[0].variant==-2)''')

    def test_placement_uses_builtins_declared_by_installed_game(self):
        self.placement_ui()
        self.check('''ui.open(10);drawPlacement()
        recipes.XiaomBuildingMoverPlacementWindow(toolStack.param)''')
        with zipfile.ZipFile(NATIVE_GUI) as archive:
            source = archive.read("gui/main/builtin.lua").decode("utf-8")
        available = set(re.findall(r"builtin\.(\w+)\s*=\s*react\.DeclareBuiltin", source))
        used = {node["nodeKind"] for node in self.lua.globals().nodes.values()}
        self.assertFalse(used - available, f"Unimplemented native builtins: {used - available}")
        self.assertIn("builtin.type.ConstructionAction.ConstructionBuilder =", source)

    def test_native_snap_late_callbacks_and_copied_error_record(self):
        self.placement_ui()
        self.check('''ui.open(10);local session=toolStack.param
        local action=drawPlacement();local builder=action.children[2]
        local proposal=nativeBuilderProposal(builder.constructionBuilder)
        local originalError={critical=false,messages={}}
        local data=setmetatable({}, {
            __index=function(_,key) if key=='errorState' then return clone(originalError) end end,
            __newindex=function(_,key,value) if key=='errorState' then originalError=clone(value) end end,
        })
        session.adjust('angle',15)
        builder.getProposalStringsFn(proposal,data)
        assert(originalError.critical and not session.proposal and not session.valid)
        local current=drawPlacement().children[2]
        session.cancel();current.getProposalStringsFn(proposal,data)
        assert(originalError.critical and not session.active and #world.commands==0)''')

    def test_placement_window_adjustments_work_and_block_while_pending(self):
        self.placement_ui()
        self.check('''ui.open(10);local session=toolStack.param
        recipes.XiaomBuildingMoverPlacementWindow(session)
        click('旋转 +15°');click('升高')
        assert(session.angle==15 and session.height==1)
        local viewer=placementViewer(drawPlacement());acceptPlacement(viewer);session.place()
        local angle,height=session.angle,session.height
        session.adjust('angle',15);session.adjust('height',1)
        assert(session.angle==angle and session.height==height and #world.commands==1)''')

    def test_cursor_off_map_clears_preview_and_switching_tool_cancels(self):
        self.placement_ui()
        self.check('''ui.open(10);local session=toolStack.param
        acceptPlacement(placementViewer(drawPlacement()))
        world.cursor=nil;session.update(nil)
        assert(not session.valid and session.proposal==nil)
        session.place();assert(#world.commands==0)
        toolStack.tool.shelve({},session,true)
        assert(not session.active and toolStack.tool==nil)''')

    def test_cursor_status_opens_same_buildings_module_controls(self):
        self.placement_ui()
        self.check('''ui.open(10);local session=toolStack.param
        recipes.XiaomBuildingMoverPlacementWindow(session)
        click('移动单个模块');assert(not session.active and toolStack.tool==nil)
        assert(windowApi.params.entity==10)
        redraw();for _,fn in ipairs(stepFns) do fn() end;redraw()
        chooseModuleTarget();click('预览移动');generate();redraw();click('确认移动')
        assert(#world.commands==1 and world.commands[1].cmd.playerInitiated==false)''')


class NativeRecipeTests(unittest.TestCase):
    """Run TF3's shipped React registration code; replace only C++ contexts.

    These checks cover deferred nodes, original calls, replacement dispatch and
    wrapper metadata. They do not claim to run the native C++ renderer.
    """

    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        self.lua.globals().core = self.lua.execute((MOD / "content/mover_core.lua").read_text("utf-8"))
        self.lua.execute(UI_MOCK)
        self.lua.execute(r'''
        mockReact=react
        _react={builtin={WithComponentParams=1},recipes={},recipeMetas={},
            originalRecipeFn={},recipeReplace={},tools={},extensionPoints={},
            recipeReplacementAllowed=true}
        nativeIds={};nativeNodes={};local nextRecipe=100
        log={verbose=function() end,warning=function() end,error=error}
        require=function() return {format=function(s) return s end} end
        ug_require=function() return {} end
        api.gui.react={
            params={builtin={WithComponentParams={new=function() return {} end}}},
            detail={IAHandle={new=function() return {} end},makeRecipeId=function(name)
                nextRecipe=nextRecipe+1;nativeIds[name]=nextRecipe;return nextRecipe
            end},
            fireEvent=function() end,
        }
        ''')
        with zipfile.ZipFile(NATIVE_GUI) as archive:
            self.lua.globals().react = self.lua.execute(archive.read("gui/main/react.lua").decode("utf-8"))
        self.lua.execute(r'''
        builtin={type={Orientation={Horizontal=1,Vertical=2},
            ConstructionAction={ConstructionBuilder={new=function() return {} end}}}}
        for id,name in ipairs({'BoxLayout','TextView','Button','ActionDescriptor',
            'ProposalViewer','Selector','Window','ComboBox','ComboBoxItem','ConstructionAction'}) do
            _react.builtin[name]=id+1
            builtin[name]=react.DeclareBuiltin(name,function() end)
        end
        entityWindow={
            ActionButtonBar=react.RegisterRecipe('ActionButtonBar',function(param)
                return builtin.BoxLayout{children={}}
            end),
            makeConfigureOnClickFunction=function(entity) return function() end end,
        }
        replacementApi={ReplaceRecipe=react.GloballyReplaceRecipeBeforeInitInternal}
        ug_require=function(path)
            if path:find('entity_window_util',1,true) then return entityWindow
            elseif path:find('mover_ui',1,true) then return ui
            elseif path:find('mover_placement',1,true) then return placement
            elseif path:find('react.lua',1,true) then return react
            elseif path:find('builtin.lua',1,true) then return builtin
            elseif path:find('game_react_globals',1,true) then return globals
            else return core end
        end
        function transformRecipe(recipeId,param)
            local ctx={}
            function ctx:makeNodeWithProps(id,key,props)
                local node=#nativeNodes+1
                nativeNodes[node]={recipeId=id,props=props};return node
            end
            function ctx:checkRecipeMatch(node,id)
                assert(nativeNodes[node].recipeId==id,'Wrapper child mismatch')
                return true
            end
            function ctx:setResult(result) self.result=result end
            function ctx:declareState(v) return mockReact.useState(v) end
            function ctx:declareRef(v) return mockReact.useRef(v) end
            function ctx:onStep(fn) mockReact.onStep(fn) end
            function ctx:onStepTimer(fn) mockReact.onStepTimer(fn) end
            function ctx:onUnmount(fn) mockReact.onUnmount(fn) end
            function ctx:useComponentInternals()
                return {setInputActionConfig=function(_,id,cfg) inputActions[id]=cfg end}
            end
            _react.recipes[recipeId](ctx,{props=table.pack(param)})
            assert(#ctx.result==1)
            local child=nativeNodes[ctx.result[1]]
            if not _react.recipeMetas[recipeId] then
                assert(child.recipeId==_react.builtin.BoxLayout,
                    'Recipe child must be a layout')
            end
            return child
        end
        ''')
        self.lua.globals().placement = self.lua.execute((MOD / "content/mover_placement.lua").read_text("utf-8"))
        self.lua.globals().ui = self.lua.execute((MOD / "content/mover_ui.lua").read_text("utf-8"))
        self.lua.globals().details = self.lua.execute((MOD / "content/detail_button.lua").read_text("utf-8"))
        self.lua.execute("details.install(replacementApi)")

    def test_native_original_call_is_deferred_and_wrapper_targets_original_bar(self):
        self.lua.execute('''
        local id=nativeIds.XiaomBuildingMoverActionBar
        local originalId=react.GetRecipeId(entityWindow.ActionButtonBar)
        assert(_react.recipeMetas[id].innerRecipeId==originalId)
        local configure=entityWindow.makeConfigureOnClickFunction(10)
        local action=transformRecipe(id,{primaryButtons={{onClick=configure}}})
        assert(action.recipeId==originalId)
        local param=action.props.props[1]
        assert(#param.primaryButtons==2 and param.primaryButtons[2].description=='移动')
        assert(param.primaryButtons[1].onClick==configure)
        assert(transformRecipe(originalId,param).recipeId==_react.builtin.BoxLayout)
        assert(_react.recipeReplace[originalId]~=nil)
        assert(transformRecipe(id,{}).recipeId==originalId)
        local parent=react.RegisterRecipe('DetailParent',function(p)
            return builtin.BoxLayout{children={entityWindow.ActionButtonBar(p)}}
        end)
        local layout=transformRecipe(react.GetRecipeId(parent),{primaryButtons={{onClick=configure}}})
        local replacement=nativeNodes[layout.props.props[1].children[1]]
        assert(replacement.recipeId==id)
        local original=transformRecipe(replacement.recipeId,replacement.props.props[1])
        assert(original.recipeId==originalId)
        ''')

    def test_native_window_and_preview_wrap_correct_builtin(self):
        self.lua.execute('''
        local windowId=nativeIds.XiaomBuildingMoverWindow
        local previewId=nativeIds.XiaomBuildingMoverPreview
        assert(_react.recipeMetas[windowId].innerRecipeId==_react.builtin.Window)
        assert(_react.recipeMetas[previewId].innerRecipeId==_react.builtin.ActionDescriptor)
        assert(ui.openModules(10))
        local window=transformRecipe(windowId,windowApi.params)
        assert(window.recipeId==_react.builtin.Window)
        assert(window.props.props[1].title=='移动单个模块 · 免费')
        local p,_,s=core.proposal(10,{kind='building',x=1,y=0,z=0,angle=0})
        local preview=transformRecipe(previewId,{proposal=p,snapshot=s,serial=1,onData=function() end})
        assert(preview.recipeId==_react.builtin.ActionDescriptor)
        local viewer=nativeNodes[preview.props.props[1].children[1]]
        assert(viewer.recipeId==_react.builtin.ProposalViewer)
        assert(viewer.props.props[1].simpleProposal==p)
        ''')

    def test_reproduces_previous_registration_error(self):
        # A negative control: the old registrations must fail the same layout
        # contract even though each returned node itself is well-formed.
        self.lua.execute('''
        react.RegisterRecipe('BrokenActionBar',function(param)
            return react.CallOriginalRecipe(entityWindow.ActionButtonBar,param)
        end)
        react.RegisterRecipe('BrokenWindow',function() return builtin.Window{} end)
        react.RegisterRecipe('BrokenPreview',function() return builtin.ActionDescriptor{} end)
        for _,name in ipairs({'BrokenActionBar','BrokenWindow','BrokenPreview'}) do
            local ok,err=pcall(transformRecipe,nativeIds[name],{})
            assert(not ok and tostring(err):find('Recipe child must be a layout',1,true))
        end
        ''')

    def test_native_placement_action_and_status_use_matching_wrappers(self):
        self.lua.execute('''
        local actionId=nativeIds.XiaomBuildingMoverPlacementAction
        local statusId=nativeIds.XiaomBuildingMoverPlacementWindow
        assert(_react.recipeMetas[actionId].innerRecipeId==_react.builtin.ActionDescriptor)
        assert(_react.recipeMetas[statusId].innerRecipeId==_react.builtin.Window)
        assert(ui.open(10))
        local action=transformRecipe(actionId,toolStack.param)
        assert(action.recipeId==_react.builtin.ActionDescriptor)
        local children=action.props.props[1].children
        assert(nativeNodes[children[1]].recipeId==_react.builtin.Selector)
        assert(nativeNodes[children[2]].recipeId==_react.builtin.ConstructionAction)
        local builder=nativeNodes[children[2]].props.props[1]
        assert(builder.inputActions.constructOpt1=='rotation')
        assert(builder.inputActions.constructRaise=='raiseOrLower')
        local proposal,data=nativeBuilderProposal(builder.constructionBuilder)
        builder.getProposalStringsFn(proposal,data)
        assert(data.errorState.critical)
        local updated=transformRecipe(actionId,toolStack.param)
        assert(nativeNodes[updated.props.props[1].children[3]].recipeId==_react.builtin.ProposalViewer)
        assert(inputActions.IA_APPLY)
        assert(transformRecipe(statusId,toolStack.param).recipeId==_react.builtin.Window)
        ''')


if __name__ == "__main__":
    unittest.main(verbosity=2)
