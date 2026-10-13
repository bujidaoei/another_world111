# Main真实保存故障与退出保护

2026-10-13；`game/tests/test_session_persistence.gd`，Root持有Main/HUD/Repository/Preferences实现。此代理仅独占新suite、实际引擎生成的`.uid`及验证产物，没有fakeRepository、mock IO或业务替身。

## 首个真实业务RED

`artifacts/session-persistence-business-red/report_1/results.xml`和`.log`实际4案例、0运行错误、22断言失败、0skip／orphan、exit100。Main仍为旧源SHA `fcbee72e7a4087d2b31d569f3e51f3b8c082ff89d7bb4f4f797594d9c664a73c`。真实有效双槽基线后，在下一inactive目标`slot_*.json.tmp`位置创建已核验隔离范围的空目录，实际FileAccess.WRITE拒绝写入：旧Main丢失偏好dirty、不能返回保存结果。已经启动的Main外部通过正常repository.save写入domain3后，下一Main保存改变了slot_a字节，而非阻写。两个真实headless子进程中的旧Main虽然保存失败，仍置_quitting=true并在0.2秒正常生产退出，未活到0.4秒观察；父GdUnit存活并保存完整XML。

子进程原始证据在 `artifacts/session-persistence-probes/69100_1508989-progress/` 和 `69100_1508989-preferences/`。RED元数据见`session-persistence-red-results.json`。首轮`session-persistence-first-red`中的子probe类型推断parse已纠正，不计为退出业务RED；该原始失败也完整保留。

## 第一轮修复后5例结果与明示诊断

Root实施Main返回真实Dictionary、偏好成功才清dirty、现有双槽纯guard、失败quit/Title保护后，正式报告 `artifacts/session-persistence-final-green/report_1/results.xml`、`.log`实际5/5、0JUnit error／failure／skip／flaky／orphan、exit0。元数据 `session-persistence-results.json`保存这轮所有源SHA与两个最终子进程证据路径。这个5例时点随后发现新的菜单恢复缺陷，不能当作当前6例源码最终通过声明。

| 案例 | 实际路径及断言 | 父进程预期ERROR次数 |
| --- | --- | --- |
| progress_write_failure | 真实tmp目录阻写，结果io_error、两槽SHA不变；移除仅本案空目录后真实重试成功，sequence+1、当前受伤生命保存。 | save/save/io_error/version0.1.0 ×1 |
| preferences_write_failure | 实际设置动作标dirty，真实tmp阻写保dirty及原槽；移除阻写后真实重试保存0.25音量，成功才清dirty。 | preferences/save/io_error ×1 |
| external_future_domain | 已启动Main外部正常写入future3，下一保存future_schema、阻写标记启用、两槽字节不变。 | save/save/future_schema/version0.1.0 ×1 |
| title_save_failure | 同时阻断偏好与进度两目录；单次生产Title产生两真实错误，session/dirty/vitals/库存/roster/原槽保留；实际取消按钮恢复camp，再Title失败；解除两阻写后实际retry_title按钮成功保存并进入标题。 | preferences/io ×2；save/io/version0.1.0 ×2 |
| failed_quit_child | 实际Main两子进程分别进度/偏好阻写，失败后_quitting=false，0.4秒仍活、三实际错误菜单按钮存在；实际取消按钮恢复原mode/paused，再直接生产save重试成功。 | 父0；每child恰1实际JSON错误 |

所有父日志由官方 `assert_error(...).is_push_error(精确JSON)` 接收；保留原始7个ERROR头及完整生产/官方assert/case堆栈，不删除或宽过滤。Title单次真实调用产生两条错误，用同一官方logger逐条断言，callback的once标记只防重新执行写操作，不伪造错误。这个5例时点的child检查精确ERROR和SCRIPT ERROR，后来强化原生退出警告审查发现音频泄漏，不能据先前5/5声称子日志完全无异常；见下文实际生产退出校正。

第一份名为`session-persistence-first-green`的报告实际5例有2断言失败，不能当green：当时只阻断进度写入，而偏好写入已经成功，我却错误期望dirty保持。改为双目录真实阻写后分别验证失败保dirty和成功清dirty，没有改业务迎合该错误断言。

## 只读终审发现的第二个真实RED

新Main取消持久化对话框按mode枚举恢复，漏掉真实`settlement`模式。原待入库菜单会变pause，丢失重试/放弃按钮。新增 `test_cancel_failed_quit_restores_pending_settlement_menu_without_committing_rewards`：满scrap库存是明确容量夹具，pending的3scrap由实际远征注册节点_interact取得；生产_finish_run因真实容量进入待结算，再以真实tmp目录阻写退出保存，实际取消按钮后应恢复原结算菜单与inactive玩家，原域和槽字节不变。

`artifacts/session-persistence-settlement-red/report_1/results.xml`、`.log`实际6例，新增1例3断言失败（mode变pause／缺两按钮），0运行错误、0skip／orphan、exit100；其余5例通过。Root据此准备通用HUD菜单层保存恢复；这个缺陷尚需对应green与最后全量wrapper，不能用先前5/5代替关闭。新增父预期JSON错误save/save/io_error/version0.1.0 ×1，总数为8；每条仍必须对应当轮通过case、精确JSON、生产/官方assert堆栈及固定预算，未知Native/Script/C++或额外次数继续失败。

本轮未全工程import、GodotMCP/GPU、设备或真人验证；所有目录限定于`user://tests/session_persistence/<pid_usec>`，清理核验绝对路径、拒链接，仅删除本案创建的空阻写目录和逐层已知叶目录。Root的最后严格wrapper需单独核对实际总数、源SHA与明确预期故障诊断。

## 新菜单层与最终7例GREEN

Root使用HUD保存原Control树并恢复，无按mode枚举重建。Case6追加原VBox／两结算Button身份同一和stack清空断言，实际通过。只追加一个有意义菜单层输入案例 `test_cancel_failed_quit_preserves_unsubmitted_preset_text_focus_scroll_and_control_identity`：真实构筑三预设长菜单、PresetName_2实际键盘InputEvent输入`7`未保存；失败quit／实际Cancel之后，同原Control树、LineEdit实例、原focus／scroll／文本仍在、预设与领域不变、stack为空。普通命名LineEdit未连接失焦保存，不把SpinBox原生失焦提交行为误当缺陷。Title真实retry后同样检查无遗留layer。

强化子日志门槛后，`session-persistence-menu-layers-first`与`session-persistence-child-lifecycle-verbose`实际7例有2断言失败：每child退出有8个ObjectDB泄漏。verbose原始日志显示全部为AudioStreamWAV／AudioStreamSynchronized及其Playback；历史5例child也有相同警告。旧harness在观察完成后直接free Main再自己quit，绕过生产audio.stop_all和AudioServer退役过程；额外两个process frame实验仍失败，完整保留，不当修复。遵循Root建议，最后仅在隔离child调用成功生产 `_request_quit()`，观测`_quitting=true`，由真实停止音频、0.2秒退休与Tree退出完成；父runner从不调用成功quit。

最终 `artifacts/session-persistence-production-exit-final/report_1/results.xml`、`.log`：7/7、0JUnit error／failure／skip／flaky／orphan、exit0，约2.44秒。父恰9个已捕获ERROR，每个有精确JSON、实际Main方法、官方GdUnitGodotErrorAssertImpl／is_push_error及该case堆栈。新Case6／7各增加save/save/io_error/version0.1.0一次；原五例矩阵不变。两最终child原始证据为 `artifacts/session-persistence-probes/53672_1958922-progress/` 与 `53672_1958922-preferences/`，各exit0、恰一个精确IO ERROR及production／probe栈、0SCRIPT ERROR、0ObjectDB／RID／资源泄漏诊断，真实成功退出标记为true。未过滤或删除stderr。

最终源SHA／逐块诊断关联／两child审计在`session-persistence-final-results.json`。这是当前7例源码的局部门槛，不复用旧5例结论，根的精确expected-diagnostic严格wrapper与最后全量仍需独立执行；Root实施改变日志header预算时必须同步冻结名单和当轮通过case，不允许宽忽略ERROR。
