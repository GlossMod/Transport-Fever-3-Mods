# 相连路网批量升级 / Connected Network Upgrade

独立 TF3 Mod，ID `xiaom_connected_network_upgrade`，revision **2**。

**本版本未游戏内验证。** 按项目约定没有运行测试、检查器、游戏或 Model Editor。代码依据本机 TF3 API 类型定义、原版建造菜单和已有原生 UI Mod 核对，实际加载、布局、替换效果、扣款及存读档由用户复测。

## 启用和使用

1. 完全退出并重启游戏，在新地图或现有存档的 Mod 列表启用“相连路网批量升级”。
2. 选中希望使用的公路／轨道类型，切换到原版的升级模式；也可以直接选择电气化、公交专用道等附加设施工具。
3. 在原版工具参数区开启“整个相连路网”。默认关闭，关闭建造菜单后重置。
4. 点击一段道路或轨道。等待扫描和预检完成，查看当前目标及所选参数、发现／计划升级／已符合／跳过／失败数量，以及预计费用。
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
- 采用本机 `replaceSegment` 生成的原生映射，修改原生 proposal 副本中的路段，并保留原生信号、站点、路径点映射。
- 自定义动作实时读取原版参数窗口及工具栏的 React API；切换当前选项后不会继续使用先前复制的参数。电气化只改变模板及对应电气化通行模式，保留自定义车道速度、偏移等其他设置。
- 只提交保持路段几何和拓扑的替换。若原生 helper 为升级要求更改其他路段、节点、建筑或关联设施，则跳过并显示原因。
- 碰撞、坡度、资源不兼容、权限和其他引擎检查仍有效。失败后继续其他路段；余额不足则停止剩余任务。
- 预计费用为逐段预检之和，邻段升级可能影响后续报价。实际按每条命令重新检查和结算，窗口累计实际费用。
- 目标或参数变化会使预览失效，执行中变化则停止后续任务。确认前再次检查路网和节点版本，执行前逐段检查版本。
- 保存的是正常游戏路网修改；扫描队列和 UI 状态不写入存档。卸载 Mod 后入口消失，已完成的升级保留。

## 安装位置与文件

工作目录：`F:\mod\Transport Fever 3\staging_area\xiaom_connected_network_upgrade`。

本机 Steam 用户目录的 `staging_area` 已通过目录联接指向项目的 `staging_area`，本 Mod 不另建第二份同 ID 安装。运行资源列在 `_content.json`，公开发布包包含 `mod.json`、`strings.json`、`_content.json`、`_metadata/` 和 `content/` 即可。开发或本地使用不包含 mod.io 上传。

技术故障的游戏日志前缀为 `[xiaom_connected_network_upgrade]`。手动复测步骤见 `VALIDATION.md`。

## 名称与封面

默认名称为“相连路网批量升级 | Connected Network Upgrade”；英文名称也附带中文，简体中文名称为“相连路网批量升级”。

封面位于 `_metadata/0.png`，1920×1080 PNG。封面为 AI 生成的功能示意插画，非游戏实机截图；使用青色高亮铁路分叉、桥梁、隧道，以金色高亮独立公路网络。封面标题为 `CONNECTED NETWORK UPGRADE`。

源图：`F:\mod\Transport Fever 3\output\imagegen\xiaom-connected-network-upgrade-cover-v1.png`。提示词：`F:\mod\Transport Fever 3\output\imagegen\xiaom-connected-network-upgrade-cover-prompt.txt`。采用用户确认的 CLI 生成方式，提供方 `model_providers.custom`（glosc.ai），模型 `gpt-image-2.5`；通过 Pillow 整理发布画幅。源图和提示词不加入 Mod 运行资源索引。

## English

Enable **Connected Network Upgrade**, choose a road/track replacement or a supported feature tool, and turn on **Whole connected network**. Click a segment, wait for the counts and estimated costs, then select **Upgrade whole network**. All branches of the physically connected network are included. Roads and tracks stay separate. Locked construction segments and rejected proposals are skipped, while traversal continues through them. Cancellation stops remaining work after the current command returns. Normal construction costs apply. Closing the construction menu resets the switch. Completed upgrades remain when the mod is removed.

Revision 2 has **not been verified in game**, and no tests or automated checks were run. Restart the game after installing or updating the mod.
