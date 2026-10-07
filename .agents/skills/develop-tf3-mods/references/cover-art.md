# TF3 Mod 封面生成

用于制作 Mod Hub / mod.io 的展示封面。以下流程于 2026-10-04 在本项目跑通：custom-imagegen 生成源图，Pillow 处理发布尺寸，确认图片后加入 `_metadata/0.png`。记录的是封面制作与发布包准备；不代表 Mod 已上传或通过游戏验证。

## 发布规格与图像内容

- 2026-10-04 读取的[官方 Guidelines & Requirements](https://wiki.transportfever3.com/doku.php?id=modding:general:guidelines)要求封面为 **1920×1080、16:9、不超过 8 MB**，封面文字使用英语。该页面标有 **old revision**，后续发布时重新核对当前页面和游戏验证器，不能把这些数值当成永久规则。
- [游戏内 Mod Manager 发布指南](https://mod.io/g/transportfever3/r/creating-and-updating-mods-via-the-in-game-mod-manager)说明封面位于 Mod 根目录的 `_metadata/0.png`。这是 mod.io 社区指南；实际识别和上传结果以当前游戏为准。
- 中英文标题和说明放在 `_metadata/modinfo.json` 或发布页面；封面上的英文标题与最终 Mod 名称相符。页面文案与游戏内语言适配分别说明。
- 车辆、涂装、模型等外观 Mod 优先使用实际成品截图。脚本、功能类 Mod 可以用表达功能的示意插画；不要把生成图写成实机截图，不画不存在的功能、官方标志或 UI。

## 提示词与产物位置

先明确 Mod 的功能、封面表达的场景、标题文字和最终画幅。提示词说明主体、配色、构图、逐字标题、裁切安全区域及避免内容；少放文字，降低生成拼写错误的概率。生成结果不能证明脚本功能已实测。

源图与最终提示词保存到工作区 `output/imagegen/`，采用可区分版本的文件名，例如 `<mod_id>-cover-v1.png`、`<mod_id>-cover-prompt.txt`。修改已有封面时按用户要求保留或替换，不默认覆盖原图。发布包只加入最终 `_metadata/0.png`，提示词、源图和处理依赖不放进 Mod 的运行内容。

若生成接口使用 1536×1024，目标为 16:9，可先裁到 1536×864，再缩放为 1920×1080。中心裁切会在上下各去掉 80 像素，重要文字和主体应放在中央约 75% 高度内，并留水平边距。主体靠边时调整裁切位置或重新构图，不能机械地裁掉关键信息；缩放不会增加原图细节。

## 使用 custom-imagegen

用户指定 custom-imagegen 时，先读取本机 [custom-imagegen/SKILL.md](C:/Users/xiaom/.codex/skills/custom-imagegen/SKILL.md)，遵循其当前执行方式。迁移机器后重新定位该技能；用户选了其他提供方时沿用其选择。以下是本项目成功使用的路径和命令示例，运行前替换示例 Mod 名和输出文件名。

- 必须通过技能包装器，提供方元数据为 `model_providers.custom`，模型固定为 `gpt-image-2.5`，端点由该技能固定为 `https://www.glosc.ai/v1`。
- 包装器从 Codex 配置和 `auth.json` 读取信息；不把密钥复制到提示词、命令参数或日志，不修改 Codex 中原有的 `base_url`。
- 先运行 `--check-config`；只有实际制作新图时才调用付费生成接口。整理技能和检查已有图片不需要重新生成。

```powershell
$coverWrapper = 'C:\Users\xiaom\.codex\skills\custom-imagegen\scripts\custom_image_gen.py'
py -X utf8 $coverWrapper --check-config
py -X utf8 $coverWrapper generate --prompt-file 'F:\mod\Transport Fever 3\output\imagegen\auto-line-names-cover-prompt.txt' --size 1536x1024 --quality high --out 'F:\mod\Transport Fever 3\output\imagegen\auto-line-names-cover-v2.png'
```

本次旧环境的 OpenAI SDK 1.52.2 在请求发出前因不支持 `output_format` 参数失败。随后把 OpenAI SDK 3.24.0 和 Pillow 12.3.0 安装到工作区 `.agents/tools/imagegen_runtime/`，仅为该命令进程设置 `PYTHONPATH` 后成功。复用时先检查现有环境；只在依赖缺失或出现同类兼容错误时更新隔离环境，不要求未来固定这些版本。

```powershell
py -m pip install --target 'F:\mod\Transport Fever 3\.agents\tools\imagegen_runtime' openai pillow
$env:PYTHONPATH = 'F:\mod\Transport Fever 3\.agents\tools\imagegen_runtime'
# 在同一个命令进程内运行上述包装器。
```

设置 `PYTHONPATH` 前检查已有值，必要时保留原有搜索路径。接口不支持所需功能时如实报告，不悄悄更换用户指定的模型或提供方。

## 转为发布封面并检查

下面的 Python 示例使用 Pillow 等比裁切，适用于已预留中央安全区的源图。目标为首次创建；如已有 `0.png`，先保留旧版或确认替换范围。

```python
from pathlib import Path
from PIL import Image, ImageOps

source = Path("output/imagegen/auto-line-names-cover-v1.png")
target = Path("staging_area/xiaom_auto_line_names/_metadata/0.png")
if target.exists():
    raise FileExistsError(f"Cover already exists: {target}")
target.parent.mkdir(parents=True, exist_ok=True)
with Image.open(source) as original:
    cover = ImageOps.fit(
        original.convert("RGB"), (1920, 1080),
        method=Image.Resampling.LANCZOS, centering=(0.5, 0.5),
    )
    with target.open("xb") as output:
        cover.save(output, format="PNG", optimize=True)
print(target, target.stat().st_size)
```

用 `view_image` 分别查看源图和处理后的最终封面，确认标题逐字准确、主体完整、边缘没有裁掉关键元素、没有水印或额外文字。重新打开最终文件检查实际像素尺寸、格式和字节大小；超过当前限制时使用适当的无损优化或减少颜色，并复查画质。必要时只调整出问题的提示词或裁切参数后再迭代。

确认后把最终封面复制到**游戏实际用户数据目录**下目标 Mod 的 `_metadata/0.png`；工作区 `staging_area/` 不等于游戏当前扫描的 staging area，定位方法见[核心流程](core-workflow.md)。原版游戏目录不放生成源图。预览或复制完成不代表上传成功；发布还要检查 Mod Manager 校验和上传结果。

交付时给出最终封面路径、提示词文件、提供方与模型名称，并展示最终图片。生成插画在发布说明中如实标注；其他语言介绍及行为限制写在文本元数据中。

## 本次成功示例：Auto Line Names

封面表达两座城镇、客运列车、煤炭货列和两条线路；用图标与抽象笔画表示自动生成的名称，避免在示意图中宣称游戏已经支持英文线路前缀。英文主标题为 `AUTO LINE NAMES`，副标题为 `Transport Fever 3 Mod`。

当时的产物位置（示例，不作为新 Mod 默认路径）：

- 提示词：`F:\mod\Transport Fever 3\output\imagegen\auto-line-names-cover-prompt.txt`
- 源图：`F:\mod\Transport Fever 3\output\imagegen\auto-line-names-cover-v1.png`，1536×1024。
- 最终封面：`F:\mod\Transport Fever 3\staging_area\xiaom_auto_line_names\_metadata\0.png`，1920×1080，3,441,550 字节。
- 提供方：`model_providers.custom`；模型：`gpt-image-2.5`。

完整提示词保留如下，复用时替换 Mod 功能、场景和标题；裁切参数随目标规格调整。

```text
Use case: ads-marketing / game mod cover.
Create a polished landscape promotional cover illustration for a Transport Fever 3 mod called Auto Line Names. The mod automatically names newly created passenger and freight routes.
Scene: a handsome miniature isometric transport landscape with two compact towns connected by railway and roads, a white-and-blue passenger train and a charcoal freight train carrying coal. Restrained navy, teal and warm gold palette, crisp detailed 3D illustration, softly lit, sophisticated simulation-game aesthetic. Show two simple luminous route lines joining the town station nodes and two floating route-name cards, suggesting automatic route naming. Include a small subtle magic-wand sparkle near the cards.
Typography: prominent clear title rendered verbatim: "AUTO LINE NAMES". A small subtitle rendered verbatim: "Transport Fever 3 Mod". The two floating route-name cards use only simple passenger-train and coal pictograms followed by stylized abstract text strokes, rather than readable example names. No Chinese text appears on the cover; the listing title and description will supply both Chinese and English separately.
Composition: harmonious wide banner with generous breathing room, clear hierarchy, scenery behind and beneath the typography; all title and route-card text must stay inside the central 75 percent of the image height, so the 1536x1024 source can be cropped vertically to a 16:9 banner without losing any lettering or trains. Maintain at least 8 percent safe padding horizontally. Keep words perfectly accurate, no extra text, no invented UI menus, no logos, no watermark, no claim that this is a gameplay screenshot.
```
