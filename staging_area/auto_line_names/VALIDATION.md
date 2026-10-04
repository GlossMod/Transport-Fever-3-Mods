# 验证记录

验证日期：2026-10-04（Asia/Shanghai）。目标安装：Steam AppID `3493540`，Build `25533170`。

## 已完成

- JSON 可解析；`modId` 与两项脚本引用的命名空间一致，所有目标文件存在。
- 文件为 UTF-8 无 BOM；资源采用 TF3 的 `content`、`.gs.lua`、`.script.lua` 结构。
- Lua 5.4 实际执行了发布目录中的两个 Lua 文件，验证语法和脚本入口。
- 通过 28 项模拟 API 测试，包括：客运、货运、多货物排序、自定义货物 ID、非零旅客 ID、最大装载比例为零、车辆容量筛选、待定货物补齐、城内线路、无城镇归属站点、环线、未完成线路、追加站点、货物切换、旧线路保护、其他玩家保护、手动改名、状态复制后的恢复、改名命令延迟与失败重试、更新与命令执行之间手动改名、删除线路与站点、`dt=0` 的更新。
- 模拟 `GameScriptState:get/set` 每次深拷贝，避免测试依赖状态对象共享引用。

测试代码：工作区 `.agents/tests/test_auto_line_names.py`，测试依赖位于 `.agents/tools/line_naming_test_runtime`。两者不属于 Mod 运行内容。

复现命令（工作区根目录）：

```powershell
py -X utf8 '.agents\tests\test_auto_line_names.py'
```

## API 核对依据

安装目录 `E:\steam\steamapps\common\Transport Fever 3` 中：

- `api/tealdef/api/engine.d.tl`：`Line.Stop`、`StationGroup`、`TransportVehicle.Config`、`PlayerOwned`、`getComponent`、`entityExists`。
- `api/tealdef/api/engine/system.d.tl`：`getLinesForPlayer`、`getStation2TownMap`、`getLineVehicles`。
- `api/tealdef/api/engine/util.d.tl`：`getPlayer`、`getEntityName`、`isStationOfType`。
- `api/tealdef/api/res.d.tl`：`cargoTypeRep`、`getPassengerCargoTypeId`。
- `api/tealdef/api/cmd.d.tl`：`makeEntitySetNameCmd`、`sendCommand`。
- `base/tealdef/scripts/gamescript.d.tl`：`update(captureParams, state, dt)`、`postUpdate(captureParams, state, dt, updateResult)`、持久状态读写。
- `base/content/game_mechanics.zip`：原版 `.gs.lua` 引用脚本及 `industries` 的更新/命令执行阶段分离。
- `base/content/gui.zip`：`line_util` 和命名组件确认 `stopConfig.load[cargoId+1]`、`maxLoad`、车辆容量数组、货物名称与城镇映射的实际用法。
- `base/content/scripts.zip`：原版 `.script.lua` 的 `function data()` 资源入口。

## 尚未完成的游戏内验收

本次没有启动游戏、加载测试地图或保存游戏存档。实际资源加载、游戏帧调度、暂停行为和存档序列化仍需游戏内确认；模拟测试不覆盖这些项目。

建议在测试地图启用后完成：

1. 确认 Mod 列表显示“新线路自动命名”，进入地图后日志含 `initialized; existing line names preserved`。
2. 建立跨城客运线路，至少两个停靠站，确认 `[客运] 城镇A-城镇B`。
3. 建立货运线路，确认货物显示名称、首末地点和派车后的筛选；空配置确认待定货物能补齐。
4. 给自动命名的线路追加站点，再手动改名，确认后续编辑保留自定义名称。
5. 保存、退出并重载，确认自动管理和手动改名选择均保留，已有线路名称不被批量修改。
6. 停用 Mod 后重载，确认已生成名称保留，可以继续建立线路。
