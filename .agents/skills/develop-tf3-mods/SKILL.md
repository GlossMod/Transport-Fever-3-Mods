---
name: develop-tf3-mods
description: "开发、修改、调试或迁移《狂热运输 3》（Transport Fever 3 / TF3）Mod。适用于配置与 Teal/Lua 脚本、车辆和涂装、模型材质、建筑车站、道路轨道、产业及本地化，也用于准备 Mod 发布包。以 TF3 官方手册、本机 API 和原版示例为依据；不把 TF1/TF2 格式直接用于 TF3。"
---

# 狂热运输 3 Mod 开发

交付能在用户当前 TF3 版本中验证的 Mod；明确区分静态检查、Model Editor 验证和游戏内实测。默认用中文解释，文件名、资源 ID 和代码标识符使用英文。

## 项目约定与版本依据

- 项目：`F:\mod\Transport Fever 3`；游戏：`E:\steam\steamapps\common\Transport Fever 3`。先读取任务所在目录的 `AGENTS.md`，迁移到其他机器时重新定位路径。
- **一个 Mod 一个文件夹**。本项目已有 `staging_area/`，新开发默认放在 `staging_area/<mod_id>/`；若用户已有目标 Mod，则直接继续该目录，避免重复创建同 ID 的副本。
- 游戏安装目录用于读取原版资源、类型定义和工具；通过独立 Mod 实现改动。工作源文件与发布内容分离，避免把 `.blend`、`.psd`、测试存档和缓存打包。
- 本技能资料核对于 **2026-10-04**，安装快照为 Steam AppID `3493540`、BuildID `25533170`。BuildID 是核对依据，不是硬性版本要求。游戏升级后重查相关示例和字段。
- 优先级：当前安装包中的实际 API/原版代码 + 同版实测，随后是已适配的 TF3 官方文档。网页标有旧版或未适配提示时，只作为线索；不要从 TF2 推断可调用函数、路径或字段。

## 按任务读取资料

| 当前任务 | 读取内容 |
| --- | --- |
| 新建 Mod、参数、脚本钩子、依赖、加载失败、发布准备 | [核心开发流程](references/core-workflow.md) |
| 查实际 API、读取 ZIP 内原版代码、配置编辑器、核对版本差异 | [本机环境与取证方法](references/local-environment.md) |
| 车辆、涂装、模型材质、建筑、道路产业、TF2 迁移 | [内容开发与迁移](references/content-workflows.md) |
| 学习教程、更新规范或需要准确出处 | [官方资料和教程索引](references/sources.md) |

只读与当前修改有关的章节。未知字段先搜索本机定义和最相近的原版实现，再打开对应官方页面；没有证据时标为待验证，不生成臆测 API。

## 执行流程

1. 明确要改变的行为和验收方式；从请求和现有文件判断是配置、资源、脚本或模型任务。只有会阻塞实现的缺失信息才询问。
2. 检查目标目录的 `mod.json`、`_metadata/modinfo.json`、`content/` 及依赖，选一个相近原版资源作为对照。大型资源通常在 ZIP 内，`rg` 搜不到不代表不存在。
3. 新建时可使用下面的脚手架。它创建 UTF-8 无 BOM 的 TF3 文件，拒绝覆盖已有目录；`pre-run` 模式只加入日志钩子，不实现具体玩法。

   ```powershell
   py -X utf8 '.agents/skills/develop-tf3-mods/scripts/init_mod.py' --output-root 'F:\mod\Transport Fever 3\staging_area' --mod-id 'local_vehicle_tuning' --name 'Vehicle Tuning' --script pre-run
   ```

4. 完成请求所需的最小修改；沿用当前 API、资源类型和作用阶段。资源使用 TF3 命名空间路径；基础配置优先查实际 `preRunFn`，加载后的资源修改查 `postRunFn` 与 `api.res`。
5. 验证 JSON、文本编码、ID、引用和实际存在的资源；有 Teal 检查器时结合本机 `.d.tl` 检查。涉及模型时使用 Model Editor 的校验、LOD 和材质预览。
6. 在测试地图或存档副本中启用 Mod，验证目标行为、参数切换以及保存后重新加载。涉及依赖时同时测试缺少依赖的提示和与目标 Mod 的组合。没有运行游戏就明确写“未游戏内验证”。
7. 交付 Mod 路径、主要变化、启用方法、验证结果和剩余限制。用户要求发布时才进行发布操作；仅做开发或整理技能不包含对外上传。

## 容易误用的 TF3 规则

- 技术定义是 `mod.json`，描述信息是 `_metadata/modinfo.json`，资源在 `content/`。不要创建 TF2 式 `mod.lua + res/` 作为 TF3 新项目。
- `modId` 决定身份，目录名不决定身份；不要把末尾 `_1` 当成 TF3 必需的主版本规则。官方旧示例中仍有 `_1`，不要为此重命名已有 Mod。
- `::/…` 指原版，`some_mod::/…` 指对应 Mod 的 `content/` 根；`/…` 指当前 Mod 根。资源引用不使用 `../`。
- JSON `defaultIndex` 为 0 起始；参数默认返回值是 1、2、3…，配置 `numbers` 时返回所配置的数值。不要沿用 TF2 的“读到索引再统一加一”。
- 脚本引用中的首参 `captureParams` 不能漏；以当前原版签名为准。通用辅助脚本与 `.script.*` 资源的返回形式也要分别查证。
- 价格、速度、容量或产量改变不属于纯外观 Mod；`cosmetic` 和移除风险需要根据最终实现设置。

## 完成标准

“结构正确”不等于“游戏验证通过”。最终状态应能回答：创建/修改了哪个独立 Mod、依据哪个版本和资源、实际测试了什么、尚有哪些未核实行为。若网页示例与本机不符，说明采用本机实现的理由。
