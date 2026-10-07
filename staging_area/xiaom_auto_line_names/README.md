# 自动线路命名 / Auto Line Names — revision 4

默认 `[铁路客运] 北京-天津-001`、`[铁路货运] 煤炭-矿山-钢厂-001`。标签随游戏语言切换；可强制中文或英文。其他语言回退英文。

## 使用

启用后创建至少有两个不同停靠点的线路。新线路只有仍使用游戏默认名称时才自动接管；首次启用时旧线路保留。类型无法判断时继续等待，派车后优先按实际车辆判断。

载入选项：命名格式（完整／原始／紧凑／自定义）、标签语言、地点类型（城市／简称／站点／产业）、货物样式、区域分类及自动复核间隔（默认 60 秒、30／120 秒或仅新线路）。新线路发现及手动改名检查约每两秒，暂停时 GUI 时钟仍触发检查；无 GUI 时使用模拟时间作为后备。

产业只选站点货运服务范围内的产业，优先最近者，相同距离按实体 ID，找不到时回退站点。城市模式同城和无城市归属时使用站点。环线跳过末尾重复首站。货物按资源顺序显示前三项，再加 `+N`。

## 手动保护和批量操作

手动改名后退出自动管理；`Cst ` 前缀也受保护。将名称改成 `r` 或 `reload` 可恢复，编号保留（交通类别／客货类型变化时转入对应类别）。分类编号从 001 起，不回收，不因站点或货物变化而重排。

线路管理器顶部点击“批量自动命名”：选择所选线路或当前玩家全部线路，检查旧名、新名和跳过原因。默认跳过受保护名称，可勾选包含。预览和取消不分配编号；确认前复核，变化时需刷新后再次确认。确认后持续自动管理；之后再手动改名仍可退出。

## 高级配置

编辑 [content/user_config.lua](content/user_config.lua)，重启游戏、载入存档，再在线路管理器点击“重新载入配置”。第一次启用导入该文件，之后使用存档中的配置；更新 Mod 不会自动覆盖。每个存档单独导入。格式／语言等载入选项不保存在高级配置中，以当前载入选项为准。

支持 `{transportType}`、`{serviceType}`、`{cargoTypes}`、`{placeA}`、`{placeB}`、`{lineType}`、`{lineNumber}`。英文 `{transportType}` 含末尾分隔空格，便于与 `{serviceType}` 连用。`lineType` 为 LO／IC／RE，取沿途不同城市数 1／2／3+；未知为空。自定义模板自行控制是否显示它。

可配置编号宽度（1–8）、简称字符数（1–32，按 Unicode 字符截断）、货物显示数量（1–16）、中文英文标签和货物覆盖。货物键支持资源全名或 basename，如 `coal`；覆盖值支持 `full`、`short`、`code`。没有内置缩写的货物保留全名，标准货物代码和常见中英文简称由模块提供。错误配置拒绝导入，保留上次有效值；首次错误使用默认值并显示原因。

自定义例子：

```lua
return {
  passengerTemplate = "{lineType}-{transportType}{serviceType}-{placeA}-{placeB}-{lineNumber}",
  freightTemplate = "{cargoTypes}-{placeA}-{placeB}-{lineNumber}",
  numberWidth = 4,
  labels = { zh_CN = { train = "火车" }, en = { train = "Rail" } },
  cargoOverrides = { coal = { short = "煤", code = "COAL" } },
}
```

## 更新和验证

revision 4 修复 Build 40408 中 `naming_runtime.lua` 的 `get_native` 致命断言：模拟线程统一使用普通表存储 API，调度心跳不写入存档。高级配置、管理状态、编号及待确认命令仍按版本 2 状态格式保存。旧存档直接继续使用；更新后需要重新启动游戏，让脚本重新加载。

同一 Mod ID `xiaom_auto_line_names`；revision 2 状态迁移至 2，保留受保护名称和待确认改名命令。仅修改名称、保留 cosmetic 属性，停用后名称不还原。无需依赖。原有封面及 mod.io 绑定 6426466 保留，本次不上传。

71 项测试：`py -3.11 -X utf8 .agents/tests/test_auto_line_names.py`、`py -3.11 -X utf8 .agents/tests/test_line_names_v3.py`、`py -3.11 -X utf8 .agents/tests/test_line_names_ui.py`。模拟测试与游戏实测分开记录，见 VALIDATION.md。

## English

Revision 4 fixes the fatal `get_native` assertion in Build 40408 by using the plain-table GameScript storage API. Scheduling heartbeats do not write save data. Save state version 2 remains compatible; restart the game to load the updated scripts.

Select naming format, label language, place/cargo styles and refresh interval in loading options. The line manager provides batch preview and confirmation, enabling ongoing updates after takeover. Manual names are protected; rename to `r` or `reload` to resume. Edit `content/user_config.lua`, restart TF3, then use Reload configuration. Applied advanced settings live in each savegame and survive mod updates. This local upgrade does not upload to mod.io.
