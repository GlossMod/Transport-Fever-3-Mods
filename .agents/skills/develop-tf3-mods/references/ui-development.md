# 原生 UI 开发与美化

本机取证日期：2026-10-07；基于 `xiaom_vehicle_upgrade` 开发中遇到的实际报错、本机原版代码和类型定义。安装依据见 [本机环境](local-environment.md)。这里记录可复用的判断与写法，不把代码检查或样式解析当作 C++ 渲染、扣款与存档验收。

按问题阅读：节点类型与统计页接入、运行上下文与主线程、按钮反馈、美化与样式。当前项目要求完成后由用户自行测试；本参考中的复测建议不是自动运行测试或接管游戏的授权。

## 原生节点类型与接入

Lua/Teal 的 `TreeNodeId` 不保证节点能放进任意控件。C++ 会检查组件、布局及包装基础类型；函数返回布局，也不意味着该注册配方的根节点就是原生布局。

| 实际报错或现象 | 本次定位结果 | 后续开发时的判断 |
| --- | --- | --- |
| `Item of Component must be a layout` | 普通注册的 `VehiclesStatistic` 被直接赋给 `Component.layout` | `Component.layout` 要接原生布局；把原组件放进布局的 `children` |
| `dynamic_cast<Target>(x) == x`，位于替换统计页 | 原页是普通注册组件，替换页却包装了 `builtin.BoxLayout`，改变了根类型 | 对照原配方注册方式和父容器要求；不要仅依据函数返回值选择包装基础类型 |
| `ScrollArea does not accept a Layout as content` | `ScrollArea.content` 直接使用 `BoxLayout` | 滚动区内容为组件，组件内部再接布局 |

组件和布局的正确方向：

```lua
builtin.ScrollArea {
    content = builtin.Component {
        layout = builtin.BoxLayout {
            orientation = builtin.type.Orientation.Vertical,
            children = rows,
        },
    },
}
```

给普通注册页面加入口时，保持其组件根类型，并通过 `CallOriginalRecipe` 保留原列表及参数：

```lua
local VehicleTab = react.RegisterRecipe("ExampleVehicleTab", function(param)
    return builtin.BoxLayout {
        orientation = builtin.type.Orientation.Vertical,
        children = {
            toolbar,
            builtin.Component {
                layout = builtin.BoxLayout {
                    children = {react.CallOriginalRecipe(originalVehicles, param)},
                },
            },
        },
    }
end)
```

`toolbar` 与 `originalVehicles` 由调用方提供；示例只展示节点关系。捕获上下文时包装真正接收 `gameCtx` 的入口，继续透传原参数；不要从另一个页面猜测当前游戏上下文。

`RegisterWrapperRecipe` 用于保留已确认的基础类型。例如包装原生窗口时基础配方是 `builtin.Window`，函数也返回 `builtin.Window`。不能把所有页面都改成布局包装器，也不能把所有 `content` 都一律包成组件：本机 `Window.content` 可以承载布局；按钮和下拉项通常接文本或图片组件，`TableLayout.rows` 接 `Row`，`Row.cells` 再接实际单元格。

取证位置：`gui.zip` 内 `gui/main/react.lua`、`gui/main/builtin.lua`、`gui/statistics/statistic_vehicles.tl`；原商店的 `vehicle_store_window.tl` 中 `ScrollArea → Component → BoxLayout`；`base/tealdef/scripts/builtin.d.tl`。

## API 上下文与主线程

### 类型定义存在，不代表当前 UI 可调用

本次游戏日志中，目录和全部载具读取都失败于 `modelRep.getAsTable` 为 `nil`。通用 `api/res.d.tl` 包含它，但当前原生 UI 环境未提供。原版 `vehicle_store_util.tl` 和 `vehicle_util.tl` 使用只读访问：

```lua
local model = api.res.modelRep.get(modelId)
local tv = model.metadata.transportVehicle
```

只读取需要的属性，不写回模型仓库。不要为了得到普通 Lua 表去调用当前上下文不可用的接口，也不要在不需要时缓存整份模型 userdata。

遇到方法为 `nil`，先核对调用发生于内容加载、游戏脚本还是 React UI，再找同一上下文的原版实现。测试替身若额外提供不存在的函数，会掩盖实际问题；后续获准运行测试时，要覆盖当前 UI 缺少该方法的情形，以及只读仓库返回值。不能仅靠 `.d.tl` 宣称运行兼容。

### 定时回调不能默认视作主线程

`base/tealdef/scripts/react.d.tl` 的 `enqueueJoin` 明确用于所有并行 React 工作完成后的主线程调用。原版 `gui/construction/construction.tl` 从 `onStepTimer` 中切回主线程后访问 GUI 服务。

包含 GUI 脚本事件、购买检查或命令提交的定时工作，沿用同版原生调度；不要直接在并行工作中调用主线程服务：

```lua
react.onStepTimer(function()
    react.enqueueJoin(function()
        if state:hasExpired() then return end
        controller.step()
        refresh()
    end, "ExampleUpgrade:step")
end, 0.1, false)
```

`state`、`controller`、`refresh` 由窗口实现提供。延后执行前检查状态是否过期，防止窗口关闭后继续访问；状态钩子应保持稳定的声明顺序。大型目录或车队仍需分批推进，切回主线程不是一次扫描全部数据的理由。

本次购买事件异常后的修正采用上述主线程调度，但此前捕获的异常全文不足，且修正尚未实机复核。记录时区分“已证实的调度语义”和“尚待确认的购买检查根因”，不要把猜测写成唯一原因。

## 按钮状态与确认反馈

“余额够但按钮不能用”和“点击后没有升级”需要分开排查。

- 禁用时显示实际原因：没有选择、方案或载荷不合法、购买检查异常、任务拒绝、余额不足、正在处理。原因放在结算区，并可重复到按钮提示；不要只依赖灰色按钮或逐辆错误。
- 捕获异常后记录原始错误。购买检查抛错不等于任务明确禁止购买，也不应直接跳过检查使按钮可用。
- 确认日志应能区分：点击进入、选中与阻止数量、报价及余额、复核开始、退回或通过、发送命令、回调成功或失败。没有命令日志不能单独证明点击没有进入处理。
- 配置或报价变化退回预览时，显示“未开始升级”及具体原因。记录首个变化字段的前后值、单辆价格差额；自动装载、手动货物配置、线路、编组及保留部件状态不要混为同一原因。
- 空闲刷新不应立刻覆盖此次确认的退回提示。必要时提示用户在暂停的测试副本中重新扫描确认，但不要自动暂停或替用户提交。

日志可能同时包含其他 Mod 的回调或只读成员错误。按时间、线程、命名空间和堆栈归属定位；未证实因果关系前，不把相邻异常当成当前 Mod 的根因。

## 窗口美化方法

### 信息布局

本次预览采用顶部筛选、中间滚动列表、底部结算三个区域。根据具体窗口调整，不把固定宽高照搬到所有界面。

- 背景透出原列表时，在原生窗口内增加实色 `Component` 底板，保留窗口标题、关闭和拖动控件。背景画在组件上，内部间距放在实际 `BoxLayout` 上。
- 原车与目标并排显示为卡片，名称独立成行；年代、速度、容量和必要的铁路动力指标分行排列。目标卡片使用适度的强调色，避免用一条长句同时塞入所有信息。
- 分组标题表达用途和数量；展开后再显示逐辆线路、价格、状态及列车部件。筛选控件使用标签和一致高度，分页与批量选择在单独的工具栏内。
- 结算区明确显示“新购部分 − 被替换部分的折旧抵扣 = 净支出／返还”，同时显示余额及全部已选数量。筛选后总价仍包含筛选外的已选项时，要说明这一点。
- 供电、设施要求及性能下降使用独立提示底色，保留对应文本。失败列表可默认收起，展开后分页；不要让大量重复黄色错误挤满窗口，也不要把失败项隐藏为成功。

窗口宽度需扣除内边距、列间距和滚动条占位后再分配控件；展开后的嵌套面板也会减少可用宽度。长车型名、线路名、多货物容量、金额和禁用原因都要考虑换行。逻辑尺寸不是最终屏幕像素，字体缩放与高 DPI 效果由用户实机查看。

### 原生样式与资源

使用 `.css.lua` 和原版 `stylesheetutil`，只影响自己的窗口或入口：

```lua
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
    local result = {}
    local add = ssu.makeAdder(result)
    add("#example-upgrade-window !upgrade-content", {
        backgroundColor = {0.105, 0.14, 0.175, 1},
        padding = {12, 16, 12, 16},
    })
    add("#example-upgrade-window !upgrade-content > BoxLayout", {
        innerSpacing = {8, 8},
    })
    return result
end
```

上述窗口和类名是占位示例，需要与实际 `Window.id`、控件 `meta.class` 一致。

- `#id` 限定窗口，`!class` 对应样式类；多个 `meta.class` 用原版逗号分隔写法。逗号连接多个选择器时，每个选择器都要带作用域；简单拼接前缀只会限定第一个。
- 主操作沿用 `meta = {class = "primary"}`，其他按钮可用 `secondary`；原版 `default.css.lua` 已提供悬停、按下和禁用状态。自定义文字色时检查是否遮蔽了这些状态。
- 同一元素兼有余额和警告类时，可以用 `!balance!warning` 提高特异性，防止普通灰色文字规则覆盖资金不足提示。
- 圆角卡片复用 `::/gui/entity_window/design/card_surface.tga` 和 `card_contour.tga`，切片参数取自同版 `content_card.css.lua`：横向和纵向均为 `{0, 6, 26, 32}`。该安装包实际条目为 `@2x.tga`；按原版引用无后缀的逻辑路径，不能仅因找不到同名裸 `.tga` 就认定资源缺失。
- 中文 `TextView` 沿用 `useUnicodeCompatibilityFont = true`；必要时用 `textAutoWrap` 与 `maxSize` 约束文本，避免扩宽整张卡片。图片尺寸、缩放模式和滤镜字段仍以同版定义为依据，不添加猜测的 Web CSS 属性。

样式解析成功只证明规则可读取；组件容器检查只证明已覆盖的类型关系。它们都不能证明视觉效果、字体缩放、下拉窗口位置或游戏替换结果正确。

## 交付与用户复测

完成后说明改了什么、实际加载目录及 revision、是否需要重启，以及本次哪些项目尚未测试。本项目当前由用户自行测试，不运行检查器、自动化、游戏或编辑器；旧版本通过记录要标明版本，准备了测试代码也不能写成已通过。

修改已加载的 React 注册和 Lua 模块后，通知用户完全退出并重启游戏再复测，避免缓存旧配方。更新既有 `.css.lua` 不需要新增资源，但新增运行文件时应同步 `_content.json`；核对实际 staging area 是否为联接或另有同 ID 副本。

给用户的复测要点按此次改动选择：打开原页与新窗口、展开卡片和列车部件、长文本与图片、筛选分页、失败列表、禁用原因、确认退回及命令回调。涉及价格、货物和存档的结果，继续由测试副本中的实际余额、载荷、保留状态及重载证明。

本次详细案例在工作区 `staging_area/xiaom_vehicle_upgrade/VALIDATION.md`；可复用代码在该 Mod 的 `upgrade_entry.lua`、`upgrade_ui.lua`、`upgrade.css.lua` 与控制器中。参考当前文件和验证状态，避免把其中尚未实测的修正当成运行保证。
