# 全公司载具升级 | Fleet Upgrade

中文说明

为全公司自有载具生成可编辑的升级方案。打开统计窗口的“载具”标签，点击“升级载具”，查看推荐、调整目标并确认批量升级。

主要功能
• 道路车辆、列车、电车、船舶和航空载具；读取游戏实际加载的车型，包括具备有效载具数据的已启用 Mod 车型。
• 按原车型与运输用途分组，支持运输方式、线路和名称筛选，以及逐辆选择、分组修改、单辆覆盖和“保持原样”。
• 根据装载配置、当前货物与线路货物过滤识别用途；空载时保留可识别的用途，不能确定时保留原车型支持范围。
• 自动推荐先保证对应货物容量与额定速度不下降，再优先最新年代；机车还比较功率和牵引力。手动可选更新但性能较低的车型，并显示下降项。
• 普通列车逐节匹配机车、客车厢和货物车厢；保留部件顺序、数量与朝向。固定编组动车按整组处理。
• 原车与目标并排预览图片、名称、年代、容量、速度及适用动力指标。柴油转电力等变化会显示供电与设施提示。
• 显示新购费用、旧部件折旧抵扣、最终净支出、余额及升级数量；净支出为负时显示预计返还。部分替换会抵消保留部件价值。

价格与执行
新购部分总价 − 被替换部分折旧抵扣 = 最终净支出。
点击确认后按执行时的最新报价升级，支出上涨也继续；最新费用超出余额时阻止提交或停止剩余队列。载具配置变化、无效购买目标、货物装不下或命令失败仍会阻止执行。
替换使用游戏原生命令；按净支出从低到高开始逐辆处理并等待结果。首个失败后停止，显示成功、失败和未执行项目；已成功项目不能整批回滚。线路、电气化和停靠设施由玩家自行核对。

使用方法
1. 启用本 Mod，并在存档副本中载入。
2. 打开统计窗口 → 载具 → 升级载具。
3. 查看或修改分组与逐辆目标，检查容量、供电提示和费用。
4. 点击“确认升级”，查看逐辆处理结果。
更新 Mod 后请重启游戏。无需额外 Mod 依赖。

语言与发布状态
发布标题、摘要和描述提供中文与英文；当前游戏内升级界面为中文。
当前为功能开发版，最新变更尚未完成游戏内验收，建议先在存档副本中使用。
封面为 AI 生成的功能示意插画。

English Description

Create editable upgrade plans for your company's vehicles. Open the Vehicles tab in the statistics window, select the upgrade button, review recommendations, adjust targets and confirm a batch upgrade.

Features
• Road vehicles, trains, trams, ships and aircraft. Reads models actually loaded by the game, including enabled mod vehicles with valid vehicle metadata.
• Groups parts by original model and transport purpose. Filter by transport mode, line or name; select individual vehicles, set group targets, override individual choices or keep original parts.
• Identifies purpose from loading configurations, current cargo and line cargo filters. Retains identifiable purposes for empty vehicles; when purpose is unknown, preserves the original model's supported cargo range.
• Automatic recommendations require no reduction in relevant cargo capacity or rated speed, then favor the newest introduction year. Locomotives also compare power and tractive effort. Manual choices may use newer, weaker models, with performance reductions shown.
• Matches locomotives, passenger coaches and freight wagons individually in ordinary trains, retaining part order, count and orientation. Fixed multiple units are handled as complete sets.
• Shows original and target images, names, years, capacity, speed and applicable traction figures side by side. Power changes, such as diesel to electric, show infrastructure notices.
• Shows purchase cost, depreciation credit, net cost, balance and upgrade count. Negative net cost indicates an expected refund. Partial replacements account for the value of retained parts.

Pricing and execution
New purchase cost − depreciation credit for replaced parts = net cost.
Confirmation authorizes upgrades at the latest quote before execution, including price increases. Insufficient funds prevent submission or stop the remaining queue. Configuration changes, invalid purchase targets, insufficient cargo capacity and command failures still block execution.
Uses the game's native replacement command. Starts with lower net-cost vehicles, processes one vehicle at a time and waits for the result. Stops at the first failure and reports completed, failed and unexecuted items; completed upgrades cannot be rolled back as a batch. Check line electrification and stopping facilities yourself.

How to use
1. Enable the mod and load a copy of your savegame.
2. Open Statistics → Vehicles → the vehicle upgrade button.
3. Review or edit group and individual targets; check capacity, power requirements and costs.
4. Confirm the upgrade and review the per-vehicle results.
Restart the game after updating the mod. No additional mod dependencies.

Language and release status
The listing title, summary and description are bilingual. The in-game upgrade interface is currently Chinese.
This is a development release. Full in-game acceptance checks for the latest changes have not been completed; use a savegame copy first.
Cover: AI-generated illustration of the mod's purpose.

revision 10 — 发布资料整理 / Publication materials

中文：准备中英双语标题、摘要、描述和独立上传包，沿用 Fleet Upgrade 封面。运行代码沿用 revision 9：支出上涨时按最新报价继续升级，余额不足仍停止；保留可编辑预览、货物用途匹配、折旧报价和逐辆执行。

English: Adds a bilingual title, summary, description and a clean upload archive, retaining the Fleet Upgrade cover. Runtime code is unchanged from revision 9: upgrades continue at the current quote when prices rise, while insufficient funds still stop execution. Includes editable previews, cargo-aware matching, depreciation pricing and sequential replacement.
