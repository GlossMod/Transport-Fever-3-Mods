-- Read-only planning and owned native proposals. No world commands in this module.
local core = {}
-- Native Lua exceptions can be tables. tostring(table) discards the actual error.
function core.errorText(value)
    if type(value) == "string" then return value end
    if type(toString) == "function" then
        local ok, formatted = pcall(toString, value)
        if ok and type(formatted) == "string" then return formatted end
    end
    local seen = {}
    local function render(v, depth)
        if type(v) ~= "table" then return tostring(v) end
        if seen[v] then return "<cycle>" end
        if depth > 4 then return "<nested error>" end
        seen[v] = true
        local fields, count = {}, 0
        for key, item in pairs(v) do
            fields[#fields + 1] = tostring(key) .. "=" .. render(item, depth + 1)
            count = count + 1
            if count >= 32 then break end
        end
        table.sort(fields)
        return "{" .. table.concat(fields, ", ") .. "}"
    end
    return render(value, 0)
end

function core.protect(fn, ...)
    local result = table.pack(xpcall(fn, function(err)
        local message = core.errorText(err)
        return core.errorText(debug.traceback(message, 2))
    end, ...))
    -- Native exceptions can bypass Lua's xpcall handler and arrive as tables.
    -- Normalize at the boundary, not only inside the Lua error handler.
    if not result[1] then result[2] = core.errorText(result[2]) end
    return table.unpack(result, 1, result.n)
end

local function call(stage, fn, ...)
    local result = table.pack(core.protect(fn, ...))
    if not result[1] then error(stage .. ": " .. core.errorText(result[2]), 0) end
    return table.unpack(result, 2, result.n)
end

function core.apiSummary()
    local fields = {}
    for _, name in ipairs({"SegmentAndEntity", "Proposal", "Context", "LayerConfig"}) do
        local ok, constructor = pcall(function()
            local record = api.type[name]
            return record and record.new
        end)
        fields[#fields + 1] = "api.type." .. name .. ".new=" .. (ok and type(constructor) or "unavailable")
    end
    return table.concat(fields, "; ")
end

local function newRecord(name)
    -- Type declares Proposal.SegmentAndEntity but exports its runtime factory
    -- directly as api.type.SegmentAndEntity, not below api.type.Proposal.
    local record = api.type[name]
    if not record or type(record.new) ~= "function" then
        error("required constructor api.type." .. name .. ".new unavailable; " .. core.apiSummary(), 0)
    end
    return record.new()
end
local supported = {
    ACTION_STREET_BUILDER_UPGRADER = "street",
    ACTION_TRACK_BUILDER_UPGRADER = "track",
    ACTION_BUS_LANE_TOOL = "street",
    ACTION_TRAM_TRACK_TOOL = "street",
    ACTION_PLAYER_OWNED_TOOL = "street",
    ACTION_TRACK_ELECTRIFICATION_TOOL = "track",
    ACTION_TRACK_EDGE_DECORATION_TOOL = "decoration",
}

function core.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = core.copy(v) end
    return result
end

function core.component(entity, name)
    if type(entity) ~= "number" or entity < 0 or not api.engine.entityExists(entity) then return nil end
    local kind = api.type.ComponentType[name]
    if not kind then return nil end
    return api.engine.getComponent(entity, kind)
end

function core.template(name)
    if not name or name == "" then return nil end
    local id = api.res.streetTemplateRep.find(name)
    if not id or id < 0 then return nil end
    return api.res.streetTemplateRep.get(id), api.res.streetTemplateRep.getName(id)
end

local function hasTag(tags, wanted)
    for _, tag in ipairs(tags or {}) do if tag == wanted then return true end end
    return false
end

function core.network(definition)
    local network = definition and supported[definition.action]
    if network ~= "decoration" then return network end
    local custom = definition.customAction and definition.customAction.customParam
    if custom and custom.network then return custom.network end
    local decoration = api.res.edgeDecorationRep.get(definition.resIndex)
    if not decoration then return nil end
    if hasTag(decoration.requiredTags, "street") then return "street" end
    if hasTag(decoration.requiredTags, "track") then return "track" end
    for _, category in ipairs(definition.menuCategory and definition.menuCategory.categories or {}) do
        if (category.category or ""):find("road", 1, true) then return "street" end
    end
    return "track"
end

function core.enabled(definition, params)
    if not core.network(definition) or not params or params.xiaom_connected_network ~= 2 then return false end
    if definition.action == "ACTION_STREET_BUILDER_UPGRADER" then return params.mode_street == 3 end
    if definition.action == "ACTION_TRACK_BUILDER_UPGRADER" then return params.mode == 2 end
    return true
end

function core.matches(edge, network)
    local types = api.type["enum"].RoadType
    return edge and edge.roadType == (network == "track" and types.TRACK or types.STREET)
end

-- Only parameters used by these tools belong in a target identity. Height,
-- search text, hover state and the underground visibility layer are not edits.
local editKeys = {"overrideLaneConfigs", "busLane", "tramTrack", "tramOnlyRoadCatenary", "ownStreet", "catenary", "symmetricLanes"}
function core.intent(definition, params, invert, side)
    local result = {
        action = definition.action, network = core.network(definition),
        resource = definition.resName, decoration = definition.resIndex,
        name = definition.name, invert = invert == true and definition.action ~= "ACTION_TRACK_BUILDER_UPGRADER", side = side == true,
        params = {},
        labels = {},
    }
    local key = {result.action, tostring(result.resource), tostring(result.decoration), tostring(result.invert), tostring(result.side)}
    for _, k in ipairs(editKeys) do
        result.params[k] = params[k]
        key[#key + 1] = k .. "=" .. tostring(params[k])
    end
    for _, spec in ipairs(definition.params or {}) do
        local value = result.params[spec.key]
        if value ~= nil and spec.values and spec.values[value] then
            local label = spec.values[value]
            if spec.name and spec.name ~= "" then label = spec.name .. ": " .. label end
            result.labels[#result.labels + 1] = label
        end
    end
    result.key = table.concat(key, "|")
    return result
end

function core.revision(entity)
    if not api.engine.entityExists(entity) then return nil end
    local n = api.engine.getRevision(entity).num
    return {n[1], n[2], n[3]}
end

function core.unchanged(entity, revision)
    local n = core.revision(entity)
    return n and revision and n[1] == revision[1] and n[2] == revision[2] and n[3] == revision[3]
end

local function vec(v) return {v.x, v.y, v.z} end
local function vecEqual(a, b)
    return math.abs(a[1] - b.x) < 0.0001 and math.abs(a[2] - b.y) < 0.0001 and math.abs(a[3] - b.z) < 0.0001
end
function core.geometry(edge)
    return {node0 = edge.node0, node1 = edge.node1, p0 = vec(edge.position0), p1 = vec(edge.position1),
        t0 = vec(edge.tangent0), t1 = vec(edge.tangent1), type = edge.type, typeIndex = edge.typeIndex, roadType = edge.roadType}
end

function core.sameGeometry(shape, edge)
    return edge and shape.node0 == edge.node0 and shape.node1 == edge.node1
        and shape.type == edge.type and shape.typeIndex == edge.typeIndex and shape.roadType == edge.roadType
        and vecEqual(shape.p0, edge.position0) and vecEqual(shape.p1, edge.position1)
        and vecEqual(shape.t0, edge.tangent0) and vecEqual(shape.t1, edge.tangent1)
end

function core.neighbors(node, network)
    local system = api.engine.system.streetSystem
    return network == "track" and system.getNodeTrackSegments(node) or system.getNodeStreetSegments(node)
end

local function modes(lane) return lane.transportModes or {} end
local function vehicleLane(lane)
    local m, t = modes(lane), api.type["enum"].TransportMode
    return m[t.CAR] or m[t.BUS] or m[t.TRUCK] or m[t.TRAM] or m[t.ELECTRIC_TRAM] or m[t.TRAM_TRACK] or m[t.ELECTRIC_TRAM_TRACK]
end
local function laneCopies(lanes)
    local result = {}
    for _, lane in ipairs(lanes or {}) do
        result[#result + 1] = {speed = lane.speed, width = lane.width, height = lane.height,
            forward = lane.forward, offset = lane.offset, transportModes = core.copy(modes(lane))}
    end
    return result
end
local function lanesEqual(a, b)
    if #a ~= #b then return false end
    for i, x in ipairs(a) do
        local y = b[i]
        for _, k in ipairs({"speed", "width", "height", "forward", "offset"}) do if x[k] ~= y[k] then return false end end
        for k, v in pairs(modes(x)) do if not not v ~= not not modes(y)[k] then return false end end
        for k, v in pairs(modes(y)) do if not not v ~= not not modes(x)[k] then return false end end
    end
    return true
end

-- Choose the curb lane in each requested travel direction using the installed
-- template's busAndTramRight setting. Side is captured at the initial click.
local function selectedLanes(lanes, template, symmetric, side)
    local result = {}
    for _, direction in ipairs({true, false}) do
        if symmetric or direction == not side then
            local selected
            for i, lane in ipairs(lanes) do
                if vehicleLane(lane) and lane.forward == direction then
                    if not selected then selected = i
                    else
                        local right = template.busAndTramRight ~= false
                        local outward = direction == right
                        if outward and lane.offset > lanes[selected].offset or not outward and lane.offset < lanes[selected].offset then selected = i end
                    end
                end
            end
            if selected then result[#result + 1] = selected end
        end
    end
    return result
end

local function changeBus(lanes, template, enabled, symmetric, side)
    local t = api.type["enum"].TransportMode
    local selected = selectedLanes(lanes, template, symmetric, side)
    if #selected == 0 then return false end
    for _, i in ipairs(selected) do
        local m = lanes[i].transportModes
        if enabled then
            m[t.CAR], m[t.TRUCK], m[t.BUS] = false, false, true
        else
            local reference
            for _, lane in ipairs(template.laneConfigs) do
                if vehicleLane(lane) and lane.forward == lanes[i].forward then reference = lane; break end
            end
            for _, mode in ipairs({t.CAR, t.TRUCK, t.BUS}) do m[mode] = reference and not not modes(reference)[mode] or false end
        end
    end
    return true
end

local function changeTram(lanes, template, tramType, symmetric, side)
    local t = api.type["enum"].TransportMode
    local selected = selectedLanes(lanes, template, symmetric, side)
    if #selected == 0 then return false end
    for _, i in ipairs(selected) do
        local m = lanes[i].transportModes
        if tramType == 0 and not (m[t.CAR] or m[t.BUS] or m[t.TRUCK]) then return false end
        local hasTrackModes = m[t.TRAM_TRACK] or m[t.ELECTRIC_TRAM_TRACK]
        m[t.TRAM], m[t.ELECTRIC_TRAM] = tramType > 0, tramType == 2
        -- Stock street lanes use TRAM/ELECTRIC_TRAM. Do not introduce the
        -- separate track modes into them; preserve that family where present.
        if hasTrackModes then m[t.TRAM_TRACK], m[t.ELECTRIC_TRAM_TRACK] = tramType > 0, tramType == 2 end
    end
    return true
end

local function decorationsEqual(a, b)
    if #a ~= #b then return false end
    for i, x in ipairs(a) do if x[1] ~= b[i][1] or x[2] ~= b[i][2] then return false end end
    return true
end

local function copyDecorations(entries)
    local result = {}
    for _, entry in ipairs(entries or {}) do result[#result + 1] = {entry[1], entry[2]} end
    return result
end

local function defaultDecorations(template)
    local result = {}
    for _, entry in ipairs(template.defaultEdgeDecorations or {}) do
        local id = api.res.edgeDecorationRep.find(entry[1])
        if not id or id < 0 then return nil end
        result[#result + 1] = {id, entry[2]}
    end
    return result
end

local function constructionLocked(entity, original)
    local system = api.engine.system.streetConnectorSystem
    local connector = system.getConstructionEntityForEdge(entity)
    -- The owning construction may be a subconstruction, not a CONSTRUCTION
    -- component on this exact entity. Any nonnegative owner locks this edge.
    if connector and connector >= 0 then return true end
    for _, node in ipairs({original.node0, original.node1}) do
        local parent = system.getConstructionEntityForNode(node)
        if parent and parent >= 0 then
            if core.component(parent, "SUBCONSTRUCTION") then parent = system.getConstructionEntityForSubconstruction(parent) end
            local construction = core.component(parent, "CONSTRUCTION")
            for _, frozen in ipairs(construction and construction.frozenEdges or {}) do
                if frozen == entity then return true end
            end
        end
    end
    return false
end

local function ownedEdge(original)
    -- Engine API results are read-only, including values reached through them.
    -- Copy into a fresh proposal record before editing its BaseEdge value.
    local segment = newRecord("SegmentAndEntity")
    segment.comp = original
    return segment.comp
end

-- Returns an owned editable component and the target template, or a reason.
function core.transform(entity, intent)
    local original = core.component(entity, "BASE_EDGE")
    if not core.matches(original, intent.network) then return nil, "changed" end
    if constructionLocked(entity, original) then return nil, "locked" end
    local owner = core.component(entity, "PLAYER_OWNED")
    if owner and owner.player >= 0 and owner.player ~= api.engine.util.getPlayer() then return nil, "ownership" end
    local source, sourceName = core.template(original.roadTemplate)
    if not source then return nil, "resource" end
    local edge = call("copy BaseEdge to owned segment entity=" .. tostring(entity)
        .. " source=" .. tostring(sourceName), ownedEdge, original)
    local targetName = sourceName
    local params, action = intent.params, intent.action
    local templateEdit = action == "ACTION_TRACK_BUILDER_UPGRADER" or action == "ACTION_STREET_BUILDER_UPGRADER"
    if templateEdit then targetName = intent.resource end
    if action == "ACTION_TRACK_ELECTRIFICATION_TOOL" then
        local t = api.type["enum"].TransportMode
        local electric = false
        for _, lane in ipairs(original.laneConfigs) do if modes(lane)[t.ELECTRIC_TRAIN] then electric = true end end
        if electric == not intent.invert then return nil, "unchanged" end
        if intent.invert then targetName = source.catenaryRemove else targetName = source.catenaryAdd end
        if not targetName or targetName == "" then return nil, "resource" end
    end
    local template, canonicalName = core.template(targetName)
    if not template or template.roadType ~= original.roadType then return nil, "resource" end
    targetName = canonicalName
    local styleId = api.res.streetStyleRep.find(template.streetStyle)
    if not styleId or styleId < 0 then return nil, "resource" end
    local lanes = laneCopies(original.laneConfigs)
    if targetName ~= original.roadTemplate or templateEdit then
        local targetLanes = laneCopies(template.laneConfigs)
        if action == "ACTION_TRACK_ELECTRIFICATION_TOOL" then
            -- Electrification changes the mapped template and electric modes,
            -- keeping custom speeds, offsets and all unrelated lane settings.
            local t = api.type["enum"].TransportMode
            local targetElectric = false
            for _, lane in ipairs(targetLanes) do if modes(lane)[t.ELECTRIC_TRAIN] then targetElectric = true end end
            if targetElectric ~= not intent.invert then return nil, "incompatible" end
            targetLanes = lanes
            for _, lane in ipairs(targetLanes) do
                if modes(lane)[t.TRAIN] or modes(lane)[t.ELECTRIC_TRAIN] then lane.transportModes[t.ELECTRIC_TRAIN] = targetElectric end
            end
        elseif action == "ACTION_STREET_BUILDER_UPGRADER" and params.overrideLaneConfigs ~= 1 then
            -- Preserve user changes relative to the old template. The target
            -- template still supplies the new lane count, dimensions and speed.
            local sourceLanes = source.laneConfigs
            for _, newLane in ipairs(targetLanes) do
                local nearest, distance
                for i, oldLane in ipairs(lanes) do
                    if oldLane.forward == newLane.forward and vehicleLane(oldLane) and vehicleLane(newLane) then
                        local d = math.abs(oldLane.offset - newLane.offset)
                        if not distance or d < distance then nearest, distance = i, d end
                    end
                end
                if nearest and sourceLanes[nearest] then
                    local oldModes, defaults = modes(lanes[nearest]), modes(sourceLanes[nearest])
                    for _, mode in ipairs({api.type["enum"].TransportMode.CAR, api.type["enum"].TransportMode.BUS,
                        api.type["enum"].TransportMode.TRUCK, api.type["enum"].TransportMode.TRAM,
                        api.type["enum"].TransportMode.ELECTRIC_TRAM, api.type["enum"].TransportMode.TRAM_TRACK,
                        api.type["enum"].TransportMode.ELECTRIC_TRAM_TRACK}) do
                        if not not oldModes[mode] ~= not not defaults[mode] then newLane.transportModes[mode] = not not oldModes[mode] end
                    end
                end
            end
        end
        lanes = targetLanes
        if action == "ACTION_STREET_BUILDER_UPGRADER" and intent.invert then
            for _, lane in ipairs(lanes) do if vehicleLane(lane) then lane.forward = not lane.forward end end
        end
        edge.roadTemplate, edge.roadStyle = targetName, api.res.streetStyleRep.getName(styleId)
    end
    local decorations = copyDecorations(original.edgeDecorations)
    if action == "ACTION_STREET_BUILDER_UPGRADER" and params.overrideLaneConfigs == 1 then
        decorations = defaultDecorations(template)
        if not decorations then return nil, "resource" end
    end
    if action == "ACTION_BUS_LANE_TOOL" then
        if not changeBus(lanes, template, not intent.invert, params.symmetricLanes == 2, intent.side) then return nil, "incompatible" end
    elseif action == "ACTION_TRAM_TRACK_TOOL" then
        local tramType = intent.invert and 0 or (params.catenary == 1 and 2 or 1)
        if not changeTram(lanes, template, tramType, params.symmetricLanes == 2, intent.side) then return nil, "incompatible" end
    elseif action == "ACTION_STREET_BUILDER_UPGRADER" then
        if (params.busLane or 0) > 0 and not changeBus(lanes, template, params.busLane == 2, true, intent.side) then return nil, "incompatible" end
        local tram, catenary = params.tramTrack or 0, params.tramOnlyRoadCatenary or 0
        if tram > 0 or catenary > 0 then
            local tramType = (tram == 1 and catenary == 0) and 0 or (tram == 2 or catenary == 1) and 1 or 2
            if not changeTram(lanes, template, tramType, true, intent.side) then return nil, "incompatible" end
        end
    elseif action == "ACTION_PLAYER_OWNED_TOOL" then
        edge.roadDevelopmentLocked = not intent.invert
    elseif action == "ACTION_TRACK_EDGE_DECORATION_TOOL" then
        local decoration = api.res.edgeDecorationRep.get(intent.decoration)
        if not decoration then return nil, "resource" end
        local tags = {[intent.network] = true}
        local edgeType = api.type["enum"].BaseEdgeType
        if original.type == edgeType.BRIDGE then tags.bridge = true end
        if original.type == edgeType.TUNNEL then tags.tunnel = true end
        if #decorations > 0 then tags.decorated = true end
        -- Engine checks still decide climate/other tag compatibility.
        if not intent.invert then
            for _, tag in ipairs(decoration.requiredTags or {}) do
                if (tag == "street" or tag == "track" or tag == "bridge" or tag == "tunnel") and not tags[tag] then return nil, "incompatible" end
            end
            for _, tag in ipairs(decoration.incompatibleTags or {}) do
                if (tag == "street" or tag == "track" or tag == "bridge" or tag == "tunnel") and tags[tag] then return nil, "incompatible" end
            end
        end
        local found, kept = false, {}
        for _, entry in ipairs(decorations) do
            if entry[1] == intent.decoration and (decoration.snapMode == 0 or entry[2] == intent.side) then
                found = true
                if not intent.invert then kept[#kept + 1] = entry end
            else kept[#kept + 1] = entry end
        end
        if not found and not intent.invert then kept[#kept + 1] = {intent.decoration, intent.side} end
        decorations = kept
    end
    edge.laneConfigs, edge.edgeDecorations = lanes, decorations
    local currentOwner = owner and owner.player or -1
    local desiredOwner = currentOwner
    if action == "ACTION_PLAYER_OWNED_TOOL" and edge.roadDevelopmentLocked ~= original.roadDevelopmentLocked
        and not api.gui.game.isMapEditor() then desiredOwner = api.engine.util.getPlayer() end
    if action == "ACTION_STREET_BUILDER_UPGRADER" and (params.ownStreet or 0) > 0 then
        desiredOwner = params.ownStreet == 2 and api.engine.util.getPlayer() or -1
    end
    if edge.roadTemplate == original.roadTemplate and edge.roadStyle == original.roadStyle
        and edge.roadDevelopmentLocked == original.roadDevelopmentLocked
        and lanesEqual(lanes, original.laneConfigs) and decorationsEqual(decorations, original.edgeDecorations)
        and desiredOwner == currentOwner then return nil, "unchanged" end
    return edge, nil, targetName, desiredOwner ~= currentOwner and desiredOwner or nil
end

function core.context()
    local context = api.type.Context.new()
    context.player = api.engine.util.getPlayer()
    local refundable = api.gui.construction.getRefundableEntities()
    if refundable ~= nil then context.refundableEntities = refundable end
    return context
end

local modeNames = {"PERSON", "CARGO", "CAR", "BUS", "TRUCK", "TRAM", "ELECTRIC_TRAM", "TRAIN",
    "ELECTRIC_TRAIN", "AIRCRAFT", "SHIP", "SMALL_AIRCRAFT", "SMALL_SHIP", "HELICOPTER", "TRAM_TRACK", "ELECTRIC_TRAM_TRACK"}
local function edgeSignature(entity, edge)
    local values = {}
    local function add(v) values[#values + 1] = tostring(v) end
    for _, key in ipairs({"node0", "node1", "type", "typeIndex", "roadType", "roadTemplate", "roadStyle", "roadDevelopmentLocked"}) do add(edge[key]) end
    for _, key in ipairs({"position0", "position1", "tangent0", "tangent1"}) do
        local v = edge[key]; add(v.x); add(v.y); add(v.z)
    end
    add(#edge.laneConfigs)
    for _, lane in ipairs(edge.laneConfigs) do
        for _, key in ipairs({"speed", "width", "height", "forward", "offset"}) do add(lane[key]) end
        for _, name in ipairs(modeNames) do add(not not modes(lane)[api.type["enum"].TransportMode[name]]) end
    end
    add(#edge.edgeDecorations)
    for _, item in ipairs(edge.edgeDecorations) do add(item[1]); add(item[2]) end
    add(#edge.objects)
    for _, item in ipairs(edge.objects) do add(item[1]); add(item[2]) end
    local owner = core.component(entity, "PLAYER_OWNED")
    add(owner and owner.player or -1)
    add(api.engine.system.streetConnectorSystem.getConstructionEntityForEdge(entity))
    return table.concat(values, "|")
end

function core.snapshot(entity)
    local edge = core.component(entity, "BASE_EDGE")
    return edge and {entity = entity, revision = core.revision(entity), shape = core.geometry(edge), signature = edgeSignature(entity, edge)} or nil
end

function core.snapshotMatches(snapshot)
    local current = core.snapshot(snapshot.entity)
    -- Revision[1] protects entity identity. Other counters can change while
    -- traffic runs; compare all editable edge data instead of unrelated ECS data.
    return current and current.revision[1] == snapshot.revision[1] and current.signature == snapshot.signature
end

function core.nodeSnapshot(entity, network)
    local node = core.component(entity, "BASE_NODE")
    if not node then return nil end
    local neighbors = {}
    for _, edge in ipairs(core.neighbors(entity, network) or {}) do neighbors[#neighbors + 1] = edge end
    table.sort(neighbors)
    return {entity = entity, revision = core.revision(entity), network = network,
        signature = tostring(node.position.x) .. ":" .. tostring(node.position.y) .. ":" .. tostring(node.position.z) .. "|" .. table.concat(neighbors, ",")}
end

function core.nodeMatches(snapshot)
    local current = core.nodeSnapshot(snapshot.entity, snapshot.network)
    return current and current.revision[1] == snapshot.revision[1] and current.signature == snapshot.signature
end

local nativeFault
local streetFields = {"addedNodes", "addedSegments", "removedSegments", "removedNodes", "edgeObjectsToAdd",
    "new2oldEdgeObjects", "old2newEdgeObjects", "nodeConfigsToAdd", "nodeConfigsToRemove"}

function core.build(entity, intent)
    if nativeFault then return nil, "native", nativeFault end
    local edge, reason, templateName, owner = call("transform", core.transform, entity, intent)
    if not edge then return nil, reason end
    -- The target-template form of this helper triggered StreetTemplate::Get(-1)
    -- in Build 40408. Refresh the existing valid segment only, then apply the
    -- selected edit to an owned proposal, keeping native object/config mappings.
    local ok, native = core.protect(api.engine.util.proposal.replaceSegment, entity)
    if not ok then
        nativeFault = "replaceSegment (source only), entity=" .. tostring(entity) .. " target=" .. tostring(templateName)
            .. ": " .. core.errorText(native)
        return nil, "native", nativeFault
    end
    if not native then return nil, "proposal" end
    local street = {}
    for _, key in ipairs(streetFields) do street[key] = core.copy(native.proposal[key]) end
    local segments = street.addedSegments
    local shape = core.geometry(edge)
    local changed = false
    for i, sourceSegment in ipairs(segments or {}) do
        if core.sameGeometry(shape, sourceSegment.comp) then
            -- The helper may replace signals/stops and update their references.
            -- Preserve those references instead of restoring stale source IDs.
            local objects = {}
            for _, object in ipairs(sourceSegment.comp.objects or {}) do objects[#objects + 1] = {object[1], object[2]} end
            edge.objects = objects
            local segment = call("create replacement segment entity=" .. tostring(entity)
                .. " target=" .. tostring(templateName), newRecord, "SegmentAndEntity")
            segment.entity, segment.type = sourceSegment.entity, sourceSegment.type
            segment.comp = edge
            segment.streetEdge = sourceSegment.streetEdge
            segment.emissionEmitter = sourceSegment.emissionEmitter
            segment.playerOwned = sourceSegment.playerOwned
            if owner ~= nil then
                -- PlayerOwned is a record, not an exported api.type constructor.
                segment.playerOwned = {player = owner}
            end
            segments[i] = segment
            changed = true
            break
        end
    end
    if not changed then return nil, "geometry" end
    -- Do not edit any records read through engine results or clone those locks.
    -- Native constructors own writable values; write complete copied records.
    street.addedSegments = segments
    local proposal = call("create owned Proposal entity=" .. tostring(entity), newRecord, "Proposal")
    proposal.toRemove = core.copy(native.toRemove)
    proposal.old2new = core.copy(native.old2new)
    proposal.toAdd = core.copy(native.toAdd)
    proposal.terrain = native.terrain
    proposal.proposal = street
    return proposal
end

function core.checkProposal(proposal, entity)
    for _, removed in ipairs(proposal.toRemove or {}) do
        if core.component(removed, "CONSTRUCTION") or core.component(removed, "SUBCONSTRUCTION") then
            return false, "buildings", nil
        end
    end
    local before = core.component(entity, "BASE_EDGE")
    if not before then return false, "changed", nil end
    -- Reject any helper result that alters other road segments or topology.
    local street = proposal.proposal
    if #street.removedSegments ~= 1 or street.removedSegments[1].entity ~= entity or #street.addedSegments ~= 1
        or not core.sameGeometry(core.geometry(before), street.addedSegments[1].comp) then return false, "geometry", nil end
    if #(street.removedNodes or {}) > 0 or #(street.addedNodes or {}) > 0 then return false, "geometry", nil end
    -- Original stops/signals must remain or have an explicit native replacement.
    local objects = {}
    for _, object in ipairs(street.addedSegments[1].comp.objects or {}) do objects[object[1]] = true end
    if #(street.addedSegments[1].comp.objects or {}) ~= #(before.objects or {}) then return false, "objects", nil end
    for _, object in ipairs(before.objects or {}) do
        local kept = objects[object[1]]
        for _, replacement in ipairs((street.old2newEdgeObjects or {})[object[1]] or {}) do
            if objects[replacement] then kept = true end
        end
        if not kept then return false, "objects", nil end
    end
    return true
end

function core.prepare(entity, intent)
    local proposal, reason, detail = call("build proposal", core.build, entity, intent)
    if not proposal then return nil, reason, detail end
    local valid, message = call("check proposal", core.checkProposal, proposal, entity)
    if not valid then return nil, message end
    return {snapshot = core.snapshot(entity)}, nil, nil, proposal
end

-- Called synchronously inside ProposalViewer.onCreateProposalData. No borrowed
-- Proposal or ProposalData is retained; only scalar receipt fields leave here.
function core.capturePreview(entity, data, generated)
    local errors = data and data.errorState
    if not errors or errors.critical or #(errors.messages or {}) > 0 then
        return {valid = false, reason = "rejected", detail = errors and table.concat(errors.messages or {}, "; ") or ""}
    end
    local collisions = data.collisionInfo
    if collisions and (#(collisions.buildingEntities or {}) > 0 or #(collisions.removableModules or {}) > 0) then
        return {valid = false, reason = "buildings"}
    end
    if not generated then return {valid = false, reason = "proposal"} end
    local valid, reason = core.checkProposal(generated, entity)
    return {valid = valid, reason = reason, cost = data.costs or 0}
end

return core
