# 验证记录

更新日期：2026-10-07，Asia/Shanghai。Anarchy / 无碰撞，身份 xiaom_no_collision，当前修订 3。遵循 `AGENTS.md` 的“完成后不要直接测试，告诉我，我自行测试”，本轮未执行自动化或游戏内测试。

## 修订 3：建筑放置回调异常修复

- 当前 `local/crash_dump/stdout.txt` 于 2026-10-07 13:48:47–13:48:50 UTC 连续记录 `cannot write to read only member 'errorState'`，堆栈指向 `xiaom_no_collision::/anarchy_util.lua:20` 的 `filterPreviewErrors`，随后出现 `Lua bridge userdata error while triggering callback`。旧代码在原版 `getProposalStringsFn` 中修改嵌套错误列表，并赋值 `proposalData.errorState = errors`；该赋值在实际 UI 回调的只读 userdata 上抛错。
- 本机 `api/tealdef/api/type.d.tl:2688` 声明 ProposalData 和 ErrorState 字段，但字段声明不保证 UI 回调可写。旧自动化替身允许复制后写回，因此其通过记录未捕获真实约束。
- 新实现仅读原版错误字段，复制 critical、messages、warnings、infos 到自有 Lua 表。只在副本中移除允许的非致命碰撞/曲率信息；将副本交给强制建造窗口判断，不写原版 ProposalData 或 ErrorState。
- 普通菜单的原版回调继续先执行并保留其返回值。菜单扩展和强制预览捕获使用异常隔离；扩展失败时清除旧强制方案并记录原始原因，同一连续错误合并记录，原版回调正常返回。
- 强制命令仍使用自有 Proposal.clone 副本、原版玩家/退款上下文及 ignoreErrors=true；未知或致命错误继续禁止强制建造。普通合法位置沿用原版建造；仅有允许碰撞错误时，原版预览可能保持红色，使用独立强制按钮。
- 已改写错误过滤与回调检查，替身将 ProposalData 及嵌套成员设为只读；另准备普通合法只读预览、扩展失败时原版结果仍可返回且旧预览失效、原生碰撞数据保持不变但可用副本提交强制命令的回归代码。**本轮均未运行**。
- 修订 3 源文件通过 staging_area 目录联接供游戏读取。需完全退出并重启游戏，让旧 `getActionParams` 包装和 Lua 模块缓存失效，然后在测试副本复测普通仓库、道路及建筑放置、碰撞处的强制按钮、取消/切换工具、费用与存读档。尚未将这些行为标记为游戏内验证通过。

## 历史自动检查（修订 2）

2026-10-05 曾运行：py -X utf8 .agents/tests/test_no_collision.py。修订 2 的 14 项 Lua 5.4 检查通过，使用工作区既有 Lupa 运行库，测试与依赖不随 Mod 分发。以下为历史范围，不能作为修订 3 的通过结果；当时可写错误记录替身与实际 UI 不符。

- 精确过滤英文及中文碰撞和曲率错误，保留未知错误、费用及信息。
- 保留致命错误及其他 Mod 主动设置的提交限制。
- 钩子重复安装安全，原回调和声誉信息保留，仅处理标准道路和建筑菜单。
- Proposal.clone 创建自有副本，不在回调外保留借用对象。
- 实際命令忽略非致命错误、设置玩家归属及退款上下文。
- 重复提交、工具切换、失效会话及失败处理。
- React 重建相同定义时保留会话，改选建筑、模板或实体时使旧预览失效。
- 初始菜单没有 Anarchy 窗口时不改动窗口容器；鼠标离开地图进入按钮区域时保留最后的预览。
- 用当前游戏 GUI ZIP 中的 React 实现验证窗口包装及按钮回调。
- JSON、UTF-8 无 BOM、身份、本地化、内容索引与引用；无 pre/postRun 资源改写。

## 本机依据

游戏版本 40408 Windows 64-bit，Steam BuildID 25533170。

- api/tealdef/api/type.d.tl：Proposal.clone、ProposalData.errorState、ErrorState.critical/messages、Context。
- api/tealdef/api/cmd.d.tl：makeWorldBuildProposalCmd 的 ignoreErrors 允许非致命错误提案。
- base/tealdef/scripts/builtin.d.tl：ConstructionActionParam.getProposalStringsFn。
- base/content/gui.zip：construction_react_util.tl 的 getActionParams、bootstrap_game.tl 的 react-replacement-config、原生 React 和窗口组件。
- 原版中文 base.mo：Collision 为“碰撞”，Too Much Curvature 为“曲率过大”。

## 游戏内状态

最终采用 GUI 提案提交，不改写全局模型或道路模板。之前的资源改写方案在独立新地图载入时发生原生崩溃，已移出 Mod。资源载入日志不能证明建造成功。

模组列表已确认英文名 Anarchy 和 ANARCHY 封面。仅启用当前 GUI 方案的全新进程能够加载预览钩子，但在进入地图时停住；没有完成实际建造。

另以全新进程、不启用任何 Mod 创建原版对照地图，种子 3PRYEllbIR。日志的 Active mods 列表为空，15:19:45 UTC 到达 GUI 初始化的 push() default tool；至 15:59 UTC 仍停在载入页，Escape、前台激活和关闭快捷键没有恢复。对照日志保留在工作区 .agents/diagnostics/anarchy_resource_attempt/no_mod_baseline_stdout.txt，不随 Mod 分发。说明载入阻断也发生于无 Mod 环境，不能据此认定 Anarchy 运行正确或确认故障根因。

待完成：最终方案进入可操作地图、道路与建筑实际强制放置、保存并重新加载。上述项目均未标为通过。

日志源：C:\Program Files (x86)\Steam\userdata\233840157\3493540\local\crash_dump\stdout.txt。原用户存档未覆盖，使用独立新地图测试。
