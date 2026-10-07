# Revision 4 崩溃修复与验证记录

日期：2026-10-07。状态：崩溃路径已修复，71 项自动化检查通过；本次游戏内复测由用户停止，未确认实际引擎运行结果。本次没有上传 mod.io。

## 故障证据与修复

当前 TF3 日志显示 Build 40408、commit c55a97f1。2026-10-07 10:12:18 UTC（本地 18:12:18），模拟线程触发 `gamescript_util.cpp:385` 原生断言，堆栈为：

```text
get_native
xiaom_auto_line_names::/naming_runtime.lua (14): persist
xiaom_auto_line_names::/naming_runtime.lua (194): handle
xiaom_auto_line_names::/naming_runtime.lua (230): handleEvent
```

错误来自 revision 3 的持久化优化：以方法存在作为可用性判断，调用 GameScriptState:get_native()。该方法虽在当前 .d.tl 中声明，但当前 Lua GameScript 的实际调用触发致命断言。Lua pcall 不能作为原生致命断言的可靠恢复措施。

revision 4 完全移除此状态写入路径的 get_native/set_native 调用，统一使用普通表 state:set。初始化只读取一次 state:get，其后复用模拟线程中的缓存；GUI 调度心跳只修改瞬时队列标志，不保存状态。改名命令发送前仍先保存待确认意图，状态版本维持 2，配置、分类编号、保护状态及旧存档迁移逻辑保留。

存储现在使用普通表快照，不再声称原生增量写入。5,000 条线路测试只验证处理预算和完成性，不能证明实际引擎中的性能。

GUI 从 GAME_SCRIPT 组件读取 state_native 是另一种 API：当前安装包的通知、城市和产业 GUI 有实际用例。它未出现在此次崩溃堆栈中，保留该分页读取路径；游戏内批量窗口仍需实测。

## 自动化

使用本机 Python 3.11 与已有隔离 Lupa 2.5 / Lua 5.4，执行实际发布 Lua 文件：

```powershell
py -3.11 -X utf8 .agents/tests/test_auto_line_names.py
py -3.11 -X utf8 .agents/tests/test_line_names_v3.py
py -3.11 -X utf8 .agents/tests/test_line_names_ui.py
```

| 检查组 | 数量 | 覆盖 |
| --- | ---: | --- |
| 原有回归 | 28 | 原始格式、客货识别、环线、同城、稀疏货物 ID、延迟/失败命令、手动保护、删除、暂停更新 |
| 升级及崩溃回归 | 37 | 原升级 34 项及新增 3 项：心跳不写状态；普通存储跨命名、配置、批量及重载；延迟派发前先保存待确认意图 |
| 界面及原生 React | 6 | 所选线路、整数复选框、保护切换、确认接管、关闭取消、实际 React 注册和根类型契约 |

所有模拟状态包装器均提供 get_native/set_native，但调用即报错。新增回归先在 revision 3 上失败，重现 persist → handle → handleEvent 调用栈；修复后 71 项全部通过，没有任何原生状态存储调用。此类替身仍无法模拟 C++ 引擎的全部行为。

5,000 条模拟新线路全部完成命名，最大每次处理 64 条，最后一条编号 5000；整个状态仅初始化读取一次。界面测试执行安装包 base/content/gui.zip 中实际 gui/main/react.lua，原生控件及引擎仍为替身。

## 结构与兼容

- revision 4；Mod ID xiaom_auto_line_names、cosmetic 属性和 mod.io 绑定 6426466 保留。
- 状态版本仍为 2，无新增存档迁移要求；旧版保护名和待确认命令保持兼容。
- _content.json 索引全部 14 个内容文件。JSON、Lua 语法及 UTF-8 无 BOM 检查通过。
- 封面 SHA256：7e6f18d009dcc9bddba0d2abf8ac53ef5840162439f6b52c98e95d93e42a19bb。
- 游戏 staging_area 是指向项目 staging_area 的目录联接，本地修复已供游戏重新加载；需重启游戏以重新载入脚本。

## 游戏复测状态

修复后尝试启动游戏，Computer Use 报告用户通过物理 Esc 停止操作，随后停止所有游戏界面输入。未确认修复后地图载入、心跳事件或命名的引擎运行结果，不能将修复前加载日志作为 revision 4 验收结果。

仍需在测试存档副本确认：地图载入后运行至少 60 秒无该断言；创建及自动命名线路；批量预览、取消和确认；配置重载；手动名称保护；保存重载；Mod Manager revision 4 校验。升级计划的完整交通模式及参数组合实测同样保留为待验收项。

## 交付与备份

- revision 3 备份及原始崩溃日志：output/backups/xiaom_auto_line_names-revision3-20261007-181717/。
- revision 2 备份：output/backups/xiaom_auto_line_names-revision2-20261007-170059/。
- 修复包：output/mod_packages/xiaom_auto_line_names_r4.zip。
- 发布状态：output/mod_packages/xiaom_auto_line_names_r4-status.json，packaged_pending_ingame_validation、uploaded: false。
- 发布包包含验证记录；ZIP CRC 及逐文件字节核对由打包脚本执行。

English: revision 4 removes the crashing GameScriptState native-storage calls and uses plain-table snapshots, keeping save-state version 2 compatible. All 71 automated checks pass, including 5,000 simulated lines. The regression first failed on revision 3 with the same call path. The user stopped desktop game automation with Esc; post-fix in-game testing and Mod Manager validation remain pending. No mod.io upload occurred.
