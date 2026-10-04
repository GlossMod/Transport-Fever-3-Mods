# 内容开发与 TF2 迁移

按当前任务阅读对应段落；参数和路径细节见 [核心流程](core-workflow.md)，官方入口见 [资料索引](sources.md)。

## 配置、资源与运行时脚本

先判断效果发生在加载期还是模拟运行期。一次性的基础配置修改查看本机 `preRunFn`；车辆元数据批量调整查看 `postRunFn` 和 `api.res`。持续游戏行为需查 `.gs.lua`、原版 game scripts 与当前 engine/GUI 上下文，不能用加载钩子冒充每帧运行逻辑。

对使用的 API 定位到具体声明，验证参数、返回类型、可用上下文以及读操作/命令操作的区别。索引本身不保证某个函数可用。[API 导读](https://wiki.transportfever3.com/doku.php?id=modding:scripting:api)、[API 索引](https://wiki.transportfever3.com/script-doc/)

## 车辆与涂装

改现有载具数值时先看实际 `.mdl` 的 metadata，不用 TF2 字段表盲改。当前基础教程中有 `transportVehicle`、运输模式、`compartmentsList`、`loadConfigs` 和 `cargoEntry`；核对真实容量层级及单位后改动。出现车辆不在购买菜单，需检查年代、车型支持、`filterTags` 和分组引用，而不只是文件存在。[Vehicle Basics](https://wiki.transportfever3.com/doku.php?id=modding:vehicles:basics)

涂装采用独立 `modId`：添加自己的 `.mdl`、发生变化的 `.mtl`、贴图和 UI 图标，未改网格引用原资源；以其他 Mod 为基础时声明依赖。复制材质会改变相对路径的上下文，未更改的贴图要改成指向原来源的正确引用。每个 LOD 都检查材质映射。分发改造的第三方资源前核对许可；不因为浏览到示例就把作者授权视作已有。[Repaint Mods](https://wiki.transportfever3.com/doku.php?id=modding:vehicles:repaints)

验收：购买、线路运行、载客/装货、门和车轮动画、日夜灯光、远近 LOD、图标、存读档；只改数值时把验证集中在该数值和受影响行为上。

## 模型、材质与贴图

模型以 `.mdl` 描述，网格由 `.msh` 和同名 `.msh.blob` 配套；TF3 模型格式使用 `version = 2`，但这不是将旧文件改一个数字就完成转换的理由。资源目录按车辆或资产组织，不要求照搬 TF2 按文件类型集中组织的 `res/`。[资源类型](https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes)

实用流程：从同类原版模型确认尺寸和 metadata → 在建模工具输出 FBX → Model Editor 导入到明确的目标 Mod → 检查材质、动画和 metadata → Validate → 生成图标 → 游戏内验证。Blender FBX 导入时核对坐标选项。Model Editor 的保存会写入所选目标 Mod，操作前看清该目标。[Model Editor](https://wiki.transportfever3.com/doku.php?id=modding:tools:modeleditor)

DDS 应带 mipmaps，尺寸采用 2 的幂；法线、透明度及颜色贴图的压缩方式按当前材质需求选择。UI 图标可用 `.tga`。不要通过改扩展名伪装纹理格式，也不要把新画的一张图当成已完成网格、UV 和 metadata 的模型。[资源贴图说明](https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes)

LOD 不仅减面，也减少网格/材质组合产生的 draw calls；在模型编辑器查看统计。透明玻璃排序、远景材质、灯光范围及数量要实测，优先对照同类原版模型。[性能与内容建议](https://wiki.transportfever3.com/doku.php?id=modding:general:bestpractice)

## 建筑、车站、产业、道路和环境

`.con.lua` 是多类建筑和可放置资产的入口，静态声明与动态 `.script.lua`/`.script.tl` 分开核对。以同类型原版实例为起点，追踪菜单分类、参数、更新脚本、连接节点和实际生成数据；参数选项的默认返回值是 1 起始。[Construction Basics](https://wiki.transportfever3.com/doku.php?id=modding:constructions:basics)

车站重点验证线路接入、路径和装卸；产业验证货物类型、生产行为和存档；道路/轨道验证几何、连接、运输模式及升级。不要把建筑成功显示等同于功能正常。相应专章的链接在资料索引中，其中未研读章节需要按任务打开。

## TF2 → TF3 迁移

先保留旧 Mod 的工作副本，盘点模型、材质、脚本和依赖。Model Editor 的 Convert 提供 `res`→`content`、材质及模型 metadata 的部分迁移；新字段仍需补齐，脚本行为不因此自动兼容。[官方转换说明](https://wiki.transportfever3.com/doku.php?id=modding:tools:modeleditor)

| 旧项目常见内容 | TF3 核对动作 |
| --- | --- |
| `mod.lua`、目录名末尾版本号 | 建立 `mod.json` 与 `_metadata/modinfo.json`，显式确定身份和修订号 |
| `res/` 和旧绝对/相对资源引用 | 转到 `content/`，逐个修正当前 Mod、原版和依赖 Mod 的命名空间 |
| 旧材质、模型 metadata | 使用 Convert 后验证材质与新字段，再检查 LOD、动画、灯光和图标 |
| 脚本直接修改 `game.config` | 对照本机 `preRunFn` 与 `BaseConfig`，重新选择阶段和实际字段 |
| 选项返回 0 起始 | 重审所有参数计算、条件和数组索引，核对 `numbers` |
| 旧回调、文件后缀、引擎 API | 按 `.d.tl` 和原版逐项替换；不得只把扩展名改为 `.tl` |

迁移验收至少包含独立加载、实际使用、参数切换、保存重载。只有通过对应测试才写“已兼容”；其余明确记录未验证的部分。
