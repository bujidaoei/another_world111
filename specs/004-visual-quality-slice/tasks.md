# Tasks: 原创视觉品质样板

**Input**: 本feature spec/plan/research/data-model/contracts。所有任务当前未验收；真实证据全部满足才能勾选。每项协议和依赖详见task-records.json/validation.md。

## Phase 1: Setup

- [x] TASK-301 冻结用户原创画风优先级、参考证据与Spec Kit设计，路径 `specs/004-visual-quality-slice/spec.md`；只验收规划激活/独立审查门槛。

## Phase 2: Foundational

- [ ] TASK-302 建立原创维修雨庭视觉合同和首个样区，路径 `source-assets/quality-slice/art-direction.md`。
- [ ] TASK-303 定位并收敛原生渲染缺陷，路径 `source-assets/engine-native-runtime.md`。

## Phase 3: User Story 1 - 原创街区

- [ ] TASK-304 [US1] 制作原创PBR干湿材料代表样区，路径 `source-assets/quality-slice/materials/`。
- [ ] TASK-317 [US1] 执行单个材料铺装A的实际Main前置验收，只有源/技术/真实Main观察和采用结论满足才扩家族，路径 `game/presentation/world_builder.gd`。
- [ ] TASK-305 [US1] 制作原创破损维修铺装和排水家族，路径 `source-assets/quality-slice/scripts/environment_factory.py`。
- [ ] TASK-306 [US1] 制作两层雨水回收检修建筑代表，路径 `source-assets/quality-slice/scripts/environment_factory.py`。
- [ ] TASK-307 [US1] 将精修环境家族接入真实营地和雨庭，路径 `game/presentation/world_builder.gd`。
- [ ] TASK-311 [US1] 完成真实干湿光照雨水动态样板，路径 `game/presentation/world_builder.gd`。

## Phase 4: User Story 2 - 角色与反馈

- [ ] TASK-308 [US2] 制作两角色原创精修代表样本，路径 `source-assets/quality-slice/characters/`。
- [ ] TASK-309 [US2] 精修接地转向持枪自疗与受击动作，路径 `game/presentation/character_animator.gd`。
- [ ] TASK-310 [US2] 精修事件驱动能力与敌人反馈，路径 `game/presentation/game_session.gd`。

## Phase 5: User Story 3 - 完整游玩表现

- [ ] TASK-312 [US3] 精修游戏HUD与统一菜单表现，路径 `game/presentation/game_hud.gd`。
- [ ] TASK-313 [US3] 收敛严格回归及生产启动关闭故障，路径 `tools/export_game.ps1`。

## Phase 6: Polish

- [ ] TASK-314 执行可比画风完成度和生产性能评审，路径 `specs/004-visual-quality-slice/evidence/2026-10-13/quality-comparison.md`。
- [ ] TASK-315 取得独立设备真人与长期稳定性验收，路径 `specs/004-visual-quality-slice/evidence/2026-10-13/device-and-human.md`。
- [ ] TASK-316 收敛审查与规范证据并安全交付，路径 `specs/004-visual-quality-slice/progress.md`。

## Dependencies & Execution Order
301→302视觉合同→304单个材料/铺装A→317真实Main采用门槛→305/306家族生产；305/306顺序使用同Blender脚本（不标[P]）。307实际环境与308/309角色可分目录研究，Blender只有一个owner顺序操作。303原生诊断与资产制作独占文件可并行，但313集成必须待实际修复。310反馈需环境/动作，311光/雨接环境，312UI接合同；313统一→314通用分数及主要维度不低于参考/可比成本→316技术交付。315设备/真人/长稳独立，316技术checkpoint不代315。

## Parallel Example
原生diagnostic artifacts与材料DCC新源可独占并行；sharedMain/HUD/WorldBuilder由根持有，资产owner只输出接口与源。GPU烘焙/推理/性能采样协调，性能不与重负载并行。

## Implementation Strategy
先真实一个样区进入Main看过再扩家族，再完成整套可玩场景；任何技术通过不当最终画风通过。视觉门槛前保留后继玩法需求并后置实现。
