# 003 角色、构筑与预设规则证据

2026-10-13；核心规则代理独占文件，根复核与场景集成仍需独立验收。

## 交付与接口

已实际实现 `game/config/character_builds.json`、`character_builds_config.gd`、`features/characters/build_evaluator.gd`、`character_roster.gd`；不是规划占位文件。固定两身份、九节点、三通用技能、专属自疗配置及两共鸣，所有注册项有中文label/description；严格字段、类型、有限值、阶段、引用与效果界限校验。

`AWCharacterBuildsConfig.load_file(path,presentation={})` 原子载入。pulse只在JSON声明 `source="presentation.weapon"`，`skill(id)` 从已经验证的中央weapon配置归一成本、冷却、伤害、半径，返回深复制。`presentation_data()` 返回同一验证来源的深复制，供共享战斗状态使用attack/dodge/anchor，不引入第二份数值或规则层新IO。缺文件或重载无效参数保持先前已载入配置。

`AWBuildEvaluator.new(config,rules,presentation)` 要求与配置使用的中央参数一致。`evaluate` 返回stats实际绝对量、active_resonances、inactive_resonance_reasons、spent_points、available_points、branch_points；`validate_structure` 还返回规范化 `data.build`。装备比例从现有rules定义读取；武器伤害阶级倍率2与词条预算倍率1.5独立。攻速使用原冷却除以1+攻速比例，连锁距离使用原范围乘以1+比例；装备与同类天赋百分比相加在不可变原始基数上。派生计算拒绝非有限溢出。`get_rules()` 提供候选Progress/Inventory构造需要的同一已验证规则引用，迁移消费者不修改规则；`presentation_data()` 深复制已验证基础参数。

`AWCharacterRoster.new(config,evaluator)` 持有两独立档案；`profile(id)`、`active_build()`、`snapshot()`均深复制。`save_preset` 可显式接实时progress/inventory，省略时使用initialize/restore绑定的同一对象，资格每次即时求值。营地/Ended/开始状态与生命资格由核心验证；四字段vitals为health/stamina/max_health/max_stamina，旧上限必须与当前实际活动构筑一致。preview仅读，apply重新求值、预检并只调用一次库存事务，更新全部实际穿戴标记后提交档案。输出new_vitals/effective_build/derived_build/equipment_updates。所有装备身份、普通词条和历史字段保持。

restore检查两角色的applied/draft/六槽全部结构，仅当前生效配置需完整资格；非活动失效引用保留。所有领域键都是String；JSON整数读回浮点时只接受精确合法整数并规范为int。`references_to` 返回真实全部引用位置，材料消耗后不删除或重绑引用。金币余数公开只读，`can_commit_coin_remainder(expected,updated)`与`commit_coin_remainder`提供0..19与旧值核对，真实远征奖励与幂等仍由远征结算域负责。

## 真实业务red与修复

最初完整角色suite的重复initialize案例发现：再次初始化会清空已有草稿和19已入库余数。`artifacts/build-core-business-red/report_1/results.xml` 实际发现并执行10例，0错误、2失败断言（同一案例），其余9例通过；进程退出100。修复为已有档案拒绝重新初始化，返回roster_already_initialized且快照不变。该案例随后实际通过。

`artifacts/build-core-first-red.log` 的局部GDScript类型推断编译失败不作为业务red；`build-core-green-01`中的测试夹具typed Array传参错误也不作为产品业务red。后者另暴露JSON整数类型规范化不一致，现通过结构规范化确保可重复序列化的整数域。

## 实际测试

首个稳定报告为`artifacts/build-core-stable-56/report_1/results.xml`、`artifacts/build-core-stable-56.log`，56例全通过。真实CombatState落地后去掉不透明夹具，补施放/切换及领域命名边界；最新稳定独立报告为`artifacts/build-core-real-combat-future-stable/report_1/results.xml`、`artifacts/build-core-real-combat-future-stable.log`。实际Godot4.7.2.stable.ed1daf0bf、GdUnit4 6.2.2，7个suite总71例、0失败、0错误、0跳过、0flaky、0orphans，退出0；日志无SCRIPT ERROR/原生ERROR。

| suite | 实际案例数 | 范围 |
| --- | ---: | --- |
| test_character_builds | 14 | 严格配置/单一pulse来源、独立预算10/11、非法节点/技能、草稿隔离、绝对属性、上下文/生命守卫、比例与体力、100次往返、初始化保护、溢出、真实非零持续状态切换 |
| test_build_presets | 13 | 六槽深复制、空槽/名称、资格无效可保存、实际融合消耗后失效引用、确认重验/幂等、穿戴及经历保护、全部档案恢复、JSON/String键、余数核对、外域字段拒绝、JSON安全范围内全部未来schema拒绝 |
| test_build_resonance | 6 | 0/7/8阈值、装备tier与装配条件、旧词条scale、共鸣理由、冷却/消耗界限、阶段资格和衰减cap |
| test_combat_state | 12 | 另一owner的真实共享技能/恢复、有限快照、玩法时钟、吸收及配对边界回归 |
| test_progression | 8 | 原成长及恢复规则回归 |
| test_equipment | 10 | 原装备身份/培养规则回归 |
| test_expedition | 8 | 原真实目标、奖励及结算规则回归 |

单元夹具明确通过真实公开规则方法建立合法世界与已有装备，不是完整游戏输入流程证据。最新夹具已全部使用真实AWCombatState；新增案例按真实活动身份/已生效装配连续施放barrier/focus/self_heal/attack/anchor/dodge，从120体力实际支付至2，生命比例从0.4经自疗变0.7；tick0.5后屏障真实容量27.6/剩余2.5秒、聚焦3.5秒、自疗与家族均19.5秒。随后100次合法身份/天赋/技能槽应用逐次对照完整CombatState快照不变，卸载Focus也不重施或清除其实际剩余效果；体力、生命比例和库存资源守恒。暂停tick不推进，真实恢复受共享冷却拒绝，原施放operation_id仍重复拒绝，另一个真实CombatState恢复快照一致。这个局部规则证明不替代场景伤害/触控/实机技能反馈验收。

## 菜单只读审查

真实AWGameHUD/AWBuildMenu headless控件信号探针见`artifacts/build-menu-signal-probe.gd`与`.log`：九节点和三预设的loop捕获路由正确。发现P2刷新边界：旧`build_menu.gd:52–60`只刷新反馈Label与应用按钮，拒绝重复技能后真实草稿仍pulse，但主槽控件仍显示barrier。根owner随后同步SpinBox、技能及装备控件，代理复验见`artifacts/build-menu-signal-probe-after-refresh-fix.log`：拒绝重复技能后实际草稿和显示均pulse，九天赋/三预设捕获仍正确，退出0且原生日志无ERROR。代理未修改菜单源；这是实际控件信号与拒绝恢复的局部验证，不是完整游戏鼠标/键盘/UI门槛通过。

候选边界另识别Migration直接读取可缺省equipped标记风险，已消息存档owner按现有装备契约修复并由其独立做red→green；该存档证据归其owner。本Roster的future_schema识别已覆盖合法JSON安全整数2至9007199254740991，不再把1,000,001以上未来版本归为一般损坏；2/1,000,001/最大安全整数三边界均拒绝且原快照不变。

## 可重跑命令

```powershell
& 'D:/bugu_software/ai-game-toolchain/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_character_builds.gd -a res://tests/test_build_presets.gd -a res://tests/test_build_resonance.gd -a res://tests/test_combat_state.gd -a res://tests/test_progression.gd -a res://tests/test_equipment.gd -a res://tests/test_expedition.gd -c -rd 'D:/bugu_projects/another_world/artifacts/build-core-new-unique-report' --ignoreHeadlessMode
```

报告目录须每次新建；同时核对进程退出、JUnit非零且无失败/错误/跳过、原生日志无ERROR。代理本轮没有GodotMCP、GPU操作或全工程import，避免与根集成冲突。

## 状态与限制

TASK-202/203/206/210/211/213/214/218规则或测试交付存在并通过本轮局部门槛，待根复核；TASK-219两共鸣纯规则存在，但实际锚点/屏障接入仍待根集成。没有勾选共享任务状态，没有宣称UI、实机输入、迁移完整集成、Android/手柄/真人、商业品质或002渲染开放缺陷通过。
