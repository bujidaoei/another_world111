# 原生PC真实InputEvent流程

2026-10-13。通过Godot MCP附加开发用 `game/tests/runtime/input_playtest_driver.gd`，事件为InputEventKey/MouseMotion/MouseButton，由Godot真实GUI/未消费输入路由执行。driver读取状态和相机投影用于观察/选择动作；没有修改玩家位置、发放经验/资源、直接伤害或调用菜单业务命令。直接滚动ensure_control_visible仅帮助QA到达按钮，不能冒充手柄/滚轮设备验证；这些有独立回归。

从实际新旅程按钮及确认开始，7次雨庭远征各真实击败6敌人、采集3节点、完成目标并撤离；首次96XP、24金币、9废铁、1晶片。个人level30停级、banked92。完整事件/结算快照见[input-playtest-seven-runs.json](input-playtest-seven-runs.json)。过程中一次真实APPLICATION_FOCUS_OUT暂停，driver通过菜单“继续”事件恢复；未绕过暂停标志。

随后真实点击建设维护台、融合预览/锁定武器功率/确认融合、4→5扩槽；挑战守卫胜利后realm2且晋阶记录一次，原starter-lightning在营地进阶2、保持instance_id/首次经历/5槽。F输入布置锚点，随后导体工场真实战斗/三采集/撤离。见[input-playtest-ascension-and-conduit.json](input-playtest-ascension-and-conduit.json)。原型一至二阶关键流程成功不代表玩法乐趣、正式平衡或完整内容。

发现并修订：虚拟视口与窗口输入坐标转换、菜单锚点offset、失焦输入清理、南侧边界、敌人风up计时；先前单独执行失败回营保留经验/装备并丢pending。后续仍需新代码版完整重跑成败/恢复与锚点跨距实测。

本次二阶远征结束后的18秒锚点到期触发了“Lambda capture ... freed”引擎错误，不能将该运行声明为无错误验收。已换WeakRef绑定回调；独立生命周期回归通过，完整新版锚点跨距仍待重跑。原生Renderer null-particles随后在GPUParticles、CPUParticles和当前批量Shader雨完整运行均复现，另立BUG-112-01，不以换表现方案或隐藏日志关闭。所有当前报告与源码阶段分别留存。

这是自动化引擎输入流程，不是人类试玩或物理键鼠/触控设备验收；完整TASK-114保持开放。
