# GdUnit 严格诊断契约 v2

`run_gdunit.ps1`固定Godot/GdUnit版本，每轮创建独立报告，先验证实际非零JUnit、failure/error/skip/flaky全部为0，再分类原始stderr。版本和导入阶段仍拒绝所有ERROR/Script/Parse；测试超时先保留日志再失败。没有放宽错误或自动学习名单的开关。

唯一规则文件为`gdunit_expected_diagnostics.json`，仅支持`policy_version=2`。`suites`明确注册每个允许产生预期诊断的测试资源、JUnit classname、真实观察来源及日志SHA256；每条rule通过`suite_resource`归属注册suite。普通无故障suite可出现在全量JUnit而不注册；它们产生的任何ERROR仍不受允许规则覆盖。v1不再兼容。

每条rule固定精确JSON、唯一ID、预算1以及生产方法、官方GdUnit `_execute:17`/`is_push_error:132`、对应通过case的完整前缀栈和具体行号。前缀仅能包含Main、官方assert与所属suite；末帧必须是该suite的同名case。suite不能借用其他suite的case或尾栈，重复JSON/stack签名拒绝。官方框架尾栈与各suite自身实际观察到的尾栈分别登记。

JSON键和值区分大小写、必须为字符串、重复键/额外字段/缺字段全部拒绝。保存诊断仅为save/save/io_error或future_schema/version0.1.0；偏好诊断仅为preferences/save/io_error。每块必须来自stderr，包含固定Godot push_error原生位置和连续编号GDScript栈。每个允许诊断必须对应本轮真实通过JUnit case以及冻结Main、所有注册suite和官方assert源码SHA；wrapper再次检查执行前后源SHA未改变。超量、漏量、未知Native/Script/Parse、ObjectDB/RID泄漏和非零orphan全部失败。

session persistence矩阵来自真实7case：进度IO1、偏好IO1、运行中future1、Title双故障两次4、取消退出恢复未结算菜单1、取消退出保留未提交预设文本/焦点/滚动/Control身份1，共9条父诊断。child故障不并入父规则：suite独立核验每child精确IO1、生产栈、成功生产退出、Script/泄漏0。

新增suite规则只能由对应实际GREEN日志采集，不能使用RED日志或预测行号注册。规则更新必须重新核对当轮真实case、原始块、源hash、预算与本文，再执行纯判别和真实目标测试。当前v2注册session persistence与rebinding transition两个suite、15条规则。新重绑suite真实6case的诊断矩阵为：失败quit导航/Enter1、失败quit Escape1、重绑偏好IO及其Title重试IO2、重置偏好IO及其Title重试IO2，共6条；另两个文本/天赋及合成pad capture案例无预期ERROR。合成pad只证明输入适配，未称真实硬件验收。

纯判别工具接受多个实际日志和JUnit报告，合并后仍检查非零、计数一致和case身份不重复。它使用原日志完整故障块进行分流，仅验证分类函数；真实wrapper单独验证stdout/stderr来源。2026-10-13当前已运行36条纯判别，含未注册suite、错归属/错case、源码偏差、重复签名、旧policy拒绝，以及原24条诊断/JUnit检查；这36条不计入游戏GdUnit数量。

```powershell
./tools/test_gdunit_diagnostic_gate.ps1 -ObservedLog @('./artifacts/session-persistence-final-source-1c56493873e640c6a105cbd3477f88ab/tests.stdout.log', './artifacts/session-persistence-final-source-1c56493873e640c6a105cbd3477f88ab/tests.stderr.log', './artifacts/003-rebinding-transition-green.stdout.log', './artifacts/003-rebinding-transition-green.stderr.log') -ObservedJUnit @('./artifacts/session-persistence-final-source-1c56493873e640c6a105cbd3477f88ab/report_1/results.xml', './artifacts/003-rebinding-transition-green/report_1/results.xml')
./tools/run_gdunit.ps1 -GodotExecutable $env:GODOT_BIN -Suite res://tests/test_session_persistence.gd
```

独立代理于2026-10-13 14:35（北京时间）使用根已导入缓存、未重跑import，冻结源码7/7、exit0、精确预期9、未知Native/Script/diagnostic0。原始日志、执行参数、前后SHA及报告在`artifacts/session-persistence-independent-b4806fc60079401889d2a0ac7eb61301/`；此结果是旧Main `C86D34D7…`时点，不能覆盖后续Main修改。可重复的缓存目标审计命令记录于feature evidence，正式根wrapper仍执行完整导入检查。

最终Main `F783556715327ACD5925BBE1E5593DAB7D6394F4CD6E614CA79F2496117247B2`上已重新真实执行两个目标严格门槛，suite源均未改变：session persistence 7/7、9条预期；rebinding transition 6/6、6条预期；各exit0、未知Native/Script/diagnostic0。报告在`artifacts/session-persistence-independent-2ffbac7132394f27a6fc101053a9f847/`及`artifacts/session-persistence-independent-b70d6a6109fc4b48a2766b4c4ee3074a/`。这两次独立目标运行不可冒充一次完整全量报告。

v1历史冻结：2026-10-13，Godot4.7.2/GdUnit6.2.2，政策SHA `49C69C307AD8D309F8E718698609D9F9573DB52112B08BF9388C0180DE071C70`。v2最终冻结：同日，政策SHA `95C58ABE932C34DB1049754C75104544606B63D8E59EE737E4D07911F0395022`；两个真实GREEN观察联合纯36/36在`artifacts/gdunit-diagnostic-gate/1f7f76af1f88431199a30647a8c22ec9/summary.json`。全量、实际Windows渲染/构建、设备与真人门槛由其新执行证据分别记录。
