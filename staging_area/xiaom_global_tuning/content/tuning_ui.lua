local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local globals = ug_require "::/gui/main/game_react_globals.tl"
local gameBar = ug_require "::/gui/game_bar/game_bar.tl"
local settings = ug_require "xiaom_global_tuning::/settings.lua"
local controller = ug_require "xiaom_global_tuning::/tuning_controller.lua"
local ui = {}
local windowId = "xiaom-global-tuning-window"
local loggedLauncher = false
local installed = false

local function text(value, class)
    return builtin.TextView {meta = {class = class}, text = value, useUnicodeCompatibilityFont = true}
end

local function button(label, click, enabled, id)
    return builtin.Button {meta = {id = id, enabled = enabled ~= false}, content = text(label), onClick = click}
end

local fields = {
    industryProduction = {label = "工厂生产", badge = "实时", hint = "仍需要原料、运输和需求；调整产业的生产能力。"},
    railTraction = {label = "火车牵引能力", badge = "下次载入", hint = "机车和动车组动力单元的功率与牵引力。"},
    freightCapacity = {label = "货运容量", badge = "下次载入", hint = "一次可装载的货物数量。"},
    passengerCapacity = {label = "客运人数", badge = "下次载入", hint = "一次可搭载的旅客人数。"},
    freightWeight = {label = "满载货物重量", badge = "下次载入", hint = "满载时增加的重量，影响车辆动力表现。"},
    vehicleSpeed = {label = "载具 / 路网速度", badge = "载具实时", hint = "载具最高速度实时调整；道路、轨道、桥隧及道口限速在下次载入生效。实际速度仍受动力和路网限制。"},
    freightLoading = {label = "货运装载速度", badge = "下次载入", hint = "所有非旅客货种的装载速度。"},
    passengerLoading = {label = "客运装载速度", badge = "下次载入", hint = "旅客上下车速度。"},
    simulationSpeed = {label = "模拟速度", badge = "实时", choices = settings.simulationSpeeds, hint = "整体模拟速度；应用后仍可用原游戏按钮手动切速。"},
    calendarSpeed = {label = "日历速度", badge = "实时", choices = settings.calendarSpeeds, hint = "日期推进倍率；暂停日期不影响车辆移动。"},
}

local function layout(children, class, horizontal)
    return builtin.BoxLayout {
        meta = {class = class},
        orientation = horizontal and builtin.type.Orientation.Horizontal or builtin.type.Orientation.Vertical,
        children = children,
    }
end

local function card(title, subtitle, children)
    local rows = {layout({text(title, "xiaom-tuning-section"), text(subtitle, "xiaom-tuning-caption")}, "xiaom-tuning-card-heading", true)}
    for _, row in ipairs(children) do rows[#rows + 1] = row end
    return builtin.Component {
        meta = {class = "xiaom-tuning-card"},
        layout = layout(rows, "xiaom-tuning-card-layout"),
    }
end

local Window
Window = react.RegisterWrapperRecipe("XiaomGlobalTuningWindow", builtin.Window, function()
    local status = react.useStateLazy(function()
        local params, message, _, pending = controller.read()
        return {params = params, message = message, pending = pending}
    end)
    local function refresh()
        if status:hasExpired() then return end
        local params, message, _, pending = controller.read()
        local old = status:old()
        local changed = old.message ~= message or old.pending ~= pending
        for key, value in pairs(params) do if old.params[key] ~= value then changed = true end end
        if changed then status:set({params = params, message = message, pending = pending}) end
    end
    react.onStepTimer(refresh, 0.2, false)
    local state = status:old()
    local function close()
        local windows = globals.getDefaultWindowApi()
        if windows then windows.removeAllWindows(Window) end
    end
    local function field(key)
        local spec = fields[key]
        local items = {}
        for _, value in ipairs(spec.choices or settings.multipliers) do
            local label = value == -1 and "保持当前设置" or value == 0 and
                (key == "calendarSpeed" and "暂停日期" or "暂停") or tostring(value) .. " 倍"
            items[#items + 1] = builtin.ComboBoxItem {value = value, content = text(label)}
        end
        return builtin.Component {
            meta = {class = "xiaom-tuning-field", localKey = key, tooltip = spec.hint},
            layout = layout({
                layout({text(spec.label, "xiaom-tuning-label"), text(spec.badge,
                    spec.badge == "下次载入" and "xiaom-tuning-badge-load" or "xiaom-tuning-badge-live")}, "xiaom-tuning-field-heading", true),
                builtin.ComboBox {
                    meta = {id = "xiaom-tuning-" .. key, class = "xiaom-tuning-choice"},
                    value = state.params[key], items = items,
                    onValueChange = function(value) controller.edit(key, value); refresh() end,
                },
            }, "xiaom-tuning-field-layout"),
        }
    end
    local function pair(a, b) return layout({field(a), field(b)}, "xiaom-tuning-field-pair", true) end
    local body = {
        layout({text("全局倍率", "xiaom-tuning-heading"), text("自动保存配置", "xiaom-tuning-autosave")}, "xiaom-tuning-intro", true),
        text("选择后自动应用；鼠标悬停可查看各项说明。", "xiaom-tuning-note"),
        card("生产与动力", "", {pair("industryProduction", "railTraction")}),
        card("载具与运输", "路网限速在下次载入应用", {
            pair("freightCapacity", "passengerCapacity"), pair("freightWeight", "vehicleSpeed"),
            pair("freightLoading", "passengerLoading"),
        }),
        card("时间控制", "日期暂停不影响载具移动", {pair("simulationSpeed", "calendarSpeed")}),
        builtin.Component {meta = {class = "xiaom-tuning-status-panel"}, layout = layout({
            text(state.message, "xiaom-tuning-status"),
            text("配置在本机独立保存，所有存档共用。", "xiaom-tuning-note"),
        }, "xiaom-tuning-status-layout")},
        layout({
            button("重新应用", function() controller.retry(); refresh() end, true, "xiaom-tuning-retry"),
            button("恢复默认", function() controller.reset(); refresh() end, true, "xiaom-tuning-reset"),
            text(state.pending > 0 and "下次载入：" .. state.pending .. " 项" or "资源设置已同步", "xiaom-tuning-pending"),
        }, "xiaom-tuning-actions", true),
    }
    return builtin.Window {
        meta = {class = "xiaom-tuning-window"}, id = windowId, title = "内置修改器",
        movable = true, closable = true, initialX = 60, initialY = 70, onClose = close,
        -- Window consumes a layout. Padding and painting belong to the inner
        -- Component; applying component padding to a BoxLayout is ineffective.
        content = layout({builtin.Component {
            meta = {class = "xiaom-tuning-body"}, layout = layout(body, "xiaom-tuning-body-layout"),
        }}, "xiaom-tuning-window-layout"),
    }
end)

function ui.open()
    local windows = globals.getDefaultWindowApi()
    if not windows then return false end
    windows.addSingletonWindow(Window, {})
    windows.moveSingletonWindowToFront(Window)
    api.gui.byId.setVisible(windowId, true)
    debugPrint("[xiaom_global_tuning] UI settings window opened")
    return true
end

-- Button is a native fast-path builtin in this build and has no Lua recipe ID.
-- Return its node directly inside the bar layout; it cannot be a wrapper recipe.
function ui.Launcher()
    if not loggedLauncher then
        loggedLauncher = true
        debugPrint("[xiaom_global_tuning] UI lower-right launcher mounted")
    end
    return builtin.Button {
        meta = {id = "xiaom-global-tuning-launcher", tooltip = "打开内置修改器，调整全局倍率"},
        content = builtin.Component {
            meta = {class = "xiaom-tuning-launcher-icon"},
            layout = builtin.BoxLayout {children = {
                builtin.ImageView {
                    path = "::/gui/main/icons/symbol_gear_28.tga",
                    scaling = builtin.type.ImageViewScaling.AutoFit,
                },
            }},
        },
        onClick = ui.open,
    }
end

local originalGameBar = gameBar.GameBar
local GameBar = react.RegisterRecipe("XiaomGlobalTuningGameBar", function(params)
    -- ModEntryPointExtension lives below an intentionally invisible EntryPoints
    -- node in this build. Attach to the visible bar and retain its entire recipe.
    react.setMouseTransparent(true)
    return builtin.FloatingLayout {children = {
        builtin.FloatingLayoutChild {h = -1, v = 1, item = react.CallOriginalRecipe(originalGameBar, params)},
        builtin.FloatingLayoutChild {h = 1, v = 1, item = ui.Launcher()},
    }}
end)

function ui.install(replacementApi)
    if installed then return end
    replacementApi.ReplaceRecipe(originalGameBar, GameBar)
    installed = true
    debugPrint("[xiaom_global_tuning] UI visible GameBar wrapper installed")
end

return ui
