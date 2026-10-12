# Specification Quality Checklist: 阶段0研发入口

**Purpose**: 检查当前阶段规格质量，不证明游戏验收。
**Created**: 2026-10-13
**Feature**: [spec.md](../spec.md)
**Audience**: 制作/技术审阅者；下一阶段再评审未冻结规则。

## Content Quality

- [x] CHK001 当前阶段和未来内容是否明确区分？[Clarity, Spec §范围]
- [x] CHK002 原文规则和用户确认是否有依据？[Completeness, Spec §Clarifications]
- [x] CHK003 游戏需求是否聚焦玩家结果，架构留在计划？[Clarity, Spec §Requirements]
- [x] CHK004 方向明确时是否避免重复选题？[Consistency, Spec §Assumptions]

## Requirement Completeness

- [x] CHK005 阶级/品质、融合/扩槽/进阶、天赋/专属是否分别写明？[Completeness, REQ-007至018]
- [x] CHK006 等级门槛/经验、遭遇结束、切换保持规则是否定义？[Clarity, REQ-005/017/018]
- [x] CHK007 存档错误、拒绝操作和重复事务是否有AC？[Coverage, REQ-025, Edge Cases]
- [x] CHK008 单人全途径与合作个人资格是否保留？[Consistency, REQ-006/020/021]
- [x] CHK009 采集制作/设施和资源用途是否纳入？[Completeness, REQ-028]
- [x] CHK010 未冻结数值/失败/技能数量是否列决策门槛，未冒充全游戏可编码？[Clarity, Assumptions, D-002至006]

## Acceptance Criteria Quality

- [x] CHK011 REQ/NFR是否都有稳定AC及任务/验证关联？[Traceability, Spec §Success Criteria]
- [x] CHK012 环境调查与工具操作/构建是否区分？[Clarity, REQ-001]
- [x] CHK013 优于参考是否规定对照/动态/独立评审？[Measurability, REQ-027, research-design §7]
- [x] CHK014 帧预算建议与具名设备实测是否区分？[Measurability, NFR-002]
- [x] CHK015 真人观察与技术自测是否分开？[Coverage, NFR-003]

## Dependencies & Assumptions

- [x] CHK016 手机/手柄/预算/人力/日期与许可缺口是否保留？[Assumption, decisions]
- [x] CHK017 合作/账号/云存档/体量是否独立决策？[Consistency, REQ-020/021]
- [x] CHK018 安全认证、资产分发、固定版本是否约束？[Coverage, NFR-004/005]

## Notes

18项仅表示阶段0工件清晰/完整性审阅，不是18项游戏测试。
阶段1数值/失败/范围和设备门槛在tasks/decisions保持开放；本表不授权跳过。
