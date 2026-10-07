local react=ug_require "::/gui/main/react.lua"
local builtin=ug_require "::/gui/main/builtin.lua"
local globals=ug_require "::/gui/main/game_react_globals.tl"
local manager=ug_require "::/gui/line_vehicle_mgmt/manager_window.tl"
local control=ug_require "xiaom_auto_line_names::/naming_controller.lua"
local U=ug_require "xiaom_auto_line_names::/naming_util.lua"
local M={}
local function text(s) return builtin.TextView{text=tostring(s or ""),useUnicodeCompatibilityFont=true} end
local function button(key,fn,enabled,id)
    return builtin.Button{meta={id=id,enabled=enabled ~= false},content=text(control.text(key)),onClick=fn}
end
local Window
Window=react.RegisterWrapperRecipe("XiaomLineNamingPreview",builtin.Window,function()
    local refresh=react.useState("")
    react.onStepTimer(function()
        if refresh:hasExpired() then return end
        local value=control.read(); local sig=U.signature(value)
        if sig ~= refresh:old() then refresh:set(sig) end
    end,0.25,false)
    local value=control.read(); if not value then return nil end
    local session=value.session; local busy=value.key == "applying"
    local function close() if busy then return end; control.close(); globals.getDefaultWindowApi().removeAllWindows(Window) end
    local rows={builtin.Row{cells={text(control.text("old")),text(control.text("new"))}}}
    for _,row in ipairs(value.rows) do rows[#rows+1]=builtin.Row{cells={text(row.oldName),text(row.reason and control.text(row.reason) or row.name)}} end
    if #value.rows == 0 then rows[#rows+1]=builtin.Row{cells={text(control.text(value.key == "working" and "working" or "empty")),text("")}} end
    return builtin.Window{
        id="xiaom-line-naming-preview",title=control.text("preview"),movable=true,closable=not busy,initialX=90,initialY=90,onClose=close,
        content=builtin.BoxLayout{orientation=builtin.type.Orientation.Vertical,children={
            builtin.BoxLayout{orientation=builtin.type.Orientation.Horizontal,children={
                builtin.ComboBox{meta={enabled=not busy},value=session.all and "all" or "selected",items={
                    builtin.ComboBoxItem{value="selected",content=text(control.text("selected")),available=#session.ids>0},
                    builtin.ComboBoxItem{value="all",content=text(control.text("all"))}},onValueChange=function(v) control.set("all",v == "all") end},
                builtin.CheckBox{meta={id="xiaom-line-naming-include",enabled=not busy},label=control.text("include"),value=session.include and 1 or 0,onValueChange=function(v) control.set("include",v == 1) end},
                button("refresh",control.preview,not busy),
            }},
            builtin.TableLayout{columnWeights={1,1},rows=rows},
            builtin.BoxLayout{orientation=builtin.type.Orientation.Horizontal,children={
                button("previous",function() control.page(-1) end,session.page>1),text(session.page .. " / " .. (value.pages or 1)),
                button("next",function() control.page(1) end,session.page<(value.pages or 1)),
                text(value.eligible .. " / " .. value.total),
            }},
            text(value.message),text(control.text("configNote")),
            builtin.BoxLayout{orientation=builtin.type.Orientation.Horizontal,children={
                button("confirm",control.commit,value.key == "preview" and value.eligible>0,"xiaom-line-naming-confirm"),
                button("reload",control.reload,not busy,"xiaom-line-naming-reload"),button("close",close,not busy),
            }},
        }},
    }
end)
function M.open(ids)
    control.open(ids)
    local windows=globals.getDefaultWindowApi()
    windows.addSingletonWindow(Window,{}); windows.moveSingletonWindowToFront(Window)
end
local original=manager.ManagerWindowContent
local Wrapper=react.RegisterRecipe("XiaomLineNamingManager",function(param)
    local function selected()
        local state=param.toolParam.lineManagerStateRef:get(); local ids={}
        for _,item in ipairs(state.lineListEntitiesSelected or {}) do ids[#ids+1]=item.entity end
        return ids
    end
    return builtin.BoxLayout{orientation=builtin.type.Orientation.Vertical,children={
        builtin.BoxLayout{orientation=builtin.type.Orientation.Horizontal,children={
            button("bulk",function() M.open(selected()) end,true,"xiaom-line-naming-bulk"),
            button("reload",function() M.open(selected()); control.reload() end,true,"xiaom-line-naming-toolbar-reload"),
        }},
        -- Preserve the native component/layout root distinction.
        builtin.Component{layout=builtin.BoxLayout{orientation=builtin.type.Orientation.Vertical,children={react.CallOriginalRecipe(original,param)}}},
    }}
end)
local installed
function M.install(api)
    if installed then return end
    api.ReplaceRecipe(original,Wrapper); installed=true
    U.report("line manager naming actions registered")
end
return M
