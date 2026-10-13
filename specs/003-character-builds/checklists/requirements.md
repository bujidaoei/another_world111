# Specification Quality Checklist: 角色、天赋与流派预设

**Purpose**: 检查需求和计划的完整性，不能替代实现测试。

**Created**: 2026-10-13

**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] CHK001 规格聚焦玩家选择/收益/恢复，工程细节放plan/contracts。
- [x] CHK002 场景、需求、实体、成功条件与假设全部具体。
- [x] CHK003 完整目标与本阶段边界分明，三阶/分支/珠宝没有空实现承诺。

## Requirement Completeness

- [x] CHK004 共享总量、每角色独立预算和切换不发点无歧义。
- [x] CHK005 两身份、5%整数余数/任务排除、失败/中断共同结算有规则。
- [x] CHK006 三预设、两技能槽、专属身份、失效引用与当期装备保护有明确结果。
- [x] CHK007 最大生命比例、体力截断、恢复家族/技能身份冷却、效果与离线定义完整。
- [x] CHK008 共鸣点数+武器/技能门槛、连锁上限与高阶后继明确。
- [x] CHK009 envelope v2/domain1→2、旧客户端拒未来域、部分域/未来子schema/非法type/自定义键冲突迁移计划不补资源或覆盖唯一有效档。
- [x] CHK010 每REQ/NFR均有AC、TASK、TEST关联，异常/失败路径可验证。

## Feature Readiness

- [x] CHK011 所有新代码路径明确为拟建，任务目前未验收。
- [x] CHK012 单元fixture、原生PC、设备、真人与商业品质是不同门槛。
- [x] CHK013 当前范围不需要未批准付费服务、用户回答或虚构人力/期限。

## Notes

勾选只表示对应需求描述已具备，绝不表示游戏能力已实现或测试通过。结构脚本与只读语义分析的实际执行结果见[analysis.md](../analysis.md)；后续实现/验收遵循[tasks.md](../tasks.md)。
