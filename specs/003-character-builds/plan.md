# Implementation Plan: 角色、天赋与流派预设

**Branch**: `codex/003-character-builds`（已实际激活） | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

**Input**: `specs/003-character-builds/spec.md`；源码已进入实施，本文是方案，实际结果由task-records与evidence记录。

## Summary

在已存在单人核心上新增独立角色/构筑域及共享战斗状态。完整校验候选后同步库存穿戴标记、生效构筑、推导属性和生命/体力；编辑不触碰生效态。角色金币只作用真实怪物事件并与战利品共同提交，旧存档领域迁移不重建库存。两个角色与三选二通用技能先闭环，再落实两共鸣和完整恢复/输入验收。

## Technical Context

**Language/Version**: 既有Godot4.7.2.stable / 类型明确GDScript，沿用阶段002锁定版本。

**Primary Dependencies**: 既有GdUnit4 6.2.2、GodotAI4.3.0、BlenderMCP/本地ComfyMCP/Playwright；不升级引擎或增加云服务。

**Storage**: 原SaveRepository v2双有效槽，1MiB与原校验不变；payload.domain_version从1升2，内部character_builds/combat_state各schema1，独立preferences沿用。输入绑定扩至schema2并有旧schema1纯迁移。

**Testing**: GdUnit纯规则/真实InputMap/主场景/持久化；独立测试user目录；真实PC输入流程及后接设备/真人门槛。

**Target Platform**: 当前Windows优先，Android接入后实测；手柄无硬件证据不称通过。

**Project Type**: 原生离线3D动作RPG，只有一活动角色；无账号/后端/网络。

**Performance Goals**: 沿用具名PC1080p60实验预算；本阶段构筑预览一次性推导，禁止逐帧枚举预设或读存档；新增技能在可比场景记录帧时增量。

**Constraints**: 纯规则无Node/Input/GPU，快照深复制，有限节点/槽位/字段，未知字段/未来域拒绝，不注入假奖励。

**Scale/Scope**: 两角色、各3预设、9天赋节点、两通用槽、3通用技能、1专属自疗、2一至二阶共鸣。

## Constitution Check

研究前：用户已授权自主决策；范围与完整后继明确；无设备/付费/真人推断。设计后：领域配置集中，规则与适配分离；测试协议与真实执行状态分开；双槽及历史保护沿用；资产原源与实际游戏内门槛独立。实施期遵守相同边界，未发现需要例外的宪章冲突。

Spec Kit templates已读。根已切换真实分支与feature.json，运行setup-plan、完整填入收敛计划、setup-tasks与RequireTasks/IncludeTasks的check-prerequisites；所有路径返回003正确目录，AGENTS已更新。正式脚本证据见evidence/2026-10-13/activation.md。

## Project Structure

### Documentation (this feature)

```text
specs/003-character-builds/
  spec.md plan.md research.md decisions.md data-model.md quickstart.md
  contracts/gameplay.md tasks.md task-records.json validation.md
  checklists/requirements.md analysis.md progress.md
  evidence/2026-10-13/                 # 只写实际发生证据
```

### Source Code (repository root)

```text
game/config/character_builds.json             # 已实现角色/天赋/技能/共鸣配置
game/config/character_builds_config.gd        # 已实现有限schema与交叉校验
game/features/characters/character_roster.gd # 已实现草稿/预设/两阶段应用
game/features/characters/build_evaluator.gd  # 已实现资格/推导属性/共鸣
game/features/combat/combat_state.gd         # 已实现共享cooldown/状态/恢复
game/features/expedition/expedition_state.gd # 已有，追加真实怪币pending余数
game/persistence/build_migration.gd          # 已实现领域迁移，原envelope不变
game/platform/input_bindings.gd              # 已有，schema2+纯旧版迁移
game/platform/input_adapter.gd               # 已有，追加两命名意图
game/presentation/build_menu.gd              # 已实现查看/草稿/应用/预设UI
game/presentation/game_session.gd            # 已有，协调真实输入/提交/保存
game/presentation/player_controller.gd       # 已有，推导属性和屏障命中
game/tests/test_character_builds.gd           # 已实现规则边界
game/tests/test_combat_state.gd               # 已实现共享冷却/真实计算
game/tests/test_build_migration.gd            # 已实现旧档/未来/拒绝
game/tests/test_build_session.gd              # 实际真实GUI/主场景集成
source-assets/blender/                       # 已有，角色形象实际源
```

**Structure Decision**: 每模块为当前职责服务；不提前创建三阶/珠宝类，也不新增无实现抽象后端。规则变更集中到character_builds配置，原rules/presentation保持既有一至二阶语义。

## 实施与集成

Phase0完成来源/数值/时钟/迁移研究，见[research.md](research.md)。Phase1冻结[data-model.md](data-model.md)与[contracts/gameplay.md](contracts/gameplay.md)。Phase2由[tasks.md](tasks.md)安排先危险测试、规则、迁移，再UI/输入/真实能力和验收。

预设应用：检查session开始、camp、Ended、存活、角色ID/点数/技能阶段/真实weapon → 生成库存穿戴更新与推导属性/vitals → inventory.can_apply_operation → 一次inventory.apply_operation → 纯赋值提交roster/vitals → 事件更新场景/HUD并保存。确认需重新预检，不能复用陈旧preview；任意前置失败不变更计数/资源/效果。

恢复：原envelope读取 → payload.domain_version门槛（缺字段按1，future阻写）→ 纯领域迁移 → 候选world/inventory/全部profile结构/runtime/input/settings校验 → 当前live build资格与vitals范围校验 → 一次替换 → 重建场景并应用派生值。非活动丢失装备引用仅作为失效配置保留，当前live缺武器必须失败。未来域或部分域不能当旧版补默认。002旧客户端须先落地domain_version>1拒读/阻写及标题新档不覆盖未来域的保护，才有新域可安全演进。

CR-003-03：保存也需在SaveRepository现有process mutex内逐一纯校验两个有效槽，不能只验证内存候选或最新槽。Main与Prefs都绑定真实领域守卫；拒绝不写tmp/槽。Main保存返回Result，dirty只有成功才清除；错误暂停自动偏好重试直到新编辑或明确重试，退出/标题转换失败保留内存会话。错误菜单支持重试/取消，退出另提供明确放弃；取消恢复进入前菜单、暂停和可见性状态。真实IO错误以隔离tmp空目录阻断验证，实际quit于独立headless子进程验证，脚本/未知Native错误仍是失败。现有互斥保证限于同进程，不虚称跨进程并发安全。

冷却/增益由AWCombatState唯一拥有：场景只投递实际命中/施放意图、调用tick，不各角色另起Timer。tick使用受暂停定义约束的玩法delta；保存剩余秒，重启不使用墙钟衰减。技能和恢复成功及时checkpoint，同次快照含消费/生命/冷却；突然强制结束的最后周期损失仍按002明确限额记录，不伪零损失。

盗窃奖励：远征开始冻结活动身份和已入库余数；每个合法真实kill以基础怪币整除20计算pending bonus，XP仍沿002即时；目标币不送入bonus计算；rewards commit预检库存后一次提交金币与余数。失败/中断保留已入库余数，丢pending；禁止先加币再做XP/容量验证。

## 风险与质量门槛

R201旧输入默认冲突、R202恢复计时复用、R203多引用材料、R204最大值重算漂移、R205效果切换/重启复制、R206旧档部分字段误迁移均有[validation.md](validation.md)协议。制作数值暂非真人平衡结论。GodotMCP由根持有，原创资产代理使用Blender/Comfy，网页来源走Playwright并记录；GdUnit和导出沿既有严格工具链。Android/手柄/真人/最终商业品质未有事实不勾选。

## Complexity Tracking

当前没有宪章例外；共享CombatState是避免多角色计时和保存来源分裂的必要模块，有限配置与纯领域迁移是明确版本演进，不是一次性兼容补丁。
