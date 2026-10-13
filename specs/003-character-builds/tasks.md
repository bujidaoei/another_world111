# Tasks: 角色、天赋与流派预设

**Input**: `specs/003-character-builds/`设计工件。

**Prerequisites**: 阶段002核心/存档/输入基础实际通过相应局部门槛；本功能spec、plan、research、data-model、contracts准备完成后由根激活。

**Tests**: 用户要求充分覆盖真实业务，危险边界先写可执行测试、记录真实失败原因，再实现修复；语法错误或0发现不是有效业务red证据。

**Organization**: 按故事分组；当前19/25任务通过各自独立技术门槛，其余6项保持开放；完整feature未验收，`task-records.json`保存REQ/NFR/AC/依赖/TEST/状态。`[P]`只指不同独占文件且前置完成后可并行。

## Phase 1: Setup (Shared Infrastructure)

- [x] TASK-201 激活本feature并按实际Spec Kit scripts完成规划/任务/检查、确认规格分析与状态，路径 `specs/003-character-builds/plan.md`。
- [x] TASK-202 [P] 落实集中角色/天赋/技能/共鸣配置与非法schema/跨引用校验、实际非零验证，路径 `game/config/character_builds_config.gd`。

## Phase 2: Foundational (Blocking Prerequisites)

- [x] TASK-203 实现深复制角色档案/构筑结构、资格与派生值基础并独立测试，路径 `game/features/characters/build_evaluator.gd`。
- [x] TASK-204 [P] 写共享计时/恢复/屏障/增益真实边界测试并记录业务失败，路径 `game/tests/test_combat_state.gd`。
- [x] TASK-205 实现共享CombatState及有限快照/恢复、玩法时钟/身份冷却/效果结算，路径 `game/features/combat/combat_state.gd`。

**Checkpoint**: 纯配置、资格、共享计时接口实际可用，之后角色与菜单集成才进入。

## Phase 3: User Story 1 - 两种身份 (Priority: P1)

**Goal**: 两角色真实切换、盗窃怪币与自疗闭环。

**Independent Test**: 受伤切角无补给，盗窃怪币整数/余数实际结算，治疗与共享冷却跨切换/重载保持。

- [x] TASK-206 [US1] 实现两角色初始化/营地Ended原子切换与生命比例/资源截断，路径 `game/features/characters/character_roster.gd`。
- [x] TASK-207 [US1] 写并实现真实注册怪币5%与pending余数、失败/中断/重复提交守恒，路径 `game/features/expedition/expedition_state.gd`。
- [x] TASK-208 [US1] 集成疗愈者真实自疗与药包/口粮共享恢复限制、及时存档和效果反馈，路径 `game/presentation/game_session.gd`。
- [ ] TASK-209 [US1] 执行两角色真实PC输入与金币/失败/恢复对照，路径 `specs/003-character-builds/evidence/2026-10-13/characters.md`。

## Phase 4: User Story 2 - 天赋草稿与生效 (Priority: P1)

**Goal**: 共享总量、各自配置，草稿与生效分离。

**Independent Test**: 10点各角色10合法/11拒绝，编辑不变伤害与上限，100次属性往返守恒。

- [x] TASK-210 [P] [US2] 写预算/节点/草稿/深复制/生命比例/100次重算边界测试，路径 `game/tests/test_character_builds.gd`。
- [x] TASK-211 [US2] 落实九节点独立预算与有界属性重算、预览/确认重验事务，路径 `game/features/characters/build_evaluator.gd`。
- [x] TASK-212 [US2] 实现随时查看编辑、营地Ended应用与前后比较/拒绝原因，路径 `game/presentation/build_menu.gd`。

## Phase 5: User Story 3 - 预设、装配与引用 (Priority: P1)

**Goal**: 六槽保存独立，三选二技能有实际作用，引用失效可理解。

**Independent Test**: 六槽互不污染、冷却不随调槽刷新、材料消耗后陈旧配置拒绝且原装备经历保护。

- [x] TASK-213 [P] [US3] 写六槽/空槽/非法或陈旧引用/当前材料保护/多非活动引用测试，路径 `game/tests/test_build_presets.gd`。
- [x] TASK-214 [US3] 实现预设保存/载入草稿/完整应用及引用影响/失效显示数据，路径 `game/features/characters/character_roster.gd`。
- [x] TASK-215 [US3] 实现barrier真实受击吸收、focus真实武器增益和主/次通用槽调用，路径 `game/presentation/player_controller.gd`。
- [x] TASK-216 [US3] 实现新命名动作及schema1→2原子键位迁移/冲突/触控手柄意图测试，路径 `game/platform/input_bindings.gd`。
- [x] TASK-217 [US3] 集成六槽/技能选择/影响提示及真实滚轮/焦点/GUI消费回归，路径 `game/tests/test_build_session.gd`。

## Phase 6: User Story 4 - 阈值与恢复 (Priority: P2)

**Goal**: 两共鸣在真实阶段下生效，旧进度安全演进。

**Independent Test**: 阈值/阶段/装配条件前后对照；旧v2不增资源/装备、重复迁移一致、未来/非法拒绝保档。

- [x] TASK-218 [P] [US4] 写0/7/8分支点、weapon tier、skill stage、连锁上限及共鸣理由测试，路径 `game/tests/test_build_resonance.gd`。
- [x] TASK-219 [US4] 实现两共鸣并接实际锚点范围/屏障容量，路径 `game/features/characters/build_evaluator.gd`。
- [x] TASK-220 [P] [US4] 写旧v2真实副本/部分新域/未来域/坏槽/迁移幂等/共享冷却恢复测试，路径 `game/tests/test_build_migration.gd`。
- [ ] TASK-221 [US4] 实现纯领域迁移、完整候选预检/一次提交与退出重启恢复，路径 `game/persistence/build_migration.gd`。
- [ ] TASK-222 [P] [US4] 制作两角色原创代表样本与技能反馈、源/许可/实际游戏内审查，路径 `source-assets/blender/`。

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] TASK-223 执行严格全量非零回归、干净导入/发布资源/PC构建和可比性能采样，路径 `specs/003-character-builds/evidence/2026-10-13/regression-and-build.md`。
- [ ] TASK-224 取得并单独记录真人构筑体验、Android/手柄真实设备/角色视听验收，路径 `specs/003-character-builds/evidence/2026-10-13/device-and-human.md`。
- [ ] TASK-225 收敛独立审查与Spec Kit状态/变更，根安全Git交付并核对远端SHA，路径 `specs/003-character-builds/progress.md`。

## Dependencies & Execution Order

Setup201→配置202→基础203/204→共享状态205。US1依赖基础；US2预算/evaluator与US1角色状态集成；US3独立预设测试可与US2菜单并行、实现依赖角色域；US4共鸣依赖真实技能与派生属性，迁移测试可先独立准备，迁移实现等待schema冻结。实际依赖以`task-records.json`逐项图为准，无循环。

现有game_session/player/HUD/InputMap是共享热点，根专有集成；规则/持久化/资产代理按文件独占。不得标同一文件并行；当TASK-211与TASK-219修改evaluator时顺序执行。所有故事局部检查可独立执行，不用后继feature004给本功能制造假前置。

## Parallel Example: User Story 3

TASK-213预设边界suite与TASK-216输入迁移可独占不同文件并行；TASK-220旧档夹具与TASK-222原创样本也可并行。涉及全工程import、GodotMCP或运行输入由根协调，代理只执行独立headless报告，避免抢会话和覆盖证据。

## Implementation Strategy

先实现两身份/共享状态的小闭环并实际验证，再增天赋菜单、预设/三技能、共鸣及迁移；每个增量运行原规则回归，不把文件存在视为完成。技术测试与真实输入均满足后才勾相应任务；设备/真人缺事实保持TASK-224开放，同时继续能独立推进的后继内容。

## 本项目必填补充

每个TASK在[task-records.json](task-records.json)关联REQ/NFR、AC、路径、依赖、TEST、标准和状态。当前19/25任务通过各自独立技术门槛，其余6项保持开放；完整feature未验收；[validation.md](validation.md)中协议是计划，不是执行数量。禁止提前创建三阶/分支/珠宝占位模块或假玩法。
