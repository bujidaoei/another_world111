# 重绑捕获、失败弹层与真实输入独立审查

2026-10-13。审查读取AGENTS、宪章、003 spec/plan/tasks/progress/validation及最新真实证据，使用input-systems、godot-ui-control、godot-gdscript与headless-testing skill。审查代理对生产代码和共享Spec均只读；本轮仅新增独占`game/tests/test_rebinding_transition.gd`与审查证据。生产修复由根完成。没有MCP、GPU、全局import、全量回归、设备或真人调用。

## 实际业务 RED

固定Godot4.7.2.stable.ed1daf0bf/GdUnit4 6.2.2，测试完整真实Main，保存/偏好使用每case新建`user://tests/rebinding_transition/<PID>_<ticks>/main`。在下一写入槽的`.tmp`同名空目录制造真实FileAccess失败，使用官方`assert_error().is_push_error()`核验精确JSON诊断；无mock仓储、空接口或伪造业务实现。每case退出恢复InputMap/暂停/auto_accept_quit，删除前检查绝对隔离范围、非链接、空目录，并由Scene释放实际Main树。

报告：`artifacts/003-rebinding-transition-business-red/report_1/results.xml`；原始日志`artifacts/003-rebinding-transition-business-red.stdout.log`和`.stderr.log`。共6case，5个失败case、21个失败断言，0 runtime errors/skips/flaky/orphans，Godot实际exit100。stderr保留4条官方断言捕获的预期IO诊断；这不是零ERROR green，也不是严格wrapper通过。check-only先实际exit0，失败源为业务断言，不是parse/缺API/零发现。

冻结源码SHA256：测试`C8FF8D5C36E493186C5DEDDDD77D5344FA3FC666BD43695E23A9815DC2660A1B`，Main `C86D34D70352058D0A620FEA14163BA596F13F6F1B72C4BF6672BE94827912A3`。此记录保存修复前事实，根修复后需另写green及新源SHA。

| 发现 | 实际触发/观察 | 修复前位置与建议 |
| --- | --- | --- |
| P2 失败弹层被底层捕获抢键 | 正在重绑时正常quit遇真实IO失败；Tab未移至下一按钮，取消按钮焦点下Enter未取消；Esc把失败层内容替换为按键菜单，pending quit和旧menu layer仍保留。 | `game_session.gd:1078`仅判断`_binding_action`，没有顶部失败层门槛；先把失败层输入交给真实GUI/暂停取消，再恢复被保留的底层捕获。 |
| P2 捕获退出未清理 | 合成真实JoyStart InputEvent经现有InputAdapter关闭modal；`_binding_action`仍为move_forward。之后构筑名称字段的Ctrl+A/X被旧捕获拒绝，原生文本未改变。 | `_handle_action:303`→`_close_menu:1121`未释放捕获；关闭当前菜单时清理捕获状态。合成Joy事件仅是路由回归，不代表实体手柄。 |
| P2 重绑/默认恢复的偏好失败丢dirty | 真实F8重绑或真实bindings_reset写偏好时IO失败，`_preferences_write_failed=true`但dirty仍false；随后Title不重试偏好且丢内存会话。两条独立case均复现。 | `_save_preferences:1115`失败需统一保留dirty；`_save_before_transition:1172`因此能拒绝转换并显示真实重试；移除blocker后Enter重试与回读已写入同case，green尚待。 |

普通BuildMenu文本没有复现吞键：`test_normal_main_build_preset_text_and_talent_submission_reach_native_controls`在真实Main下通过。真实Viewport.push_input Ctrl+A/Q/7得到名称Q7，按Q没有排队主技能；SpinBox真实输入7未提交时草稿0，Enter后草稿7且live仍0。直接的领域/初始化调用只建立单元场景与页面；实际编辑走InputEvent，不手工写字段文本或提交信号。此非PC硬件/原生GPU验收。

## 修复后的实际 GREEN

根在Main `_input`的pending/quitting门槛、`_close_menu`和成功Title捕获清理、`_save_preferences`统一保dirty路径完成生产修复，冻结Main SHA `F783556715327ACD5925BBE1E5593DAB7D6394F4CD6E614CA79F2496117247B2`。审查代理对完全不变的6case重跑：`artifacts/003-rebinding-transition-green/report_1/results.xml`，6/6通过，failure/error/skip/flaky/orphan均0、Godot实际exit0，测试SHA仍为上列C8FF。

真实Tab导航、Enter取消、Esc取消恢复原Control内容与捕获、合成JoyStart关闭后清理、普通Main文本/SpinBox输入，以及重绑/恢复默认偏好失败保持dirty、Title拒绝、移除真实blocker后Enter重试与磁盘回读都通过。stdout/stderr在同名前缀日志，stderr保留6条官方`assert_error`实际捕获的精确IO JSON与生产/官方/具体case堆栈；无SCRIPT/Parse/Native/泄漏诊断。不称零ERROR，不把直接GdUnit runner代替严格wrapper。已向存档代理提供全部日志进行精确policy2分类，根仍须实际跑新冻结全量。

## TASK-209/221 未完成步骤

独立核对`standalone-character-input.json`为completed/ok=true，已发生两盗窃远征49币/余数4、GUI疗愈者切换、草稿/应用、疗愈者3名字、真实敌伤自疗、暂停、标题继续与实际死亡；其原生ERROR仍开放，见native-character-contrasts.md。此前失败报告保留，不改为通过。

剩余真实输入应逐步补：

1. 盗窃者实际赚到pending怪币和余数后失败/中断，比较已入库币/余数、既有XP、pending丢弃与再次继续；现有healer死亡没有先赚pending，不能替代这个对照。
2. 真实受伤/消耗资源后回营，冷却仍剩时切身份/应用不同上限构筑，逐项比较生命比例、体力不补、世界总量、库存和共享冷却；现有首切是满血，不能替代受伤比例。
3. 盗窃者实际按专属能力，验证身份拒绝且生命/体力/冷却不变；恢复满血/不足资源等拒绝保留自动化与真实流程分列。
4. 两角色共六个不同内容预设，实际覆盖、载入草稿、应用及保存退出重启；目前thief三槽为空，healer三槽只同一构筑改名。冷却跨调槽/卸装/重装、屏障实际受击与聚焦实际命中仍需真实输入补充，driver相关coverage明确false。
5. 完整迁移和CR-003-03拒写/失败转换以修复后冻结源重新跑危险suite及严格全量；本轮三类业务red已由上述6case green收敛，新全量仍由根执行。实际跨进程重启已有值观察，技术验收报告仍应固定进程/构建/源SHA与六槽内容，而不得把同进程title/continue说成退出重启。

其余预设材料消耗影响、两共鸣、制作/性能和视听遵循validation的完整协议；局部规则/Control通过不替代TEST-210整体验收。

## 状态与Git技术checkpoint

只读关联核查实际25条record、19条done、tasks19项勾选/6项开放，record引用的证据文件全部存在。209/221/222/223/224/225未勾符合未收敛事实；当前progress正确区分旧冻结225与新保存变更待新报告。最旧integration-status.md是历史实施中快照，不能当当前状态；可补头部历史声明，不应悄悄改写当时记录。

当前branch为`codex/003-character-builds`，HEAD `2439042`（002技术checkpoint），origin是已配置HTTPS仓库。`git diff --check`无内容错误，仅既有CRLF→LF提示。审查代理没有提交、暂存或推送。本轮三类缺陷已真实green；根完成新严格全量后，可提交已验证规则/场景/UI/迁移/工具链/原创源及证据与同步Spec为明确“003技术checkpoint”；保持原生渲染、真实PC剩余覆盖、生产构建/性能、设备/真人、品质任务开放。不能把源码存在、旧225或此review替代完整feature验收。
