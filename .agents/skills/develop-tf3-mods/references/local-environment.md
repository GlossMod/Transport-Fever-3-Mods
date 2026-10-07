# 本机环境与取证方法

这是 2026-10-04 的只读核对结果。不要把机器路径或 Steam BuildID 当成 TF3 的通用要求。

## 已发现的文件

| 位置 | 作用 |
| --- | --- |
| `E:\steam\steamapps\common\Transport Fever 3\TransportFever3.exe` | 游戏主程序 |
| 同目录 `api\tealdef\` | 引擎 API 类型定义，包括 `main.d.tl`、`api/res.d.tl`、`api/type/mod.d.tl` |
| 同目录 `base\tealdef\` | 原版内容类型与工具函数定义 |
| 同目录 `base\content\` | 原版资源；大量内容打包为 ZIP，不能只用 `rg` 搜松散文件 |
| 同目录 `base\content\base.zip` | `base/mod.script.tl`、`base/base_config.lua` 等基础实现 |
| 同目录 `mods\release\urbangames_no_costs\` | 小型配置 Mod 的完整官方实例 |
| 同目录 `mods\release\urbangames_sandbox\` | 另一份 `preRunFn` 配置实例 |
| 同目录 `vscode-template\` | `tlconfig.lua`、`all_def.tl`、`.vscode/extensions.json` |
| 同目录 `ModelEditor.bat`、`model_editor\ModelEditor.exe` | 随游戏附带的模型编辑器；启动器设置插件搜索路径 |
| `F:\mod\Transport Fever 3\staging_area\example_mod_1\` | 已有最小示例，只有 `mod.json` 与 `_metadata/modinfo.json`；保留原样 |
| 项目 `staging_area\tlconfig.lua`、`all_def.tl` | 已指向上述 API 和 base 类型目录 |
| `%APPDATA%\Transport Fever 3\model_editor_settings_v13.lua` | 本次 `userDataPath` 指向 `F:\mod\Transport Fever 3`，只证明编辑器配置 |
| `C:\Program Files (x86)\Steam\userdata\233840157\3493540\local\` | 后续游戏日志确认的实际游戏用户数据目录；此账号路径仅为本机记录 |
| 上述目录的 `staging_area\xiaom_auto_line_names\` | 已准备发布的独立 Mod 目录；上传流程见 [mod.io 发布与更新](modio-publishing.md) |

Steam 清单 `E:\steam\steamapps\appmanifest_3493540.acf` 中核对到 AppID `3493540`、BuildID `25533170`。后续只需读取版本字段，不必保存账号字段。游戏运行时也有 `getBuildVersion()`，定义见 `api/tealdef/main.d.tl`。

## 常用只读查询

```powershell
$tf3Game = 'E:\steam\steamapps\common\Transport Fever 3'
rg -n 'ug_require|getCurrentModId|debugPrint|getBuildVersion' "$tf3Game\api\tealdef\main.d.tl"
rg -n 'ModDependency|ModDesc' "$tf3Game\api\tealdef\api\type\mod.d.tl"
rg --files "$tf3Game\base\tealdef" | rg 'vehicle|construction|config'
Get-Content -LiteralPath "$tf3Game\mods\release\urbangames_no_costs\mod.json" -Raw
Get-Content -LiteralPath "$tf3Game\mods\release\urbangames_no_costs\content\mod.script.tl" -Raw
```

只读 ZIP 的 Python 示例：先列出条目，再读取已确认的单个文件；不要为查一个字段解包整个游戏。

```python
from pathlib import Path
from zipfile import ZipFile

game = Path(r"E:\steam\steamapps\common\Transport Fever 3")
with ZipFile(game / "base/content/base.zip") as archive:
    print("\n".join(n for n in archive.namelist() if n.endswith(".tl")))
    source = archive.read("base/mod.script.tl").decode("utf-8")
    # 按当前问题打印或搜索必要片段，避免输出整个大型脚本。
    for line in source.splitlines():
        if "preRunFn" in line or "noCosts" in line:
            print(line)
```

`base/content/locale.zip` 内实际存在 `locale/zh_CN.lang.lua`、`locale/zh_TW.lang.lua`、`locale/en.lang.lua`。需要核对语言标识时读对应定义。

## 编辑器配置的具体差异

[External Tools](https://wiki.transportfever3.com/doku.php?id=modding:tools:external) 描述 `dev-workspace` 和 `workspace_def`；此安装包实际使用 `vscode-template` 与 `all_def.tl`。本机 staging area 的配置为：

```lua
return {
    include_dir = {
        "E:/steam/steamapps/common/Transport Fever 3/api/tealdef",
        "E:/steam/steamapps/common/Transport Fever 3/base/tealdef",
    },
    global_env_def = "all_def"
}
```

`all_def.tl` 引入 `api_def` 和 `content_def`。添加自定义 `.d.tl` 时才相应扩展 include 和 require，保留已有条目。本次 `py` 可用，未在 PATH 中发现 `tl`、`lua`、`luac`；这不代表整机没有其他安装，但不能声称已经编译验证。

## 文档冲突的处理

- [Base Config](https://wiki.transportfever3.com/doku.php?id=modding:scripting:baseconfig) 明示未适配，仍写旧 `res/config`。当前 `base/base_config.lua` 只是薄初始化，主要配置位于 `base.zip` 中的 `base/mod.script.tl`；调整时沿真实调用链查找。
- 网页钩子说明未总是列出 `captureParams`，当前 no-costs 和 base 示例都有该首参。
- [Model Editor](https://wiki.transportfever3.com/doku.php?id=modding:tools:modeleditor) 的 Setup 段混有 TF2 名称，使用已存在的 TF3 启动器；只读研究无需启动游戏或修改设置。
- 本机最小 staging 示例没有 `_content.json`，不能据此认为发布包不需要索引。后续读取的游戏内发布指南要求列出 `content/` 中的文件；本项目已为待发布 Mod 准备该索引，格式和依据见 [mod.io 发布与更新](modio-publishing.md)。本记录尚未证明游戏验证器已接受发布包。

本技能没有修改游戏安装文件、现有 staging 示例或编辑器设置，也没有将原版资源复制进技能。
