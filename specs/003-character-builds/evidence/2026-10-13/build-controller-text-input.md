# 冷却时钟与未提交天赋输入

2026-10-13。本轮仅修改 `game/presentation/build_controller.gd` 与 `game/tests/test_build_menu.gd`；视图的 `refresh_cooldowns(text: String)` 由根实现。没有修改共享任务勾选、主场景、HUD、输入映射或存档。

`AWBuildController.refresh_cooldowns()` 的公开签名和 Result 保持一致：读取真实 Combat/config 时钟，更新 `_model["cooldown_text"]`，调用视图的标签专用方法。该定时路径不调用完整 `refresh_feedback()`，因此不写 SpinBox、技能选项或装备选项，也不重新推导候选、资格与预设。用户编辑及领域拒绝仍走原来的完整反馈同步。

新增回归使用实际 `InputEventKey`，由 `Viewport.push_input()` 路由到真实 SpinBox 的 LineEdit，不手工设置数字值或发射提交信号。先等待控件真实 deferred 编辑生命周期，然后输入 `7`，尚未 Enter 时 numeric value 和真实草稿仍为 0；真实屏障施放、`Combat.tick(0.12, true)` 与时钟刷新后，文本仍为 `7`，草稿、资格、焦点、操作 ID 和编辑次数保持不变。Enter 经原生控件实际提交后，草稿为 7，活动构筑仍为 0。再通过另一实际 LineEdit 输入并 Enter 提交 4，真实总量 10 的预算拒绝应用且不分配操作 ID。既有冷却案例还校验真实 `BuildCooldowns` Label 更新。

Godot 4.7.2 的 [SpinBox 官方源代码](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/gui/spin_box.cpp#L685) 将 text_submitted 和 editing_toggled 回调连接为 deferred；测试等待两个 process frame 后观察。最初即时观察的报告 `build-controller-unsubmitted-red`（17 例、9 个断言失败）和 `build-controller-unsubmitted-baseline`（17 例、10 个断言失败）是测试驱动时序问题，不是产品业务 red；中途 `baseline-corrected` 有 helper 插入位置导致的 parse 错误，已纠正，也不作为业务 red。校正后的旧 Controller 路径 `build-controller-unsubmitted-baseline-events-stable` 实际 17/17 通过，未在本次 headless 控件路径复现输入被覆盖，因此记录为路径职责收敛与回归保障，不宣称已证实原生覆盖缺陷。

最终源码报告 `artifacts/build-controller-unsubmitted-final/report_1/results.xml` 和 `.log`：Godot 4.7.2.stable.ed1daf0bf / GdUnit4 6.2.2，1 suite，17 个测试、0 failures、0 errors、0 skipped、0 flaky、0 orphans、0 原生 ERROR/SCRIPT ERROR，进程 exit 0。结果和源哈希在 `build-controller-text-input-results.json`。这是实际控件与领域规则回归，不是键鼠硬件、GPU、MCP、真人或 Android 验收；全工程门槛由根最后统一重跑。

可重跑（每次使用新报告目录）：

```powershell
& 'D:/bugu_software/ai-game-toolchain/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_build_menu.gd -c -rd 'D:/bugu_projects/another_world/artifacts/build-controller-text-input-new-unique' --ignoreHeadlessMode
```
