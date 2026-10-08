# 相连路网批量升级 / Connected Network Upgrade

独立 TF3 Mod，ID `xiaom_connected_network_upgrade`，revision **5**。

**本版本未游戏内验证。** 按项目约定没有运行测试、检查器、游戏或 Model Editor。代码依据本机 TF3 API 类型定义、原版建造菜单和已有原生 UI Mod 核对，实际加载、布局、替换效果、扣款及存读档由用户复测。

## 启用和使用

1. 完全退出并重启游戏，在新地图或现有存档的 Mod 列表启用“相连路网批量升级”。
2. 选中希望使用的公路／轨道类型，切换到原版的升级模式；也可以直接选择电气化、公交专用道等附加设施工具。
3. 在原版工具参数区开启“整个相连路网”。默认关闭，关闭建造菜单后重置。
4. 点击一段道路或轨道。等待扫描和预检完成，查看当前目标及所选参数、六张数量卡片、进度和预计费用。费用计算中会标明状态；未收到有效报价时显示“—”。窗口内容可以滚动，操作按钮固定在底部。
5. 点击“升级整个路网”。程序先再次核对整个预览范围是否变化，然后逐段提交，正常计费。
6. “取消剩余任务”会等待当前命令返回，再停止剩余任务；已完成的升级保留。结束后可关闭窗口，继续选另一片网络。

## 支持的工具

| 工具 | 整网执行的目标 |
| --- | --- |
| 公路升级 | 当前公路模板及当前公交、轨道、归属、覆盖车道配置选项 |
| 铁路升级 | 当前轨道模板，包括模板自身的轨距、速度和电气化设置 |
| 铁路电气化 | 每段当前模板对应的 `catenaryAdd` 变体，保留各段轨道种类 |
| 公交专用道 | 当前单向／双向选项，在目标方向的靠边车道设置公交专用道 |
| 有轨电车轨道 | 当前单向／双向、电气化选项 |
| 道路锁定 | 锁定道路发展，沿用玩家主动修改后的归属规则 |
| 路段边缘设施 | 当前所选隔音墙、绿化等边缘设施及初始点击侧别 |

原版“反向操作”键（默认 Ctrl，读取 `IA_SECONDARY_MODE`）的状态在第一次点击路段时固定：附加设施工具用于移除设施／解除锁定，公路类型工具用于翻转车道方向。轨道类型工具始终使用当前选中的模板。无需在点击确认按钮时继续按住此键。

单向车道和单侧设施以各段存储方向解释初始点击侧别；任意岔路网络不存在统一的行驶方向或地理侧别。铁路电气化的反向操作读取各段模板的 `catenaryRemove`，缺少相应映射时跳过。移除有轨电车轨道时，不会将只有电车通行模式的专用车道改成无车辆可用的车道。

开关关闭时使用原版操作及快捷键。整网模式按全连通范围选择，不采用 Shift 的单段范围。路口信号配置、逐车道连线、单个信号灯摆放和建筑编辑没有此开关。已有第三方自定义动作的工具不被覆盖。

## 连通范围和结果

- 按道路／轨道的节点邻接关系遍历，经过全部岔路口，包括桥梁、隧道和支线；环路和重复节点不会重复处理。
- 公路和铁路分别遍历，平交道口不会将两者合并为同一网络。上方交叉、贴近或线路站点关系不代表物理路网相连。
- 已符合目标、无法升级和建筑锁定的路段仍用于寻找其后方的连接。车站、车库、建筑内的锁定路段列为跳过项，建筑及模块不会被重新建造。
- 使用不带目标模板参数的 `replaceSegment(entity)` 刷新原路段以生成原生映射，再用 `api.type.Proposal.new()` 和 `api.type.SegmentAndEntity.new()` 建立自有记录，写入当前升级目标；保留原生信号、站点、路径点及节点配置映射。模板与样式名称取自对应资源仓库的标准名称。
- 通过原生 `ProposalViewer` 异步读取预检与报价，每次只检查一段；不会在预览回调中提交命令，也不保存借用的 `ProposalData`。执行前再次用同一路径检查，成功后更新原版退款实体记录。
- 自定义动作实时读取原版参数窗口及工具栏的 React API；切换当前选项后不会继续使用先前复制的参数。电气化只改变模板及对应电气化通行模式，保留自定义车道速度、偏移等其他设置。
- 只提交保持路段几何和拓扑的替换。若原生 helper 为升级要求更改其他路段、节点、建筑或关联设施，则跳过并显示原因。
- 碰撞、坡度、资源不兼容、权限和其他引擎检查仍有效。失败后继续其他路段；余额不足则停止剩余任务。
- 预计费用为逐段预检之和，邻段升级可能影响后续报价。实际按每条命令重新检查和结算，窗口累计实际费用。
- 目标或参数变化会使预览失效，执行中变化则停止后续任务。确认前再次核对实体身份、实际路段属性、节点位置及同类邻接关系，执行前逐段复核；不再将全部 ECS 计数器变化都判为道路被编辑。
- 重复错误合并计数，展开后查看最多五类错误样本；日志记录完整正文、调用阶段与堆栈。原生预览回调持续未返回时停止任务并显示错误，避免每一段都重复等待超时。已提交的命令回调只结算一次，回调处理异常不会重试已完成的升级。
- 资源不兼容、建筑锁定和原生检查拒绝仍逐段跳过。未知 API 异常停止整次任务；原生刷新调用抛异常后，该接口在本次会话禁用，重启游戏后才重新启用，避免在原生异常状态下继续调用。
- 保存的是正常游戏路网修改；扫描队列和 UI 状态不写入存档。卸载 Mod 后入口消失，已完成的升级保留。

## 安装位置与文件

工作目录：`F:\mod\Transport Fever 3\staging_area\xiaom_connected_network_upgrade`。

本机 Steam 用户目录的 `staging_area` 已通过目录联接指向项目的 `staging_area`，本 Mod 不另建第二份同 ID 安装。运行资源列在 `_content.json`，公开发布包包含 `mod.json`、`strings.json`、`_content.json`、`_metadata/` 和 `content/` 即可。开发或本地使用不包含 mod.io 上传。

技术故障的游戏日志前缀为 `[xiaom_connected_network_upgrade]`。启动时记录 revision 和四种构造器的可用性；每次操作记录 session、工具与参数目标、起始实体和源模板、扫描数量、预览汇总、确认、提交结果及停止原因。异常保留阶段、实体和完整正文／堆栈。手动复测步骤见 `VALIDATION.md`。

## revision 3 修订依据

2026-10-08 的截图与日志显示大量 `API 错误`、`路段已变化`，且错误详情只有 `table: ...` 地址。旧的 `tostring(error)` 丢失了异常正文，因此现有日志无法确定每个 API 失败的原始原因。本次将直接调用 `makeProposalData` 的预检改为本机原版桥隧替换界面的 `ProposalViewer` 回调流程，并加入分阶段异常记录；这是依据源码作出的兼容性修正，不能据此宣称旧日志中的全部异常已实机解决。

路段变化判断改为实体身份与实际可编辑属性比对，仍会拦截删除、重建、几何、模板、车道、设施、归属及连通关系变化。截图中的建筑锁定计数属于预期跳过项，不会为了减少该计数拆建车站。

## revision 4 崩溃修复

最新日志确认 revision 3 已载入。本地时间 2026-10-08 05:34:04，在预检的 `replaceSegment(entity, targetTemplate)` 调用内出现 `StreetTemplate::Get` 的索引 `-1` 原生断言，接着出现 `ParkException / CheckedCall` 的 `!g_parkedException` 断言和游戏崩溃。此前还有错误包装器直接拼接表导致的 `attempt to concatenate ... (a table value)`；仅在 Lua `xpcall` handler 中格式化不足以覆盖原生异常返回。

本版在 `xpcall` 返回处统一格式化异常，取消刷新 helper 的可选目标参数，用源路段刷新生成映射，并将编辑对象复制到新建的自有原生记录。补充建筑所有者、子建筑及冻结边检查；不直接修改从引擎结果读取的嵌套记录。遇到未知 API 异常即停止队列，原生刷新异常后还会禁用本会话的后续刷新调用。

日志已证实触发位置和连续异常链；helper 内部具体哪个资源查找产生 `-1` 无法仅从日志确定。上述调用路径与记录所有权修订依据本机 API 定义完成，**revision 4 未游戏内验证**，不能据此宣称所有场景均已排除原生断言。完整退出并重启游戏后再复测。

## revision 5 构造器路径修复

最新 `stdout.txt` 确认 revision 4 于 UTC 2026-10-08 04:37:05 加载；04:37:42 和 04:38:40 两次预检均在实体 `72086` 的 `copy BaseEdge to owned segment` 阶段报错：`attempt to index field 'SegmentAndEntity' (a nil value)`。对应本地时间为 12:37:42 和 12:38:40，错误尚未进入原生刷新、报价或提交阶段。

上一版把类型定义内的 `Proposal.SegmentAndEntity` 当成运行时路径。本机 `api/tealdef/api/type.d.tl` 第 3832 行在 `Type` 导出表中明确写为 `SegmentAndEntity : Proposal.SegmentAndEntity`，实际构造器为 `api.type.SegmentAndEntity.new()`。两处构造调用均已改用根导出；调用前检查构造器，缺失时给出明确的 API 路径和可用性记录，不再仅显示 nil 字段错误。

预检中断的窗口保留该阶段的“已检查”进度，费用标为“预检未完成”；尚无有效报价时显示“—”，只有进入执行阶段才显示已结算费用。补充按 session 关联的操作与异常日志，便于定位后续原生接口问题。**revision 5 未游戏内验证**，没有运行测试或检查器，原生刷新与实际升级效果仍需手动复测。

## 名称与封面

默认名称为“相连路网批量升级 | Connected Network Upgrade”；英文名称也附带中文，简体中文名称为“相连路网批量升级”。

封面位于 `_metadata/0.png`，1920×1080 PNG。封面为 AI 生成的功能示意插画，非游戏实机截图；使用青色高亮铁路分叉、桥梁、隧道，以金色高亮独立公路网络。封面标题为 `CONNECTED NETWORK UPGRADE`。

源图：`F:\mod\Transport Fever 3\output\imagegen\xiaom-connected-network-upgrade-cover-v1.png`。提示词：`F:\mod\Transport Fever 3\output\imagegen\xiaom-connected-network-upgrade-cover-prompt.txt`。采用用户确认的 CLI 生成方式，提供方 `model_providers.custom`（glosc.ai），模型 `gpt-image-2.5`；通过 Pillow 整理发布画幅。源图和提示词不加入 Mod 运行资源索引。

## English

Enable **Connected Network Upgrade**, choose a road/track replacement or a supported feature tool, and turn on **Whole connected network**. Click a segment, wait for the counts and estimated costs, then select **Upgrade whole network**. All branches of the physically connected network are included. Roads and tracks stay separate. Locked construction segments and rejected proposals are skipped, while traversal continues through them. Cancellation stops remaining work after the current command returns. Normal construction costs apply. Closing the construction menu resets the switch. Completed upgrades remain when the mod is removed.

Revision 5 fixes both segment constructors to use the exported `api.type.SegmentAndEntity.new()` path. It logs constructor availability and session stages, and preserves preview progress and incomplete-cost status when preview stops. The source-only refresh, owned proposals, native previews and error stopping remain. It has **not been verified in game**, and no tests or automated checks were run. Restart the game after installing or updating the mod.
