# 核心开发流程

## 目录和身份

```text
staging_area/<mod_id>/
├── mod.json
├── _metadata/
│   └── modinfo.json
├── content/
│   └── mod.script.tl       # 仅在需要脚本时添加
└── strings.json            # 仅在需要翻译时添加
```

`modId` 使用小写字母、数字和下划线，推荐作者前缀。沿用已有 ID；兼容更新增加 `revision`，不兼容重做再考虑新 ID。同 ID 的本地多份安装存在优先级：staging area → 手动安装 → 订阅版本。出现“修改没生效”先核对实际加载来源。[官方定义](https://wiki.transportfever3.com/doku.php?id=modding:general:moddefinition)

`mod.json` 是技术配置；`modinfo.json` 放名称、摘要、说明、作者等展示信息。新内容完成前重新判断 `severityAdd`、`severityRemove` 和 `cosmetic`。技术依赖引用游戏 `modId`，发布页面元数据里的依赖可能引用 mod.io 数字 ID，二者不能混用。

脚手架 `../scripts/init_mod.py` 提供 `none` 和 `pre-run` 两种模式。无脚本模式只建结构；日志模式额外建立钩子供加载验证，不代表用户请求的玩法已完成。

## 生命周期和签名

| 阶段 | 选择依据 |
| --- | --- |
| `preRunScript` | 资源加载前，修改传入的 `baseConfig`。查看当前原版配置及官方 no-costs/sandbox 示例。 |
| `runScript` | 资源加载前注册必要的过滤或修改逻辑；具体注册 API 必须查当前版本。 |
| `postRunScript` | 所有资源加载后，使用当前 `api.res` 检查、调整或添加资源；官方建议可行时在此过滤/修改资源。 |

作用阶段来自[参数与脚本文档](https://wiki.transportfever3.com/doku.php?id=modding:general:modscripts)。网页有时只列业务参数而省略首参；实际函数还接受 `captureParams`。本机 `urbangames_no_costs` 和 base 脚本核实的签名为：

```lua
local mod = {}

mod.preRunFn = function(captureParams, configDict : {{string, string}}, allModParams : {string : {string : integer}}, baseConfig : BaseConfig)
    debugPrint("[my_mod] preRunFn")
    -- 在这里实现已核实的基础配置调整。
end

return mod
```

对应文件是 `content/mod.script.tl`，`mod.json` 引用形如：

```json
"preRunScript": {
  "fileName": "my_mod::/mod.script@preRunFn"
}
```

此处是 JSON 片段，合入完整对象；`my_mod` 要替换为真实 ID。资源引用省略末尾 `.tl`，保留 `.script` 和 `@函数名`，与本机官方示例一致。不要把 Teal 的类型注解交给普通 Lua 解释器验证，也不要把资源脚本返回表和普通辅助模块的契约混为一谈。

## 参数与语言

JSON 中的 `defaultIndex` 是 0 起始；脚本中默认收到 1 起始的选项数值。若定义了 `numbers`，按该数值解释，不再当作数组位置。使用 `allModParams[getCurrentModId()]` 获取当前 Mod 参数；兼容旧存档缺失字段及越界数据。修改容量等数值时按目标资源类型过滤，避免重复乘算。参数规则见[官方脚本文档](https://wiki.transportfever3.com/doku.php?id=modding:general:modscripts)。

Mod 文本使用 `strings.json`，显示元数据可在 `modinfo.json.localization` 中翻译。简体中文标识本机核实为 `zh_CN`，英语为 `en`；保留 `%1%`、`{townName}` 等格式占位。整套新增游戏语言涉及 `.lang.lua` 和 `.mo`，不应为普通 Mod 翻译引入这套流程。[本地化说明](https://wiki.transportfever3.com/doku.php?id=modding:misc:localizations)

## 资源解析

以下都是游戏资源路径，与 Windows 文件系统路径不同：

| 引用 | 解析起点 |
| --- | --- |
| `mat/paint.mtl` | 当前资源所在目录、当前 Mod |
| `/vehicle/demo/demo.mdl` | 当前 Mod 的 `content/` |
| `::/vehicle/demo/demo.mdl` | 原版 `content/` |
| `other_mod::/vehicle/demo/demo.mdl` | `other_mod` 的 `content/` |

不使用 `../`。跨 Mod 引用需要实际存在的目标和相应依赖。文本使用 UTF-8 无 BOM，资源名用小写 ASCII、数字、下划线或连字符，不含空格。游戏靠后缀区分资源类型，不能把 `.con.lua`、`.script.tl`、`.gs.lua` 任意互换。[资源规范](https://wiki.transportfever3.com/doku.php?id=modding:general:resourcetypes)

## 验证和定位故障

1. 解析完整 JSON，确认 ID、版本、钩子目标和依赖；逐个检查引用的文件或 ZIP 条目，避免只检查磁盘松散文件。
2. 检查器可用时结合 staging area 的 `tlconfig.lua` 检查 Teal；没有检查器就报告缺少该项，不为了文档任务安装完整工具链。
3. 游戏主菜单设置中的“打开用户数据文件夹”用于确认实际运行目录。Model Editor 的 `userDataPath` 只能证明编辑器配置，不能证明游戏正在从该目录加载 Mod。
4. 先测试 Mod 可见、可启用，再加载小型测试地图。日志标记证明钩子执行后，验证目标行为、相关参数边界和存读档。
5. 日志从实际用户数据目录或当前 UI 找到；旧 Wiki 的快捷键和路径未适配，不能直接承诺。对最新运行的错误读取上下文和首个相关失败，区分语法、找不到资源、函数参数错位、缺依赖或运行阶段错误。

典型排查：

| 现象 | 优先检查 |
| --- | --- |
| Mod 不出现或旧行为持续 | 实际用户数据路径、JSON、`visible`、同 ID 副本优先级 |
| 钩子不执行或参数类型不对 | `fileName`、`@函数`、返回表、`captureParams`、加载阶段 |
| 缺模型/紫色贴图/远景恢复旧涂装 | 命名空间、材质贴图引用、每个 LOD、依赖版本 |
| 参数选项偏移 | `defaultIndex` 与参数返回值的起始值，是否配置 `numbers` |
| 保存后读档失败 | 资源 ID 是否改变、依赖是否完整、序列化数据和移除风险 |

## 发布准备

准备可复查的目标目录、变更说明、截图、依赖和测试结果。发布包仅包含运行所需内容。核对当前[发布要求](https://wiki.transportfever3.com/doku.php?id=modding:general:guidelines)及官方验证器；本次页面带旧版标记，不把其中容量上限硬编码进脚手架。

用户要求上传后，从 Mod Hub 的 My Mods 完成。更新已有条目要保留 `_metadata/mod.io_fileid.txt`，并确认 UI 表示更新现有条目，防止创建重复发布；新修订增加 `revision`。仅授权本地开发时做到发布准备即可。当前流程来自[Publish a Mod](https://wiki.transportfever3.com/doku.php?id=modding:general:publishing)，操作时重新核实；本技能创建过程没有发布任何 Mod。
