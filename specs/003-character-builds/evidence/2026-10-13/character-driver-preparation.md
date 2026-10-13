# 角色真实输入驱动准备

源为game/tests/runtime/character_playtest_driver.gd；仅开发QA，tests整体排除生产包。2026-10-13固定Godot4.7.2 check-only解析实际通过，日志artifacts/character-driver-check-only.log。根主场景/玩家正在合并，代理未启动游戏、MCP或GPU；下列是可执行驱动计划，不是实际游玩通过。

API：new()后add_child，再start(session,report_prefix:String="")->Dictionary。主场景必须先配置独立save_directory并完成_ready；驱动严格拒绝普通user://saves，仅允许工程artifacts或user://tests下的独立保存/报告路径。prefix是日志文件前缀，生成prefix.json；省略时在独立存档目录写character-input.json。start主动拒绝headless，防合成窗口输入被误称PC玩法。

驱动复用已有input_playtest_driver的路由和巡回，嵌套ExpeditionPilot替换当前共享CD访问、按实际bindings映射运动/技能/交互以及真实Viewport.push_input。暂停标题通过真实GUI点击启动，不直接解除tree.paused。它不构造进度payload、不改生命/位置/XP/资源，不调用角色controller.handle_intent或roster业务提交；只读真实模型、生产Control rect和物理导航。

序列：新档两次盗窃者完整远征，每次真实登记击杀/采集/目标/撤离后按实际配置核对基础怪币、任务币、额外怪币和共享余数（默认12杀额外1币、余数4）；真实GUI选择疗愈者并确认应用；SpinBox LineEdit经Ctrl+A/键码unicode/Enter编辑生命天赋，先证明draft未改live，再GUI应用；GUI键入三个名字并分别保存疗愈者3槽；疗愈者真实进入远征站立等待敌人伤害，通过当前专属绑定（默认T）自疗并观测真实健康/体力/CD；真实Escape暂停、两秒真实时间检查冻结；真实“保存并回到标题”/“继续旅程”验证保存与重载冷却；再入远征不攻击不恢复，等实际死亡，检查failed回营且不授予战利品。

所有游戏操作走InputEventKey/MouseMotion/MouseButton和GUI命中；滚轮为真实事件，不直接改scroll值或Control文本。report只有完成所有上述实际观察才ok=true；stage timeout、成本/健康/收益/冻结/回读不符则error并保日志。原Base driver日志改为独立内存观察后由本驱动统一写报告，避免共享input-playtest.json污染。

明确未覆盖：盗窃者三预设、两角色共六槽不同内容/覆盖/载入、技能槽编辑与聚焦/屏障实际命中、物理Android/手柄、真人、独立进程退出重启（本序列title/continue仍同进程）、最终视听和性能。coverage中相关项false，不把三个同草稿命名槽说成完整六槽验收；后续根真实运行还可能暴露导航/UI坐标或时序问题，需要记录失败再修。

读取stage/completed/succeeded/results可观察运行；输出JSON保coverage逐项事实。代理未勾选TASK-209/215/217/223/224。

run15 后真实修订：根保存的 run15-character-driver-incomplete.json 显示两次盗窃者实际结算正确（49币、余数4），随后角色应用未生效，healer_observe 等待超时；该轮不算疗愈者或PC整体通过，也有根记录的原生渲染错误。原 driver 同帧投递鼠标移动/按下/释放且没有 GUI warp，不能以“已发送点击”当作业务生效。

修稿统一 pilot 与后续菜单的异步真实输入投递：先 Input.warp_mouse(final_transform×logicalPoint) 和 MouseMotion，再下一帧按下、下一帧释放、下一帧观察；滚轮也成对释放。pending 锁防止尚未投递完就点击另一个控件，代次取消与退出释放保留鼠标/键盘中断安全。GUI 选择、应用、分页、出营、标题继续均依据真实 Control/selected_character_id/active_character_id/session_started 状态推进，click 返回只代表排队，不记通过。LineEdit 先观察实际焦点，再逐帧投递 Ctrl+A、退格、unicode 和 Enter；未获焦点不会直接赋文本。日志记录命中控件路径/逻辑位置、实际角色/焦点/分页和应用资格，帮助下一轮区分输入未命中与业务拒绝。

修稿源码 SHA256：B14A90D0ECBA841AE370F31F2EEA1662427D55374410099473D4046A52DC30CE。固定 Godot 4.7.2 check-only 实际退出0，日志 artifacts/character-driver-click-delivery-check-only.log；未执行全局导入、MCP或GPU。此修订当时尚待根的新独立冷启动运行，不能从 check-only 推断真实 GUI 或疗愈者已通过。另有独立 owner 将构筑时钟刷新改为仅更新冷却 Label，解除其与 SpinBox 文本更新的耦合；校正 Godot SpinBox deferred focus/Enter 的等待时序后，旧路径也通过真实控件回归，未证实“旧时钟覆盖输入”的业务 red，不由本 driver 修改产品代码。

后续真实冷启动 fresh-editor-run1 已记录在同目录 fresh-editor-run1-character-input.json：两次盗窃者收益、GUI 疗愈者切换、键盘 vitality=1 草稿与应用（maxHP127）、疗愈者3命名预设、真实敌伤后的T自疗/扣35体力、暂停2真实秒冻结都已实际观察。随后标题存档比较误报：实际内存/保存的共享CD仅约3.55e-15浮点往返差异，JSON schema_number 与内存整数类型不同。该旧 report 的 error 仍保留，不改写为整条流程通过；继续/真实死亡未到达，新的原生渲染错误也由根保持开放。

观察器修复后的源码 SHA256 为 B0851EA45DB1787581019833110F877677439C2CFFC74484733E49CCDCCD6AF4。暂停同内存 snapshot 保持严格相等，仅保存/重载改递归 JSON 数字语义比较：完全相同 String 键/结构、schema 整数值精确、非数字类型不互换、所有数字finite；一般浮点绝对误差最多1e-9。继续后不使用固定宽松时间窗口，预期整份八CD/三效果仅推进 driver 实际累计的未paused且session_started帧delta；pending GUI 投递期间也计数，离线/标题/暂停墙钟不扣CD。

固定 Godot check-only 退出0（artifacts/character-driver-json-check-only.log）。另有独立 headless QA 比较器回归以该真实冷启动暂停checkpoint及根观察的一ULP表示差异为依据，24断言全部通过（character-driver-json-probe-result.json）：旧严格比较误判可复现、新数值比较接受；清空/重置CD、缺/多字段、分数/未来schema、bool/string混型、NaN/Inf和超1e-9误差仍拒绝；按游戏帧推进与效果过期计算可验证。它是观察器回归，不计入GdUnit测试数量，也不能替代新的真实GUI继续/重启/死亡验收；没有编辑产品业务代码、全局导入、GPU或MCP调用。
