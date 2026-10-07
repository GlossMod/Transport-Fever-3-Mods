local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local globals = ug_require "::/gui/main/game_react_globals.tl"
local core = ug_require "xiaom_vehicle_upgrade::/upgrade_core.lua"
local native = ug_require "xiaom_vehicle_upgrade::/upgrade_native.lua"
local controller = ug_require "xiaom_vehicle_upgrade::/upgrade_controller.lua"
local ui = {}
local windowId = "xiaom-vehicle-upgrade-window"

local function text(value, class)
    return builtin.TextView {meta = {class = class}, text = tostring(value), useUnicodeCompatibilityFont = true}
end

local function button(label, onClick, enabled, id, class, tooltip)
    return builtin.Button {meta = {id = id, class = "upgrade-button, " .. (class or "secondary"),
        enabled = enabled ~= false, tooltip = tooltip}, content = text(label), onClick = onClick}
end

local function panel(class, children)
    return builtin.Component {meta = {class = class}, layout = builtin.BoxLayout {
        orientation = builtin.type.Orientation.Vertical, children = children}}
end

local function notice(value, warning)
    return panel(warning and "upgrade-warning-box" or "upgrade-info-box", {
        text(value, warning and "upgrade-warning" or "upgrade-note")})
end

local function money(value)
    local number = math.floor(math.abs(value or 0) + 0.5)
    local formatted = tostring(number)
    while true do
        local replaced, count = formatted:gsub("^(%d+)(%d%d%d)", "%1,%2")
        formatted = replaced
        if count == 0 then break end
    end
    return ((value or 0) < 0 and "−" or "") .. "$" .. formatted
end

local function purposeLabel(unit)
    local names = {}
    for _, id in ipairs(core.keys(unit.purpose)) do names[#names + 1] = native.cargoName(id) end
    if #names == 0 then return "机车" end
    return table.concat(names, "、") .. (unit.uncertain and "（用途未确定，保留支持范围）" or "")
end

local function capacityLabel(item, purpose)
    local capacities = {}
    for _, id in ipairs(core.keys(purpose)) do capacities[#capacities + 1] = native.cargoName(id) .. " " .. (item.capacities[id] or 0) end
    if #capacities > 0 then return "容量  " .. table.concat(capacities, " / ") end
    return item.hasEngine and string.format("功率 %.0f kW · 牵引力 %.0f kN", item.power, item.traction) or "无装载舱室"
end

local function itemIcon(item)
    if item.icons and item.icons[1] and item.icons[1] ~= "" then
        return builtin.ImageView {meta = {class = "upgrade-model-icon"}, path = item.icons[1]}
    end
end

local function modelComparison(unit, target, mixed)
    local function modelCard(label, item, isTarget)
        local children = {text(label, "upgrade-caption")}
        if item then
            children[#children + 1] = text(item.name, "upgrade-model-name")
            local metrics = {
                text((item.yearFrom > 0 and (item.yearFrom .. " 年") or "年代未标明") .. "  ·  " ..
                    string.format("%.0f km/h", item.speed * 3.6), "upgrade-model-metrics"),
                text(capacityLabel(item, unit.purpose), "upgrade-model-metrics"),
            }
            if item.compareTraction and item.power > 0 and next(unit.purpose) then
                metrics[#metrics + 1] = text(string.format("%.0f kW · %.0f kN", item.power, item.traction), "upgrade-model-metrics")
            end
            local body = {}
            local icon = itemIcon(item)
            if icon then body[#body + 1] = icon end
            body[#body + 1] = builtin.BoxLayout {orientation = builtin.type.Orientation.Vertical, children = metrics}
            children[#children + 1] = builtin.BoxLayout {meta = {class = "upgrade-model-body"},
                orientation = builtin.type.Orientation.Horizontal, children = body}
        else
            children[#children + 1] = text(mixed and "按每辆载具的选择" or "保持原样", "upgrade-model-name")
            children[#children + 1] = text(mixed and "展开查看每辆载具的升级目标。" or "可从下方选择其他车型。", "upgrade-model-metrics")
        end
        return panel(isTarget and "upgrade-model-card, upgrade-target-card" or "upgrade-model-card", children)
    end
    return builtin.TableLayout {meta = {class = "upgrade-comparison"}, columnWeights = {1, 1}, rows = {
        builtin.Row {cells = {modelCard("现有车型", unit.old, false), modelCard("升级目标", target, true)}}}}
end

local function targetSelector(unit, choices, value, onChange, enabled, id, mixed)
    local items = {builtin.ComboBoxItem {value = "keep", content = text("保持原样")}}
    if mixed then items[#items + 1] = builtin.ComboBoxItem {value = "mixed", content = text("逐辆选择不同"), available = false} end
    for _, item in ipairs(choices or {}) do
        local declines = not core.nonRegressing(unit.old, item, unit.purpose)
        items[#items + 1] = builtin.ComboBoxItem {
            value = item.key,
            content = text(item.name .. " · " .. item.yearFrom .. "年 · " .. money(item.price) .. (declines and "（性能下降）" or "") ..
                (item.electric and not unit.old.electric and "（需供电）" or "")),
        }
    end
    return builtin.ComboBox {meta = {id = id, class = "upgrade-target", enabled = enabled},
        value = mixed and "mixed" or value or "keep", items = items,
        onValueChange = function(key) if key ~= "mixed" then onChange(key) end end}
end

local function unitView(row, unit, busy)
    local _, byKey = native.catalog()
    local key = row.changes[unit.index]
    local target = key and byKey[key]
    local children = {
        text((unit.old.multipleUnit and "固定编组 " or "部件 ") .. unit.index, "upgrade-subheading"),
        text("用途：" .. purposeLabel(unit), "upgrade-note"),
        modelComparison(unit, target),
        targetSelector(unit, row.candidates[unit.index], key, function(value)
            controller.target(row.entity, unit.index, value)
        end, not busy and row.status ~= "成功", "upgrade-target-" .. row.entity .. "-" .. unit.index),
    }
    if target then
        local warnings = core.warnings(unit.old, target, unit.purpose)
        if #warnings > 0 then children[#children + 1] = notice(table.concat(warnings, "；"), true) end
    elseif row.reasons[unit.index] and row.reasons[unit.index] ~= "" then children[#children + 1] = text(row.reasons[unit.index], "upgrade-note") end
    return panel("upgrade-unit", children)
end

local function rowView(row, busy)
    if not row.snapshot then return panel("upgrade-error-row", {
        text("载具 " .. row.entity, "upgrade-row-name"), text(row.error or "无法扫描", "upgrade-note")}) end
    local snapshot = row.snapshot
    local details = row.quote and row.quote.changed > 0 and
        ("新购 " .. money(row.quote.purchase) .. " − 折旧抵扣 " .. money(row.quote.refund) .. " = " ..
            (row.quote.net < 0 and "返还 " or "支出 ") .. money(math.abs(row.quote.net))) or "保持原样"
    local children = {
        builtin.BoxLayout {meta = {class = "upgrade-row-header"}, orientation = builtin.type.Orientation.Horizontal,
            children = {
                builtin.CheckBox {meta = {id = "upgrade-select-" .. row.entity, enabled = not busy and row.status ~= "成功"},
                    value = row.selected and 1 or 0, onValueChange = function(value) controller.select(row.entity, value == 1) end},
                button((row.expanded and "▼ " or "▶ ") .. snapshot.name, function() controller.toggleRow(row) end,
                    true, nil, "upgrade-disclosure"),
                text(row.status, "upgrade-status, " .. (row.status == "成功" and "upgrade-success" or "upgrade-note")),
            },
        },
        text(snapshot.lineName, "upgrade-row-line"), text(details, "upgrade-row-price"),
    }
    if row.error then children[#children + 1] = notice(row.error, true) end
    if row.expanded then
        for _, unit in ipairs(snapshot.units) do children[#children + 1] = unitView(row, unit, busy) end
    end
    return panel(row.selected and "upgrade-vehicle-row, upgrade-selected" or "upgrade-vehicle-row", children)
end

local function collectGroups(session)
    local map, groups, errors = {}, {}, {}
    for _, row in ipairs(session.rows) do
        if controller.matches(row) then
            if not row.snapshot then errors[#errors + 1] = row
            else
                local added = {}
                for _, unit in ipairs(row.snapshot.units) do
                    local key = unit.groupKey
                    local group = map[key]
                    if not group then
                        group = {key = key, unit = unit, choices = row.candidates[unit.index], rows = {}, count = 0, values = {}}
                        groups[#groups + 1] = group; map[key] = group
                    end
                    if not added[key] then group.rows[#group.rows + 1] = row; added[key] = true end
                    group.count = group.count + 1
                    group.values[row.changes[unit.index] or "keep"] = true
                end
            end
        end
    end
    table.sort(groups, function(a, b)
        if a.unit.old.name ~= b.unit.old.name then return a.unit.old.name < b.unit.old.name end
        return a.key < b.key
    end)
    return groups, errors
end

local Window
Window = react.RegisterWrapperRecipe("XiaomVehicleUpgradeWindow", builtin.Window, function()
    local state = react.useState(0)
    local page = react.useState(1)
    local rowPages = react.useState({})
    local errorsExpanded = react.useState(false)
    local function refresh()
        if state:hasExpired() then return end
        local _, rev = controller.read()
        if rev ~= state:old() then state:set(rev) end
    end
    -- Timer work is deferred by React. GUI script events and command submission
    -- must join the main UI thread before touching native UI services.
    local function onMainThread(fn, scope)
        react.enqueueJoin(function()
            if state:hasExpired() then return end
            fn(); refresh()
        end, scope)
    end
    react.onStepTimer(function() onMainThread(controller.step, "XiaomVehicleUpgrade:step") end, 0.1, false)
    react.onStepTimer(function() onMainThread(controller.refresh, "XiaomVehicleUpgrade:refresh") end, 1, false)
    local session = controller.read()
    if not session then return nil end
    local busy = controller.busy()
    local function close()
        if not controller.close() then return end
        local api = globals.getDefaultWindowApi(); if api then api.removeAllWindows(Window) end
    end
    local function setFilter(key, value) controller.filter(key, value); page:set(1); rowPages:set({}); refresh() end
    local carriers = {builtin.ComboBoxItem {value = "all", content = text("全部运输方式")}}
    local lines = {builtin.ComboBoxItem {value = "all", content = text("全部线路")}}
    local carrierSet, lineSet = {}, {}
    for _, row in ipairs(session.rows) do
        if row.snapshot then carrierSet[row.snapshot.carrier] = true; lineSet[row.snapshot.line] = row.snapshot.lineName end
    end
    for _, carrier in ipairs(core.keys(carrierSet)) do
        carriers[#carriers + 1] = builtin.ComboBoxItem {value = tostring(carrier), content = text(native.carrierName(carrier))}
    end
    for _, line in ipairs(core.keys(lineSet)) do
        lines[#lines + 1] = builtin.ComboBoxItem {value = tostring(line), content = text(lineSet[line])}
    end
    local groups, errors = collectGroups(session)
    local matchedVehicles = 0
    for _, row in ipairs(session.rows) do if row.snapshot and controller.matches(row) then matchedVehicles = matchedVehicles + 1 end end
    local rows = {}
    local pageSize = 12
    local pages = math.max(1, math.ceil(#groups / pageSize))
    local currentPage = math.min(page:old(), pages)
    for index = (currentPage - 1) * pageSize + 1, math.min(currentPage * pageSize, #groups) do
        local group = groups[index]
        local unit = group.unit
        local expanded = session.groupExpanded[group.key]
        local values = core.keys(group.values)
        local _, byKey = native.catalog()
        local target = #values == 1 and values[1] ~= "keep" and byKey[values[1]] or nil
        local children = {
            builtin.BoxLayout {meta = {class = "upgrade-group-heading"}, orientation = builtin.type.Orientation.Horizontal, children = {
                button((expanded and "▼ " or "▶ ") .. native.carrierName(unit.old.carrier) .. " · " .. purposeLabel(unit),
                    function() controller.toggleGroup(group.key); refresh() end, true, nil, "upgrade-group-toggle"),
                text(#group.rows .. " 辆 · " .. group.count .. (unit.old.multipleUnit and " 组" or " 部件"), "upgrade-group-count"),
            }},
            modelComparison(unit, target, #values > 1),
            builtin.BoxLayout {meta = {class = "upgrade-target-line"}, orientation = builtin.type.Orientation.Horizontal, children = {
                text("升级为", "upgrade-target-label"),
                targetSelector(unit, group.choices, values[1], function(key)
                    controller.groupTarget(group.key, key); refresh()
                end, not busy, "upgrade-group-target-" .. index, #values > 1),
            }},
        }
        if #values == 1 and values[1] ~= "keep" then
            if target then
                local warnings = core.warnings(unit.old, target, unit.purpose)
                if #warnings > 0 then children[#children + 1] = notice(table.concat(warnings, "；"), true) end
            end
        elseif #values == 1 and values[1] == "keep" then
            local reason = group.rows[1].reasons[unit.index]
            if reason and reason ~= "" then children[#children + 1] = text(reason, "upgrade-note") end
        end
        if expanded then
            local rowPage = rowPages:old()[group.key] or 1
            local countPages = math.max(1, math.ceil(#group.rows / 16))
            rowPage = math.min(rowPage, countPages)
            local function turnRowPage(delta)
                local new = core.copy(rowPages:old()); new[group.key] = rowPage + delta; rowPages:set(new)
            end
            for i = (rowPage - 1) * 16 + 1, math.min(rowPage * 16, #group.rows) do children[#children + 1] = rowView(group.rows[i], busy) end
            if countPages > 1 then
                children[#children + 1] = builtin.BoxLayout {orientation = builtin.type.Orientation.Horizontal, children = {
                    button("上一批载具", function() turnRowPage(-1) end, rowPage > 1),
                    text(rowPage .. " / " .. countPages),
                    button("下一批载具", function() turnRowPage(1) end, rowPage < countPages),
                }}
            end
        end
        rows[#rows + 1] = panel("upgrade-group", children)
    end
    if #errors > 0 then
        local errorChildren = {
            button((errorsExpanded:old() and "▼ " or "▶ ") .. "读取失败的载具 · " .. #errors .. " 辆",
                function() errorsExpanded:set(not errorsExpanded:old()) end, true, "upgrade-errors-toggle", "upgrade-disclosure"),
            text("这些载具保持原样。展开查看详情，或重新扫描。", "upgrade-note"),
        }
        if errorsExpanded:old() then
            local errorPages = math.ceil(#errors / 8)
            local errorPage = math.min(rowPages:old().errors or 1, errorPages)
            local function turnErrorPage(delta)
                local nextPages = core.copy(rowPages:old()); nextPages.errors = errorPage + delta; rowPages:set(nextPages)
            end
            for i = (errorPage - 1) * 8 + 1, math.min(errorPage * 8, #errors) do errorChildren[#errorChildren + 1] = rowView(errors[i], busy) end
            if errorPages > 1 then
                errorChildren[#errorChildren + 1] = builtin.BoxLayout {meta = {class = "upgrade-actions"},
                    orientation = builtin.type.Orientation.Horizontal, children = {
                        button("上一批", function() turnErrorPage(-1) end, errorPage > 1),
                        text(errorPage .. " / " .. errorPages, "upgrade-caption"),
                        button("下一批", function() turnErrorPage(1) end, errorPage < errorPages),
                    }}
            end
        end
        rows[#rows + 1] = panel("upgrade-error-section", errorChildren)
    end
    if #rows == 0 then rows[#rows + 1] = panel("upgrade-empty", {
        text(busy and "正在准备升级方案…" or "没有匹配的载具", "upgrade-empty-title"),
        text(busy and "车型和车队分批读取，完成后将在这里显示。" or "试试更换运输方式、线路，或清空搜索。", "upgrade-note"),
    }) end
    local totals = controller.totals()
    local function metric(label, value, class)
        return panel("upgrade-summary-metric, " .. (class or ""), {
            text(label, "upgrade-caption"), text(value, class == "upgrade-final-metric" and
                (totals.net < 0 and "upgrade-net, upgrade-success" or "upgrade-net") or "upgrade-number"),
        })
    end
    local balance = "可用余额  " .. (totals.balance == nil and "无限资金" or money(totals.balance)) ..
        (not totals.enough and "  ·  资金不足" or "")
    local selection = "已选 " .. totals.count .. " 辆" ..
        (totals.blocked > 0 and (" · " .. totals.blocked .. " 辆需调整") or "")
    local blockedReason
    if not busy then
        if totals.blocked > 0 then
            for _, row in ipairs(session.rows) do
                if row.selected and row.status ~= "成功" and
                    (row.error or not row.quote or (row.quote.changed > 0 and not row.config)) then
                    blockedReason = "无法确认：" .. (row.error or "升级方案尚未就绪") ..
                        "。共 " .. totals.blocked .. " 辆需调整，可展开查看或取消勾选。"
                    break
                end
            end
        elseif not totals.enough then blockedReason = "余额不足，请减少升级数量或选择更便宜的目标车型。" end
    end
    local function field(label, control)
        return builtin.BoxLayout {meta = {class = "upgrade-filter-field"}, orientation = builtin.type.Orientation.Vertical,
            children = {text(label, "upgrade-caption"), control}}
    end
    return builtin.Window {
        id = windowId, title = "载具升级", movable = true, closable = not busy,
        initialX = 60, initialY = 60, onClose = close,
        content = panel("upgrade-content", {
            builtin.BoxLayout {meta = {class = "upgrade-intro"}, orientation = builtin.type.Orientation.Vertical, children = {
                text("全公司升级方案", "upgrade-heading"),
                text("优先保持性能，再推荐更新车型。展开查看每辆载具与列车部件。", "upgrade-note"),
            }},
            builtin.BoxLayout {meta = {class = "upgrade-filters"}, orientation = builtin.type.Orientation.Horizontal, children = {
                field("运输方式", builtin.ComboBox {meta = {class = "upgrade-carrier-filter", enabled = not busy}, value = session.filters.carrier,
                    items = carriers, onValueChange = function(v) setFilter("carrier", v) end}),
                field("线路", builtin.ComboBox {meta = {class = "upgrade-line-filter", enabled = not busy}, value = session.filters.line,
                    items = lines, onValueChange = function(v) setFilter("line", v) end}),
                field("搜索", builtin.TextInputField {meta = {class = "upgrade-search", enabled = not busy}, value = session.filters.search,
                    placeholderText = "载具名称、线路或车型", onValueChange = function(v) setFilter("search", v) end}),
            }},
            builtin.BoxLayout {meta = {class = "upgrade-toolbar"}, orientation = builtin.type.Orientation.Horizontal, children = {
                button("全选当前筛选", function() controller.selectAll(true); refresh() end, not busy),
                button("取消当前筛选", function() controller.selectAll(false); refresh() end, not busy),
                button("重新扫描", function() controller.open(session.gameCtx); page:set(1); refresh() end, not busy),
                text(matchedVehicles .. " 辆 · " .. #groups .. " 类车型", "upgrade-results-count"),
                button("上一页", function() page:set(currentPage - 1) end, currentPage > 1, nil, "secondary, upgrade-page-button"),
                text(currentPage .. " / " .. pages, "upgrade-page-number"),
                button("下一页", function() page:set(currentPage + 1) end, currentPage < pages, nil, "secondary, upgrade-page-button"),
            }},
            builtin.ScrollArea {meta = {class = "upgrade-scroll"}, horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
                verticalPolicy = builtin.type.ScrollBarPolicy.Simple,
                -- ScrollArea requires a component; Component itself requires a layout.
                content = panel("upgrade-scroll-content", rows)},
            panel("upgrade-summary", {
                builtin.BoxLayout {meta = {class = "upgrade-invoice"}, orientation = builtin.type.Orientation.Horizontal, children = {
                    metric("新购部件", money(totals.purchase)), text("−", "upgrade-operator"),
                    metric("折旧抵扣", money(totals.refund)), text("=", "upgrade-operator"),
                    metric(totals.net < 0 and "预计返还" or "最终净支出", money(math.abs(totals.net)), "upgrade-final-metric"),
                    text(selection, totals.blocked > 0 and "upgrade-selection-count, upgrade-warning" or "upgrade-selection-count"),
                }},
                builtin.BoxLayout {meta = {class = "upgrade-summary-actions"}, orientation = builtin.type.Orientation.Horizontal, children = {
                    text(balance, totals.enough and "upgrade-balance" or "upgrade-balance, upgrade-warning"),
                    button(busy and "处理中…" or ("确认升级 · " .. totals.count .. " 辆"), function() controller.confirm(); refresh() end,
                        not busy and totals.count > 0 and totals.blocked == 0 and totals.enough, "xiaom-upgrade-confirm", "primary", blockedReason),
                    button("关闭", close, not busy, "xiaom-upgrade-close"),
                }},
                text(blockedReason or session.reviewMessage or
                    "确认后按执行时最新报价升级，支出上涨也继续；余额不足时停止。",
                    (blockedReason or session.reviewMessage) and "upgrade-footer-blocked" or "upgrade-footnote"),
            }),
            text(session.message, "upgrade-message"),
        }),
    }
end)

function ui.open(gameCtx)
    local session = controller.read()
    if session and session.gameCtx ~= gameCtx and not controller.busy() then
        native.resetCatalog(); controller.close(); session = nil
    end
    if not session then controller.open(gameCtx) end
    local windows = globals.getDefaultWindowApi()
    if not windows then return false end
    windows.addSingletonWindow(Window, {})
    windows.moveSingletonWindowToFront(Window)
    api.gui.byId.setVisible(windowId, true)
    return true
end

return ui
