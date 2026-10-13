# 构筑控制器与真实控件回归

2026-10-13。实现文件`game/presentation/build_controller.gd`，对应TASK-212/TASK-217的独立适配与控件局部交付；根持有主场景、视图、HUD和最终验收。

## 已落地行为

`AWBuildController extends Node`，依赖AWBuildMenu、真实config/evaluator/roster/progress/inventory/combat与三Callable；不依赖GameSession、不读写文件、不修改InputMap。公开接口：

```gdscript
configure(hud, config, evaluator, roster, progress, inventory, combat,
    context_provider: Callable, vitals_provider: Callable,
    operation_id_provider: Callable) -> Dictionary
show(section: String = "overview") -> Dictionary
refresh() -> Dictionary
refresh_cooldowns() -> Dictionary
handle_intent(action: String, payload: Dictionary) -> Dictionary
view_model() -> Dictionary
```

只读`view`和`selected_character_id`供主场景/测试查询。signals为`build_applied(data:Dictionary)`、`edited()`、`closed()`。configure预检依赖与活动构筑成功后才断旧view并绑定新域；失败保持原菜单可用，exit_tree断信号。初始查看活动角色，点击其他身份只编辑其档案。

ViewModel从真实配置、库存实例、草稿、预设资格和实时providers生成，包含四页面需要的中文标签/描述、世界点数、绝对属性前后比较、技能解锁、共鸣及缺失条件；不写入领域存档。装备标签给出名称、品质、阶槽、首次获得地点等级与由原实例ID导出的稳定短编号；description提供原始实例与真实经历。被消耗引用保留为失效选项，预设同样显示具体资格理由；不复制或重建装备。

草稿/预设成功变更才发edited；rank/skill反馈刷新同步真实值且保持原控件焦点。角色、装备、预设变更重建当前页面。所有intent字段/类型完整预检；拒绝显示中文notice并同步实际model。应用先Roster.preview_apply，成功后才调用操作IDprovider，再重新读取实时场所/生命并交Roster.apply重验。一次库存事务成功后仅发build_applied，根同步vitals/造型/装备并保存；不再额外发edited重复保存。back仅closed，屏幕栈和暂停由根处理。

后续根要求低成本实时冷却刷新，已新增`refresh_cooldowns()`：只读取同一Combat/config格式化四技能与共享恢复时钟，更新已有model和视图；不调用Evaluator、不重新枚举资格/三个预设。真实施放屏障后该路径更新10秒，合法世界增长后原资格展示保持缓存直到显式refresh，新增回归通过。最后单suite报告`artifacts/build-controller-cooldown-stable/report_1/results.xml`及`.log`实际16/16、0fail/error/skip/orphan/nativeERROR、exit0。先前87例报告是当时15控件案例的历史联合门槛，不混称为时钟变更后的全量重跑。

随后已将定时刷新改为视图标签专用 `refresh_cooldowns(text)`，完整反馈仅用于编辑与领域结果；新增真实键盘事件、未提交文本与 Enter 后预算资格回归。最新单 suite 是 `artifacts/build-controller-unsubmitted-final/report_1/results.xml`，实际 17/17 通过。旧路径的校正回归也通过，未宣称已复现覆盖缺陷；完整事实见 [冷却时钟与未提交天赋输入](build-controller-text-input.md)。

## 实际验证

`artifacts/build-controller-final-stable/report_1/results.xml`与`.log`：Godot4.7.2.stable.ed1daf0bf/GdUnit4 6.2.2，8suite共87案例，0失败、0错误、0跳过、0flaky、0orphans，exit0且无SCRIPT ERROR/原生ERROR。该报告内`test_build_menu`实际15例，另外72例为角色/预设/共鸣/共享Combat/原成长装备远征回归。

控件suite使用真实AWGameHUD、AWBuildMenu、AWBuildController与真实全部纯规则，涵盖：四页面完整model和焦点；实际SpinBox仅编辑草稿；选择身份不暗中应用；重复技能拒绝恢复OptionButton；实时营地/Ended/开始/存活守卫在分配opID前拒绝；成功应用信号与生命比例；opID分配期间场所变化的确认重验；三个实际保存按钮与载入草稿；真实融合消耗后的失效装备/预设可见；重新configure断旧view；非法providers/intent无类型运行错误；关闭后拒绝旧意图；超预算/锁定技能可编辑但不可应用；移出树待free的SpinBox更新不改新身份；失败configure保留原连接。

没有为本控制器造缺失class/parse/0测试的业务red。初始12案例全通过，后扩至15。目录`build-controller-retired-control-red`只是一次生命周期假设探查的名称，当次14案例实际全部通过，不作为red或产品缺陷证据；稳定状态以上述final报告为准。

测试通过控件信号驱动实际适配和规则，有明确世界/装备单元夹具；它不是键鼠硬件/实际PC游玩/主场景技能与存档/Android/手柄/真人/商业品质验收。全工程import、GodotMCP与GPU仍由根协调，本轮代理未使用。

## 可重跑

```powershell
& 'D:/bugu_software/ai-game-toolchain/godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_build_menu.gd -c -rd 'D:/bugu_projects/another_world/artifacts/build-controller-new-unique-report' --ignoreHeadlessMode
```

每轮使用新报告目录，并核对非零JUnit、exit、fail/error/skip及原生日志。未修改共享任务勾选；根统一整合Spec Kit状态。
