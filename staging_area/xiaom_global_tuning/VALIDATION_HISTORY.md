# revision 1～5 历史记录

以下为旧版本记录，不代表 revision 6 已通过测试。

# 内置修改器验证记录

日期：2026-10-07。安装依据：Steam BuildID 25533170，游戏显示 Build 40408。

## 修改窗口滚动区修复（revision 5）

- 2026-10-07 日志确认右下角入口已挂载且点击后调用了 `UI settings window opened`。当前错误发生在窗口转换阶段：`ScrollArea does not accept a Layout as content`，不是入口注册问题。
- 本机 `gui/menu/mod_manager_react_util.tl:2057` 使用 `ScrollArea.content = builtin.Component { layout = ... }`。revision 5 对照该结构，在滚动区和纵向布局之间增加 `Component`。
- 对照本机 `base/tealdef/scripts/builtin.d.tl` 核对 Window、ComboBox、ComboBoxItem 和 ScrollArea 参数。ComboBox 支持数值选项，包括小数倍率；窗口内容布局保留。
- 43 项自动检查通过。UI 测试替身现在拒绝 ScrollArea 直接接收布局，窗口打开、单例、再次打开及十项设置编辑均在该约束下执行。
- 修复后的真实游戏 UI 验证结果另行记录，自动检查不等于游戏内实测。

## UI 启动错误修复（revision 4）

- 2026-10-06 实际启动日志确认 `XiaomGlobalTuningLauncher as wrapper around nil`，随后 `Recipe child must be a layout` 导致游戏 UI 启动失败。revision 3 的静态测试未覆盖原生按钮配方 ID，不能作为实际加载通过的证据。
- 原生 `builtin.Button` 在本机 GUI 中不能作为 Lua 包装配方的目标。revision 4 删除按钮的 `RegisterWrapperRecipe`；辅助函数直接在工具栏布局中返回原生按钮。保留原版 `GameBar`、中文窗口及倍率控制。
- 自动测试明确禁止将该原生按钮注册为包装配方，43 项检查通过。
- 使用从“新游戏”复制的 `内置修改器UI验证-20261006.sav` 验证，原存档不改动。实际界面结果见后续记录。

## 界面修复（revision 3）

- 已核对用户实际载入日志：revision 2 的界面资源已注册，且打印了 `UI lower-right launcher mounted`，但屏幕仍无按钮。问题不是未安装或未重新载入。
- 本机 `gui/main/game.tl` 将 `EntryPoints` 放在 `internal-hidden`、`class="invisible"` 的节点下，`ModEntryPointExtension` 插件因此继承不可见状态。revision 3 改用 `react-replacement-config` 的启动入口，在可见的 `GameBar` 外添加布局，保留原工具栏及其全部参数。
- 实际载入进一步验证了 TF3 的配方约束：普通配方必须返回布局，包装配方必须返回声明的直接子配方。revision 3 尝试包装 `builtin.Button`，但 2026-10-06 实测发现该原生按钮没有可包装的配方 ID，最终改用 revision 4 的直接原生按钮；外层工具栏使用普通布局配方。
- 核对本机 `gui/menu/mod_manager_react_util.tl:5841`：Mod 参数页向控件传递 `values`，不传 `numbers`。实测存档参数中序号 9 表示 5 倍，序号 10 表示 10 倍，时间序号 1 表示保持设置。原来直接解释为倍率会得到错误效果，现已在加载/保存边界统一转换；`mod.json` 删除不会被该参数页采用的 `numbers`，保持参数键、顺序及默认索引。
- 当前 31 项数据脚本测试与 12 项 UI/controller 测试，共 43 项通过。覆盖全部档位的序号往返、越界回退、0.1/1/2/100 倍、容量取整、混合共享舱室、时间初始化、界面单例、保存与异步读取顺序、其他 Mod 参数保留、重载参数写入、失败清理及原工具栏保留。
- JSON、UTF-8 无 BOM、content 索引及全部 Lua 语法检查通过。测试替身不能证明实际绘制、像素位置或引擎保存重载成功，实际界面验证结果另行记录。

## 名称与封面

- 中文展示名称已改为“内置修改器”，启用说明同步更新；Mod ID 保持 `xiaom_global_tuning`。
- custom-imagegen 使用 `model_providers.custom` / `gpt-image-2.5` 生成源图，保存于开发工作区 `output/imagegen/built-in-trainer-cover-v1.png`；最终提示词为同目录的 `built-in-trainer-cover-prompt.txt`。
- 源图为 1536×1024，经居中裁切和等比缩放后保存为 `_metadata/0.png`。重新读取确认 PNG 格式、1920×1080、2,565,127 字节，小于 8 MB。
- 人工查看源图和最终封面，确认“BUILT-IN TRAINER”与“Transport Fever 3 Mod”拼写准确，列车、卡车、客车和主体符号完整，主要文字未被裁切。
- 三份 JSON 解析、UTF-8 无 BOM、中文名称、Mod ID 和 10 项参数数量检查通过。此次只修改展示名称、封面及说明，未重新进行地图内功能实测。
- 封面为 AI 功能示意插画，已在元数据和使用说明中注明。

## 自动检查

- 当前 43 项测试通过，使用 Lua 5.4（`lupa`）执行交付脚本。
- 完整 JSON 解析、UTF-8 无 BOM、10 个参数的选项与默认索引、content 索引、所有 Lua 语法检查通过。native modParams 与实际倍率在加载/保存边界转换。
- 覆盖默认值与异常参数、0.1/1/2/100 倍、容量取整、零值及负哨兵值、货种排除、客货混合共享舱室、独立重量、火车牵引过滤、陆水空速度、步行与滑行道过滤、弯道公式、桥隧限速、加载期去重及新载入不叠乘。
- 覆盖暂停状态下初始化时间、保持原设置、暂停模拟、暂停日期、延迟世界就绪、仅应用一次及资源修改失败日志。
- 读取并执行本机原版资源数据：295 份车辆模型（卡车 48、客车 24、火车 70、车厢 41、船舶 27、飞机 30、电车 55）；107 份基础设施配置（道路 81、轨道 6、桥 4、隧道 6、道口 10）。验证资源字段变换。
- 自动化使用 API 测试替身，不等于游戏内经济、物理、装载或存档验证。

## 游戏内检查

已启动本机 TF3 并核对日志。初次识别发现 `numbers` 中整数字面量导致 `Value is not a double`，已改成浮点字面量并加入自动检查。修复后游戏于 15:05:24 识别 staging Mod，日志记录 `new ModHubMod ... xiaom_global_tuning`，模组数从 22 增加为 23，后续刷新成功。

游戏用户数据目录的 `staging_area` 是指向本工作区的目录联接，最终只有一个生效来源；无需复制安装。曾创建的安装目录副本已移至 `output/global_tuning_install_archive` 留存，不在游戏模组扫描目录中。

用户已在地图中启用本 Mod，日志确认生产/资源/时间脚本均运行。以下场景尚未完成全面游戏内实测，不能据自动检查或加载日志宣称已经通过：

- 既有和新购车辆的实际容量、装载时间及满载重量行为。
- 工厂实际生产、重载列车牵引表现。
- 既有与新建路网的有效速度以及桥隧、弯道限速。
- 保存重载、倍率切换、已装货车辆缩小容量、移除 Mod。
