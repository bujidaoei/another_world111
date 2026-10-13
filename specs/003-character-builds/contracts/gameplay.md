# 角色/构筑/共享战斗契约

本文件冻结拟实现API，尚无对应实现或测试通过声明。统一返回`{ok:bool,code:String,message:String,data:Dictionary}`；输入深复制，失败无副作用。规则RefCounted不访问Node、InputMap、AudioServer或文件；配置/存档适配负责IO。

## AWCharacterBuildsConfig

- `load_file(path:String="res://config/character_builds.json")->Dictionary`：严格有限schema及交叉引用校验，成功ready=true/data深复制。
- `validate(candidate:Dictionary)->Dictionary`：纯校验，未知字段/未来配置拒绝，不部分加载。

## AWBuildEvaluator

- `evaluate(build:Dictionary,progress:AWWorldProgress,inventory:AWInventoryLedger)->Dictionary`：结构、预算、技能阶段与实例校验后输出`{stats,active_resonances,inactive_resonance_reasons,spent_points,available_points}`。
- `validate_structure(build:Dictionary)->Dictionary`：用于可编辑但暂不合格草稿/非活动引用，不能替代evaluate。
- `reference_status(build,progress,inventory)->Dictionary`：可见缺装备/超点/技能未解锁等稳定reason code，不修改配置。

## AWCharacterRoster（constructor config/evaluator）

- `initialize(weapon_id:String,progress,inventory)->Dictionary`：只绑定一个实际已有合法装备，两档案深复制；不创建装备或奖励。
- `set_draft(character_id:String,build:Dictionary)->Dictionary`：任何场所可结构合法编辑；不修改生效配置和场景。
- `save_preset(character_id:String,slot:int,name:String)->Dictionary`：slot0..2，复制该角色draft；可保存暂不合格配置，但返回其资格原因。
- `load_preset_draft(character_id:String,slot:int)->Dictionary`：复制到draft，不应用；空槽返回preset_empty。
- `preview_apply(character_id:String,source:Dictionary,progress,inventory,context:Dictionary,vitals:Dictionary,combat_state:AWCombatState)->Dictionary`：context必须camp=true、encounter_ended=true、session_started=true；当前生命>0；完整预检，返回派生值/生命比例/体力截断/库存穿戴变化，仅读。
- `apply(character_id:String,source:Dictionary,progress,inventory,context:Dictionary,vitals:Dictionary,combat_state:AWCombatState,operation_id:String)->Dictionary`：重新预检、单次库存操作再提交roster，返回new_vitals/effective_build；共享combat_state不刷新。场景接收结果后才更新实体。
- `snapshot()->Dictionary`、`restore(candidate:Dictionary,progress,inventory)->Dictionary`：全域结构+当前活动配置资格校验，未来域拒绝；非活动失效引用保留并可见。失败原roster不变。
- `references_to(weapon_id:String)->Array[Dictionary]`：所有角色applied/draft/preset引用位置，供材料确认真实影响提示。

预设应用由load_preset_draft和apply组成，草稿变更不等于应用成功；UI不可在失败时替换实际武器。重复operation_id返回duplicate_operation。旧武器与新武器穿戴标记变化均经inventory.can_apply_operation/apply_operation一次提交；不覆盖history。

## AWCombatState（constructor config）

- `tick(delta:float,gameplay_running:bool)->Dictionary`：finite delta≥0；normal模式推进所有共享冷却及效果；其他状态无变化。
- `preview_cast(skill_id:String,context:Dictionary,vitals:Dictionary,derived_build:Dictionary)->Dictionary`：context含真实active_character_id、realm、loaded通用技能槽、gameplay_running；专属身份、阶段、存活、体力、冷却及恢复家族统一验证。
- `cast(skill_id:String,context:Dictionary,vitals:Dictionary,derived_build:Dictionary,operation_id:String)->Dictionary`：返回cost/new_vitals/effect_spec并提交共享冷却，拒绝/重复不扣体力；真实目标射线/碰撞/伤害由场景执行effect_spec，规则不伪击杀。
- `preview_recovery(kind:String,context:Dictionary,vitals:Dictionary)->Dictionary`与`commit_recovery(kind:String,context:Dictionary,vitals:Dictionary,operation_id:String)->Dictionary`：药包/口粮使用与self_heal相同恢复家族，确认重新校验存活/受伤/玩法状态及冷却；物品库存预检后与成功消耗和生命一起提交，失败不能先设冷却。
- `absorb_damage(post_defense_damage:float)->Dictionary`：有限非负，输出absorbed/health_damage并扣实际barrier_capacity；屏障过期不吸收，不产生治疗。
- `snapshot()->Dictionary`、`restore(candidate:Dictionary)->Dictionary`：按配置检查全部字段/有限值/状态配对，拒绝未来域，失败状态不变；不按墙钟减少剩余时间。

## 真实奖励接入

AWExpeditionState.begin追加冻结character_id与starting_coin_remainder（合法0..19）；record_kill仍先验证登记/重复/容量/XP事务，再按基础怪币更新pending奖励/余数。任务奖励入口不调用怪币修正。commit_rewards的完整预检包括库存与roster余数事务，成功同次确认；失败保留未提交状态供安全重试，不重复发XP或币。失败/中断丢pending余数，已入库值不变。

## BuildMigration与输入

`AWBuildMigration.migrate_payload(payload:Dictionary,config,evaluator)->Dictionary`是纯函数：返回规范化候选和migrated标志；不IO、不InputMap、不建场景、不grant/create_drop。先检查payload.domain_version：缺字段按旧1，1仅不含新域时迁移并升2；2按[data-model.md](../data-model.md)恰14字段与子schema配对验证；未来>2 return future_schema并阻写/保护标题。002旧程序须拒绝domain>1。当前活动装备资格优先，非活动陈旧引用保留，active_weapon_id与活动build.weapon_id必须一致。输入schema1→2纯normalize扩动作，原自定义physical keys保留；新增默认冲突用ADR-034固定候选，无法分配时拒绝。迁移两次结果一致。

InputAdapter旧pulse动作投递当前主通用槽，新skill_secondary投递第二槽，character_ability仅疗愈者投递self_heal；键鼠/触控/手柄共用动作，提示从真实bindings读取。不能用仅GUI禁用保护业务；所有入口必须走规则校验。

## 稳定错误语义

character_unknown / build_schema_invalid / talent_budget / talent_rank / skill_locked / skill_duplicate / exclusive_skill_forbidden / equipment_missing / realm_required / camp_required / encounter_active / actor_dead / cooldown_active / recovery_cooldown_active / insufficient_stamina / preset_empty / future_schema / duplicate_operation。UI显示中文原因与保留状态，不吞错误后回退默认配置。日志仅模块/操作/版本/code，不输出完整敏感存档。
