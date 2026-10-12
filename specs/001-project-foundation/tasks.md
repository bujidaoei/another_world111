# Tasks: 《另一个世界》阶段0与后续路线

**Input**: [spec.md](spec.md)、[plan.md](plan.md)、[research.md](research.md)、[data-model.md](data-model.md)、[契约](contracts/gameplay.md)。
**状态日期**: 2026-10-13。
**组织**: 本轮仅阶段0，后续按US1→US2/US3→US4→US5评估/正式内容。
**编号**: TASK-001起；每项对应同号TEST验证协议，具体见[validation.md](validation.md)。
**完成定义**: [x]仅表示该任务的交付、规定验证和验收满足；研究完成不代表游戏功能实现。
**状态**: 实现/已测试/待验收/已验收分开；证据为空即未取得。未来路径拟建，尚不存在。
**结构镜像**: [task-records.json](task-records.json)供关联检查；本表与spec是审阅主源。
完整产品规则保留，但TASK-037至039只做后续评估/规格拆解；产品实施任务尚待另立规格，不假装已全部可编码。

## 阶段0

- [x] TASK-001 核查工程、设备与工具，交付/实现位置 `research.md`。
- [x] TASK-002 正式初始化Spec Kit并写宪章，交付/实现位置 `../../.specify/memory/constitution.md`。
- [x] TASK-003 访问参考视频与官方资料，分析图像、输入和原创方向，交付/实现位置 `research-design.md`。
- [x] TASK-004 编写规格、澄清、ADR、规则模型与契约，交付/实现位置 `spec.md`。
- [x] TASK-005 建立阶段计划、任务、测试和需求质量检查，交付/实现位置 `plan.md`。
- [x] TASK-006 实现关联验证并执行独立分析和收敛核对，交付/实现位置 `../../tools/verify_spec.py`。
- [x] TASK-007 敏感/许可扫描、提交推送并核对远端SHA，交付/实现位置 `evidence/2026-10-13/delivery.md`。
## 阶段0门槛

- [ ] TASK-008 审阅并冻结下一阶段内容、失败规则、点数解释、数值和资源门槛，交付/实现位置 `decisions.md`。
## 基础

- [ ] TASK-009 连接工具并执行引擎/渲染/GLB兼容探针，交付/实现位置 `../../game/project.godot`。
- [ ] TASK-010 配置Android路径、SDK版本、debug签名并实测导出，交付/实现位置 `../../game/export_presets.cfg`。
- [ ] TASK-011 固定并集成GdUnit4，验证4.7.2兼容性与非零发现，交付/实现位置 `../../game/tests/test_toolchain.gd`。
- [ ] TASK-012 冻结并校验规则/输入/渲染/音频与存档配置，交付/实现位置 `../../game/config/`。
## US1

- [ ] TASK-013 [US1] 编写远征、奖励、营地和升级门槛真实边界测试，交付/实现位置 `../../game/tests/test_expedition.gd`。
- [ ] TASK-014 [US1] 实现远征/遭遇/结算/撤离/失败核心状态，交付/实现位置 `../../game/features/expedition/`。
- [ ] TASK-015 [US1] 实现三输入意图、镜头、UI消费和基本菜单，交付/实现位置 `../../game/platform/`。
- [ ] TASK-016 [US1] 实现战斗时序、两敌人职责及一阶闪电三目标连锁，交付/实现位置 `../../game/features/combat/`。
- [ ] TASK-017 [US1] 实现采集、制作、补给和有功能营地设施，交付/实现位置 `../../game/features/expedition/crafting/`。
- [ ] TASK-018 [US1] 实现世界升级、个人挑战、二阶锚点与区域回访，交付/实现位置 `../../game/features/progression/`。
- [ ] TASK-019 [US1] 实现双有效槽存档、迁移、设置、错误/后台恢复，交付/实现位置 `../../game/persistence/`。
- [ ] TASK-020 [US1] PC完整流程实测及首个原型交付，交付/实现位置 `evidence/pc-prototype/`。
- [ ] TASK-021 [US1] 目标玩家原型观察、问题修订与对比验证，交付/实现位置 `evidence/human-prototype/`。
## US2

- [ ] TASK-022 [US2] 编写装备预算、融合、扩槽、进阶事务边界测试，交付/实现位置 `../../game/tests/test_equipment.gd`。
- [ ] TASK-023 [US2] 实现装备生成与营地融合/扩槽/进阶，交付/实现位置 `../../game/features/equipment/`。
- [ ] TASK-024 [US2] 实现装备预览、概率/成本说明和完整培养流程UI，交付/实现位置 `../../game/presentation/equipment/`。
## US3

- [ ] TASK-025 [US3] 编写角色、点数、配置、恢复冷却与预设边界测试，交付/实现位置 `../../game/tests/test_characters.gd`。
- [ ] TASK-026 [US3] 实现角色专属与公共解锁、天赋、技能和三预设，交付/实现位置 `../../game/features/characters/`。
- [ ] TASK-027 [US3] 实现营地应用/切换UI并验证构筑成长完整流程，交付/实现位置 `../../game/presentation/builds/`。
## US4

- [ ] TASK-028 [US4] Blender原创代表模型/骨骼/动作/场景样本与风格批准，交付/实现位置 `../../source-assets/`。
- [ ] TASK-029 [US4] 验证Comfy本地工作流、模型/节点许可并制作采用图像样本，交付/实现位置 `../../source-assets/workflows/`。
- [ ] TASK-030 [US4] 集成原创地编/雨水/电弧/音频/UI，修订视听样本，交付/实现位置 `../../game/assets/`。
- [ ] TASK-031 [US4] 参考对照视觉评审与动态实机证据，交付/实现位置 `evidence/visual-comparison/`。
- [ ] TASK-032 [US4] PC分位帧时间、内存/加载和渲染档位测量优化，交付/实现位置 `evidence/pc-performance/`。
- [ ] TASK-033 [US4] Android真实设备接入、导出安装与存档升级流程，交付/实现位置 `evidence/android-install/`。
- [ ] TASK-034 [US4] Android多指/安全区/后台/声音与30分钟热性能验收，交付/实现位置 `evidence/android-device/`。
- [ ] TASK-035 [US4] 实际手柄与PC DPI/窗口/重映射/焦点验收，交付/实现位置 `evidence/input-devices/`。
- [ ] TASK-036 [US4] 双端真人切片试玩与循环/品质修订验收，交付/实现位置 `evidence/human-slice/`。
## US5评估

- [ ] TASK-037 合作价值/网络权威/跨境界适配与首发去留评估，交付/实现位置 `decisions.md`。
## 后续规则

- [ ] TASK-038 冻结三阶分支、共鸣、珠宝/外观单人路径并拆独立实施验收任务，交付/实现位置 `spec.md`。
## 正式内容

- [ ] TASK-039 按通过切片产能冻结首发体量与正式内容规格、拆任务，交付/实现位置 `plan.md`。
## 发行基础

- [ ] TASK-040 固定CI/依赖/Actions并执行干净检出测试和两平台构建，交付/实现位置 `../../.github/workflows/`。
## 稳定性

- [ ] TASK-041 2小时连续游玩/反复切区存档、严重缺陷回归，交付/实现位置 `evidence/stability/`。
## 发行验收

- [ ] TASK-042 源资产许可/秘密/产物/安装升级/远端SHA及交接验收，交付/实现位置 `evidence/release/`。

## 任务执行与验收记录

| TASK | 需求 | AC | 依赖 | 验证/验收 | 状态 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| TASK-001 | REQ-001 | AC-001 | 无 | TEST-001：命令/MCP真实返回含失败和限制 | 已验收（核查任务） | [记录](evidence/2026-10-13/tool-audit.md) |
| TASK-002 | REQ-002 | AC-002 | TASK-001 | TEST-002：CLI初始化exit0、skills/脚本/模板真实存在 | 已验收（初始化任务） | [记录](evidence/2026-10-13/speckit-audit.md) |
| TASK-003 | REQ-001, REQ-003, REQ-026, REQ-027 | AC-001, AC-003 | TASK-001 | TEST-003：指定BV实际解码帧，事实/推断/限制分离 | 已验收（研究任务） | [记录](research-design.md) |
| TASK-004 | REQ-002, REQ-003, NFR-004 | AC-002, AC-003, AC-031 | TASK-002, TASK-003 | TEST-004：全部原文规则保留，已确认与建议不同，凭据不入库 | 已验收（阶段0工件与真实检查） | [记录](evidence/2026-10-13/validation-result.json) |
| TASK-005 | REQ-002, REQ-003, NFR-003 | AC-002, AC-003, AC-030 | TASK-004 | TEST-005：每项路径/依赖/验证/AC/状态/证据可查 | 已验收（阶段0工件与真实检查） | [记录](evidence/2026-10-13/validation-result.json) |
| TASK-006 | REQ-002, NFR-004 | AC-002, AC-031 | TASK-005 | TEST-006：关联非零错误拒绝，独立语义审查无未修高风险冲突 | 已验收（阶段0工件与真实检查） | [记录](evidence/2026-10-13/validation-result.json) |
| TASK-007 | REQ-003, NFR-004 | AC-003, AC-031 | TASK-006 | TEST-007：不含参考截图/凭据，安全Git推送成功且远端SHA一致 | 已验收（安全推送/远端SHA/干净检出） | [记录](evidence/2026-10-13/delivery.md) |
| TASK-008 | REQ-003, REQ-008, REQ-010, REQ-015, REQ-023 | AC-003, AC-008, AC-010, AC-015, AC-023 | TASK-005 | TEST-008：D-002至006有可执行决定，预算/日期不虚构，Android仍独立门槛 | 待决策；阶段0技术资料可交付 | 尚无 |
| TASK-009 | REQ-001, NFR-001 | AC-001, AC-028 | TASK-008 | TEST-009：正确工程会话、导入/运行、GLB变形/材质和Mobile对照证据 | 未开始 | 尚无 |
| TASK-010 | NFR-005 | AC-032 | TASK-009 | TEST-010：依所选APK/Gradle路径验证依赖，导出真实成功，签名不入仓库 | 未开始 | 尚无 |
| TASK-011 | NFR-003, NFR-005 | AC-030, AC-032 | TASK-009 | TEST-011：固定SHA，实际pass/fail/zero-discovery退出码符合，非零真实测试 | 未开始 | 尚无 |
| TASK-012 | REQ-005, REQ-008, REQ-010, REQ-012, REQ-023, NFR-001 | AC-005, AC-008, AC-010, AC-012, AC-023, AC-028 | TASK-008, TASK-011 | TEST-012：逐阶预算、概率、经验/成本、动作时序、输入参数、保存损失及错误行为具体化 | 未开始 | 尚无 |
| TASK-013 | REQ-004, REQ-005, REQ-028 | AC-004, AC-005, AC-033 | TASK-012 | TEST-013：测试含至少一个真实目标任务/击杀经验资源、重复领奖拒绝、状态/门槛；先失败后实现通过，不测试假业务 | 未开始 | 尚无 |
| TASK-014 | REQ-004, NFR-001 | AC-004, AC-028 | TASK-013 | TEST-014：一次结算与目标任务奖励幂等、真实资源、短脱战仍active、重置后结束，TEST-013/014通过 | 未开始 | 尚无 |
| TASK-015 | REQ-022, REQ-023, REQ-024 | AC-022, AC-023, AC-024 | TASK-012 | TEST-015：移动/瞄准/技能/防御/闪避/取消/固定镜头无漏入，设备未测单独开放 | 未开始 | 尚无 |
| TASK-016 | REQ-004, REQ-012 | AC-004, AC-012 | TASK-014, TASK-015 | TEST-016：真实命中、范围/资格/冷却、预备命中恢复；无障碍穿透假判定 | 未开始 | 尚无 |
| TASK-017 | REQ-004, REQ-028 | AC-004, AC-033 | TASK-014 | TEST-017：成本守恒、选择影响准备，设施真实作用且存档持久 | 未开始 | 尚无 |
| TASK-018 | REQ-005, REQ-006, REQ-012, REQ-014 | AC-005, AC-006, AC-012, AC-014 | TASK-016, TASK-017, TASK-023 | TEST-018：真实任务/击杀升级到30、失败/重试/胜利、经验储备、同一电枪合法进阶、二阶新区域/旧区用途/锚点实操 | 未开始 | 尚无 |
| TASK-019 | REQ-024, REQ-025, NFR-001 | AC-024, AC-025, AC-028 | TASK-014, TASK-012 | TEST-019：完整存档故障矩阵通过、失败保留有效槽，设置和游戏时钟一致 | 未开始 | 尚无 |
| TASK-020 | REQ-004, REQ-005, REQ-006, REQ-012, REQ-022, REQ-024, REQ-025, REQ-028, NFR-003 | AC-004, AC-005, AC-006, AC-012, AC-022, AC-024, AC-025, AC-030, AC-033 | TASK-018, TASK-019 | TEST-020：首次启动→出营→真实任务/击杀奖励→成败→暂停→晋阶与电枪进阶→保存退出→恢复；融合/扩槽UI另在TASK-024，不以夹具代替 | 未开始 | 尚无 |
| TASK-021 | NFR-003 | AC-030 | TASK-020 | TEST-021：真实匹配参与者/观察/原话/构建/情境，关键假设有证据；无人不通过 | 未开始 | 尚无 |
| TASK-022 | REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-014 | AC-007, AC-008, AC-009, AC-010, AC-011, AC-014 | TASK-012 | TEST-022：枚举预算/互斥/锁定/候选不足/重复确认/身份经历/资格，真实实现验 | 未开始 | 尚无 |
| TASK-023 | REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-014 | AC-007, AC-008, AC-009, AC-010, AC-011, AC-014 | TASK-022 | TEST-023：所有普通词条合法、固定金币、完整原子事务、历史来自实际事件 | 未开始 | 尚无 |
| TASK-024 | REQ-009, REQ-010, REQ-011 | AC-009, AC-010, AC-011 | TASK-023, TASK-020 | TEST-024：真实获得资源装备后完成熔炉/扩槽/进阶/保存，取消无消费 | 未开始 | 尚无 |
| TASK-025 | REQ-015, REQ-017, REQ-018 | AC-015, AC-017, AC-018 | TASK-012 | TEST-025：D-005冻结后验证共享总点/角色独立配置解释、3套、生命比例资源冷却、治疗轮换拒绝 | 未开始 | 尚无 |
| TASK-026 | REQ-015, REQ-017, REQ-018 | AC-015, AC-017, AC-018 | TASK-025, TASK-018 | TEST-026：D-005冻结后两角色样本真实解锁、通用内容资格、专属不转移；独立配置与共享总量按确认解释执行，状态保持 | 未开始 | 尚无 |
| TASK-027 | REQ-006, REQ-012, REQ-015, REQ-017, REQ-018 | AC-006, AC-012, AC-015, AC-017, AC-018 | TASK-026, TASK-024 | TEST-027：编辑与生效分离、遭遇结束检查、三目标→锚点打法对比、实际角色切换 | 未开始 | 尚无 |
| TASK-028 | REQ-026 | AC-026 | TASK-009, TASK-021 | TEST-028：实际源工程/GLB/LOD/UV/材质/骨骼/接触时序及游戏内检查 | 未开始 | 尚无 |
| TASK-029 | REQ-026, NFR-004 | AC-026, AC-031 | TASK-008, TASK-028 | TEST-029：服务运行、许可/哈希/版本/种子/产物、纹理和UI真实采用；不调用未授权收费节点 | 未开始 | 尚无 |
| TASK-030 | REQ-024, REQ-026, REQ-028 | AC-024, AC-026, AC-033 | TASK-028, TASK-029, TASK-027 | TEST-030：实际可玩尺度、碰撞/遮挡、视听同步、总线/削波/循环、资源清单对应 | 未开始 | 尚无 |
| TASK-031 | REQ-027 | AC-027 | TASK-030, TASK-032 | TEST-031：相近构图/分辨率、无剪辑动作雨水镜头、非制作方逐项原因；未胜出不通过 | 未开始 | 尚无 |
| TASK-032 | NFR-002 | AC-029 | TASK-030 | TEST-032：同场景保存全部样本、P50/95/99与长帧、CPU/GPU/峰值内存和画质可读 | 未开始 | 尚无 |
| TASK-033 | REQ-023, REQ-025, NFR-005 | AC-023, AC-025, AC-032 | TASK-010, TASK-030 | TEST-033：记录真实型号/系统、签名产物哈希、安装/首次/升级/重载；缺设备开放 | 等待后续手机 | 尚无 |
| TASK-034 | REQ-022, REQ-023, REQ-024, REQ-026, NFR-002 | AC-022, AC-023, AC-024, AC-026, AC-029 | TASK-033 | TEST-034：真实完整流程、误触/遮挡/生命周期、P95/99/温升电量与扬声器；仿真不代替 | 等待后续手机 | 尚无 |
| TASK-035 | REQ-022, REQ-023, REQ-024 | AC-022, AC-023, AC-024 | TASK-015, TASK-030 | TEST-035：具名手柄、设备切换、失焦/返回、重映射和不同帧率，实测证据 | 设备待核查 | 尚无 |
| TASK-036 | REQ-004, REQ-026, REQ-027, NFR-003 | AC-004, AC-026, AC-027, AC-030 | TASK-031, TASK-034, TASK-035 | TEST-036：两设备匹配玩家真实观察；技术/体验/生产门槛分别达成 | 未开始 | 尚无 |
| TASK-037 | REQ-020, REQ-021 | AC-020, AC-021 | TASK-021 | TEST-037：规则/成本/风险实验后用户决定；评估不代表合作实现，另建规格与真实客户端任务 | 单人验证后评估 | 尚无 |
| TASK-038 | REQ-013, REQ-016, REQ-019 | AC-013, AC-016, AC-019 | TASK-036 | TEST-038：完整专属不能叠加、高阶资格/真伤/阈值/皮肤判定数值与真实测试范围冻结 | 后续，非首原型 | 尚无 |
| TASK-039 | REQ-006, REQ-013, REQ-016, REQ-019, REQ-020, REQ-021 | AC-006, AC-013, AC-016, AC-019, AC-020, AC-021 | TASK-036, TASK-037, TASK-038 | TEST-039：预算人力/生产吞吐支持数量与工期；每批规则/原创建模/单人途径/真实验收独立 | 后续，未承诺 | 尚无 |
| TASK-040 | NFR-003, NFR-004, NFR-005 | AC-030, AC-031, AC-032 | TASK-011, TASK-033, TASK-039 | TEST-040：非零测试、资源许可/静态引用、最小权限、失败阻断与归档、独立检出 | 未开始 | 尚无 |
| TASK-041 | REQ-025, NFR-002, NFR-003 | AC-025, AC-029, AC-030 | TASK-036 | TEST-041：暴露量和故障真实记录，无崩溃/卡死/存档损坏阻断缺陷，修复有回归 | 未开始 | 尚无 |
| TASK-042 | REQ-003, NFR-004, NFR-005 | AC-003, AC-031, AC-032 | TASK-040, TASK-041 | TEST-042：所有规定平台/真人/内容子任务通过后交付构建、源项目、许可与完整证据 | 未开始 | 尚无 |

## Dependencies & Execution Order

- 环境与视频/竞品研究独立委派；没有两代理同时操作同一编辑器/浏览器。
- TASK-008进入阶段1规格冻结；TASK-009/011兼容探针、TASK-012配置合法，测试先于高风险逻辑。
- US1贯通真实循环，TASK-020是PC技术流程，TASK-021是真人观察，不能混为通过。
- US2装备和US3角色分文件并行；集成与UI顺序按依赖，共用配置由主代理冻结。
- US4模型/声音/UI可分工；共用Blender/Godot会话独占协调，Comfy许可/采用链明确。
- Android/手柄缺设备不阻止PC准备，但TASK-034/035/036不能勾选，切片整体不通过。
- US5只评估；三阶/正式内容另立规格。TASK-039完成不代表正式内容生产完成。
- TASK-042还依赖未来各规格必需实现/平台/真人任务全部通过。

## Parallel Example

装备代理负责`game/features/equipment/`与tests，角色代理负责`game/features/characters/`与tests。
主代理冻结共享配置/契约，集成后验证营地+遭遇结束、存档和资源事务。
输入与核心状态可分工，先定义意图/事件契约并避免同文件并改。

## Implementation Strategy

阶段0交付/范围审阅→PC可玩原型/真实玩家观察/修订→代表品质和装备角色完整操作/Android真机→扩大生产。
缺证据不完成；失败建立BUG，回归后附记录。以已确认需求/验收推进，不以文档数量代表游戏进度。
