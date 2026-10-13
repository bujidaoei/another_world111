# 003 持久化、交易与退出审查

2026-10-13，persistence_testing代理。先只读检查当前Spec Kit宪章、003规格/方案/任务/进度及15个生产模块，不运行Godot/MCP/GPU、不修改产品代码；发现两条静态保护范围后，根明确授权实施仓储/偏好前向守卫，退出失败流程由根及独立session persistence测试owner负责。本文区分原审查结论、已完成的局部修复和仍待验的门槛，不是游戏完整验收。

## 交易与恢复结论

- Roster.apply完整预览后先预检库存操作ID与装备标记，再无await/signal/callback地提交库存和生效构筑。当前源的Progress/Inventory/Expedition/Roster/Combat纯规则段无用户回调，标量CAS不会在这段主线程执行中被其他规则插入改变；这不承诺数据库ACID、外部多进程或未来加入回调后的安全。
- Expedition.commit_rewards采用`expedition-settlement:<run_id>`，资源和全部新装备同一库存事务预检/提交，再提交共享余数；不能用外部新请求ID重放旧Ended状态。restore按真实注册击杀、节点、目标、挑战和身份重算余数/战利品，不接受只配对余数的伪造币值。根已有canonical/batch业务red→green，详见expedition-bonus.md；本次审查没有重新执行这些测试或给重叠案例加总。
- Main的Ended重试不再次resolve/reset；容量不足时保留pending，成功才一起资源/装备/余数入库。放弃会新建DORMANT远征并按discarded回营，不借此触发35%失败补血；run_counter仍保留，稳定结算ID存入库存journal。中断远征载荷只保存已入库资源及既有即时世界经验，不复原pending货物/掉落。
- Main消费先校验Combat恢复ID/CD和Inventory费用，再无回调/await提交库存、共享恢复CD和健康；重复ID不能先扣物品再发现CD重复。守卫适用单一主线程当前源码；若未来引入线程或通知，必须重新审查提交边界。
- BuildMigration是无IO/InputMap的完整候选边界，envelope2/domain2/角色schema1/Combat schema1/输入schema2分别处理；未来大JSON安全整数、未知/缺字段、非法vitals或生效装备拒绝，inactive陈旧引用保留可见。realm1不能恢复focus CD/效果或anchor CD，realm2合法卸技能/换枪仍保留持续共享状态。
- `_restore_payload`先校验/恢复全部候选，再应用已验证InputMap并替换live引用；没有在前半候选失败时修改玩家资源。HP0纯迁移保持0，标题读取不补血；继续显式按ADR-036恢复35%、清buff/pending、保CD和已入库进度。场景/视觉失败走fatal并停止写档，不把旧槽清成新档。
- 仓储SHA256用于检出损坏，未作为离线反作弊认证；1MiB/深度/值数量/finite安全边界、双槽回读和元数据诊断仍保留。生产领域目录扫描未找到硬编码服务URL或credential关键词；这只是指定源码的静态检查，不代表所有部署环境或第三方包审计。

## 审查发现及处理

| 发现 | 原始控制流与范围 | 当前证据/剩余工作 |
| --- | --- | --- |
| F-01 前向领域保护只在启动/载入时生效 | 原Main._save_progress只检查新内存候选，原Repository只识别envelope未来版本；已启动会话目录随后出现envelope2/domain3时，旧客户端可能继续保存domain2。Prefs原先独立load→validate→save也只检查最新payload，旧有效future键位槽会漏检。 | 根已授权下述锁内全部有效槽守卫；库/Prefs真实文件red→green已通过。Main绑定与已启动会话真实未来域测试由根/独立owner完成，不能用库81例代其测试。 |
| F-02 保存失败仍继续退出/偏好dirty提前清除 | 原`_save_progress`返回void，失败只通知/日志；原`_request_quit`无法判保存结果，仍等0.2s后quit。原`_save_preferences`先清dirty，失败后最新偏好可能不再被退出重试。 | 已向根给出真实隔离故障方案：在inactive槽.tmp建空目录导致真实FileAccess失败，验证原槽/dirty/继续运行，再移除目录真实重试。根实施结构化保存结果、retry/保留dirty；独立owner负责生产Main关闭路径子进程测试。此文写入时未接到其最终green/真实窗口退出结果，不关闭该门槛。 |

审查前关键源码：Main SHA256 `FCBEE72E7A4087D2B31D569F3E51F3B8C082FF89D7BB4F4F797594D9C664A73C`；Repository `E41CF945B27DFC1FD029C397390F3B42C359A9DBE9ABBD404FE8A01F49F647F0`；Prefs `65F732732A20B725218F7639A312813B3C4B87AC0D6B8E88F1417776E03D4143`。这些是发现时点，不能冒充后续根修改后的当前源码hash。

## 锁内前向守卫交付

`SaveRepository.save(payload, existing_validator:Callable=Callable())`在现有进程Mutex内扫描两个槽，得到全部已验证valid_slots，随后逐一用deep-copy payload执行标准{ok,code,message}纯同步守卫。失败原code返回；无效守卫返回existing_validator_invalid；这些分支不建/改tmp、槽或序号。已有临时文件也保持原字节。无guard保留通用JSON仓储API；envelope未来版本和全坏槽仍由原逻辑拒绝。纯守卫不得IO、await、发信号或重入仓储，否则超出契约。

Prefs.save直接把现有_validate_payload传给仓储，删除独立load→save窗口，并验证较旧有效future/非法键位槽。库不硬编码游戏领域版本；Main以纯migrate guard判断future，仅按自身业务策略阻写。所有进程内仓储实例仍共用同一mutex；没有声称多个外部进程同时读写同一路径安全。

真实red：`artifacts/persistence-forward-guard-business-red/report_1/results.xml`，Prefs17例中2个失败案例/6失败断言，0errors、exit100。用正常Repository API真实写入较旧future输入schema3或键冲突槽，再写入较新支持槽，原Prefs.save实际覆盖旧槽。不是API缺失、parse错误、mock IO或伪造执行结果。

修复首轮：Repo24+Prefs17=41例、exit0。关联回归：`artifacts/persistence-forward-guard-local-regression/report_1/results.xml`，五套81/81（Repo24/Prefs17/Migration11/Combat13/Input16），0failure/error/skip/flaky/orphan、无原生/脚本ERROR、exit0。报告均在user://tests新建独立目录，真实双槽字节/临时文件/回读/InputMap对照；坏checksum仍正常恢复，非法守卫响应拒写，guard clone变异不污染新候选。后两项是仓储API防御性测试，不另说成业务red。最小JUnit在本目录保存。

已稳定交付源码SHA256：

| 文件 | SHA256 |
| --- | --- |
| game/persistence/save_repository.gd | 2B2779AA879D0E8C86007BBA1DD0F1FA964440A283B19A613B2BFA34C2AFF626 |
| game/persistence/user_preferences.gd | 3F9A5CE5311BA2A635DDF138279289148CC3C47FC69AEA508F3D5051C6D7B2D5 |
| game/tests/test_save_repository.gd | 1252ECF4AC17A7D9468203CAB2B2E1305935A3854070A53CCA51E0144785DE32 |
| game/tests/test_user_preferences.gd | 34F500BED0E049AB2F3DB943D345724B71F8383175E28BDBA04EA4C17BD339C1 |

## 验收边界

81、历史55/53、核心/主场景/canonical报告相交，不累加成全量；根全量严格JUnit需独立报告。driver另有24条比较器断言，仅证明JSON numeric/schema/finite/1e-9错误分类及实际游戏秒预期计算；不计入GdUnit或PC流程数量。fresh-editor-run1已真实观察两thief/GUI healer/talent/3命名preset/伤害T/暂停冻结，原始title_observe错误报告保留；观察器修复后完整continue/跨进程/死亡流程仍需根实际证据。

原生cpp759错误在新Editor冷启动仍出现，不能归因旧heap而关闭；002旧生产零错误不代表003当前渲染。当前源的生产重导、完整PC窗口玩法/退出、性能、真实Android/手柄/真人和商业品质仍各自待验。代理未改共享任务勾选，未宣称003或完整游戏验收完成。
