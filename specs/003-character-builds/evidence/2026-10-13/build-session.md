# 003 主场景独立集成回归

2026-10-13；`game/tests/test_build_session.gd`对应TASK-217实际路径及技能/恢复/存档的局部门槛。源代码由根/角色代理持有，本测试代理没有修改GameSession、Player、HUD、BuildMenu、角色资产或存档实现。

最新新增实际锚点链桥与屏障容量两个共鸣阈值案例，同一suite当前14/14通过，最终报告为 `artifacts/build-session-resonance-target-path-stable/report_1/results.xml`。见 [两共鸣主场景证据](build-session-resonance.md)；以下12案例与冷run14冻结记录保留为当时交付历史，不混称为最新全量结果。

## 原12例报告的执行事实

根完成主场景与角色真实导入/原19例严格门槛后才运行此suite。首轮9例在`artifacts/build-session-first-nine/report_1/results.xml`通过；补容量重试、放弃与两视口后，稳定报告为`artifacts/build-session-capacity-and-viewports/report_1/results.xml`、`artifacts/build-session-capacity-and-viewports.log`。实际Godot4.7.2.stable.ed1daf0bf/GdUnit4 6.2.2，12案例、0失败、0错误、0跳过、0flaky、0orphans，exit0，原生日志无ERROR或SCRIPT ERROR。执行约3.06秒。不把根先前动画导入失败或测试nil连带计作本suite业务red。

全部使用实际Main场景、角色/装备/技能/库存/存档/控件生产路径。每案例独立`user://tests/build_session/<pid_usec>/<scene>`目录；重载用同一案例的第二个真实场景。未来保护用真实双槽，旧档来自已归档的真实domain1容器。测试保存/恢复原命名InputMap动作，不留下键位更改；释放场景后仅清理显式受限目录和preferences叶目录，拒绝链接/未知子目录，未递归清用户存档。

启动失败先断言并返回，不用nil错误掩盖真正启动原因。测试关闭自动Session过程和玩家物理帧输入/自然恢复，单独驱动生产方法及明确玩法时钟，避免保存/状态比较时受偶然帧推进影响；GUI布局/输入与需要空间同步的物理帧仍真实运行。

## 原12例报告的实际覆盖

| 案例 | 生产路径与断言 |
| --- | --- |
| 草稿与应用保存 | Main→真实SpinBox→Controller；草稿不改生效属性；确认应用保留0.4生命比例、70体力及资源/装备；domain2真实保存4点生命天赋与最新vitals。 |
| 屏障吸伤 | `_cast_skill("barrier")`实际支付20体力；玩家生产take_damage(30)先扣24真实容量，生命仅减6；CD10和生命保存。 |
| 聚焦真实攻击 | 二阶境界保留一阶原电枪，生产focus与`_attack`命中真实登记拾荒体；基准武器30乘1.15为34.5，64生命敌人剩29.5，不用饱和死亡掩盖伤害增量。 |
| 恢复跨身份/预设/重载 | Main真实自疗从0.4恢复至0.7比例并扣35体力；20秒self_heal/家族跨角色/预设/第二Scene与继续保持，药包/口粮不消耗或重复治疗。 |
| 药包阻止自疗 | 真实药包消费设置家族20秒，期间自疗无扣体力/回血；暂停tick不推进，真实玩法tick20秒后自疗可支付并治疗。 |
| 实际死亡回营 | 真实玩家致命伤触发died→远征失败→回营；恢复35%生命，只清持续增益，共享CD、已入库资源及世界不变并保存。 |
| HP0检查点 | 明确死亡检查点夹具以真实保存载入；标题保持0生命且暂停；continue按明确失败恢复35%，清屏障、保10秒CD/40体力并更新真实存档。 |
| 未来domain3 | 在真实容器保存future领域并记录两个slot SHA；新场景阻写、new_game/confirm_new/continue守卫生效，两原始slot保持。 |
| 真实domain1迁移 | 从真实容器payload恢复；世界、资源、全部原装备身份/词条/经历和数量不变（只规范穿戴标记）；两角色引用同一原活动实例；继续/保存后domain2。 |
| 容量失败与重试 | pending由3个实际注册敌人的生产_attack和2个实际节点_interact取得，含真实目标奖励和1件掉落；有限库存9拒绝18金币奖励时资源/装备/余数全未提交；恢复真实容量后retry一次共同入库，再重试不重复，XP不重发。 |
| 放弃待结算 | 同样真实获得pending后容量受限；abandon丢pending且回营，保已入库库存/余数、当前20%生命，不借放弃获得失败35%补给。 |
| 两视口GUI路径 | 1600×900/1280×720真实SubViewport；菜单边界、天赋tab焦点、wheel按下及释放使长真实天赋菜单滚到底、hover/真实点击返回营地，GUI不漏入鼠标攻击。 |

## 原12例报告的夹具与验收边界

这12例是明确的集成单元测试。世界境界/天赋与初始装备进阶材料是合法公开规则建立的受控前置；受伤、死亡检查点、固定角色/敌人/节点位置和有限容量是明确夹具，不声称玩出个人挑战或真实移动路线。除这些明示前置夹具外，目标与击杀收益均由真实登记敌人及节点生产路径发放，没有以直接授予XP、金币或pending掉落替代收益过程；攻击伤害源自实际已生效规则。

所有鼠标事件由真实Viewport GUI路线投递，证明控件与规则消费；不等于物理鼠标、PC原生窗口游玩或Android/手柄真人证明。该headless报告不覆盖NativeVulkan渲染、性能、长期稳定性、最终角色视听品质或002开放渲染缺陷。归档原12例时，根正在固定运行源码做Native冷启动run14，代理遵循该时点冻结且仅写spec证据；这段是历史暴露范围，不表示当前仍停留在run14。后续明确授权的新增两共鸣14例见本文开头链接，最新全量状态由根的regression-and-build与progress记录。

## 可重跑

```powershell
& 'D:/bugu_software/ai-game-toolchain/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_build_session.gd -c -rd 'D:/bugu_projects/another_world/artifacts/build-session-new-unique-report' --ignoreHeadlessMode
```

目录每次新建；核对JUnit非零、进程exit、fail/error/skip及原生日志。当前代理没有运行根最后全量wrapper，也没有改共享任务勾选；根统一复核验收及CR实施组织记录。
