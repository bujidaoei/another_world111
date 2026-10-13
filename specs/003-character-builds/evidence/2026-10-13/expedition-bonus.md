# 注册怪物金币与结算边界

2026-10-13，TASK-207局部规则证据。实际实现`game/features/expedition/expedition_state.gd`与`game/tests/test_expedition_bonus.gd`。这些是明确的领域单元夹具，不作为实际PC输入游玩证据；TASK-209另行执行。

配置启用时begin冻结真实活动身份与已提交余数。record_kill只接受本次远征注册且未击杀的enemy_id，按对应敌人基础金币乘配置分子，再用整数除法/余数累积；目标、采集和挑战奖励不计盗窃收益。先检查货载和经验事务，成功才记事件和pending金币/余数。失败丢pending并还原本次起始余数，已提交余数和经验保留。成功Ended结算先验证Roster标量CAS及Inventory全部费用/上限/操作ID，再在无signal/callback/await的纯规则段共同提交。GameSession随后保存一个完整领域2载荷；未宣称跨线程事务或数据库ACID。

restore要求精确14字段，校验角色/余数，并根据已注册击杀、采集、目标、挑战与角色配置重算pending_loot及余数，不接受伪造金额。旧无角色配置的独立远征回归仍按基础规则运行；实际GameSession必须配置角色规则并传实际Roster。

真实业务失败1：`artifacts/expedition-bonus-red/d1e78e0d8ac54a309d350ea70eeb98b3/report_1/results.xml`，候选未知角色被原restore忽略，1案例1断言失败。真实业务失败2：`artifacts/expedition-bonus-boundaries-red/8b3d6c85192b47bf969eafcbb040e82f/report_1/results.xml`，伪造金币金额在余数一致时未被拒绝，9案例中1案例2断言失败。显式类型修复产生的中间解析失败不算业务red。

修复后`artifacts/expedition-bonus-boundaries-green/4691241f246c458897f62bc8402c4ede/report_1/results.xml`，9/9真实案例通过；旧基础远征suite `artifacts/expedition-existing-regression/5782494db4804a05b2e077e4577959f2/report_1/results.xml`，8/8通过。覆盖两次合法结算10次击杀累计额外1金币、失败/目标/疗愈者/守卫不冒领、重复事件、CAS变更、真实库存溢出和伪造restore。以上报告无原生/脚本ERROR，非零JUnit。全量整合与PC行为尚待后续证据。

后续只读交叉审查发现旧Ended远征快照与已入库库存跨代组合，疗愈者余数不变时可以换请求ID重复领2金币。新真实业务red `artifacts/expedition-canonical-business-red/report_1/results.xml`，10案例中1案例3断言失败，实际金币2→4。ADR-037改为自动稳定远征身份，并扩展InventoryLedger整批新装备预检和一次资源/装备提交，客户端提供Ended重试及放弃pending回营；放弃不补生命、不假标成功。

最新稳定green `artifacts/expedition-canonical-batch-stable/report_1/results.xml`：Bonus12/12、原远征8/8、装备10/10，联合30/30，0error/failure/skip/flaky/orphan、exit0，无原生/脚本ERROR。新增跨代重放拒绝、晚位非法/重复掉落全拒绝、库存溢出后同远征重试一次、两装备原经历及快照深复制。中间名为canonical-business-green的目录实际28案例有typed Array调用错误并失败，已保留，绝不作为green证据；具体失败原因已修为明确类型的领域接口和空列表。上述仍是单元边界，主场景与实际PC另列。
