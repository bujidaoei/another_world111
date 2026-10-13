# 数据模型与不变量

本文记录当前已实施的数据格式与不变量；实现/局部测试/完整验收状态分别由tasks与progress中的实际证据追踪。后继系统不在此创建空接口。

## CharacterBuildsConfig（配置版本1）

完整声明characters、talents、skills、resonances、recovery、limits。仅thief/healer；九注册节点的分支、rank_limit8、cost1、效果和上限；技能pulse/barrier/focus/self_heal的阶段、成本、冷却、作用；两个注册共鸣的全部阈值条件。未知字段/ID、NaN/Infinity/布尔数值、非法阶段/节点、缺失字段、跨引用/上限错配应启动失败。配置不可声明feature004未实现技能。

## CharacterBuild

`{talents: {九node_id: int0..8}, skill_loadout: [skill_id, skill_id], weapon_id: String}`。

talents字段完整、不重复，skill_loadout恰2且不同，只可含三通用技能；weapon_id非空长度≤128。草稿/预设只要求结构合法，可超当前总量、引用已被消耗实例或尚未解锁技能；qualification派生显示原因。已生效的活动角色必须预算≤world.earned_talent_points、技能已解锁、武器存在且tier≤realm。专属self_heal不进入该数组。

## CharacterProfile

`{character_id, applied_build, draft, presets:[PresetSlot×3]}`；恰两个注册身份，各自保存深复制内容。`PresetSlot={name, build}`，已保存时name长度1..24且build为CharacterBuild；未保存时name=""且build=null，是真实空槽状态，不伪造装备。

当前角色ID是活动主体；非活动applied_build允许因材料消耗而变成资格失效，恢复时保留并显示、切换时拒绝。所有档案结构仍必须校验；不能只校验当前角色而放任未知身份/非法节点。

## CharacterRosterSnapshot（domain schema1）

`{schema_version:1, active_character_id, profiles:{thief:profile,healer:profile}, thief_coin_remainder:0..19}`。

世界等级/境界/总点数/库存仍在既有域，禁止复制进两角色后分别增长。预设、草稿、生效配置互不共享可变Dictionary/Array。两角色可引用同一item，仅当前活动武器标equipped；应用更新穿戴标记但不改实例ID、品质、词条、历史。迁移穿戴标记是导出状态规范化，资源、装备数、原始经历与成长记录保持。

## EncounterBonusContext（运行时，不直接作为成功入库状态保存）

`{run_id, character_id, starting_remainder, pending_remainder, applied_enemy_ids}`；远征开始冻结身份和余数。每个真实已登记敌人只进入一次；`extra_gold=(pending_remainder+base_monster_gold)/20`整数取商；pending余数取模。任务/制作/物品/无怪币守卫不进该函数。

结算预检通过后与库存战利品一起提交到roster.thief_coin_remainder；失败/活动档回营恢复丢弃pending，原已入库余数保留。commit前不改roster已入库字段。XP仍由既有真实事件即时增长，不被该奖励修正重新发放。

稳定库存操作身份为`expedition-settlement:<run_id>`，资源与所有新装备共用一次InventoryLedger事务，再提交预检后的余数CAS。Ended容量/装备错误保持原域供重试；同远征跨代旧快照重放由稳定身份拒绝。放弃pending可回营而不补生命，不能伪标rewards_committed成功。

## CombatStateSnapshot（domain schema1）

`{schema_version:1, cooldowns:{attack,dodge,pulse,anchor,barrier,focus,self_heal,recovery_family}, effects:{barrier_remaining,barrier_capacity,focus_remaining}}`；每值为有限非负秒/容量且不超过配置实际合法最大值。冷却按skill ID唯一，不按角色/槽位复制。屏障剩余时间0时容量必须0；focus时间0时无效果，推导buff不另存百分比。

生命/体力沿用payload.health/stamina，当前最大值由基础、装备、天赋推导，禁止另一个含冲突生命的角色字段。共享持续状态按实际施放结果和剩余值保持；停止/卸装/调槽不重设；死亡移除增益，保留已用技能及恢复冷却。

tick(delta,gameplay_running)只在正常玩法时间推进；pause/focus-out/title/offline不推进。秒数不能通过wall-clock减少。保存同时包括最新生命/消费/冷却/效果，同一恢复事件不能出现只存回血不存冷却的半快照。

## DerivedBuild与资格

DerivedBuild输出stats、active_resonances及inactive_reasons；不作为存档真值。9天赋从基础重算，装备词条与百分比同类相加后限幅；世代更新不把上次派生值当新基础。每个共鸣同时校验branch_points、weapon_tier、required_skill_stage/loadout，0/7/8边界有明确结果。

## 应用与恢复事务

DraftEdited只替换目标draft；PresetSaved只替换目标slot。Apply或Switch：完整资格/营地Ended/当前存活校验 → 准备标记/派生vitals → 库存操作预检 → 一次库存事务及纯状态赋值 → 场景事件。预览之后的库存/世界变化需要确认重新校验。任何拒绝不更改生效态、金币余数、资源或冷却。

生命变更：new_hp=old_hp/old_max×new_max，old_max>0，old_hp∈[0,old_max]；stamina=min(old_stamina,new_max_stamina)，不向上补。0生命禁止合法角色应用，不以1生命fallback复活。增益保持实际剩余值，资源不会因配装产生。

旧v2领域迁移需先校验world/inventory/当前武器/生命与设置，再构建两档案各自deep copy、零点、pulse+barrier两槽、三未保存槽；复用active_weapon_id，绝不调用create_drop/grant。迁移幂等、IO与InputMap提交在候选整体通过之后。

## GamePayload领域版本与严格配对

payload.domain_version=2；类型须有限正整数，bool/小数/字符串/null拒绝。prototype写1，缺该字段按旧1，future>2返回future_schema并阻写/禁止标题新档覆盖。

domain1允许规范的既有11字段及domain_version，不得出现character_builds或combat_state；只缺全新系统才迁移，不把域2部分坏数据补默认。domain2恰14字段：domain_version、world、inventory、active_weapon_id、run_counter、operation_counter、bench_built、health、stamina、settings、input_bindings、interrupted_expedition、character_builds、combat_state；缺少/未知顶层字段拒绝，两个内部域要求schema1，input_bindings要求迁移后schema2。

兼容顶层active_weapon_id须与活动profile.applied_build.weapon_id相同，否则拒绝两种权威冲突。当前装备穿戴标记由唯一活动引用规范化；不改原ID、数量、资源、首次获得或进阶经历。002客户端只接受domain≤1、不能自动读取新域后写回，这个前置保护需要独立真实测试。

保存候选合法不代表有权替换已有数据；进程内mutex下扫描全部有效代次并逐一执行纯领域守卫，旧/未来/非法候选拒绝时不写tmp或槽。Main偏好dirty仅回读验证成功清除；失败保存的退出/标题转换保持内存会话，重试/取消/明确放弃退出分别作为真实用户意图，不能把恢复失败当作正常退出成功。多外部进程同时写入不在现有进程内互斥承诺内。
