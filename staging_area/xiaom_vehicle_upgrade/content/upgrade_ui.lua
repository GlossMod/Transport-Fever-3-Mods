local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local globals = ug_require "::/gui/main/game_react_globals.tl"
local core = ug_require "xiaom_vehicle_upgrade::/upgrade_core.lua"
local native = ug_require "xiaom_vehicle_upgrade::/upgrade_native.lua"
local controller = ug_require "xiaom_vehicle_upgrade::/upgrade_controller.lua"
local i18n = ug_require "xiaom_vehicle_upgrade::/upgrade_i18n.lua"
local t = i18n.t
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
    if #names == 0 then return t("locomotive") end
    return table.concat(names, t("purpose_separator")) .. (unit.uncertain and t("uncertain_purpose") or "")
end

local function capacityLabel(item, purpose)
    local capacities = {}
    for _, id in ipairs(core.keys(purpose)) do capacities[#capacities + 1] = native.cargoName(id) .. " " .. (item.capacities[id] or 0) end
    if #capacities > 0 then return t("capacity", table.concat(capacities, " / ")) end
    return item.hasEngine and t("traction_specs", item.power, item.traction) or t("no_compartments")
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
                text((item.yearFrom > 0 and t("year", item.yearFrom) or t("unknown_year")) .. "  ·  " ..
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
            children[#children + 1] = text(t(mixed and "individual_targets" or "keep"), "upgrade-model-name")
            children[#children + 1] = text(t(mixed and "expand_targets" or "choose_model_below"), "upgrade-model-metrics")
        end
        return panel(isTarget and "upgrade-model-card, upgrade-target-card" or "upgrade-model-card", children)
    end
    return builtin.TableLayout {meta = {class = "upgrade-comparison"}, columnWeights = {1, 1}, rows = {
        builtin.Row {cells = {modelCard(t("original_model"), unit.old, false), modelCard(t("target_model"), target, true)}}}}
end

local function targetSelector(unit, choices, value, onChange, enabled, id, mixed)
    local items = {builtin.ComboBoxItem {value = "keep", content = text(t("keep"))}}
    if mixed then items[#items + 1] = builtin.ComboBoxItem {value = "mixed", content = text(t("mixed")), available = false} end
    for _, item in ipairs(choices or {}) do
        local declines = not core.nonRegressing(unit.old, item, unit.purpose)
        items[#items + 1] = builtin.ComboBoxItem {
            value = item.key,
            content = text(t("candidate", item.name, item.yearFrom, money(item.price)) .. (declines and t("decline_badge") or "") ..
                (item.electric and not unit.old.electric and t("electric_badge") or "")),
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
        text(t(unit.old.multipleUnit and "fixed_unit" or "part", unit.index), "upgrade-subheading"),
        text(t("purpose", purposeLabel(unit)), "upgrade-note"),
        modelComparison(unit, target),
        targetSelector(unit, row.candidates[unit.index], key, function(value)
            controller.target(row.entity, unit.index, value)
        end, not busy and row.status ~= "success", "upgrade-target-" .. row.entity .. "-" .. unit.index),
    }
    if target then
        local warnings = core.warnings(unit.old, target, unit.purpose)
        if #warnings > 0 then children[#children + 1] = notice(table.concat(warnings, t("warning_separator")), true) end
    elseif row.reasons[unit.index] and row.reasons[unit.index] ~= "" then children[#children + 1] = text(row.reasons[unit.index], "upgrade-note") end
    return panel("upgrade-unit", children)
end

local function rowView(row, busy)
    if not row.snapshot then return panel("upgrade-error-row", {
        text(t("vehicle", row.entity), "upgrade-row-name"), text(row.error or t("status_unreadable"), "upgrade-note")}) end
    local snapshot = row.snapshot
    local details = row.quote and row.quote.changed > 0 and
        t("row_invoice", money(row.quote.purchase), money(row.quote.refund),
            t(row.quote.net < 0 and "refund" or "cost"), money(math.abs(row.quote.net))) or t("keep")
    local children = {
        builtin.BoxLayout {meta = {class = "upgrade-row-header"}, orientation = builtin.type.Orientation.Horizontal,
            children = {
                builtin.CheckBox {meta = {id = "upgrade-select-" .. row.entity, enabled = not busy and row.status ~= "success"},
                    value = row.selected and 1 or 0, onValueChange = function(value) controller.select(row.entity, value == 1) end},
                button((row.expanded and "▼ " or "▶ ") .. snapshot.name, function() controller.toggleRow(row) end,
                    true, nil, "upgrade-disclosure"),
                text(t("status_" .. row.status), "upgrade-status, " .. (row.status == "success" and "upgrade-success" or "upgrade-note")),
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
    local carriers = {builtin.ComboBoxItem {value = "all", content = text(t("all_modes"))}}
    local lines = {builtin.ComboBoxItem {value = "all", content = text(t("all_lines"))}}
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
                text(t(unit.old.multipleUnit and "group_units" or "group_parts", #group.rows, group.count), "upgrade-group-count"),
            }},
            modelComparison(unit, target, #values > 1),
            builtin.BoxLayout {meta = {class = "upgrade-target-line"}, orientation = builtin.type.Orientation.Horizontal, children = {
                text(t("upgrade_to"), "upgrade-target-label"),
                targetSelector(unit, group.choices, values[1], function(key)
                    controller.groupTarget(group.key, key); refresh()
                end, not busy, "upgrade-group-target-" .. index, #values > 1),
            }},
        }
        if #values == 1 and values[1] ~= "keep" then
            if target then
                local warnings = core.warnings(unit.old, target, unit.purpose)
                if #warnings > 0 then children[#children + 1] = notice(table.concat(warnings, t("warning_separator")), true) end
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
                    button(t("previous_vehicles"), function() turnRowPage(-1) end, rowPage > 1),
                    text(rowPage .. " / " .. countPages),
                    button(t("next_vehicles"), function() turnRowPage(1) end, rowPage < countPages),
                }}
            end
        end
        rows[#rows + 1] = panel("upgrade-group", children)
    end
    if #errors > 0 then
        local errorChildren = {
            button((errorsExpanded:old() and "▼ " or "▶ ") .. t("failed_reads", #errors),
                function() errorsExpanded:set(not errorsExpanded:old()) end, true, "upgrade-errors-toggle", "upgrade-disclosure"),
            text(t("failed_reads_note"), "upgrade-note"),
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
                        button(t("previous_batch"), function() turnErrorPage(-1) end, errorPage > 1),
                        text(errorPage .. " / " .. errorPages, "upgrade-caption"),
                        button(t("next_batch"), function() turnErrorPage(1) end, errorPage < errorPages),
                    }}
            end
        end
        rows[#rows + 1] = panel("upgrade-error-section", errorChildren)
    end
    if #rows == 0 then rows[#rows + 1] = panel("upgrade-empty", {
        text(t(busy and "preparing" or "no_matches"), "upgrade-empty-title"),
        text(t(busy and "preparing_note" or "no_matches_note"), "upgrade-note"),
    }) end
    local totals = controller.totals()
    local function metric(label, value, class)
        return panel("upgrade-summary-metric, " .. (class or ""), {
            text(label, "upgrade-caption"), text(value, class == "upgrade-final-metric" and
                (totals.net < 0 and "upgrade-net, upgrade-success" or "upgrade-net") or "upgrade-number"),
        })
    end
    local balance = t("balance", totals.balance == nil and t("unlimited") or money(totals.balance)) ..
        (not totals.enough and t("insufficient_badge") or "")
    local selection = t("selected", totals.count) ..
        (totals.blocked > 0 and t("blocked_count", totals.blocked) or "")
    local blockedReason
    if not busy then
        if totals.blocked > 0 then
            for _, row in ipairs(session.rows) do
                if row.selected and row.status ~= "success" and
                    (row.error or not row.quote or (row.quote.changed > 0 and not row.config)) then
                    blockedReason = t("cannot_confirm", row.error or t("plan_not_ready"), totals.blocked)
                    break
                end
            end
        elseif not totals.enough then blockedReason = t("insufficient_targets") end
    end
    local function field(label, control)
        return builtin.BoxLayout {meta = {class = "upgrade-filter-field"}, orientation = builtin.type.Orientation.Vertical,
            children = {text(label, "upgrade-caption"), control}}
    end
    return builtin.Window {
        id = windowId, title = t("window_title"), movable = true, closable = not busy,
        initialX = 60, initialY = 60, onClose = close,
        content = panel("upgrade-content", {
            builtin.BoxLayout {meta = {class = "upgrade-intro"}, orientation = builtin.type.Orientation.Vertical, children = {
                text(t("heading"), "upgrade-heading"),
                text(t("intro"), "upgrade-note"),
            }},
            builtin.BoxLayout {meta = {class = "upgrade-filters"}, orientation = builtin.type.Orientation.Horizontal, children = {
                field(t("transport_mode"), builtin.ComboBox {meta = {class = "upgrade-carrier-filter", enabled = not busy}, value = session.filters.carrier,
                    items = carriers, onValueChange = function(v) setFilter("carrier", v) end}),
                field(t("line"), builtin.ComboBox {meta = {class = "upgrade-line-filter", enabled = not busy}, value = session.filters.line,
                    items = lines, onValueChange = function(v) setFilter("line", v) end}),
                field(t("search"), builtin.TextInputField {meta = {class = "upgrade-search", enabled = not busy}, value = session.filters.search,
                    placeholderText = t("search_hint"), onValueChange = function(v) setFilter("search", v) end}),
            }},
            builtin.BoxLayout {meta = {class = "upgrade-toolbar"}, orientation = builtin.type.Orientation.Horizontal, children = {
                button(t("select_filtered"), function() controller.selectAll(true); refresh() end, not busy),
                button(t("deselect_filtered"), function() controller.selectAll(false); refresh() end, not busy),
                button(t("rescan"), function() controller.open(session.gameCtx); page:set(1); refresh() end, not busy),
                text(t("result_count", matchedVehicles, #groups), "upgrade-results-count"),
                button(t("previous_page"), function() page:set(currentPage - 1) end, currentPage > 1, nil, "secondary, upgrade-page-button"),
                text(currentPage .. " / " .. pages, "upgrade-page-number"),
                button(t("next_page"), function() page:set(currentPage + 1) end, currentPage < pages, nil, "secondary, upgrade-page-button"),
            }},
            builtin.ScrollArea {meta = {class = "upgrade-scroll"}, horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
                verticalPolicy = builtin.type.ScrollBarPolicy.Simple,
                -- ScrollArea requires a component; Component itself requires a layout.
                content = panel("upgrade-scroll-content", rows)},
            panel("upgrade-summary", {
                builtin.BoxLayout {meta = {class = "upgrade-invoice"}, orientation = builtin.type.Orientation.Horizontal, children = {
                    metric(t("purchase_parts"), money(totals.purchase)), text("−", "upgrade-operator"),
                    metric(t("depreciation_credit"), money(totals.refund)), text("=", "upgrade-operator"),
                    metric(t(totals.net < 0 and "expected_refund" or "net_cost"), money(math.abs(totals.net)), "upgrade-final-metric"),
                    text(selection, totals.blocked > 0 and "upgrade-selection-count, upgrade-warning" or "upgrade-selection-count"),
                }},
                builtin.BoxLayout {meta = {class = "upgrade-summary-actions"}, orientation = builtin.type.Orientation.Horizontal, children = {
                    text(balance, totals.enough and "upgrade-balance" or "upgrade-balance, upgrade-warning"),
                    button(busy and t("processing") or t("confirm_count", totals.count), function() controller.confirm(); refresh() end,
                        not busy and totals.count > 0 and totals.blocked == 0 and totals.enough, "xiaom-upgrade-confirm", "primary", blockedReason),
                    button(t("close"), close, not busy, "xiaom-upgrade-close"),
                }},
                text(blockedReason or session.reviewMessage or
                    t("price_policy"),
                    (blockedReason or session.reviewMessage) and "upgrade-footer-blocked" or "upgrade-footnote"),
            }),
            text(session.message, "upgrade-message"),
        }),
    }
end)

function ui.open(gameCtx)
    local language = i18n.refresh()
    local session = controller.read()
    -- Refresh stored diagnostic text when reopening after a language change.
    -- Do not discard a running queue or change its internal status identifiers.
    if session and session.language ~= language and not controller.busy() then
        controller.close(); session = nil
    end
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
