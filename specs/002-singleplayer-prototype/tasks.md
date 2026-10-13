# Tasks: 单人原型
**日期**2026-10-13；所有未真实验证的实现保持未完成；TEST为验证协议而非已执行数量。

## Setup

- [x] TASK-101 自主冻结规格与更新宪章/变更记录，路径 `../../specs/002-singleplayer-prototype/decisions.md`。
- [x] TASK-102 安装验证官方GodotAI release并接通正确工程，路径 `../../game/addons/godot_ai/`。
- [x] TASK-103 固定GdUnit4并验证非零/失败/空发现阻断wrapper，路径 `../../tools/run_gdunit.ps1`。

## US1

- [x] TASK-104 [US1] 规则测试与实现：XP/任务/遭遇/库存/负载/制作，路径 `../../game/features/expedition/`。
- [ ] TASK-107 [US1] 输入、玩家/敌人、镜头和UI/菜单实装，路径 `../../game/presentation/`。
- [ ] TASK-108 [US1] 集成真实远征/目标/采集/补给/营地设施/结算，路径 `../../game/presentation/game_session.gd`。

## US2

- [x] TASK-105 [US2] 装备预算/融合/扩槽/进阶实现与真实测试，路径 `../../game/features/equipment/`。
- [ ] TASK-109 [US2] 集成30级个人挑战、二阶区域/锚点/电枪进阶与培养UI，路径 `../../game/presentation/game_session.gd`。

## US3

- [ ] TASK-106 [US3] 双槽存档/设置实现与风险测试，路径 `../../game/persistence/`。
- [ ] TASK-110 [US3] BlenderMCP制作原创代表资产与GLB导入审查，路径 `../../source-assets/blender/`。
- [x] TASK-111 [US3] ComfyMCP本地合法图像生产/规范化与许可，路径 `../../source-assets/workflows/`。
- [ ] TASK-112 [US3] GodotMCP制作/修订材质、环境、粒子特效，路径 `../../game/presentation/main.tscn`。
- [ ] TASK-113 [US3] 原创音效、音乐/氛围与真实总线/设置集成，路径 `../../game/assets/audio/`。

## QA

- [ ] TASK-114 真实PC完整输入/成败/培养/晋阶/保存端到端验收，路径 `../../specs/002-singleplayer-prototype/evidence/`。
- [ ] TASK-115 PC导出构建、分位性能、静态资源与干净检出，路径 `../../game/export_presets.cfg`。
- [ ] TASK-116 独立审查、缺陷修复回归与Spec Kit状态/Git交付，路径 `../../specs/002-singleplayer-prototype/analysis.md`。

## 外部验收

- [ ] TASK-117 Android/手柄真实设备及真人原型体验，路径 `../../specs/002-singleplayer-prototype/evidence/`。

## 后续

- [ ] TASK-118 进入完整切片角色/天赋预设/三阶分支/共鸣/内容及合作评估，路径 `../../specs/001-project-foundation/tasks.md`。

## 验收与依赖

| TASK | REQ/NFR | AC | 依赖 | TEST/条件 | 状态 | 证据 |
| --- | --- | --- | --- | --- | --- | --- |
| TASK-101 | REQ-101, REQ-104, REQ-105, REQ-106, NFR-101 | AC-101, AC-104, AC-105, AC-106, AC-109 | 无 | TEST-101 文档一致、规则数字、接口及禁止假验收有完整记录 | 已验收（明确局部门槛） | [setup-and-core](evidence/2026-10-13/setup-and-core.md) |
| TASK-102 | REQ-108, NFR-101 | AC-108, AC-109 | TASK-101 | TEST-102 签名/hash/tree验证与MCP正确session | 已验收（明确局部门槛） | [setup-and-core](evidence/2026-10-13/setup-and-core.md) |
| TASK-103 | NFR-102 | AC-110 | TASK-101 | TEST-103 真实JUnit发现>0，预期失败/空发现退出非零 | 已验收（明确局部门槛） | [setup-and-core](evidence/2026-10-13/setup-and-core.md) |
| TASK-104 | REQ-104, REQ-105, NFR-101 | AC-104, AC-105, AC-109 | TASK-101, TASK-103 | TEST-104 真实规则边界、奖励/事务幂等、合法还原非零GdUnit | 已验收（明确局部门槛） | [setup-and-core](evidence/2026-10-13/setup-and-core.md) |
| TASK-105 | REQ-106, NFR-101 | AC-106, AC-109 | TASK-101, TASK-103 | TEST-105 预算/身份/特效/候选/槽/阶级/成本/重复事务通过 | 已验收（明确局部门槛） | [setup-and-core](evidence/2026-10-13/setup-and-core.md) |
| TASK-106 | REQ-107, NFR-101 | AC-107, AC-109 | TASK-101, TASK-103 | TEST-106 回读/损坏恢复/未来拒写/1MiB/连续与迁移真实测试，未能安全注入错误单列 | 进行中/未验收 | 尚无 |
| TASK-107 | REQ-101, REQ-102, REQ-103, NFR-101 | AC-101, AC-102, AC-103, AC-109 | TASK-104 | TEST-107 实际3D行走/命中/危险预备/操作/UI消费及菜单恢复 | 进行中/未验收 | 尚无 |
| TASK-108 | REQ-101, REQ-104, REQ-105 | AC-101, AC-104, AC-105 | TASK-104, TASK-106, TASK-107 | TEST-108 新档合法流程与失败/重试/保存恢复证据 | 进行中/未验收 | 尚无 |
| TASK-109 | REQ-103, REQ-104, REQ-106 | AC-103, AC-104, AC-106 | TASK-105, TASK-108 | TEST-109 真实奖励升30并挑战，三目标→锚点，融合预览成本/概率/锁定真实交互 | 进行中/未验收 | 尚无 |
| TASK-110 | REQ-108 | AC-108 | TASK-101 | TEST-110 源blend/script/GLB/mesh指标/原型审查，最终商业品质仍独立门槛 | 进行中/未验收 | 尚无 |
| TASK-111 | REQ-108 | AC-108 | TASK-101 | TEST-111 真实工作流/节点/来源/hash/输出和实际采用，不用未知授权资产发布 | 已验收（明确局部门槛） | [setup-and-core](evidence/2026-10-13/setup-and-core.md) |
| TASK-112 | REQ-103, REQ-108 | AC-103, AC-108 | TASK-102, TASK-107, TASK-110 | TEST-112 真实MCP场景/光/材质/雨粒子/命中效果及运行截图 | 进行中/未验收 | 尚无 |
| TASK-113 | REQ-101, REQ-108 | AC-101, AC-108 | TASK-107 | TEST-113 合成源/文件、总线独立音量/并发/循环/削波/事件时序，实际播放 | 进行中/未验收 | 尚无 |
| TASK-114 | REQ-101, REQ-102, REQ-103, REQ-104, REQ-105, REQ-106, REQ-107 | AC-101, AC-102, AC-103, AC-104, AC-105, AC-106, AC-107 | TASK-109, TASK-112, TASK-113 | TEST-114 合法新档真实完成，不用eval发经验/杀怪绕过流程；夹具局部对照分列 | 进行中/未验收 | 尚无 |
| TASK-115 | NFR-101, NFR-102 | AC-109, AC-110 | TASK-114 | TEST-115 运行构建/资源合法、测试非零、FPS分位/加载/内存与对应设备 | 进行中/未验收（冻结002 PC生产/Vulkan短期门禁通过；完整及长稳/设备证据未全） | [当前冻结生产/性能](evidence/2026-10-13/windows-current-performance.md)、[旧release测量失败](evidence/2026-10-13/performance-tooling.md)、[Android开发管线](evidence/2026-10-13/android-development-build.md) |
| TASK-116 | NFR-101, NFR-102 | AC-109, AC-110 | TASK-115 | TEST-116 严重问题关闭、实际证据匹配、远端SHA一致 | 进行中/未验收 | 尚无 |
| TASK-117 | REQ-102, NFR-102 | AC-102, AC-110 | TASK-114 | TEST-117 实际设备/参与者才验收；缺证据不暂停可独立完整制作 | 进行中/未验收（无手机运行证据） | [实际开发APK及未验边界](evidence/2026-10-13/android-development-build.md)、[小型审计JSON](evidence/2026-10-13/android-build-verification.json) |
| TASK-118 | REQ-104, REQ-106, NFR-102 | AC-104, AC-106, AC-110 | TASK-116 | TEST-118 另立完整产品功能规格，实际实现/验证，不以当前原型结束完整目标 | 进行中/未验收 | 尚无 |

## 并行与顺序
核心规则与存档分文件并行；root独占Godot，资产代理独占Blender/Comfy，网页共享前协调。
测试先于高风险实现；装备核心先于晋阶/培养表现；真实PC流程先技术验收；外部设备/真人未有不勾选。
商业最终资产和完整游戏目标不能由原型通过替代，TASK-118继续正式切片/内容工作。
