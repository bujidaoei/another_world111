# CR-003-03 保存保护与失败转换

2026-10-13。映射既有REQ-210/NFR-201、AC-210/211、TASK-221/223。独立审查发现并用真实文件验证，属于现有存档标准收敛，不新增玩法或放宽格式。

Repo/Prefs：在原process mutex内扫描两个已验证代次，对每个payload副本执行纯guard；future/domain-invalid拒绝不创建tmp/不写槽。generic无guard保持原API；Prefs与Main绑定自己的真实验证器，无IO/await/信号/仓储重入。older future偏好、older冲突偏好真实red后，关联81/81通过，原始报告和审查见readonly-final-review.md及combat-input-migration.md，不与历史55/53相加。

Main：_save_progress/_save_preferences返回实际Result；dirty只成功清除，失败停止自动偏好重试直到新设置编辑或明确重试。进度/偏好任意所需保存失败，正常quit不进入_quitting或退出，Title不丢内存会话；重试、取消、明确放弃退出分别是实际命令。

真实故障以自己的隔离user://tests目录中inactive槽的.tmp同名空目录导致FileAccess.open写失败；移除经绝对范围和无链接检查的空目录后真实重试。不存在mock仓储/IO或伪造资源。退出失败在独立headless真实Main子进程中观察0.4秒，以防旧0.2秒quit终止父runner；原始child.log/observation.json保留。GdUnit官方assert_error精确捕获这些预期push_error，原始控制台仍保留ERROR；新严格wrapper须按成功JUnit、固定源SHA、精确JSON+原始官方堆栈、具体case调用位置和固定次数分类，任何未知Native/Script/Parse/泄漏/伪诊断都失败。

实际业务red：session-persistence-business-red为4case、22断言失败、0runtime errors、exit100；first-red包含子probe类型推断错误，保留但不算业务退出red。5case dual-title green验证Title双保存错误保留会话/dirty并真实取消/重试。新增settlement red为6case中1case3断言失败，0runtime errors；取消失败quit丢原结算菜单两按钮。

修复采用HUD push_menu_layer/pop_menu_layer真实原Control树保存，旧层挂HUD隐藏owned child以保持对象、回调、未提交输入，取消精准恢复同控件及focus/scroll/visible/paused/inputblocked/playeractive。retry不额外push，成功Title先pop再构建Title，不遗留层；退出时全树归Scene所有。避免枚举菜单重建对新stage遗漏。最新6case后验/严格全量证据待实际完成后追加，不先勾TASK-221。

涉及源：game/persistence/save_repository.gd、user_preferences.gd、game/presentation/game_session.gd、game_hud.gd；真实测试test_save_repository、test_user_preferences、test_session_persistence。引擎版本、存档envelope/domain及技能数值不变。多个外部进程同时写入不在现有进程内互斥承诺内，当前证据也不声称证明它。

## 接续审查：输入捕获与键位待保存状态

原会话中断后，新根重新读取Spec Kit与原会话证据。独立复验既有7case通过、9条精确预期诊断，仍不等于最终全量。发现中的两条关联路径继续归CR-003-03、REQ-210/NFR-201/NFR-203、AC-210/211/213与TASK-216/221/223：重绑捕获在保存失败弹层上须暂停，让该层接收导航/取消，恢复原捕获层后才能继续捕获；离开捕获界面须结束捕获。任何实际偏好写入失败都须保留dirty，即使失败前没有未保存的设置滑块编辑；正常退出/标题应重新尝试真实偏好写入。

测试先由独立owner在真实Main、真实InputEvent与隔离.tmp目录写故障上复现；新增suite的故障诊断采用明确suite注册、成功JUnit case、源SHA、官方完整堆栈、行号和固定次数审核，不拓宽未知引擎/脚本/泄漏错误容忍。当前为待复现/修复/最终回归，不能将静态发现或拟定规则当通过。
