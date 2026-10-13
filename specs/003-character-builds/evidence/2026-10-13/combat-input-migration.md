# TEST-204/208/209：共享战斗、纯领域及输入迁移

2026-10-13。使用已读save-systems、input-systems、godot-gdscript及既有GdUnit4/headless-testing工作流；代理不操作live GodotMCP、不改根场景/UI/实体。固定Godot4.7.2.stable.official.ed1daf0bf、GdUnit4 6.2.2。

最新持久化前向守卫关联回归为五套81例：24 SaveRepository、17 UserPreferences、11 BuildMigration、13 Combat、16 InputBindings；0失败/error/flaky/skip/orphan、exit0，实际报告 `artifacts/persistence-forward-guard-local-regression/report_1/results.xml`。这是非零局部CLI，不冒充整工程严格import、GUI真实输入、安卓/物理手柄、真人或商业品质。

历史报告保持原样：跨realm守卫完成时四套55例（13 Combat、11 BuildMigration、16 InputBindings、15 UserPreferences），`artifacts/character-builds-realm-state-green55/report_1/results.xml`与本目录persistence-local-realm-55.xml，全部通过；再前一轮四套53例（BuildMigration为9例，其余相同），`artifacts/character-builds-persistence-53/report_1/results.xml`与persistence-local-53.xml。53尚未覆盖后来发现的realm1恢复高阶CD/buff漏洞，不能用历史green代替新回归。报告有大量重叠，81、55、53不相加。

## 实现接口

`AWCombatState.new(config)` 仅读validated config及presentation_data快照。tick只推进gameplay seconds；attack/dodge/anchor/pulse/barrier/focus/self_heal按统一ID冷却，recovery_family与自疗共20秒。正常未暂停营地推进；暂停/失焦/标题/离线不推进。clear_effects死亡只清buff、冷却保留。cooldown_remaining/weapon_damage_multiplier只读；attack effect_spec.damage已含当前focus，不重复乘；pulse只用中央技能伤害/天赋。实际空间命中/伤害/库存仍由根协调。

preview_cast/cast(context,vitals,derived_build)按真实角色/realm/skill_loadout/gameplay_running及严格四vitals校验；anchor另外检查context.weapon_tier=2。cast先全预检、再一次CD/effect/operation提交，返回data含new_vitals/cost/cooldown/effect_spec。self_heal确扣35体力、恢复上限30%且clamp至满，不允许满血/死者/错误身份/不足/暂停。通用haste不作用自疗/恢复家族。

preview_recovery/can_commit_recovery/commit_recovery只验证物品类型、受伤存活、玩法/CD和重复operation；返回cost:{kind:1}、不变new_vitals及family cooldown。根在库存一次消费之前用can_commit_recovery检查ID，再依rules.data.camp唯一真实恢复量同步提交健康/CD并保存，模块不复制medkit/rations恢复常量。恢复预览不预扣冷却，确认重新检查，操作日志100000容量上限可诊断；跨重启的完整重复消费还需既有库存operation记录和根保存operation_counter。

snapshot恰schema_version1、8个cooldowns、3个effects，全String键。restore有限范围且完整配对：屏障过期容量0、effect remaining≤对应CD、自疗CD≤family CD。没有墙钟字段或角色独立CD；深复制失败原状态不变。focus固定4秒/15%，屏障3秒/24容量与合法共鸣倍率按实际吸收扣减。

`AWInputBindings` 现schema2，14旧动作+skill_secondary/character_ability；pulse仍主通用槽，新增默认X/T。static normalize_snapshot无IO/InputMap、实例validate/normalize仅读；原schema1自定义全保留，默认冲突按固定I/J/K/L选未占用项，无可选项明确binding_migration_conflict、不抢键。未来schema明确future_schema，包含2147483647大版本。apply先准备全部合法事件再替换键盘映射，保留mouse/gamepad/unrelated UI动作。

InputAdapter键鼠/触控/pad命名意图共用，新增DPAD_RIGHT/UP为独立edge，不需组合按键。echo/释放不会重发，blocked只允许正常暂停，失焦/重映射清held。测试使用真实InputEventKey/InputEventJoypadButton匹配和适配器入口；这是合成事件证据，不是硬件插入证据。AWUserPreferences加载旧global prefs规范schema2/migrated=true但不写文件、不apply；显式save才双槽升级，坏/未来/迁移冲突原文件保留，不创造游戏进度。

`AWBuildMigration.migrate_payload(payload,config,evaluator)` static返回data完整14字段候选+migrated。通过evaluator.get_rules只读规则构造候选Progress/Inventory/Roster/Combat，校验世界/库存/装备/全部档案/current资格/vitals/settings/input；无文件/节点/InputMap/奖励/实际状态提交。domain缺字段按1，只在全无新域时建立两个deep-copy零天赋档案、默认thief、pulse+barrier、六个真空槽、复用旧weapon、零CD；domain2任何部分/未知/未来/非法数据拒绝。旧版本没保存CD，零值只是一度迁移默认，不能恢复或虚构旧历史。

活动weapon冲突拒绝；当前装备缺失失败；非活动失效引用保持可见，不静默重绑。唯一active装备equipped标记规范化（旧optional缺省按false），其他原ID/数量/resources/history/世界语义不变。整数规范化与equipped导出标记不应误当资源增长；生命/体力不补、超合法max拒绝、不截断。envelope v2双槽/checksum未改。

跨域恢复新增强校验：realm1不能含focus冷却/持续focus效果或anchor冷却；realm2合法持续状态不要求当前仍装配focus或仍拿二阶枪，避免用换槽/换武器清CD或错误拒绝合法旧效果。纯迁移HP0仍保持0，实际继续后的失败回营恢复由根按ADR-036处理。

`SaveRepository.save(payload, existing_validator:Callable=Callable())`：可选纯同步领域守卫在现有进程mutex内执行，_scan_slots返回的所有有效generation均检查，包括比最新支持版本更旧的未来域槽。守卫只接收已验证payload的deep copy，标准结果为{ok,code,message}；失败原code返回，未建/改tmp或槽。无guard保持原通用JSON仓储契约；游戏领域版本由Main纯migrate守卫判断，库不硬编码领域。守卫不得做IO、await、发信号或重入Repository；这里只承诺同一进程串行，不宣称外部多个进程并发安全。

AWUserPreferences.save将_validate_payload直接传给仓储守卫，删除独立load→save的窗口；有效旧槽的未来键位、非法键位/设置仍保留，不因较新有效支持槽存在而被覆盖。坏checksum/截断槽不作为领域守卫候选，原恢复规则及有效generation保护不变。

## 实际失败与修复

- 输入旧版本新增动作和固定冲突策略：合法CLI发现13例，3 failed case/9 failure，旧代码保持schema1/无新增/耗尽仍apply；实现schema2后26、30、53相关回归绿。业务red在character-builds-input-business-red。
- 共享效果/CD配对：真实12例、1 failed case/6 failure，旧实现允许barrier/focus剩余而CD0和自疗20/family0；补全配对后42/51/53绿。业务red在character-builds-combat-pair-business-red。
- 独立规则代理审查发现合法旧装备缺optional equipped时Migration直接dot读取。真实9例/1runtime error/1 failure，Invalid access发生在实际业务函数；修为get(false)并规范String标记，51/53绿。业务red在character-builds-migration-optional-flag-red。
- schema整数误复用键码上限/1000000上限：真实29例/2 failed case/3 failure，大未来版本误归genericinvalid；更正JSON安全整数上限后53绿。character-builds-large-future-red保留。
- realm1共享高阶状态：真实11个Migration案例中1失败案例/6失败断言，focusCD/focus效果/anchorCD可被恢复；补跨realm守卫后四套55绿。`artifacts/character-builds-realm-state-red/report_1/results.xml`保留为业务red，不把此前53称全边界通过。
- 已校验旧偏好槽被漏检：真实Prefs17例中2失败案例/6失败断言，正常save实际覆盖较旧future input schema3槽和较旧键冲突槽。`artifacts/persistence-forward-guard-business-red/report_1/results.xml`、exit100、0errors；不是新API缺签名或parse错误。锁内检查全部有效槽后Repo24+Prefs17共41例green，再与Migration/Combat/Input关联回归81例green。无mock IO，均在user://tests隔离目录真实创建、读取、保存文件；malformed guard响应与故意变异收到的clone只属仓储API防御性测试，不当作业务red。

最初手写CLI参数误用-e、--分隔和两次test插入位置造成parse错误均已修正，不计作业务red。Migration首8例中的2断言是测试把整数规范化及equipped导出标记当逐字节一致，已按规格语义修正；不宣称这两个错误断言是产品缺陷。

## 真实旧档来源与双槽测试

game/tests/fixtures/domain1_real_save_slot.json 原字节来自冻结002合法InputEvent玩法4runs的seq50槽：7,388B、SHA256 5C5B755855F235E866E2D9F2E012172E36FD40AA25FFF995716141EF827182A8，envelope2/domain1/input1、level21/币96/废铁36/晶片4。来源WindowsPCK 2C6AA3FCF54EE79BEC8D8357FC2A6C1EB236827203C96A2049DE340A71A6CAEE。夹具不含私密服务数据，tests发布排除；README保留来源。

槽同时记录run_counter5/interrupted_expedition=true：4次已结算，第5次在取样结束正常退出时中断；level21/experience2含既有即时事件经验，资源只计已入库四次。不把中断的第5轮当完整通过，也不补其未入库货物。

实际复制到user://tests/build_migration/PID_ticks，SaveRepository验证原checksum读取seq50→纯迁移→另一槽写入并回读seq51→原有效槽字符串完全不变。二次迁移结果相同；所有拒绝无live world/inventory/roster/InputMap变化。测试cleanup只遍历受控新建测试目录；不访问真实玩家或外部源档。

## 待验边界

根GameSession/Player/HUD已接入新域，主场景和全量严格报告由根分别维护，不用本地81替代全量门槛。真实fresh-editor-run1 driver已完成两次盗窃者收益、GUI疗愈者切换、天赋草稿与应用、疗愈者三个命名槽、真实敌伤自疗、两真实秒暂停冻结；该轮因QA浮点字典严格比较误判在title_observe结束，完整流程仍未通过。比较器修复仅24条headless断言、不是GdUnit测试数量或PC继续/重启/死亡证明，详见character-driver-preparation.md及原始输入报告。真实冷启动仍出现原生cpp759错误，保留开放；不能把002旧冻结生产零错误代当前003。

完整六槽独立内容/技能与共鸣空间反馈、当前构建/性能、真实完整退出重启流程及Android/物理手柄/真人等门槛仍须各自证据。新的Main退出保存失败retry/dirty和在已启动会话中阻止未来域写覆盖，由根与独立session persistence suite负责；本代理不勾共享任务状态，不称全游戏验收完成。

复跑用参数化Godot路径，报告目录每次独立：

```powershell
& $env:GODOT_BIN --headless --path game --script addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/test_build_migration.gd -a tests/test_combat_state.gd -a tests/test_input_bindings.gd -a tests/test_user_preferences.gd -c -rd ../artifacts/new-unique-local-report --ignoreHeadlessMode
```
