# 官方资料和教程索引

访问日期：2026-10-04（Asia/Shanghai）。以下资料经内置浏览器从官方首页、Modding Manual 导航进入并读取。摘要为针对开发的整理，不是官方手册镜像。搜索结果中的 AI 摘要、旧代教程与安装 Mod 的视频不作为 TF3 API 证据。

## 从哪里开始

| 资料 | 用途与核验状态 |
| --- | --- |
| [TF3 官方首页](https://www.transportfever3.com/) | 已读；官方 Wiki 与论坛入口，避免把其他代际的网站当 TF3 文档。 |
| [Modding Manual](https://wiki.transportfever3.com/doku.php?id=modding) | 已读；官方总目录，覆盖资源、车辆、建筑、环境、脚本。部分栏目仍显示 Coming Soon。 |
| [Introduction](https://wiki.transportfever3.com/doku.php?id=modding:introduction) | 已读；从配置调整或静态资产入门，并提供两个可下载示例。 |
| [Mod Definition](https://wiki.transportfever3.com/doku.php?id=modding:general:moddefinition) | 已读；`mod.json`、元数据、依赖、版本和本地化。 |
| [Mod Parameters & Scripts](https://wiki.transportfever3.com/doku.php?id=modding:general:modscripts) | 已读；参数返回值和三个加载钩子，附过滤、修改、添加资源的示例。 |
| [Syntax](https://wiki.transportfever3.com/doku.php?id=modding:general:syntax) | 已读；JSON、Lua/Teal、`ug_require`；语法细节仍需编译器验证，不能逐字照搬网页中疑似排版错误。 |
| [Resource Types & Structure](https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes) | 已读；文件后缀、命名空间、静态/动态脚本、DDS 和目录组织。 |

建议学习顺序：Introduction 的配置示例 → 本机官方 no-costs 脚本 → 参数和加载阶段 → 一种具体内容（涂装或建筑）→ Model Editor 验证 → 游戏实测 → 发布。

## 按内容选择教程

| 资料 | 用途与核验状态 |
| --- | --- |
| [Model Editor](https://wiki.transportfever3.com/doku.php?id=modding:tools:modeleditor) | 已读核心流程；FBX 导入、模型属性、截图图标、Validate 和 TF2 Convert。Setup 段仍夹有 TF2 路径字样，启动路径采用本机安装包。 |
| [External Tools](https://wiki.transportfever3.com/doku.php?id=modding:tools:external) | 已读编辑器/建模部分；Teal 和 VS Code 配置、Blender→FBX 路线。文中的 `dev-workspace` 与 `workspace_def` 不匹配本次安装，见本机环境文档。 |
| [Vehicle Basics](https://wiki.transportfever3.com/doku.php?id=modding:vehicles:basics) | 已读通用元数据和容量结构部分；完整车辆类型细节开发时再查。 |
| [Repaint Mods](https://wiki.transportfever3.com/doku.php?id=modding:vehicles:repaints) | 已读；最小增量文件、材质引用、依赖、每级 LOD 和图标。 |
| [Construction Basics](https://wiki.transportfever3.com/doku.php?id=modding:constructions:basics) | 已读定义和参数部分；建筑、车站、产业等 `.con.lua` 的起点。 |
| [Common Pitfalls and Best Practices](https://wiki.transportfever3.com/doku.php?id=modding:general:bestpractice) | 已读；LOD、draw calls、透明玻璃、灯光与贴图。按目标内容取用，不将建议值当通用硬上限。 |
| [Localizations](https://wiki.transportfever3.com/doku.php?id=modding:misc:localizations) | 已读；区分 Mod 的 `strings.json` 与新增整套游戏语言包。 |

下列入口已在官方总目录中确认，但本次未逐页研读；实现相应内容前需要打开正文核对：

- [Vehicle Types](https://wiki.transportfever3.com/doku.php?id=modding:vehicles:types)、[Models](https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes:mdl)、[Materials](https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes:mtl)。
- [Construction Types](https://wiki.transportfever3.com/doku.php?id=modding:constructions:types)、[Modular Constructions](https://wiki.transportfever3.com/doku.php?id=modding:constructions:modular)、[Construction Templates](https://wiki.transportfever3.com/doku.php?id=modding:constructions:templates)。
- [Tracks and Streets](https://wiki.transportfever3.com/doku.php?id=modding:infrastructure:tracksstreets)、[Cargo Types](https://wiki.transportfever3.com/doku.php?id=modding:misc:cargo)、[Terrain Generators](https://wiki.transportfever3.com/doku.php?id=modding:environment:terraingenerators)。

## API、发布与明确的资料缺口

| 资料 | 状态与使用限制 |
| --- | --- |
| [API Reference 导读](https://wiki.transportfever3.com/doku.php?id=modding:scripting:api) | 已读；明确说明参考尚不完整，推荐用控制台和 `debugPrint` 探查。 |
| [Scripting Reference](https://wiki.transportfever3.com/script-doc/) | 已打开索引；页面显示生成日期 2026-08-19。`api.res`、`api.engine`、`api.cmd`、`api.gui` 等具体成员需进入对应页或查本机 `.d.tl`，不能仅凭模块名假定可用。 |
| [Publish a Mod](https://wiki.transportfever3.com/doku.php?id=modding:general:publishing) | 已读；当前返回页面显示 **old revision**。可参考 staging_area、Mod Hub 和更新绑定流程，发布当天重核。 |
| [Creating and Updating Mods via the In-Game Mod Manager](https://mod.io/g/transportfever3/r/creating-and-updating-mods-via-the-in-game-mod-manager) | mod.io 社区指南，作者 GlcrT，页面更新于 2026-10-02；2026-10-04 已读并复核。补充实际 staging 路径、`_content.json` 和数字 Mod ID 绑定；实际校验、上传结果仍以游戏为准。操作整理见 [mod.io 发布与更新](modio-publishing.md)。 |
| [Guidelines & Requirements](https://wiki.transportfever3.com/doku.php?id=modding:general:guidelines) | 已读主要要求；页面显示 **old revision**。尺寸、容量和主机限制须以当前规则及官方验证器为准。 |
| [Ingame Tools](https://wiki.transportfever3.com/doku.php?id=modding:tools:ingame) | 页面明确标注 **not yet adapted for Transport Fever 3**。不把其中快捷键、热重载列表或日志路径视为已验证 TF3 行为。 |
| [Base Config](https://wiki.transportfever3.com/doku.php?id=modding:scripting:baseconfig) | 页面明确标注 **not yet adapted for Transport Fever 3**；旧 `res/config`、`game.config` 示例不能代替本机 TF3 `base/mod.script.tl`。 |

## 官方可下载示例

已核实入口，未下载或运行；需要时从所属教程进入并检查内容。

- Introduction：[静态资产示例](https://wiki.transportfever3.com/lib/exe/fetch.php?media=modding:introduction:ug_tf3_example_asset.zip)、[配置修改示例](https://wiki.transportfever3.com/lib/exe/fetch.php?media=modding:introduction:wiki_example_config_change.zip)。
- Mod Parameters & Scripts：[资源过滤](https://wiki.transportfever3.com/lib/exe/fetch.php?media=modding:templates:wiki_example_mod_param_filter.zip)、[容量修改](https://wiki.transportfever3.com/lib/exe/fetch.php?media=modding:templates:wiki_example_mod_param_modifier.zip)、[资源添加](https://wiki.transportfever3.com/lib/exe/fetch.php?media=modding:templates:wiki_example_mod_param_adder.zip)。

项目技能位置依据：[OpenAI Build skills](https://learn.chatgpt.com/docs/build-skills)，已读；项目本地发现目录为 `.agents/skills`，保留自动匹配。此链接用于技能维护，不用于 TF3 开发。
