local C=ug_require "xiaom_auto_line_names::/naming_config.lua"
local I=ug_require "xiaom_auto_line_names::/naming_i18n.lua"
local M={}
local ID=C.modId
local session,sequence
local function send(name,param) api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd(ID .. "::/auto_line_names.gs",ID,name,param or {})) end
local function root()
    local entity=api.engine.system.gameScriptSystem.getEntityForGameScript(ID .. "::/auto_line_names.gs")
    if not entity or entity < 0 or not api.engine.entityExists(entity) then return nil end
    local c=api.engine.getComponent(entity,api.type.ComponentType.GAME_SCRIPT)
    return c and c.state_native
end
function M.language() return I.language(C.options().language) end
function M.text(key) return I.text(M.language(),key) end
function M.open(ids)
    session={ids=ids or {},all=not ids or #ids == 0,include=false,page=1}
    M.preview()
end
function M.preview()
    sequence=(sequence or 0)+1; session.request=tostring(api.util.getApplicationTime()) .. ":" .. sequence
    send("preview",{ids=session.ids,all=session.all,include=session.include,request=session.request})
end
function M.read()
    if not session then return nil end
    local r=root(); local p=r and r:find("preview"); local status=r and r:find("status")
    local key=status and status:find("id") == session.request and status:find("key") or "working"
    local result={rows={},key=key,eligible=0,total=0,session=session}
    if p and p:find("id") == session.request then
        result.eligible=p:find("eligible") or 0
        local rows=p:find("rows"); result.total=rows and rows:size() or 0
        result.pages=math.max(1,math.ceil(result.total/12)); session.page=math.min(session.page,result.pages)
        for index=(session.page-1)*12+1,math.min(session.page*12,result.total) do result.rows[#result.rows+1]=rows:find(index):asTable() end
    end
    result.message=key == "preview" and "" or M.text(key)
    if key == "error" then result.message=result.message .. tostring(status:find("detail")) end
    local err=r and r:find("configError")
    if err and key == "preview" then result.message=M.text("error") .. tostring(err) end
    return result
end
function M.set(key,value) session[key]=value; session.page=1; M.preview() end
function M.page(delta) session.page=math.max(1,session.page+delta) end
function M.commit() send("commit",{request=session.request}) end
function M.reload()
    sequence=(sequence or 0)+1; session.request="config:" .. tostring(api.util.getApplicationTime()) .. ":" .. sequence
    send("reloadConfig",{request=session.request})
end
function M.close() send("cancel"); session=nil end
return M
