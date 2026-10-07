# mod.io 发布与更新

适用于用户要求把 TF3 Mod 上传到 mod.io，或更新已有条目。仅整理本技能、制作封面或打包不触发上传；用户已明确要求发布时，沿用该授权，完成准备和核验后执行，无需重复询问同一发布意图。

依据于 2026-10-04 读取并复核：

- [官方 Publish a Mod](https://wiki.transportfever3.com/doku.php?id=modding:general:publishing)：Mod Hub / My Mods、上传校验、页面编辑及更新绑定。页面标有 **old revision**，实际按钮和字段以当前版本为准。
- [mod.io 社区发布指南](https://mod.io/g/transportfever3/r/creating-and-updating-mods-via-the-in-game-mod-manager)：作者 GlcrT，更新于 2026-10-02；补充内容索引和避免重复发布的步骤。社区指南不代替游戏实测。

## 确定实际发布目录

工作源文件默认位于本项目 `F:\mod\Transport Fever 3\staging_area\<mod_id>\`。游戏内上传读取的是**游戏实际用户数据目录**中的 `staging_area/`；二者可能不同。

先通过游戏“打开用户数据文件夹”或本次运行日志确认位置，不能仅依据 Model Editor 的 `userDataPath`。Steam 路径通常形如：

```text
<Steam>\userdata\<Steam ID>\3493540\local\staging_area\<mod_id>\
```

本机最近核实为 `C:\Program Files (x86)\Steam\userdata\233840157\3493540\local\`，游戏安装在 `E:\steam\steamapps\common\Transport Fever 3`。迁移机器或账号后重新定位，不把该账号路径写进通用脚手架。

每个 Mod 保持一个独立目录。检查同 `modId` 的手动安装副本，避免编辑的副本与实际加载来源不一致；社区指南指出重复 ID 会报警并优先采用 staging 副本。需要移走旧副本时先保留可恢复备份，不清理其他 Mod 或原版文件。

## 发布包与展示信息

最小示例（两项脚本仅对应本项目自动命名 Mod）：

```text
<mod_id>/
├── mod.json
├── _content.json
├── content/
│   ├── auto_line_names.gs.lua
│   └── auto_line_names.script.lua
└── _metadata/
    ├── modinfo.json
    ├── 0.png
    └── mod.io_fileid.txt       # 首次上传后生成；更新时保留
```

`_content.json` 位于 Mod 根目录。以下格式已在待发布包中使用，但尚未完成游戏内上传校验：

```json
{
  "archives": null,
  "files": [
    "auto_line_names.gs.lua",
    "auto_line_names.script.lua"
  ]
}
```

`files` 列出相对 `content/` 的资源路径，不能把 `_metadata/0.png` 或 `mod.json` 当作 content 文件。检查索引与发布内容一致；社区指南指出未列出的内容文件不会加载。有 ZIP 内容时先查当前原版索引和打包格式，不套用这里的无压缩包示例。

核对 `mod.json` 的 `modId`、`revision`、依赖、移除风险和 `cosmetic`。源图、提示词、测试代码、依赖环境、日志、编辑源文件与备份留在工作区，只把发布需要的文件复制到游戏 staging 目录。可以另建 ZIP 供备份或交付，但 ZIP 已生成不等于游戏已经上传。

`_metadata/modinfo.json` 准备 `name`、`summary`、`description`、标签及真实作者信息；不要编造作者账号或未取得的发布网址。用户要求中英文时，可在一个标题内组合两种语言，并在描述中提供中文和英文段落；按当前字段长度限制调整。列出功能、使用方法、依赖、验证结果和限制，尤其区分“双语介绍”与“游戏内自动适配语言”。

制作 `_metadata/0.png` 时读取[封面指南](cover-art.md)。上传前预览标题、说明与最终图片；确认当前规则中的标签、图像和文本要求。网页上编辑过的标题或说明可能被下一次上传的 `modinfo.json` 覆盖，先把这些修改同步回工作源文件。

复制新构建时保留目标中已有的 `_metadata/mod.io_fileid.txt`，不要用没有绑定文件的整个新目录覆盖掉它。遇到源目录和目标目录的绑定 ID 不同，先核对实际条目身份，不继续上传。

## 首次发布

1. 检查当前游戏进度并妥善保存，再正常退出和重新启动游戏，使其重新扫描 staging area。用户正在操作或控制工具检测到干预时停下相应控制；不靠强制结束游戏来完成扫描。
2. 从主菜单进入 Mod Hub / Mod Manager → **My Mods**，选择目标 Mod。若未显示，先排查实际目录、JSON、内容索引、重复 ID 和重启扫描。
3. 检查登录的发布账号。认证过程遵循当前浏览器或电脑控制技能；需要用户亲自登录时明确告知，等待完成后继续，不读取隐藏会话凭据来绕过登录。
4. 核对名称、标签、封面、可见性和变更说明。沿用用户指定的可见性；用户明确要求公开发布时设置为公开。游戏校验和运行测试分别记录，不能互相替代。
5. 首次发布时确认对话框表示创建新条目：`A new mod will be created on mod.io.` 若实际任务是更新，看到该提示就取消上传并修复绑定。
6. 执行 Upload；检查游戏验证结果，修复具体问题后再上传。跨平台批准状态以当前验证和平台结果为准，不预先承诺主机可用。
7. 按下上传按钮后等待结果，核对游戏生成的绑定文件和实际打开的 mod.io 页面，记录真实 Mod ID、网址、修订版本与可见性，再同步回源目录。

如果请求超时或结果不明，先检查本地绑定和账号中的实际条目，不盲目再次创建新条目。成功提示、绑定或页面若不一致，先排查，不能仅凭已点击 Upload 宣称发布成功。

## 更新已有条目

`_metadata/mod.io_fileid.txt` 虽然叫 fileid，但内容是 **mod.io 数字 Mod ID（条目 ID），不是上传文件 ID，也不是游戏 `modId`**。只有确认实际目标条目后才恢复丢失的绑定；从页面找到该条目的数字 ID，写入该文件。示例中的 ID 不可照抄。

1. 保持游戏 `modId` 和目标条目绑定，增加 `mod.json` 的 `revision`，准备具体变更说明。
2. 同步网页上已有的文案、依赖和展示图到源文件，再准备新的发布内容；保留绑定文件。
3. 重新启动游戏，在 My Mods 选择该 Mod，确认对话框表示更新现有条目：`The existing mod on mod.io will be updated.`
4. 如果仍表示新建，取消这次上传，核对绑定文件的位置、内容、账号权限和实际条目。不要靠创建新条目解决更新失败。
5. 完成 Update / Upload 后核对同一条目的新修订和文件状态；将绑定与最终文案继续保留在工作源文件或仓库中。

## 结果核验与交付

本地准备、游戏校验、上传成功和页面公开分别记录。上传后确认真实 mod.io 条目及文件记录，再检查可见性和页面内容；审核未完成时说明实际状态，不能把“已上传”写成“已公开可下载”。

至少保留可核对的 Mod ID、条目链接、发布修订、日期和当前状态；需要时放在工作区 `output/publish/<mod_id>/release-status.json`，不放入 `content/`。把游戏写入的绑定文件同步回源目录；如在游戏 UI 中改了文案，也同步回 `modinfo.json`。交付真实页面链接、主要变化、验证结果和仍存在的限制。

## 本项目记录的实际完成范围

`xiaom_auto_line_names` 的 revision 2 发布包已于 2026-10-04 准备：双语标题与描述、`_content.json`、1920×1080 封面及独立游戏 staging 目录。位置和备份记录在工作区 `output/publish/xiaom_auto_line_names/release-status.json`。

这次流程尚未完成游戏内发布校验和上传，记录状态为 `prepared_not_uploaded`，未取得 mod.io ID 或发布链接。游戏日志曾确认运行脚本加载与初始化，但不证明上传成功或全部功能已验收。后续执行应从实际记录和当前 UI 继续，不能把本文当作成功发布的实测记录。
