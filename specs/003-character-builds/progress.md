# 角色与构筑进度

2026-10-13。完整游戏目标继续active；本feature已激活并进入实施，不替代阶段002开放门槛收敛或完整产品交付。

已发生：读取实际Spec Kit四技能及模板、宪章/阶段001和002上下文；核查固定Godot官方计时/保存/输入资料与现有模块；和存档代理只读交叉审议领域版本/冷却；自主冻结角色/预算/余数/技能/引用/迁移方案，写入spec/plan/contracts/tasks。

规划时实际文档关联检查通过：13条REQ/NFR、13条AC、25项任务、11个协议、0 errors；分析无CRITICAL/HIGH。见[evidence/2026-10-13/planning-audit.md](evidence/2026-10-13/planning-audit.md)。根已实际切分支、设置feature、执行setup-plan/tasks/check-prerequisites并更新AGENTS，见[evidence/2026-10-13/activation.md](evidence/2026-10-13/activation.md)。规划检查本身不是新玩法测试。

当前19/25任务按自身独立技术门槛验收，开放209/221/222/223/224/225；两共鸣真实Main14/14已验收，迁移跨进程恢复已有证据，新增保存保护CR-003-03正在故障/全量回归。不是整个feature或完整游戏验收。主场景/派生属性/共享技能与恢复/控制器/原生Avatar/领域2完整保存恢复已接入。CR-003-03之前冻结源码225/225通过、无ERROR/failure/skip/flaky/orphan，当前新保存变更正待新的严格报告，证据为[evidence/2026-10-13/regression-and-build.md](evidence/2026-10-13/regression-and-build.md)及gdunit-unified-225.xml。Controller17、Avatar11、主场景19+新增14、金币12与迁移等55有局部细节，不重复相加。

真实InputEvent已发生：两thief远征12杀+采集/撤离49币/余数4；GUI切healer、键盘编辑并应用1点生命天赋、3个命名healer预设、真实敌伤后自疗扣35体力、20秒家族冷却两秒暂停冻结。已正常退出并启动新的游戏进程，标题仍保留约19.995833秒CD、127生命/85.316体力与三槽；按实际Enter继续后CD正常推进且币49/余数4及库存保留。存档driver曾因3.55e-15秒JSON往返误判，原始失败保留并修开发验证器，不修改业务补CD。

当前MCP原生cpp759错误仍复现（老会话冻结757文件Changed0，新Editor也复现）；独立冷完整60秒2run及skin/无skin各60秒11重建无错，尚无因果归属。相交差异不作为修复证明。两共鸣实际物理跨距/三目标上限与护盾受击已验证；完整PC覆盖、最终角色/场景品质、003生产构建/可比性能、设备/真人仍开放，真实失败与证据全部保留，见main-integration及regression-and-build。

当前风险：主场景单一冷却权威、实际技能/动画、引用影响提示和完整退出重启。纯规则/迁移/Control局部证据不能替代真实PC与构建/性能。新增ADR-036明确死亡检查点恢复；后续结果继续同步工件。

三阶装备/第二个人挑战/雷网绯红/珠宝/断链聚能保留到视觉门槛后的后继玩法阶段，004按用户新优先级负责原创视觉品质样板；不放未实现占位接口。没有Android/手柄/真人事实不会暂停可独立制作，也不会把其门槛标通过。

## 接续结果与用户优先级调整

2026-10-13新会话接续：CR-003-03新增真实重绑故障6case（5失败case/21断言的业务red→6/6green），主场景捕获/偏好dirty修复后全量严格247/247通过，15条已由官方断言捕获的IO诊断精确匹配policy2；未知Native/Script/diagnostic0，原始日志未过滤。当前Main SHA F783556715327ACD5925BBE1E5593DAB7D6394F4CD6E614CA79F2496117247B2。见gdunit-unified-247.xml及-summary.json、rebinding-transition-review.md与persistence-verification-audit.md。

当前正式官方引擎MCP run r271548-1完成既有8项角色输入覆盖及正常生产quit，1750源文件Changed0；全635 game日志和editor记录无ERROR、dropped0。两成功远征49币/余数4，疗愈自疗/三预设/暂停/标题恢复/实际死亡已发生。完整六个不同内容预设/通用技能装配/盗窃pending失败/受伤切角守恒等仍缺真实PC覆盖，不将这8项等同TASK-209完成。独立同副本官方引擎仍复现2次cpp759，因此BUG-112-01开放。

003新Windows导出已生成EXE/PCK且包审计阶段通过，但smoke实际超过300秒并失败，未产生accepted build-summary；完整构建/性能TASK-223仍开放，失败日志保留artifacts/003-continuation-build/c6711a109f63467ca967cd508af0a8fe/logs。不能称已交付生产构建。

用户明确否决当前粗糙demo，要求先达到参考视频的画风与精细完成度甚至超越，再继续后续开发；随后明确角色、建筑和布局须从0到1原创，不要求模型一致。制作顺序改为004视觉品质样板，先收敛空间/原创模型/PBR湿润/光照/动作/VFX/UI/可比证据与渲染错误，收住新增玩法；此前拟定004三阶等内容改为视觉门槛之后的后继，不丢原需求。003仍19/25，各开放任务继续保留，不以切feature消账。完整目标active，未自行暂停。
