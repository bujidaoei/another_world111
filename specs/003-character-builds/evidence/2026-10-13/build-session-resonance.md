# 主场景两共鸣阈值与实际效果回归

2026-10-13；关联 ADR-030、TASK-219、TASK-217。仅新增 `game/tests/test_build_session.gd` 两个案例，没有修改 GameSession、Player、Evaluator、Combat、碰撞或资产，也未勾选共享任务。完整游戏、PC游玩、Native渲染、Android与真人仍由各自证据门槛判定。

每组 7／8 点分别启动真实 Main 与独立 `user://tests/build_session/<pid_usec>/<suffix>` 存档。境界二阶、个人30级、原电枪二阶由已验证的公开领域规则建立为明确单元前置；材料和守卫资格是夹具，不宣称从实际游玩取得。天赋草稿通过真实 Roster 建立并经生产 BuildController 应用，公共库存与原装备身份不复制。玩家／NPC位置、停止非测试AI帧是空间夹具；伤害由生产攻击路径产生，不直接改敌人生命或调用敌人 take_damage。

| 实际案例 | 生产路径与门槛断言 |
| --- | --- |
| `test_real_wandering_conductor_threshold_bridges_anchor_with_three_target_limit` | 机动分支 mobility 7／8，真实二阶电枪，chain_range 4.5、chain_targets 3；anchor_range 分别7／8.5。真实 `_place_anchor()` 从玩家(4.75,.2,3.5)朝FORWARD产生锚点(4.75,.2,1)，支付15体力／CD3；再移动至(-5,.2,1)朝RIGHT，生产 `_attack()` 命中真实注册A(-3,.1,1)，B(8.25,.1,1)、C(8.25,.1,4)、D(8.25,.1,7)。A命中点到锚点约7.80米，7点只A受击，8点A／B／C受击、D不受击，验证阈值真实跨距与三个目标上限。 |
| `test_real_charged_guard_threshold_changes_cast_capacity_and_player_health_damage` | 守护分支 defense_efficiency 7／8，装配真实barrier，未防御且被动减伤0；生产 `_cast_skill("barrier")` 均付20体力，实际Combat容量24／27.6；生产Player.take_damage(30)使生命余伤6／2.4、容量耗尽，共享屏障CD仍10秒。 |

链桥测试选四个原登记拾荒体（真实ID rain_guard_01／02／04／05），使用原配置64生命；其他原登记敌人inactive。通过真实 physics_frame 同步空间后，生产 `_find_target` 额外确认：初射只能选A，A处基准4.5米没有直接后继，锚点处实际最近可见目标为B，B到C与C到D都是可见合法目标。D未命中由目标上限决定，未使用mock或关闭遮挡。原世界、碰撞层和射线保持不变，本次无需修改给定坐标。

原电枪进阶将词条25→37，实际武器伤害65.76，A被正常击杀；测试按真实生命下界0验证并确认只有A登记死亡、增加6XP、pending怪物币2／盗窃余数2，未凭空注入奖励。B／C按实际派生衰减分别扣伤，D保持64生命。首轮我错误假定二阶伤害仍低于64，导致 `artifacts/build-session-resonance-first/report_1/results.xml` 中1 case／6 assertions失败（总14例，0运行或原生错误）；全部是A负生命预期和“世界／击杀不变”的错误断言，桥距、其他目标及护盾断言已通过。首轮原始日志完整保留；仅纠正测试断言，没有改业务或抬高NPC血量，不将此诊断记为产品缺陷修复。

当前最终源码报告 `artifacts/build-session-resonance-target-path-stable/report_1/results.xml`、`.log`：Godot 4.7.2.stable.ed1daf0bf／GdUnit4 6.2.2，1 suite，14案例，0failures／errors／skipped／flaky／orphans，0原生ERROR／SCRIPT ERROR，exit0，约3.27秒。比先前12例增加两个案例；不把此局部报告与此前223例全量门槛相加宣称全量已通过。源哈希和案例列表见 `build-session-resonance-results.json`。源码至此冻结，根随后执行最终全量门槛。

可重跑（新建独立报告目录）：

```powershell
& 'D:/bugu_software/ai-game-toolchain/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_build_session.gd -c -rd 'D:/bugu_projects/another_world/artifacts/build-session-resonance-new-unique' --ignoreHeadlessMode
```

此代理未运行全工程import、GodotMCP或GPU。现有两视口真实GUI回归也在本轮14例中重跑；其InputEvent与这些生产方法调用都是集成单元证据，不能代替键鼠硬件或完整PC实玩。
