# revision 7 交付记录

日期：2026-10-07。仅调整右下角启动按钮外观：28×28 逻辑尺寸、白色圆面与蓝色齿轮，复用原版小工具按钮的圆形底图、阴影、主题配色和悬停/按下缩放。保持原有可见 GameBar 接入和点击打开窗口的逻辑。新增引用均来自本机 `gui.zip`；图标、圆形底图与阴影实际条目使用 `@2x.tga`，按原版逻辑路径引用。

遵照本项目 AGENTS.md，本轮只阅读并对照源码，**没有运行检查器、回归测试或游戏**。下述静态检查记录属于 revision 6，不能作为 revision 7 的测试结果。

用户复测：完全退出并重启游戏，确认右下角工具栏上方出现圆形齿轮；悬停有中文提示及高亮反馈；点击可打开修改窗口；原工具栏按钮、游戏速度和日期按钮仍可正常操作。

## revision 6 历史交付记录

日期：2026-10-07。依据本机 Steam Build `25533170`。项目 AGENTS.md 要求“完成后不要直接测试，告诉我，我自行测试”。本轮只进行代码审查和静态文件检查，**未运行游戏，未执行回归测试用例**。

## 改动

- 删除旧保存副本 → 异步读取存档元数据 → 载入 → 再保存流程，删除写入 GUI 存档数据的路径。用户卡在“副本已保存，正在准备重载”的流程不再存在。
- 改为选择档位自动记录独立配置；主配置及本地载入缓存用原生 userdata IO 写入并回读检查。已创建本机初始配置，保留截图中的客运 10 倍。
- 工厂产能、载具最高速度、模拟及日历速度使用原生命令；每 GUI 帧最多检查 32 个任务、发送 8 个命令，同时最多等待 8 个回调。12 秒回调超时终止该批，窗口不锁定。
- GUI 会话重新初始化时重新读取配置与本轮资源快照。旧批次回调不能完成新请求，载具实时倍率使用相对本轮已加载模型倍率的比例。
- 其余资源项仍在 postRunFn 应用，明确标注“下次载入”。没有实现全部倍率热更新，也没有实现保存时剔除原生实体状态。
- 窗口改为三块双列卡片，留白与背景放到原生 Component，间距放到 BoxLayout。移除滚动区和忙碌期间禁用/禁止关闭的交互。

## 接口依据

读取本机 `api/tealdef/app.d.tl` 的 loadUserdata/saveUserdata/getUserDataFolder；`api/cmd.d.tl` 的 StockListSetModifiers、VehicleSetModifiers、GameSetSpeed、GameSetCalendarSpeed；`api/engine.d.tl` 的 INDUSTRY.stockList、StockList.Modifiers.productivity 与 TransportVehicle.Modifiers.topSpeedScale。构造器使用 `api.type.StockList/TransportVehicle.Modifiers.new`，其余载具修正复制保留。

原版 `gui/main/styleutil.tl`、`gui/entity_window/entity_window.css.lua` 与 `base/tealdef/scripts/builtin.d.tl` 用于核对组件、布局、原生 Window、字段与样式。未猜测不存在的运行时容量或路网修改命令。

## 静态检查

13 份 content Lua 编译语法检查、3 份 JSON 解析、content 索引一致性、UTF-8 无 BOM，以及 2 份 Python 回归脚本/内嵌 Lua fixture 的语法检查通过。控制器中没有保存/载入存档及 GUI 存档数据写入调用。静态检查仅编译文本，不执行交付 Lua、不运行游戏或模拟引擎。

旧回归脚本已改为独立配置、载入快照、分批命令、超时不锁定、写盘失败、时间只应用一次、新实体覆盖和保留工具栏等用例，**尚未执行**。revision 1～5 的历史检查记录在 `VALIDATION_HISTORY.md`，不能作为新版通过证据。

## 建议用户自测

1. 重新载入，确认右下角入口、三组双列布局和关闭按钮正常；选择倍率时不要再找旧保存按钮。
2. 选择模拟 2 倍和暂停日期，确认立即响应；手动切换原生速度，等待超过 3 秒确认不被覆盖。
3. 工厂选 2 倍、载具速度选 2 倍，确认日志 errors=0、既有工厂/载具的最高速度修正变化；实际速度仍可能受原料或原路网限速限制。
4. 修改客运容量，确认显示待载入数量；关闭再打开窗口仍保留选择。下次正常载入时确认新旧载具容量及路网倍率生效。
5. 退出并重新启动，确认配置与退出前相同；也在另一个启用本 Mod 的地图确认共用配置。
6. 点击恢复默认、再重新应用，确认窗口可编辑/关闭、不创建新存档，不再卡在准备重载。
7. 另在副本测试已装货车辆缩小容量、正常保存重载与移除 Mod；不主动清除货物。

如出现配置问题，日志应提供 `external config at load`、`independent config`、`config write failed` 或 `command unavailable`。本次没有生成新的实机截图，也没有自动载入或保存用户地图。
