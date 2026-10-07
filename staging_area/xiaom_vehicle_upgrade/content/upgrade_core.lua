-- Pure planning functions. Prices are supplied by the native adapter, never
-- estimated from a home-grown depreciation curve.
local core = {}

function core.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = core.copy(v) end
    return result
end

function core.keys(map)
    local result = {}
    for k, v in pairs(map or {}) do if v then result[#result + 1] = k end end
    table.sort(result, function(a, b) return tostring(a) < tostring(b) end)
    return result
end

function core.key(map)
    local values = {}
    for _, k in ipairs(core.keys(map)) do values[#values + 1] = tostring(k) end
    return table.concat(values, ",")
end

function core.available(item, year, restrictions)
    if not item or item.hidden then return false end
    if item.yearFrom > 0 and year < item.yearFrom then return false end
    if item.yearTo > 0 and year >= item.yearTo then return false end
    local filters = restrictions or {}
    if filters.disabled and filters.disabled[item.path] then return false end
    if filters.enabled and next(filters.enabled) and not filters.enabled[item.path] then return false end
    return true
end

function core.purpose(item, parts, context)
    -- Explicit manual configurations remain relevant even when the vehicle is
    -- empty. Automatic compartments may change with the cargo at the next stop.
    local explicit, active, filtered = {}, {}, {}
    for _, part in ipairs(parts) do
        for i, config in ipairs(part.loads or {}) do
            if not (part.auto or {})[i] and config.cargo >= 0 and item.capacities[config.cargo] then
                explicit[config.cargo] = true
            end
        end
    end
    for cargo in pairs(context.active or {}) do
        if item.capacities[cargo] then active[cargo] = true end
    end
    for cargo in pairs(context.filtered or {}) do
        if item.capacities[cargo] then filtered[cargo] = true end
    end
    local result = core.copy(explicit)
    for cargo in pairs(active) do result[cargo] = true end
    for cargo in pairs(filtered) do result[cargo] = true end
    local uncertain = next(result) == nil
    if uncertain then
        for cargo, capacity in pairs(item.capacities) do
            if capacity > 0 then result[cargo] = true end
        end
    end
    return result, uncertain
end

function core.compatible(old, candidate, purpose, year, restrictions)
    if not core.available(candidate, year, restrictions) then return false end
    if candidate.yearFrom <= old.yearFrom then return false end
    if old.carrier ~= candidate.carrier or old.role ~= candidate.role then return false end
    if old.multipleUnit ~= candidate.multipleUnit then return false end
    -- A filter tag describes physical compatibility (e.g. light rail). Power
    -- requirements are separate, and can change with an explicit warning.
    if old.physicalType ~= candidate.physicalType then return false end
    for tag in pairs(old.tags or {}) do
        if not (candidate.tags or {})[tag] then return false end
    end
    for cargo in pairs(purpose) do
        if (candidate.capacities[cargo] or 0) <= 0 then return false end
    end
    return true
end

function core.nonRegressing(old, candidate, purpose)
    local eps = 0.000001
    if candidate.speed + eps < old.speed then return false end
    for cargo in pairs(purpose) do
        if (candidate.capacities[cargo] or 0) < (old.capacities[cargo] or 0) then return false end
    end
    if old.compareTraction and (candidate.power + eps < old.power or candidate.traction + eps < old.traction) then
        return false
    end
    return true
end

local function capacityFor(item, purpose)
    local result = 0
    for cargo in pairs(purpose) do result = result + (item.capacities[cargo] or 0) end
    return result
end

function core.candidates(old, catalog, purpose, year, restrictions)
    local result = {}
    for _, item in ipairs(catalog) do
        if core.compatible(old, item, purpose, year, restrictions) then result[#result + 1] = item end
    end
    table.sort(result, function(a, b)
        if a.yearFrom ~= b.yearFrom then return a.yearFrom > b.yearFrom end
        if a.speed ~= b.speed then return a.speed > b.speed end
        local ca, cb = capacityFor(a, purpose), capacityFor(b, purpose)
        if ca ~= cb then return ca > cb end
        if a.price ~= b.price then return a.price < b.price end
        return a.key < b.key
    end)
    local recommendation
    for _, item in ipairs(result) do
        if core.nonRegressing(old, item, purpose) then recommendation = item.key; break end
    end
    return result, recommendation
end

function core.warnings(old, candidate, purpose)
    local result = {}
    if candidate.speed < old.speed then result[#result + 1] = "最高速度下降" end
    for cargo in pairs(purpose) do
        if (candidate.capacities[cargo] or 0) < (old.capacities[cargo] or 0) then
            result[#result + 1] = "对应货物容量下降"; break
        end
    end
    if candidate.power < old.power then result[#result + 1] = "功率下降" end
    if candidate.traction < old.traction then result[#result + 1] = "牵引力下降" end
    if candidate.electric and not old.electric then
        result[#result + 1] = "需要供电线路／接触网，请确认整条线路已具备条件"
    end
    if candidate.length > old.length + 0.01 then result[#result + 1] = "长度增加，请检查站台／停靠设施" end
    if candidate.physicalModes ~= old.physicalModes then
        result[#result + 1] = "设施要求变化，请检查线路、车库与停靠设施"
    end
    return result
end

-- Find a feasible configuration for simultaneous loads. Adding independent
-- per-cargo maxima is unsafe: a single tank cannot hold two full cargo types.
-- Slots are { options = {{cargo,capacity,loadIndex}}, fixed? = true }.
function core.allocate(slots, demands, maxNodes, coverage)
    local need = {}
    for cargo, amount in pairs(demands or {}) do if amount > 0 then need[cargo] = amount end end
    local chosen, visited = {}, 0
    local limit = maxNodes or 20000
    -- Manual configurations must keep at least one compartment per cargo in
    -- each replaced group, even with no current load. A shared tank alone
    -- cannot preserve two explicitly configured cargo compartments.
    local uncovered = core.copy(coverage or {})
    local function solved()
        for _, amount in pairs(need) do if amount > 0 then return false end end
        for _, cargos in pairs(uncovered) do if next(cargos) then return false end end
        return true
    end
    local suffix = {}
    suffix[#slots + 1] = {}
    for i = #slots, 1, -1 do
        suffix[i] = core.copy(suffix[i + 1])
        local maxima = {}
        for _, option in ipairs(slots[i].options) do
            maxima[option.cargo] = math.max(maxima[option.cargo] or 0, option.capacity)
        end
        for cargo, amount in pairs(maxima) do suffix[i][cargo] = (suffix[i][cargo] or 0) + amount end
    end
    local function search(index)
        visited = visited + 1
        if visited > limit then return false end
        if solved() then return true end
        if index > #slots then return false end
        for cargo, amount in pairs(need) do
            if amount > (suffix[index][cargo] or 0) then return false end
        end
        for scope, cargos in pairs(uncovered) do
            for cargo in pairs(cargos) do
                local possible = false
                for i = index, #slots do
                    if slots[i].scope == scope then
                        for _, option in ipairs(slots[i].options) do
                            if option.cargo == cargo then possible = true; break end
                        end
                    end
                    if possible then break end
                end
                if not possible then return false end
            end
        end
        local required = uncovered[slots[index].scope] or {}
        local options = {}
        for _, option in ipairs(slots[index].options) do
            if (need[option.cargo] or 0) > 0 or required[option.cargo] then options[#options + 1] = option end
        end
        table.sort(options, function(a, b)
            local ua, ub = math.min(need[a.cargo] or 0, a.capacity), math.min(need[b.cargo] or 0, b.capacity)
            if ua ~= ub then return ua > ub end
            if required[a.cargo] ~= required[b.cargo] then return required[a.cargo] == true end
            if a.capacity ~= b.capacity then return a.capacity > b.capacity end
            if a.cargo ~= b.cargo then return a.cargo < b.cargo end
            return a.loadIndex < b.loadIndex
        end)
        for _, option in ipairs(options) do
            local previous = need[option.cargo]
            local manual = required[option.cargo]
            need[option.cargo] = math.max(0, (previous or 0) - option.capacity)
            required[option.cargo] = nil
            chosen[index] = option
            if search(index + 1) then return true end
            chosen[index] = nil
            need[option.cargo] = previous
            required[option.cargo] = manual
        end
        return search(index + 1)
    end
    if search(1) then return chosen end
    return nil, visited > limit and "货物组合较复杂，无法确认装载配置，请简化配置后再升级" or "目标舱室无法同时容纳当前载荷和手动货物配置"
end

function core.quote(snapshot, changes, catalogByKey)
    local retained, purchase, changed = 0, 0, 0
    for _, unit in ipairs(snapshot.units) do
        local key = changes[unit.index]
        if key and key ~= unit.old.key then
            local target = catalogByKey[key]
            if not target then return nil, "目标车型已不可用" end
            purchase = purchase + target.price
            changed = changed + 1
        else
            for _, part in ipairs(unit.parts) do retained = retained + part.value end
        end
    end
    if changed == 0 then return {purchase = 0, refund = 0, net = 0, changed = 0} end
    -- Native Modify cart = new purchase + depreciated retained parts - whole
    -- vehicle refund. Do not refund every part independently (rounding differs).
    local refund = snapshot.depreciated - retained
    return {purchase = purchase, refund = refund, net = purchase - refund, changed = changed}
end

function core.signature(snapshot)
    local result = {tostring(snapshot.entity), tostring(snapshot.line), tostring(snapshot.depot)}
    for _, unit in ipairs(snapshot.units) do
        result[#result + 1] = unit.old.key
        result[#result + 1] = tostring(unit.count)
        for _, part in ipairs(unit.parts) do
            result[#result + 1] = tostring(part.modelId) .. ":" .. tostring(part.purchaseTime) .. ":" .. tostring(part.reversed)
            result[#result + 1] = table.concat(part.color or {}, ",")
            for i, load in ipairs(part.loads) do
                result[#result + 1] = tostring(load.index) .. ":" .. tostring(load.cargo) .. ":" .. tostring((part.auto or {})[i])
            end
        end
    end
    result[#result + 1] = snapshot.filterSignature or ""
    return table.concat(result, "|")
end

-- Explain a signature mismatch without relaxing the checks or logging live
-- userdata addresses. Automatic loading changes must remain distinguishable
-- from edits to the consist and manual cargo settings.
function core.snapshotChange(before, after)
    local function difference(a, b, field, label)
        if a ~= b then return field, label, tostring(a) .. " -> " .. tostring(b) end
    end
    for _, field in ipairs({"entity", "line", "depot", "filterSignature"}) do
        local labels = {entity = "载具身份", line = "分配线路", depot = "车库状态", filterSignature = "线路货物过滤"}
        local code, label, detail = difference(before[field], after[field], field, labels[field])
        if code then return code, label, detail end
    end
    if #before.units ~= #after.units then return "units", "编组数量", #before.units .. " -> " .. #after.units end
    for index, old in ipairs(before.units) do
        local new = after.units[index]
        local prefix = "unit[" .. index .. "]"
        local labelPrefix = "部件组 " .. index .. "："
        if old.old.key ~= new.old.key then return prefix .. ".model", labelPrefix .. "车型", old.old.key .. " -> " .. new.old.key end
        if old.count ~= new.count then return prefix .. ".count", labelPrefix .. "节数", old.count .. " -> " .. new.count end
        if #old.parts ~= #new.parts then return prefix .. ".parts", labelPrefix .. "节数", #old.parts .. " -> " .. #new.parts end
        for partIndex, part in ipairs(old.parts) do
            local current = new.parts[partIndex]
            local partPrefix = prefix .. ".part[" .. partIndex .. "]"
            local partLabel = labelPrefix .. "第 " .. partIndex .. " 节 "
            for _, field in ipairs({"modelId", "purchaseTime", "reversed"}) do
                local labels = {modelId = "车型", purchaseTime = "购买时间", reversed = "朝向"}
                local code, label, detail = difference(part[field], current[field], partPrefix .. "." .. field, partLabel .. labels[field])
                if code then return code, label, detail end
            end
            local code, label, detail = difference(table.concat(part.color or {}, ","), table.concat(current.color or {}, ","),
                partPrefix .. ".color", partLabel .. "颜色")
            if code then return code, label, detail end
            if #part.loads ~= #current.loads then return partPrefix .. ".loads", partLabel .. "舱室数量", #part.loads .. " -> " .. #current.loads end
            for compartment, load in ipairs(part.loads) do
                local actual = current.loads[compartment]
                local loadPrefix = partPrefix .. ".compartment[" .. compartment .. "]"
                local auto = (part.auto or {})[compartment]
                local currentAuto = (current.auto or {})[compartment]
                code, label, detail = difference(auto, currentAuto, loadPrefix .. ".auto", partLabel .. "自动装载开关")
                if code then return code, label, detail end
                local mode = auto and "自动装载" or "手动装载"
                code, label, detail = difference(load.index, actual.index, loadPrefix .. ".loadIndex", partLabel .. mode .. "配置")
                if code then return code, label, detail end
                code, label, detail = difference(load.cargo, actual.cargo, loadPrefix .. ".cargo", partLabel .. mode .. "货物")
                if code then return code, label, detail end
            end
        end
    end
    return "signature", "载具配置签名", tostring(before.signature) .. " -> " .. tostring(after.signature)
end

return core
