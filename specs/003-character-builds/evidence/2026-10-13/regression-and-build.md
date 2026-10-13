# 严格回归与构建状态

2026-10-13。当前003实际全量GdUnit严格wrapper报告`artifacts/003-unified/0e0aa05e36e340898ee4d9836e435ab1/report_1/results.xml`，223实际案例，0error/failure/skip/flaky/orphan，import/test exit0，无原生/脚本ERROR。已归档gdunit-unified-223.xml。测试期间最后一份owned test_build_menu的修改时间晚于import日志，正在对最终完全冻结源再跑一次；首轮不当最终源码锁定证据。

最终冻结源码重跑完成：`artifacts/003-unified-frozen/29be5f890cef495b85c8290899bbb441/report_1/results.xml`，仍223/223，全部失败/错误/跳过/flaky/orphan0，import/test exit0且无原生/脚本ERROR。归档gdunit-unified-223.xml及-summary.json以这轮为准；没有复用旧结果。相交局部报告不计额外总数。

专用新Editor59216/session game@d9b72593f340469d 的第1run实际成功两thief、healer GUI/天赋1/三个命名预设/真实敌伤自疗/两秒暂停。开发driver在标题保存阶段严格Dict比较误判：实际self_heal/recovery_family与冻结快照只有JSON浮点往返3.55e-15秒差，均约19.995833，effects0，不能称CD丢失；正在修开发验证器语义比较而非改产品补CD。原始fresh-editor-run1-character-input.json保留failure状态，不标流程完全通过。新editor原生cpp759仍复现2次以上，mcp-fresh-editor-run1-log.json保留；不能称重启Editor已修复或旧Editor私有堆污染child进程。

独立主场景19及新增12、真实Control17、Avatar11与迁移55有各自细节证据，不能将重叠报告相加充作总数。原生Dummy headless回归不证明实际GPU。冻结002 Windows/Android/性能证据属于002原生产源码，不能代表003。当前003生产包/可比性能尚未完成。

真实GPU仍有开放BUG-112-01：同冻结757文件（Changed0）的MCP run15发生5次cpp759 NativeERROR；角色driver完成两thief后UI投递停于healer_observe，未完成治疗/预设过程，已归档原始状态和日志，不标PC通过。生产_request_quit实际调用成功；NativeERROR仍是失败。

Root诊断run14还发现专用老Editor的全局类缓存430缺少已存在的几个class，脚本filesystem单文件更新后scan437解决了新启动；非导入脚本的刷新不单独作为parse证据。已正常退出旧专用Editor并重启新的59216，后续新session重新验实际启动和渲染差异，不能仅因换会话认定错误解决。

独立 cold完整60秒2远征0ERROR证据在main-integration.md；另新skin AnimationTree生命周期与同mesh无skin生命周期各60秒/11重建/正常exit0/native0，见source-assets/character-renderer-investigation.md更新。各组暴露量和场景条件不同，不能替代完整MCP或release，也不推断冷热内存污染根因。

最新两共鸣Main新增2例后，根在所有game源冻结且专用Editor正常退出的条件下重新执行严格wrapper：`artifacts/003-unified-resonance-final/21cc1dcd5b214a4680a8be0cfe52f8aa/report_1/results.xml`，225/225，failure/error/skip/flaky/orphan均0，import/test exit0且无ERROR。已归档gdunit-unified-225.xml及-summary.json；223报告仍保留为此前历史。Native回归随后重新开启，不混算GPU/PC证据。

新Editor第1run结束后的完整GameLogger记录实际7次cpp759，第2run实际1次；分别归档mcp-fresh-editor-run1-final-log.json与run2-final-log.json。较早2次以上的run1截取只是当时快照，不能冒充最终计数。已正常quit59216并仅修改项目缓存game_view/embed_on_play为false，开始同Mobile渲染器的独立窗口单变量诊断；产品源码未改，原键缺省状态有备份待恢复。
