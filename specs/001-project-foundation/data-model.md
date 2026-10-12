# 数据模型与不变量（拟实现，非已有代码）

依据[spec.md](spec.md)。字段具体序列化格式在阶段1冻结；本轮不创建空接口。核心规则不依赖场景、输入或显示。

| 实体 | 必要字段 | 关系与不变量 |
| --- | --- | --- |
| WorldProgress | world_id, level, realm, experience, banked_experience, earned_talent_points, ascension_records, region_unlocks, public_unlocks | 同一世界多个角色共享；level≤realm×30；挑战成功后才提升realm；点数总量不因角色数量改变 |
| CharacterProfile | character_id, identity, equipment_ids, skill_loadout, talent_draft, active_talents, presets[3], appearance_unlocks | 通用解锁引用WorldProgress；专属身份不可转移；每角色保存配置，不共享可变对象；按共享总量独立分配的解释D-005冻结后执行 |
| RuntimeVitals | health/current_max, resources/current_caps, cooldowns, recovery_family_cooldown | 应用配置/换角色保留生命比例、截断资源、持续冷却；同类恢复冷却防轮换绕过 |
| EquipmentInstance | instance_id, name, origin, tier, quality, slot_count, affixes, inherent_effect_id, branch_id, enhancement, history | 最多5普通词条；tier独立quality；融合身份/特效/分支/经历保持；培养资格检查个人realm |
| AffixDefinition | id, category, incompatibilities, tier_ranges, slot_limits, budget_cost, sampling_weight | 普通词条池不含固有效果/角色/分支；无重复/互斥；锁定同样计预算；版本可追溯 |
| EquipmentHistory | acquired_at/location/level, ascension_events, first_six_chain_event, branch_events/current | 只由实际事件生成；原始获得信息只写一次；材料装备经历不转移；未发生六连锁不填假事件 |
| Encounter | encounter_id, state, seed, objective, participants, reward_commit_id, reset_complete | Dormant→Active→Victory/Failure/EvacuationPending→Ended；撤离完成重置才结束；AggroLost仍Active |
| Inventory | item_instances, material_quantities, currency, capacity | 数量非负、实例ID唯一；装备自融合拒绝；装备材料是否被穿戴的处理需冻结明确提示 |
| EquipmentOperation | operation_id, kind, primary_id, material_id, locked_affix_ids, rules_version, seed, cost, outcome | Validate→Preview→Confirm→Committed/Rejected；合法完整结果算出后一次性提交；重复operation_id不再扣费 |
| BuildPreset | talent_allocation, skills, equipment_branch_choice, validation_version | 3套每角色；可编辑，应用检查camp+encounter_ended和当前资格；失效引用不能半应用 |
| SaveEnvelope | schema_version, build_version, sequence, payload, checksum, written_at | 槽位回读验证后报告成功；checksum检测损坏不是防篡改密钥；未知未来版本拒绝覆盖 |
| AssetRecord | asset_id, origin, source_path, adopted_output, tool/model/workflow_versions, parameters/seed, license/source/author, distribution_rights | 原创与第三方/AI分别标明；商用与源分发都明确；参考截图没有游戏资产资格 |

## 融合、扩槽和奖励合法性

融合先核对不同实例、阶级/品质/部位/武器类型、最多2锁、camp与遭遇结束、全成本；
从双方普通词条来源构造合格候选，再按唯一性、互斥、单条上限和剩余预算形成条件抽取空间。
预览展示全部成本与抽取条件/概率，不能只展示原始权重造成误解。候选不足不自造池外词条；D-003冻结处理。
扩槽保留旧词条，新增合法一条；新预算需为任意合法4槽输入保证或明确拒绝，不能悄悄削弱旧词条。
进阶保留instance_id/quality/slot_count/history，按新阶配置换算普通词条和特效；换算方式D-003冻结。
奖励输入包含地图类型池、个人realm/level和结算ID；地图不授权超个人境界奖励。
合作权威/适配数据等另行定义；此处不建立未实现网络协议。

## 存档与状态

只持久化必要进度/设置，不保存场景Node引用。是否保存遭遇中途状态需D-004明确；安全检查点需定义最大损失。
旧版本迁移写新槽，失败保留原文件和内存有效状态；全部槽无效只提供明确新开/备份恢复选择，不能自动新档。
暂停、失焦和Android后台触发策略统一由应用状态管理；冷却以实际玩法时间定义，恢复后不凭墙钟赠送资源。
正式格式与迁移夹具在实现前写入独立存档规格，未实现不能靠本表声明可恢复。
