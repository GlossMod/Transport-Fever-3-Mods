"""Prepare Fleet Upgrade listing materials and a clean archive; never upload."""
from __future__ import annotations

import hashlib
import json
import shutil
import struct
from datetime import datetime
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "staging_area" / "xiaom_vehicle_upgrade"
OUT = ROOT / "output" / "publish" / "xiaom_vehicle_upgrade"
REVISION = 10
TITLE = "全公司载具升级 | Fleet Upgrade"
SUMMARY = (
    "同用途新车型推荐、可编辑预览与折旧报价，确认后批量升级。"
    "Cargo-aware upgrades with editable previews and depreciation pricing."
)

ZH = """中文说明

为全公司自有载具生成可编辑的升级方案。打开统计窗口的“载具”标签，点击“升级载具”，查看推荐、调整目标并确认批量升级。

主要功能
• 道路车辆、列车、电车、船舶和航空载具；读取游戏实际加载的车型，包括具备有效载具数据的已启用 Mod 车型。
• 按原车型与运输用途分组，支持运输方式、线路和名称筛选，以及逐辆选择、分组修改、单辆覆盖和“保持原样”。
• 根据装载配置、当前货物与线路货物过滤识别用途；空载时保留可识别的用途，不能确定时保留原车型支持范围。
• 自动推荐先保证对应货物容量与额定速度不下降，再优先最新年代；机车还比较功率和牵引力。手动可选更新但性能较低的车型，并显示下降项。
• 普通列车逐节匹配机车、客车厢和货物车厢；保留部件顺序、数量与朝向。固定编组动车按整组处理。
• 原车与目标并排预览图片、名称、年代、容量、速度及适用动力指标。柴油转电力等变化会显示供电与设施提示。
• 显示新购费用、旧部件折旧抵扣、最终净支出、余额及升级数量；净支出为负时显示预计返还。部分替换会抵消保留部件价值。

价格与执行
新购部分总价 − 被替换部分折旧抵扣 = 最终净支出。
点击确认后按执行时的最新报价升级，支出上涨也继续；最新费用超出余额时阻止提交或停止剩余队列。载具配置变化、无效购买目标、货物装不下或命令失败仍会阻止执行。
替换使用游戏原生命令；按净支出从低到高开始逐辆处理并等待结果。首个失败后停止，显示成功、失败和未执行项目；已成功项目不能整批回滚。线路、电气化和停靠设施由玩家自行核对。

使用方法
1. 启用本 Mod，并在存档副本中载入。
2. 打开统计窗口 → 载具 → 升级载具。
3. 查看或修改分组与逐辆目标，检查容量、供电提示和费用。
4. 点击“确认升级”，查看逐辆处理结果。
更新 Mod 后请重启游戏。无需额外 Mod 依赖。

语言与发布状态
发布标题、摘要和描述提供中文与英文；当前游戏内升级界面为中文。
当前为功能开发版，最新变更尚未完成游戏内验收，建议先在存档副本中使用。
封面为 AI 生成的功能示意插画。
"""

EN = """English Description

Create editable upgrade plans for your company's vehicles. Open the Vehicles tab in the statistics window, select the upgrade button, review recommendations, adjust targets and confirm a batch upgrade.

Features
• Road vehicles, trains, trams, ships and aircraft. Reads models actually loaded by the game, including enabled mod vehicles with valid vehicle metadata.
• Groups parts by original model and transport purpose. Filter by transport mode, line or name; select individual vehicles, set group targets, override individual choices or keep original parts.
• Identifies purpose from loading configurations, current cargo and line cargo filters. Retains identifiable purposes for empty vehicles; when purpose is unknown, preserves the original model's supported cargo range.
• Automatic recommendations require no reduction in relevant cargo capacity or rated speed, then favor the newest introduction year. Locomotives also compare power and tractive effort. Manual choices may use newer, weaker models, with performance reductions shown.
• Matches locomotives, passenger coaches and freight wagons individually in ordinary trains, retaining part order, count and orientation. Fixed multiple units are handled as complete sets.
• Shows original and target images, names, years, capacity, speed and applicable traction figures side by side. Power changes, such as diesel to electric, show infrastructure notices.
• Shows purchase cost, depreciation credit, net cost, balance and upgrade count. Negative net cost indicates an expected refund. Partial replacements account for the value of retained parts.

Pricing and execution
New purchase cost − depreciation credit for replaced parts = net cost.
Confirmation authorizes upgrades at the latest quote before execution, including price increases. Insufficient funds prevent submission or stop the remaining queue. Configuration changes, invalid purchase targets, insufficient cargo capacity and command failures still block execution.
Uses the game's native replacement command. Starts with lower net-cost vehicles, processes one vehicle at a time and waits for the result. Stops at the first failure and reports completed, failed and unexecuted items; completed upgrades cannot be rolled back as a batch. Check line electrification and stopping facilities yourself.

How to use
1. Enable the mod and load a copy of your savegame.
2. Open Statistics → Vehicles → the vehicle upgrade button.
3. Review or edit group and individual targets; check capacity, power requirements and costs.
4. Confirm the upgrade and review the per-vehicle results.
Restart the game after updating the mod. No additional mod dependencies.

Language and release status
The listing title, summary and description are bilingual. The in-game upgrade interface is currently Chinese.
This is a development release. Full in-game acceptance checks for the latest changes have not been completed; use a savegame copy first.
Cover: AI-generated illustration of the mod's purpose.
"""

DESCRIPTION = ZH.strip() + "\n\n" + EN.strip()
CHANGELOG = """revision 10 — 发布资料整理 / Publication materials

中文：准备中英双语标题、摘要、描述和独立上传包，沿用 Fleet Upgrade 封面。运行代码沿用 revision 9：支出上涨时按最新报价继续升级，余额不足仍停止；保留可编辑预览、货物用途匹配、折旧报价和逐辆执行。

English: Adds a bilingual title, summary, description and a clean upload archive, retaining the Fleet Upgrade cover. Runtime code is unchanged from revision 9: upgrades continue at the current quote when prices rise, while insufficient funds still stop execution. Includes editable previews, cargo-aware matching, depreciation pricing and sequential replacement.
"""

PUBLISH = """# Fleet Upgrade 发布资料

标题：全公司载具升级 | Fleet Upgrade
游戏 Mod ID：xiaom_vehicle_upgrade
修订版本：10
建议标签：Script Mod
作者：xiaom
状态：资料和 ZIP 已准备，由你自行上传；尚未执行游戏发布校验或上传。

## 可直接复制的字段

- TITLE.txt：中英双语标题。
- SUMMARY.txt：中英双语摘要。
- DESCRIPTION.txt：中文和英文完整描述。
- CHANGELOG.txt：本版中英变更说明。
- modinfo.json：与游戏 staging area 一致的发布元数据。
- cover.png：现有 Fleet Upgrade 封面，1920×1080 PNG；使用 AI 示意插画并已在描述中注明。
- xiaom_vehicle_upgrade_revision_10.zip：Mod 根文件、8 个内容文件、发布元数据、封面及公开说明；压缩包根目录直接包含 mod.json。
- development-records/：本地开发记录，不放入 ZIP。

## 通过游戏发布

1. 保存当前进度并正常重启游戏，使游戏重新读取本次标题和元数据。
2. 从主菜单打开 Mod Manager / Mod Hub，进入 My Mods / 我的 Mod，找到“全公司载具升级 | Fleet Upgrade”。
3. 确认来源是 staging area、修订版本为 10、封面正确。核对发布账号，按界面要求自行登录。
4. 检查标题、摘要、完整描述和 Script Mod 标签；若界面没有自动读取这些字段，复制对应 TXT 文件内容。将 CHANGELOG.txt 用于变更说明。
5. 执行游戏提供的校验，并根据实际错误处理。发布前阅读当前平台的要求；游戏发布校验与运行功能测试是不同事项。
6. 首次发布对话框应表示创建新 mod.io 条目。确认你的可见性选择后点击 Upload / 上传。如果是更新已有条目，对话框必须表示更新；显示新建时先检查绑定，避免重复条目。
7. 等待明确上传结果，打开生成的真实 mod.io 页面，检查中英文案、封面、文件修订和公开状态。
8. 保留游戏生成的 _metadata/mod.io_fileid.txt。之后更新同一条目时保留此文件，并递增 revision；它记录的是 mod.io 条目 ID。

本机游戏 staging area 已通过目录联接读取工作区 staging_area/xiaom_vehicle_upgrade，无需再复制一个相同 Mod ID 的目录。
如果上传结果不明，先检查绑定文件和账号中的条目，避免重复创建。

## 从网页手动上传文件

仅在平台提供对应文件上传流程时使用 xiaom_vehicle_upgrade_revision_10.zip；不要上传整个工作区或 development-records/。
使用 TITLE.txt、SUMMARY.txt 和 DESCRIPTION.txt 填写发布介绍，并选择 cover.png 作为封面。
首次上传后把真实条目 ID 与页面链接记下来；若以后改用游戏更新，也需正确恢复对应的本地条目绑定。

## 当前验证状态

本次仅整理元数据、发布文案、公开说明和 ZIP；没有执行自动化测试、游戏运行验收或游戏发布校验。
最新运行代码为 revision 9 的允许涨价行为。实际扣款、货物保留和存档重载仍以你的游戏内结果为准。
发布介绍为中英双语，当前游戏内升级界面仍为中文。
"""


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8", newline="\n")


def write_json(path: Path, value: object) -> None:
    write_text(path, json.dumps(value, ensure_ascii=False, indent=2))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    records = OUT / "development-records"
    records.mkdir(exist_ok=True)
    old_readme = MOD / "README.md"
    if old_readme.exists() and not (records / "README-development.md").exists():
        shutil.copy2(old_readme, records / "README-development.md")
    validation = MOD / "VALIDATION.md"
    if validation.exists():
        destination = records / "VALIDATION.md"
        if destination.exists():
            destination = records / f"VALIDATION-{datetime.now(ZoneInfo('Asia/Shanghai')):%Y%m%d-%H%M%S}.md"
        validation.replace(destination)

    manifest_path = MOD / "mod.json"
    definition = json.loads(manifest_path.read_text(encoding="utf-8"))
    definition["revision"] = REVISION
    write_json(manifest_path, definition)
    info_path = MOD / "_metadata" / "modinfo.json"
    info = json.loads(info_path.read_text(encoding="utf-8"))
    info.update(name=TITLE, summary=SUMMARY, description=DESCRIPTION, tags=["Script Mod"])
    write_json(info_path, info)

    write_text(OUT / "TITLE.txt", TITLE)
    write_text(OUT / "SUMMARY.txt", SUMMARY)
    write_text(OUT / "DESCRIPTION.txt", DESCRIPTION)
    write_text(OUT / "CHANGELOG.txt", CHANGELOG)
    write_text(OUT / "PUBLISH.md", PUBLISH)
    write_text(OUT / "listing-bilingual.md", f"# {TITLE}\n\n{SUMMARY}\n\n{DESCRIPTION}\n")
    write_json(OUT / "modinfo.json", info)
    shutil.copy2(MOD / "_metadata" / "0.png", OUT / "cover.png")
    write_text(MOD / "README.md", f"# {TITLE}\n\n{DESCRIPTION}\n\n{CHANGELOG}\n")

    index = json.loads((MOD / "_content.json").read_text(encoding="utf-8"))
    members = ["mod.json", "_content.json", "_metadata/modinfo.json", "_metadata/0.png", "README.md"]
    members.extend("content/" + name for name in index["files"])
    archive = OUT / f"xiaom_vehicle_upgrade_revision_{REVISION}.zip"
    member_info = []
    with ZipFile(archive, "w", compression=ZIP_DEFLATED, compresslevel=9) as package:
        for member in members:
            source = MOD / member
            package.write(source, arcname=member)
            member_info.append({"path": member, "bytes": source.stat().st_size,
                                "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
    cover_bytes = (OUT / "cover.png").read_bytes()
    cover_width, cover_height = struct.unpack(">II", cover_bytes[16:24])
    write_json(OUT / "package-manifest.json", {"modId": definition["modId"], "revision": REVISION,
        "archive": archive.name, "archive_bytes": archive.stat().st_size,
        "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(), "files": member_info})
    binding_path = MOD / "_metadata" / "mod.io_fileid.txt"
    write_json(OUT / "release-status.json", {
        "status": "prepared_user_will_publish", "modId": definition["modId"],
        "revision": REVISION, "runtime_code_revision": 9,
        "prepared_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds"),
        "title": TITLE, "listing_languages": ["zh-CN", "en"], "in_game_ui_language": "zh-CN",
        "archive": str(archive), "staging_path": str(MOD), "published": False,
        "modio_id": binding_path.read_text(encoding="utf-8").strip() if binding_path.exists() else None,
        "modio_url": None, "game_publish_validation": "not_run", "runtime_tests": "not_run",
        "cover_size": [cover_width, cover_height], "cover_bytes": len(cover_bytes),
        "cover_ai_generated": True, "publisher": "user"
    })
    print(json.dumps({"title": TITLE, "revision": REVISION, "title_characters": len(TITLE),
        "summary_characters": len(SUMMARY), "description_characters": len(DESCRIPTION),
        "archive": str(archive), "archive_bytes": archive.stat().st_size,
        "packaged_files": len(member_info), "status": "prepared_user_will_publish"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
