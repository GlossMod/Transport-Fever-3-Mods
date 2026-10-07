# 验证记录

日期：2026-10-04 至 2026-10-05，Asia/Shanghai。Steam AppID `3493540`，Build `25533170`。当前修订 7 候选版。

## 修订 7：吸附与调整输入，尚待实机验收

- 对照本机 `gui/construction/construction_react_util.tl`，将旋转/升降绑定从 ActionDescriptor 包装 Recipe 移到原生 `ConstructionAction.inputActions/inputActionsHandler`，按键映射与精细模式继续采用游戏设置。此项尚未实机证明按键已经修好。
- 增加旋转 ±15°、升高/降低按钮及角度、高度显示。提交期间不能修改位置或调整参数。
- 原生 `ConstructionBuilder` 使用原资源、参数和起始方向生成吸附位置。在 `getProposalStringsFn` 回调中克隆结果矩阵，再生成保留原配置、全部模块、所有权与旧→新映射的自有 SimpleProposal。原生临时 Proposal 不跨回调保存。
- 该建造器仅提供定位及按键处理，在回调中将其 ProposalData.errorState.critical 置为 true 并写回完整记录，禁用原版新建提交；最终仍由搬移工具执行一次经过独立校验的免费更新。这个提交屏蔽及双组件鼠标路由需要在 C++ 游戏中验证。
- 46 项开发检查通过，含 42 项功能模拟与 4 项原版 React 注册集成检查。新增吸附结果的矩阵所有权、完整模块/所有权保留、迟到原生回调、值拷贝错误记录写回、按钮调整及提交期间禁止调整的检查。
- 不把模拟提供的吸附矩阵等同于实际道路图连通；必须在暂停的测试副本实测：道路吸附、左键放置、M/N 与句号/逗号、Shift 精细调整、窗口按钮、取消、余额不变及存档重载。还需确认没有原版新建命令产生复制品或额外扣款。
- 已启动游戏到主菜单，未加载或修改任何地图。窗口输入接口持续返回 `foreground window did not report a process id`；重新选择窗口和恢复输入后仍失败，已请求用户恢复前台/解锁条件。此次游戏内验证未完成。
- 原版依据的只读摘录在工作区 `output/building_mover_r7_native/`，不随 Mod 发布。以下实机记录属于修订 6，不能视为修订 7 的验收。

## 本次闪退的确定原因

用户日志目录：`C:\Program Files (x86)\Steam\userdata\233840157\3493540\local\crash_dump`。

2026-10-04 23:23:51（北京时间，日志为 15:23:51Z）的日志明确记录：

```text
[xiaom_building_mover] placement completed success=true
Lua error: attempt to index local 'pair' (a number value)
mover_core.lua (264), scope sendCommand
Uncaught exception while in class UI::CSelector
Ungraceful exit
```

当时加载修订 5。建筑更新已成功，随后完成回调按 `pair[1]` 读取结果，导致 GUI 选择器未捕获异常退出。安装包的类型声明把 `resultEntities` 写成实体/修订二元组，但实际引擎返回数字实体 ID。

修订 6 同时接受数字 ID 和二元组，只选择具有 `CONSTRUCTION` 组件的结果实体。没有结果建筑 ID 时仍完成成功回调，避免工具一直停在提交状态。诊断日志分别记录提交、引擎完成、结果建筑和完成回调退出。

将测试替身改为实际数字结果后，旧代码的 4 项现有交互测试复现相同异常；修复后 42 项检查通过。另添加混合子实体/二元组和无结果建筑 ID 的回归检查。

## 免费搬移的实机修正

实测发现，旧版设置 `playerInitiated=false` 后，若 `Context.player` 仍指定当前玩家，命令照常扣款。诊断时一次仓库搬移扣除 7,787，一次入口换槽扣除 422；这些操作都在测试副本中。

修订 6 保留 `Context.new()` 的默认付款方 `-1`，不指定玩家付款账户；建筑条目的 `playerEntity` 单独保留原所有者。`ignoreErrors=false`、`playerInitiated=false`、`doDust=false` 均保留，没有修改全局 `noCosts`，没有发送账户退款命令。

改完后重新载入测试副本，在暂停状态下分别执行仓库左键放置和港口入口换槽：

| 操作 | 日志时间（UTC） | 引擎提案费用 | 搬移前余额 | 搬移后余额 |
| --- | --- | ---: | ---: | ---: |
| 金华仓库整体移动 | 2026-10-04 17:18:16Z | 8,881 | 107,302,692 | 107,302,692 |
| 港口行人入口 95010051 → 95009951 | 2026-10-04 17:39:31Z | 217 | 107,302,692 | 107,302,692 |

两次日志均包含 `payer=-1`、`success=true` 和 `completion handler returned`。实际 `withCostRep=true`，提案费用仍为正，但玩家余额未改变；不能把费用字段为零或命令布尔参数当成免费结算的证明。

## 已完成的游戏内验收

所有操作均使用“建筑搬移修复测试”存档副本，原“新游戏”未修改。测试结束保持暂停，关闭搬移窗口。

- “移动”按钮位于建筑详情的“配置”右侧；点击后进入跟随鼠标的地图预览，左键放置成功后退出搬移工具。
- 金华仓库整体搬移多次成功，完成回调正常退出，没有再出现本次数字索引异常或闪退。详情中的鱼、原油库存均保留为 500/500，所有权及配置/移动入口保留。
- 仓库搬移后的自动存档已实际重新载入，新位置和库存保留。
- 港口行人入口先从 98010150 换到 95010051；存档重载后模块选择器仍显示新插槽。随后在免费结算修正后从 95010051 换到 95009951，预览和提交均成功。
- 港口入口换槽后原三条线路仍显示：渔场、[货运] 原油-海口-金华、[货运] 鱼-海口-金华。没有另行拆除或新建建筑。
- 免费结算修正后的仓库及模块搬移均记录了暂停状态下的实际余额，结果见上表。

崩溃日志、转储及修订 6 实测日志保存在工作区 `output/building_mover_crash_20261004_232351/`，不随 Mod 发布。修订 4 崩溃材料另在 `output/building_mover_crash_20261004/`。

## 开发检查

42 项检查通过：38 项功能模拟，4 项直接加载游戏 React Lua 注册代码的集成检查。

- Lua 语法、JSON、命名空间、资源文件与发布文件 UTF-8 无 BOM。
- 保留参数、模块变体、矩阵、所有权；同类空槽筛选、占用和模块丢失拒绝。
- 预览错误、外部建筑/模块拆除保护、零起始旧→新映射及建筑修订检查。
- 鼠标位置、旋转/高度/精细模式、取消、迟到预览、重复点击和工具切换。
- 预览借用对象在回调后失效时仍可提交自有 SimpleProposal；退款上下文允许 nil。
- 数字结果、声明中的二元组、跳过子实体、无结果建筑 ID、命令失败。
- 默认付款方 `-1` 与建筑所有权分别保留；命令错误检查开启，不修改全局费用规则。
- 原生 `RegisterWrapperRecipe` / `CallOriginalRecipe` 延迟注册、布局约束、操作栏、窗口和预览包装关系。

复现：

```powershell
py -X utf8 '.agents\tests\test_building_mover.py'
```

模拟与注册检查不能代替 C++ 几何、调度或账户结算验收；本次游戏内结果单独记录在前面。

## 本机接口依据与历史修复

安装目录：`E:\steam\steamapps\common\Transport Fever 3`。

- `api/tealdef/api/type.d.tl`、`engine.d.tl`、`engine/system.d.tl`、`engine/util.d.tl`、`cmd.d.tl`、`res.d.tl`：提案、建筑/子模块、所有权、账户、修订、矩阵和命令。结果字段声明与引擎的差异以实机日志为准。
- `base/content/game_mechanics.zip` 中 `company_util.getNeededPermitsForProposal`：`old2new` 使用零起始索引。
- `base/content/gui.zip` 中 `bootstrap_game`、`entity_window_util`、`react.lua`：Recipe 替换、配置按钮、原生包装与布局约束。修订 3 修复 `Recipe child must be a layout`。
- `custom_entity_util.tl` 使用矩阵实例 `:clone()`、`:getTransl()` 和 `:setTransl()`；修订 4 按此修复错误静态方法。
- `api/gui.d.tl` 与 `construction_react_util.tl`：原生地形取点、Selector、ProposalViewer、建造输入及工具栈。
- `bridge_and_tunnel.tl`：预览回调、提交自有输入与可选退款上下文。修订 5 消除跨回调保存/读取临时原生预览对象。修订 4 的空指针转储与旧版回归测试支持该问题判断；本次确定的修订 5 闪退原因见本文开头。
- 原版脚本建造使用默认 Context；修订 6 免费结算依据为默认付款方及实际账户余额，而不是 `playerInitiated` 的推测语义。
- 本机 Steam 用户目录的 `staging_area` 目录联接指向工作区 `staging_area`，修改已同步，没有创建重复安装副本。

官方资料：[模块建筑](https://wiki.transportfever3.com/doku.php?id=modding:constructions:modular)、[API 导读](https://wiki.transportfever3.com/doku.php?id=modding:scripting:api)。实现以安装包和实机结果为准。

## 范围与尚未实测的场景

修订 7 已在代码中接入原版建造器的吸附位置，最终道路图连接仍待实机验证。外部接入道路/轨道不会整体搬走，需要检查连接。

本次实测覆盖仓库与港口入口；尚未逐类验证车辆段、产业生产、乘客状态、所有第三方建筑及其自定义实体引用。负余额免费搬移只有开发检查，未在游戏内改变玩家账户验证。复杂几何碰撞、依赖插槽、旋转/升降及多个固定窗口仍需要更广的实机覆盖。免费修正后的最新入口位置尚未再次重载；较早的仓库搬移与入口换槽已通过存档重载。
