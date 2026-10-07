local U=ug_require "xiaom_auto_line_names::/naming_util.lua"
local C=ug_require "xiaom_auto_line_names::/naming_config.lua"
local Collect=ug_require "xiaom_auto_line_names::/naming_collect.lua"
local Format=ug_require "xiaom_auto_line_names::/naming_format.lua"
local Numbers=ug_require "xiaom_auto_line_names::/naming_numbers.lua"
local ID="xiaom_auto_line_names"
local SOURCE=ID .. "::/auto_line_names.gs"
local BUDGET=64
-- Queues are transient; persistent state contains only plain data.
local R={dirty={},removed={},queue={},front={},queued={},qi=1,fi=1,fallback=0,reviewTime=0}
local function mark(id) R.dirty[tostring(id)]=true end
local function persist(state)
    -- Build 40408 exposes get_native/set_native on this wrapper, but calling
    -- them from the Lua GameScript raises a fatal C++ assertion. Use the plain
    -- table API unconditionally; method presence is not a capability check.
    state:set(R.saved)
    R.dirty={}; R.removed={}; R.previewChanged=false; R.rootDirty=false
end
local function initialize(state)
    if R.saved then return true end
    local player=api.engine.util.getPlayer(); if not player or player < 0 then return false end
    R.saved=state:get() or {}; local s=R.saved
    if state.hasEventSubscriptions and not state:hasEventSubscriptions() then
        for _,name in ipairs({"tick","preview","commit","cancel","reloadConfig"}) do state:subscribeToEvent(name) end
    end
    s.lines=s.lines or {}; s.numbers=s.numbers or {}; s.configRevision=s.configRevision or 1
    if not s.config then local value,err=C.file(); s.config=value or U.copy(C.defaults); s.configError=err end
    if not s.initialized then
        for _,id in ipairs(api.engine.system.lineSystem.getLinesForPlayer(player)) do s.lines[tostring(id)]={managed=false,reason="baseline"}; mark(id) end
        s.initialized=true; U.report("initialized; existing line names preserved")
    end
    local migrated=s.version ~= 2
    if migrated then
        for key,e in pairs(s.lines) do
            if not e.managed and not e.reason then e.reason="manual" end
            e.pendingScans=e.pendingScans or 0; R.dirty[key]=true
        end
    end
    s.version=2; s.stats={processed=0,totalProcessed=0,budget=BUDGET}; s.preview=nil; R.previewChanged=true
    R.discover=true; R.review=migrated or C.options().refresh>0; Collect.refresh()
    -- Read once into the simulation cache, then persist plain snapshots.
    state:set(s); R.dirty={}; R.removed={}; R.previewChanged=false
    return true
end
local function config() if not R.config then R.config=C.effective(R.saved.config) end; return R.config end
local function enqueue(id,review,new)
    local key=tostring(id)
    if R.queued[key] then R.queued[key].review=R.queued[key].review or review; return end
    local item={id=id,review=review}; R.queued[key]=item
    local q=new and R.front or R.queue; q[#q+1]=item
end
local function discover()
    local live={}; local ids=api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer()); table.sort(ids)
    for _,id in ipairs(ids) do local key=tostring(id); live[key]=true; enqueue(id,R.review or false,R.saved.lines[key] == nil) end
    for key in pairs(R.saved.lines) do if not live[key] then R.saved.lines[key]=nil; R.removed[key]=true end end
    R.discover=false; R.review=false; Collect.refresh()
end
local function pop()
    local item=R.front[R.fi]
    if item then R.fi=R.fi+1 else item=R.queue[R.qi]; if item then R.qi=R.qi+1 end end
    if R.fi>#R.front then R.front={}; R.fi=1 end
    if R.qi>#R.queue then R.queue={}; R.qi=1 end
    if item then R.queued[tostring(item.id)]=nil end
    return item
end
local function protect(e) e.managed=false; e.reason="manual"; e.pendingName=nil; e.pendingScans=nil end
local function own(id)
    local e=api.engine.entityExists(id) and api.engine.getComponent(id,api.type.ComponentType.PLAYER_OWNED)
    return e and e.player == api.engine.util.getPlayer()
end
local function info(id,cfg)
    local ok,value=pcall(Collect.info,id,cfg)
    if not ok then
        local key=tostring(id); R.errors=R.errors or {}
        if R.errors[key] ~= tostring(value) then R.errors[key]=tostring(value); U.report("cannot inspect line " .. key .. ": " .. tostring(value)) end
        return nil
    end
    return value
end
local function process(item,cfg,ops)
    local id=item.id; if not own(id) then return end
    local current=Collect.name(id); if not current then return end
    local key=tostring(id); local e=R.saved.lines[key]
    if not e then e={managed=Collect.defaultName(current),lastName=current,reason="manual"}; if e.managed then e.reason=nil end; R.saved.lines[key]=e; mark(id) end
    if (current == "r" or current == "reload") and not e.pendingName then e.managed=true; e.reason=nil; e.lastName=current; item.review=true; mark(id) end
    if e.pendingName then
        if current == e.pendingName then e.lastName=current; e.pendingName=nil; e.pendingScans=nil; mark(id)
        elseif current == e.lastName then
            e.pendingScans=(e.pendingScans or 0)+1; mark(id)
            if e.pendingScans>=4 then e.pendingName=nil; e.pendingScans=nil; item.review=true end
        else protect(e); mark(id) end
    elseif e.managed and current ~= e.lastName then protect(e); mark(id) end
    if current:sub(1,4) == "Cst " and not e.pendingName then protect(e); mark(id) end
    if e.managed and not e.pendingName and (item.review or not e.number) then
        local value=info(id,cfg)
        if value then
            local number=Numbers.assign(e,R.saved.numbers,value.category); mark(id)
            local name=Format.name(value,number,cfg)
            if name ~= current then ops[#ops+1]={entity=id,oldName=current,name=name} end
        end
    end
end
local function token(cfg) return U.signature({config=cfg,numbers=R.saved.numbers,revision=R.saved.configRevision}) end
local function previewRow(id,job)
    local old=Collect.name(id); local entry=R.saved.lines[tostring(id)]
    local row={entity=id,oldName=old or "",name=old or ""}
    local protected=old and (old:sub(1,4) == "Cst " or entry and not entry.managed and (entry.reason ~= "baseline" or not Collect.defaultName(old))
        or not entry and not Collect.defaultName(old))
    if not own(id) then row.reason="incomplete"
    elseif entry and entry.pendingName then row.reason="pending"
    elseif protected and not job.include then row.reason="protected"
    else
        local value=info(id,job.config)
        if value then
            local copy=U.copy(entry or {}); local number=Numbers.assign(copy,job.numbers,value.category)
            row.category=value.category; row.number=number; row.name=Format.name(value,number,job.config)
        else row.reason="incomplete" end
    end
    return row
end
local function previewStep()
    local job=R.previewJob; local count=0
    while job.index<=#job.ids and count<BUDGET do
        local row=previewRow(job.ids[job.index],job); job.rows[#job.rows+1]=row
        if not row.reason then job.eligible=job.eligible+1 end
        job.index=job.index+1; count=count+1
    end
    if job.index>#job.ids then
        R.saved.preview={id=job.id,token=job.token,rows=job.rows,eligible=job.eligible,language=job.config.language}; R.previewChanged=true
        R.saved.status={id=job.id,key="preview"}; R.previewJob=nil; R.rootDirty=true
    end
    return count
end
local function rejectCommit(job) R.saved.status={id=job.id,key="changed"}; R.commit=nil; R.rootDirty=true end
local function commitStep(cfg,ops)
    local job=R.commit; local count=0
    if job.phase == "validate" then
        if job.preview.token ~= token(cfg) then rejectCommit(job); return 0 end
        while job.index<=#job.preview.rows and count<BUDGET do
            local row=job.preview.rows[job.index]
            if not row.reason then
                local value=own(row.entity) and info(row.entity,cfg); local e=R.saved.lines[tostring(row.entity)]
                if not value or Collect.name(row.entity) ~= row.oldName or (e and e.pendingName)
                    or value.category ~= row.category or Format.name(value,row.number,cfg) ~= row.name then rejectCommit(job); return count+1 end
            end
            job.index=job.index+1; count=count+1
        end
        if job.index>#job.preview.rows then job.phase="apply"; job.index=1 end
        return count
    end
    while job.index<=#job.preview.rows and count<BUDGET do
        local row=job.preview.rows[job.index]
        if not row.reason and own(row.entity) and Collect.name(row.entity) == row.oldName then
            local e=R.saved.lines[tostring(row.entity)] or {}
            e.managed=true; e.reason=nil; e.lastName=row.oldName; e.category=row.category; e.number=row.number
            R.saved.lines[tostring(row.entity)]=e; mark(row.entity)
            R.saved.numbers[row.category]=math.max(R.saved.numbers[row.category] or 0,row.number)
            if row.name ~= row.oldName then ops[#ops+1]={entity=row.entity,oldName=row.oldName,name=row.name} end
        end
        job.index=job.index+1; count=count+1
    end
    if job.index>#job.preview.rows then R.saved.status={id=job.id,key="done"}; R.commit=nil; R.saved.preview=nil; R.previewChanged=true end
    return count
end
local function handle(state,src,id,name,param)
    if id ~= ID or src ~= SOURCE or not initialize(state) then return end
    param=type(param) == "table" and param or {}
    if name == "tick" then
        R.guiHeartbeat=true; R.discover=true; R.review=R.review or param.review == true
        return -- Scheduling is transient; a heartbeat does not alter save data.
    elseif name == "preview" and not R.commit then
        local ids=param.all and api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer()) or (type(param.ids) == "table" and param.ids or {})
        local clean,seen={},{}
        for _,entity in ipairs(ids) do if type(entity) == "number" and own(entity) and not seen[entity] then clean[#clean+1]=entity; seen[entity]=true end end
        table.sort(clean); local cfg=config()
        R.previewJob={id=tostring(param.request),ids=clean,index=1,rows={},eligible=0,include=param.include == true,config=cfg,
            token=token(cfg),numbers=U.copy(R.saved.numbers)}
        R.saved.preview=nil; R.previewChanged=true; R.saved.status={id=tostring(param.request),key="working"}
    elseif name == "commit" and not R.commit then
        local p=R.saved.preview
        if p and p.id == tostring(param.request) then R.commit={id=p.id,preview=p,phase="validate",index=1}; R.saved.status={id=p.id,key="applying"} end
    elseif name == "reloadConfig" and not R.commit then
        local value,err=C.file()
        if value then R.saved.config=value; R.saved.configRevision=R.saved.configRevision+1; R.saved.configError=nil
        else R.saved.configError=err; U.report("configuration rejected: " .. err) end
        R.saved.status={id=tostring(param.request),key=value and "imported" or "error",detail=err}
        R.config=nil; R.saved.preview=nil; R.previewChanged=true; R.previewJob=nil; R.discover=true; R.review=true
    elseif name == "cancel" and not R.commit then R.previewJob=nil; R.saved.preview=nil; R.previewChanged=true
    else return end
    persist(state)
end
local function apply(state,operations)
    if not R.saved or not operations then return end
    local ready={}
    for _,op in ipairs(operations) do
        local e=R.saved.lines[tostring(op.entity)]
        if e and e.managed and not e.pendingName and own(op.entity) then
            if Collect.name(op.entity) == op.oldName then e.pendingName=op.name; e.pendingScans=0; mark(op.entity); ready[#ready+1]=op
            else protect(e); mark(op.entity) end
        end
    end
    if #ready>0 or next(R.dirty) then persist(state) end
    for _,op in ipairs(ready) do
        local ok,err=pcall(function() api.cmd.sendCommand(api.cmd.makeEntitySetNameCmd(op.entity,op.name)) end)
        if not ok then U.report("rename command failed: " .. tostring(err)) end
    end
end
local guiLast,guiReview
return {
    update=function(_capture,state,dt)
        if not initialize(state) then return {} end
        R.fallback=R.fallback+math.max(dt or 0,0); R.reviewTime=R.reviewTime+math.max(dt or 0,0)
        local cfg=config()
        if not R.guiHeartbeat and R.fallback>=2 then R.fallback=0; R.discover=true end
        if not R.guiHeartbeat and cfg.refresh>0 and R.reviewTime>=cfg.refresh then R.reviewTime=0; R.review=true; R.discover=true end
        if R.discover and not R.commit then discover() end
        local ops,count={},0
        if R.commit then count=commitStep(cfg,ops)
        elseif R.previewJob then count=previewStep()
        else while count<BUDGET do local item=pop(); if not item then break end; process(item,cfg,ops); count=count+1 end end
        R.saved.stats.processed=count; R.saved.stats.totalProcessed=R.saved.stats.totalProcessed+count
        if count>0 or R.rootDirty or next(R.dirty) or next(R.removed) then persist(state) end
        return ops
    end,
    postUpdate=function(_capture,state,_dt,result) apply(state,result) end,
    handleEvent=function(_capture,state,src,id,name,param) handle(state,src,id,name,param) end,
    guiUpdate=function(_capture,_state,_guiState)
        local now=api.util.getApplicationTime()
        if guiLast and now-guiLast<2 then return end
        local refresh=C.options().refresh
        local review=refresh>0 and (not guiReview or now-guiReview>=refresh)
        guiLast=now; if review then guiReview=now end
        api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd(SOURCE,ID,"tick",{review=review}))
    end,
}
