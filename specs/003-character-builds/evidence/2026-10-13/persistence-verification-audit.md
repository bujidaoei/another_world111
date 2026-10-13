# CR-003-03 独立持久化复核

2026-10-13，TASK-221/223，关联REQ-210/NFR-201、AC-210/211/212。已读取AGENTS、宪章、003 spec/plan/tasks/progress、save-safety-change及readonly-final-review；应用本机Spec Kit implement、Godot GDScript和headless testing技能。实际check-prerequisites返回003目录，requirements13/13为需求质量门槛。未改共享tasks/progress或生产Main/HUD/Repo/Prefs，也未操作GodotMCP、GPU或全工程import。

## 实际独立7case

北京时间14:35:47—14:35:52执行`run-session-persistence-audit.ps1 -GodotExecutable D:/bugu_software/ai-game-toolchain/godot/Godot_v4.7.2-stable_win64_console.exe`。脚本在已有缓存直接调用固定headless GdUnitCmdTool，以独立GUID路径收集stdout/stderr、退出码、前后全部相关源SHA，随后复用项目正式strict diagnostic gate。Godot 4.7.2.stable.official.ed1daf0bf、GdUnit4 6.2.2；7/7、failure/error/skip/flaky0、exit0；9条精确官方捕获的预期JSON故障，未知Native/Script/diagnostic0。

新报告`artifacts/session-persistence-independent-b4806fc60079401889d2a0ac7eb61301/report_1/results.xml`，原日志与diagnostics/summary/source-before/source-after同目录；可提交摘要和JUnit在`session-persistence-independent-audit.json/xml`。运行前后所有6个源hash不变：suite `2E80AB6059D47E657E499956584CD1E1CDCA84BB2FB9BDBFDCC9A7B2D2C8A5CF`；Main `C86D34D70352058D0A620FEA14163BA596F13F6F1B72C4BF6672BE94827912A3`；HUD `D0F49979200EFAEFF5FF5839B7A8BA7A2DD2B85FA0862B4428EDB468882AB987`；Repo `2B2779AA879D0E8C86007BBA1DD0F1FA964440A283B19A613B2BFA34C2AFF626`；Prefs `3F9A5CE5311BA2A635DDF138279289148CC3C47FC69AEA508F3D5051C6D7B2D5`；官方assert `3A14BEE1FF7587CCA99F17A463A3F31127FF4659C7412D0607A914473C296BAB`。

两child真实生产退出probe在`artifacts/session-persistence-probes/42184_2014388-progress/`与`42184_2014388-preferences/`。各自失败退出保留文件、0.4秒仍运行、实际取消恢复camp/paused状态、实际重试成功、最后生产`_request_quit`开始并退出0；日志各恰1条对应IO、无Script/ObjectDB/RID/资源泄漏。suite清理检查随测试一起通过，保存同一Control树、焦点、滚动、未提交文本及结算菜单身份断言均实际执行。

## 只读生产审查与新发现

Repo当前在原进程Mutex内检查两个已校验有效代次、每份deep-copy纯守卫拒绝不写临时文件；Prefs绑定自己的纯_validate_payload，Main绑定完整领域迁移验证器。原已运行会话future保存保护、Title双故障、quit失败/取消/重试及实际退出等局部门槛本次真实通过。进程外并发、真正断电/磁盘故障、Windows渲染/真人/设备并未由本报告证明。

发现时Main还有另一条可达风险：成功键位重绑与bindings_reset直接调用_save_preferences，而未先标dirty；失败只标write_failed。原dirty为false时，Title/quit随后跳过独立偏好重试，重启旧偏好可能覆盖进度内新键位。已将路径交根，integration_review独占新suite取得实际业务RED，根集中保持偏好写意图dirty直至成功，并修复保存错误弹层中的重绑capture输入优先级。后续真实GREEN及本代理严格验证如下，不将静态判断冒充复现。

## 多suite诊断工具收敛

根授权我独占tools四个诊断文件，直接将policy升v2，无v1兼容。引入显式suite注册、每rule所属suite、严格prefix/case/尾帧归属及歧义signature拒绝；所有Main/官方assert/注册suite必须有源SHA锚。先以已有真实7case观察运行纯判别36/36、exit0，证据`artifacts/gdunit-diagnostic-gate/150378c87d994e46a31c0e1d18b85f37/summary.json`和`gdunit-policy2-single-suite-pure-36.json`。这不是新增36个游戏测试。

根最终Main源 `F783556715327ACD5925BBE1E5593DAB7D6394F4CD6E614CA79F2496117247B2`后，我重新实际运行原7case，报告`artifacts/session-persistence-final-source-1c56493873e640c6a105cbd3477f88ab/`，exit0、源前后相同，并从实际9条stderr stack采集新准确Main行号。integration真实6/6 GREEN在`artifacts/003-rebinding-transition-green/`与同名前缀stdout/stderr日志，exit0；新suite SHA `C8FF8D5C36E493186C5DEDDDD77D5344FA3FC666BD43695E23A9815DC2660A1B`。只依据这两个实际已通过官方断言的GREEN冻结policy2的2suite/15rules，政策SHA `95C58ABE932C34DB1049754C75104544606B63D8E59EE737E4D07911F0395022`；联合观察纯36/36、exit0，证据`artifacts/gdunit-diagnostic-gate/1f7f76af1f88431199a30647a8c22ec9/summary.json`及`gdunit-policy2-multi-suite-pure-36.json`。一次性采集命令曾因CRLF末帧正则拒绝而在写政策前失败，纠正后才冻结，不作为业务RED或game测试计数。

北京时间14:44:12—14:44:19进一步重新执行两套实际headless目标、直接使用policy2严格gate：原7/7、预期9，`artifacts/session-persistence-independent-2ffbac7132394f27a6fc101053a9f847/`；新6/6、预期6，`artifacts/session-persistence-independent-b70d6a6109fc4b48a2766b4c4ee3074a/`。各runner exit0、failure/error/skip/flaky0、未知Native/Script/diagnostic0，7个相关源SHA执行前后相同；正式摘要及JUnit保存`session-persistence-final-policy2-summary.json`、`session-persistence-final-policy2.xml`、`rebinding-transition-final-policy2-summary.json`、`rebinding-transition-final-policy2.xml`。未再次import/MCP/GPU。

本复核不勾TASK-221/223/225，不把7case、历史81case或纯36case加总为全量。最后Main修改后的目标严格、完整全量、生产构建/性能、实际Windows渲染/退出、Android/手柄/真人、商业品质及Git交付仍分别按实际证据收敛。
