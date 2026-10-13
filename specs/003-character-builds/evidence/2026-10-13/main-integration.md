# 主场景与真实输入实施记录

2026-10-13。GameSession已接入两角色、集中派生属性、共享CombatState、构筑控制器及真实Avatar。技能只由Combat预检/支付/计时，Player负责运动/动画/防御后的屏障吸收；攻击用实际目标射线、绝对伤害、阶段连锁上限和共鸣范围。自疗与药包/口粮预检后支付，消费/生命/持续冷却同一领域2载荷验证后写入双槽。构筑应用同步真实vitals、身份/武器，再保存。营地活时钟，暂停/标题/离线冻结；死亡检查点按ADR-036，结算按ADR-037。

严格主场景19/19通过：`artifacts/003-main-presentation/0e6e6436f0b640f488a8b79727492ef9/report_1/results.xml`，import/test exit0、无原生/脚本ERROR、fail/error/skip/flaky/orphan均0。含实际18秒锚点清理后timeout、真实Control滚轮/点击、未来domain3标题阻写、domain2保存/新scene恢复、暂停AI/真实cast冷却。最初`f14f39d27d5b4c62a8444ae4cf83189b`失败，因为Avatar预检误要求Pelvis旋转轨；Godot合法导入实际为Pelvis位置、其他16骨旋转，修正仍校验17bind真实skin、逐骨transform和腿关节多关键帧。最初失败未标通过。

Avatar独立11/11证据见`source-assets/character-runtime-integration.md`。它不替代主场景/实际GPU。控制器该时点16例局部通过；所有报告重叠不能相加当全量总数。

Godot MCP run13，原生Mobile Vulkan、自定义QA场景`res://tests/runtime/qa_character_session.tscn`，真实隔离保存路径`user://tests/character_playtest/20261013_003_a`。挂载开发InputEvent driver后从标题真正点击新旅程，经实际移动、物理射线、武器/技能伤害、注册击杀、搜集和撤离完成2run，31.55秒。完整阶段记录`thief-two-runs-input-events.json`。第1run 6杀+目标收益24币；第2run25币，合计49币；角色余数4，世界等级10、原starter身份及经历保留、实际四掉落入库。基础怪币24×5%=1额外币余4，目标24币不参与修正。没有直接奖XP/发物品/改HP/传送/kill调用。

同run真实GUI先点击查看疗愈者（活动仍thief），再点击确认应用（活动/视觉/已保存角色均healer），金币49/余数4、生命125/125及体力120保留。这只是满生命切换对照，未声称受伤比例、自疗或六预设PC流程完成。两张无modal原生场景图保存在artifacts/003-thief-camp-live.png与003-healer-camp-live.png；角色颜色可分，但统一格地、场景层次、近镜活动辨识仍不满足最终参考品质。

**本轮真实GPU未通过**：run13出现原生`particles_get_instance_buffer_motion_vectors_offsets` cpp759错误，见mcp-run13-log.json。它不能因没有GPUParticles节点而忽略。旧冻结002生产4run零错误不能代表当前003；正在做新角色/生命周期的独立冷启动对照。本轮玩法数据证明上述行为实际发生，整项PC/渲染门槛仍开放。截图还发现右下三行控制说明高度不足，已调整布局源，待下一次实际启动复验。

run13最终3次相同原生错误，见mcp-run13-final-log.json。随后根的一段诊断eval使用空格缩进，与插件生成的tab缩进混用，触发ParserError并停在远程调试break；是诊断工具脚本错误，不是游戏源码启动失败或业务red。按MCP契约停止该会话，故本轮无正常退出门槛通过声明。

之后实际独立冷进程`artifacts/003-cold-mobile-two-runs.log`：固定4.7.2/Mobile Vulkan/RTX4060，60秒14318帧，2次合法InputEvent远征done，生产_request_quit exit0、无ERROR/泄漏。它不是生产发布包/性能测量，也未覆盖角色切换。前段与失败MCP进程有短暂GPU重叠，后段独立；新冻结源MCP及独立角色切换对照还需执行，不能据此把run13错误归因热重载或宣布全部渲染问题解决。
