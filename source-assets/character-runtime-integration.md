# 两角色运行时集成记录

2026-10-13。原生 Godot 4.7.2.stable.official.ed1daf0bf / GdUnit4 6.2.2。应用 `godot-animation` 与 `godot-gdscript` 技能，实际只读 Godot MCP ClassDB 核实 AnimationNodeOneShot 属性与枚举；本次没有启动、停止或修改主游戏 MCP 会话，没有运行 GPU 画面采样。

## 交付与调用契约

`game/config/character_visuals.json` 是本地角色、武器、动作及已测尺寸合同的集中配置。`character_visuals_config.gd` 拒绝未知字段、错误类型、非法数值、外部或越界路径、覆盖腿或右枪臂的过滤骨。资源预检进一步确认实际 PackedScene、真实 17 骨 / 17 bind 单蒙皮网格、有效骨骼轨道、左右腿运动键及自疗过滤对应轨道。

`AWPlayerController._ready()` 加载该配置。`visual_ready` 只有全部资源、动画树和武器装配成功后为 true；初次失败由 `visual_error` 提供原因，主场景可拒绝进入。失败没有胶囊角色替身。碰撞胶囊仍为半径 .38 / 高度 1.7；真实 GLB 视觉缩放 .76。

| 方法 | 实际行为 |
| --- | --- |
| `configure_visuals(config: Dictionary) -> Dictionary` | 先预检所有候选资源，再组装、提交；失败保留已运行角色。必须在 SceneTree 中调用。 |
| `set_character(id: String) -> Dictionary` | thief/healer 替换真实蒙皮角色；保持视觉朝向、武器阶级、生命、体力和共享 CombatState；相同身份返回 changed=false。玩法阶段切换资格由角色域和 GameSession 检查。 |
| `set_weapon_tier(tier: int) -> Dictionary` | 使用已导入的实际一/二阶电枪 GLB；非法阶级拒绝，无重复挂件。挂点本地 (.42,1.15,-.28)，电枪本地缩放 .62。 |
| `play_self_heal() -> Dictionary` | healer 专属 OneShot 动作请求；盗窃者、暂停/非活动/死亡、重复活动动作明确拒绝。生命恢复、成本和冷却由共享战斗域先实际施放，动画方法不制造治疗。 |
| `begin_dodge(effect_spec: Dictionary) -> Dictionary` | 只接收已验证 kind/duration/speed 启动移动；实际 duration 来自已验证 player 配置。调用方先执行共享 Combat.cast 并应用返回 vitals；Player 不再扣体力或设冷却。 |

对外保留现有 `camera`、`input_adapter`、生命/上限、体力/上限、`configure(parameters)` 等字段。新增 `combat_state: AWCombatState` 和 `shield_absorbed(amount)`。受击按方向防御、被动减伤、共享屏障吸收、真实生命扣除处理；只对生命伤害发 hurt，对实际屏障吸收发 shield_absorbed，死亡停用角色。共享战斗域未初始化时不擅自绕过屏障规则。

连续防御体力流失与自然体力恢复仍沿用 Player 的逐物理帧运动适配；闪避/技能费用及冷却统一在 CombatState。未引入第二套技能冷却权威。

## 动画树

`AnimationPlayer` 持有每实例独立深复制的动作资源，不承担运行时播放。Idle/Walk 设置 LOOP_LINEAR；SelfHeal 设置 LOOP_NONE。没有循环所有动作，没有 AnimationPlayer.play 与 AnimationTree 的双写。

树根 BlendTree 中 Locomotion 是 Idle / Walk 状态机；Walk 子树是实际 Walk clip → TimeScale → output。healer 的 Locomotion 与 RepairClip 通过 OneShot(Heal) 输出；过滤路径是 `healer_robot/healer_robot_Rig/Skeleton3D:<bone>` 的 Spine、Head、Clavicle_L、UpperArm_L、Forearm_L、Hand_L。骨盆、双腿与右枪臂轨道保持原步态。Spine 是右臂的祖先，合法上身运动仍会影响右手的全局位置；本次验证承诺右枪臂的局部骨骼轨道不被自疗覆盖，不宣称全局手腕静止。

动画物理回调继承角色 PAUSABLE。Walk 时间缩放以 `move_and_slide()` 后 `get_real_velocity()` 的水平模长 / 2.584 计算；实际墙面阻挡后输入仍请求移动而姿态回到 Idle。自疗请求由下一次树求值消费，固定 60Hz 步进测试真实相位，不能用单个巨大 delta 冒充多帧过程。

## 实际验证

最新严格报告：`artifacts/character-visuals-gdunit/fee4404afab3402e933c6e126b2fd57a/report_1/results.xml`。11 tests / 0 errors / 0 failures / 0 skipped / 0 flaky。源资产证据目录保留该 XML 副本和机器摘要；本报告是局部技术结果。

1. 配置类型、路径、过滤腿/右枪手及非法 nominal 检查。
2. 实际 17 骨蒙皮、树独占播放、私有 clip 资源与测量挂点。
3. 真实双腿骨骼摆动与速度比率、停步 Idle。
4. 同相位 healer 基线/自疗骨骼对照：左手真实移动；腿部全局姿态不变；右侧局部旋转不被覆盖；一次结束回到原动作；thief 拒绝自疗。
5. 12 次身份替换保持武器阶级、生命/体力及共享域快照，失败配置回滚。
6. 真实屏障在防御减伤后吸收，剩余伤害才扣生命。
7. 真实 StaticBody 墙/地面运动，碰撞阻挡后输入仍向右而 Walk 停止。
8. 暂停 32 个物理帧保持手部姿态、位置及闪避剩时，恢复后一次动作自然结束。
9. 去 skin、移除 Foot_L 轨道及把 healer 场景指向实际电枪均被拒绝；原动画树不被破坏，随后合法切换成功。
10. 方向防御与被动减伤、暂停/无敌/非法伤害数值、只一次死亡事件。
11. 真实 Combat.cast 闪避后应用其实际 vitals，Player 不再次扣费/变共享域；非法效果无部分运动。

记录过的缺陷：新增逐骨旋转预检在 `56f40ac3a1544795b64f3ae917ec2917` 失败，也在根代理 Main 回归重现。actual imported 每个动作有 17 轨：Pelvis 是 POSITION_3D，其他 16 骨为 ROTATION_3D；Godot 优化掉恒定 rest 旋转合法。修正为逐骨验证有效位置/旋转/缩放轨道，并继续强制真实蒙皮和六个腿关节运动键。`character-native-tracks.json` 保存实际 type/path/key_count。新 9/9、最终 11/11 的干净 import 与测试均通过。另一次新增测试发现字典返回值不能用 := 推断，显式 Dictionary 后重新严格执行；失败结果没有列为通过。

主场景真实 PC 输入、游戏内持枪/角色大小/自疗可读性、渲染无错误、可比性能、Android/手柄与真人品质继续由各自验收协议实际取得；本局部结果不替代商业最终角色品质或完整 feature 验收。原始 Blender / GLB / 源动作审查见 `characters-production.md`。

官方核查：[AnimationNodeOneShot](https://docs.godotengine.org/en/4.7/classes/class_animationnodeoneshot.html)、[AnimationTree](https://docs.godotengine.org/en/4.7/classes/class_animationtree.html)、[AnimationNodeTimeScale](https://docs.godotengine.org/en/4.7/classes/class_animationnodetimescale.html)。原生属性与枚举还由固定引擎 MCP ClassDB 实测。
