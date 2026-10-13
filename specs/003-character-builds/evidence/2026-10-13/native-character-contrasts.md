# 角色真实输入与原生渲染对照

2026-10-13。以下各轮保存原始失败，不是发布或完整PC验收；使用实际4.7.2 ed1daf0bf、Mobile/Vulkan、RTX4060 Laptop GPU。原生错误为particles_storage.cpp:759的particles_get_instance_buffer_motion_vectors_offsets缺失owner。

独立窗口MCP：根正常quit旧专用Editor后，项目缓存唯一改动为 `[game_view] embed_on_play=false`，全局mode0不变；事务备份在artifacts/embed-diagnostic/0424b26060044ef39de370ff5b1c6d9d。新Editor48032、实际child76496命令行保持remote-debug且无--wid；window1280×720、实际viewport1600×900。运行r26973-1角色driver56.108611秒完成8项真实覆盖：两thief远征、healer切换、天赋草稿应用、healer三命名预设、自疗、暂停冻结、标题继续CD、真实敌伤死亡/失败回营。对应independent-window-character-input.json。币49/余数4，自疗耗35体力，失败回营44.45/127HP；未覆盖thief三预设/技能调槽/Android/物理手柄。

同轮GameLogger实际2条原生错误（完整game/editor日志已归档），不是clean native gate。运行前后1755个game文件（排除.godot）SHA比对Changed0，未通过改源码/关雨/关skin/关闭调试来隐藏错误。根调用实际production_request_quit正常结束子进程，然后正常quit48032，并通过同事务restore恢复原项目键缺省状态，保留其它metadata更新。恢复事务需后续新嵌入进程确认实际--wid。

随后完全独立cold进程：consolePID58624/实际GUIchild35440，无Editor、无--remote-debug/--wid，EngineDebugger.is_active=false，使用相同QA Main和最终driver、同window/viewport、同Mobile。报告003-standalone-character-input.json的8项覆盖均true，driver56.987289秒、启动到退出请求57.133796秒、13,570drawn frames，正常production_request_quit，console exit0；stderr仍1条同原生ERROR，无script ERROR。stdout/stderr/报告归档为standalone-character-*，不能因为exit0就称测试通过。

因此这些实际结果排除“窗口嵌入/MCP/远程调试是错误必要条件”的假设；未证明具体owner/base_flags写入点，未关闭BUG-112-01。先前只有两thief远征的独立60秒0错误，以及孤立skin/Tree两组0错误，其覆盖条件不同，不能替代这次完整角色流程。后续优先生产Player双模型预检/替换的最小native矩阵与完整世界资源退休交互，再决定是否需固定引擎C++符号诊断。禁止过滤日志或仅切renderer冒充修复。

严格225/225是本轮新增退出/前向保护审查发现之前的冻结代码证据；持久化后续修改需要新的局部和全量报告，不冒充已覆盖。
