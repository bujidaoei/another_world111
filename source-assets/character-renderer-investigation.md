# 新蒙皮角色与 Mobile 原生错误只读调查

2026-10-13。BUG-112-01 仍开放。根代理报告新 MCP run13 出现 `ParticlesStorage::particles_get_instance_buffer_motion_vectors_offsets` 的 cpp759 原生错误，后确认该 run 3 次；同一生产源码的独立冷 Mobile/Vulkan 完整60秒、两次真实远征、14,318帧与正常生产退出则没有 ERROR / 资源泄漏。资产代理已读取 `artifacts/003-cold-mobile-two-runs.log` 复核其开始/完成、done/completed_runs=2 标记；不将冷进程成功覆盖 MCP 失败，也不由帧总数推断性能预算通过。

最初只读阶段没有改 game、模型或源资产，没有使用 Godot MCP、GPU、Blender 或 Comfy；仅读取固定源码、运行纯 headless 资源属性检查，并在 artifacts 准备独立诊断项目。随后根已逐轮授权独立GPU对照，实际结果见本文后续段落，不能把初始阶段声明误读为整轮从未运行GPU。既有renderer调查为 `specs/002-singleplayer-prototype/evidence/2026-10-13/renderer-error-investigation.md`。

## 直接可见事实

actual imported 的旧 survivor、新 thief/healer 与两阶电枪已用固定引擎逐 MeshInstance3D 读取属性。新角色各1网格、1surface、17skin bind；旧角色没有skin。材质旗标一致：StandardMaterial3D、transparency=0、alpha=1、billboard=0、particle_trails=false、next_pass=false；GeometryInstance透明度0、无material override、shadow=1、lod_bias=1。所有这些角色/武器都非camera_occluder。完整属性证据为 `evidence/character-native-material-flags.json`。

这次属性检查是 headless 真实资源读取，没有取得运行时 C++ base_flags、owner指针或错误RID。当前 Fader 只在 world 下的camera_occluders建立稳定私有透明材质，对角色未执行该流程；不能凭静态属性排除未观察的运行时资源状态。

## 固定提交路径

重复验证既有官方 archive SHA256 `e607e9985e1c201bc9cdc1aec8a120f0c3f53b9603f1f828e2b748534a2471ef` 后，只安全提取10个 scene/animation/material 原始文件（388,584 bytes）；manifest在 `artifacts/skin-renderer-research/official-scene/manifest.json`。提交是 `ed1daf0bf001b61586d9930840f2f1394092c079`；既有310个servers/rendering源码也按此提交核查。没有全引擎内存安全证明。

- [MeshInstance3D设置mesh](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/scene/3d/mesh_instance_3d.cpp#L134)把 mesh RID 作为 base；[绑定骨架](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/scene/3d/mesh_instance_3d.cpp#L204)使用独立的 instance_attach_skeleton，未替换 mesh base。
- [SkinReference注册](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/scene/3d/skeleton_3d.cpp#L1027)创建独立 skeleton RID；[pose上传](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/scene/3d/skeleton_3d.cpp#L405)走 skeleton_bone_set_transform，MeshStorage更新骨架自己的数据/dirty队列，没有发现particles-owner操作。
- [CPU几何骨架setter](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_geometry_instance.cpp#L33)只改独立 data->skeleton 并标脏。[base分类](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/storage_rd/utilities.cpp#L54)先用mesh owner确认INSTANCE_MESH，particles owner独立。
- [Mobile更新](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp#L3152)先清base_flags；PARTICLES bit11只在base_type=INSTANCE_PARTICLES分支设置。合法蒙皮依旧走[INSTANCE_MESH skeleton uniform set分支](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp#L3198)，不置PARTICLES位。
- 材质particle_trails是shader render-mode/surface cache旗标，和 CPU geometry base_flags 分属不同字段。当前角色该功能关闭；透明队列、骨架变形或AnimationTree名称本身不能解释CPU PARTICLES位为何置位。
- [错误调用条件](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp#L2653)是surf->owner的CPU base_flags含PARTICLES；[cpp759](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/storage_rd/particles_storage.cpp#L757)是给定RID的particles_owner查询为空。函数名不能说明“骨架运动矢量buffer缺失”。

**结论限定为静态正常路径：没有找到合法skin、AnimationTree或当前材质直接置PARTICLES的代码链。** 缺少错误时owner/baseRID/flags/栈，不认定它是蒙皮缺陷，也不认定热重载、材质或引擎内存状态是根因。精确函数名与Skeleton/AnimationTree组合的官方仓库网页检索本轮没有匹配结果；这也不能证明所有官方问题不存在。没有找到可据此采用的已修版本，不自动升级/降级或更换renderer。

## 可验证对照

独立项目 `artifacts/skin-renderer-probe/` 复制生产真实GLB、配置和CharacterAnimator，保存输入hash清单；无Main/MCP/autoload/存档、世界、Fader、雨、MultiMesh或native particles。准备阶段仅执行headless import、check-only以及0.1秒skin_tree配置执行；frames=0，这些只验证探针可执行，不是原生GPU复现。后来获授权的实际GPU执行另列，未混用headless报告。

建议根代理先完成冻结源码的新MCP会话真实两角色/两远征流程，同样保存失败与正常退出事实，再在GPU空闲时逐冷进程进行60秒最小矩阵：

| 组 | 唯一被比较的关键变量 / 限制 |
| --- | --- |
| skin_unbound vs skin_bind | 同新网格/材质；诊断实例解除skin绑定 vs 保留真实17bind且不播放。 |
| skin_bind vs skin_player | 保留同一skin；静止 vs 真实Walk由AnimationPlayer单独播放。 |
| skin_player vs skin_tree | 同skin动作；AnimationPlayer单写 vs 原生产AnimationTree单写。 |
| 后缀_lifecycle | 每5秒detach+queue_free再重建；新角色thief/healer交替，检验资源退休条件。 |
| skin_tree_alpha(_lifecycle) | 首次显示前安装私有透明材质，之后只改alpha；诊断材质队列交互，不是产品补丁。 |
| old_bind / old_lifecycle | 旧survivor历史对照，几何和网格数不同，不能当作纯skin开关。 |

相机运动、整体角色移动、光照、阴影、地面、电枪、renderer/msaa和观察时长统一。synthetic矩阵没有战斗奖励/资格/完整世界，不替代正常游戏。每组报告frame/time/generation以及实际VisualInstance、mesh、SkinReference骨架、material RID；完整stdout/stderr和退出事实仍须根真实启动后保存。脚本中初次误用Skeleton3D.get_skeleton被实际源码纠正为mesh.get_skin_reference().get_skeleton，headless重新执行无SCRIPT ERROR，没有把失败算成功。

冷全流程成功说明新skin/Tree在该暴露量下并非必现；若freshMCP仅在同编辑器流程失败，应继续记录资源创建/重建和实际运行窗口，不能仅凭“冷成功/热失败”归因。若任一最小组复现，必须在精确提交的开发符号中于Mobile2653/Particles759记录p_pass_mode、frame、surf/owner地址、base_type、base_flags、baseRID与各owner注册状态和C++栈，映射报告RID。材料alpha变化、动作关闭或错误过滤都不构成针对性修复证据。

## 新增：实际 GPU 顺序对照

随后根已授权资产代理独占GPU，完整顺序执行两组独立冷进程各60秒。当前旧editor进程仍存在，但根无运行游戏并仅执行headless/文件工作。独立探针使用Console4.7.2、Mobile/Vulkan1.4.312、Windows display server、RTX4060 Laptop GPU；禁止把这两个结果换算成性能通关。启动参数、PID、源脚本hash和原始stdout/stderr全部留存，未过滤原生错误。

| 组 / 实际原始目录 | 观察与实际资源证据 | 正常退出 / 错误 |
| --- | --- | --- |
| skin_tree_lifecycle / `artifacts/skin-renderer-probe/runs/skin_tree_lifecycle/c67430b0f0974630862fcd51f31bf6be` | 60.001381s，14,368绘制帧，11次重建，12代实例，84份RID采样；首次角色17bind且有非零SkinReference骨架RID，电枪无skin。 | exit0，stderr空，native/script/cpp759均0。 |
| skin_unbound_lifecycle / `artifacts/skin-renderer-probe/runs/skin_unbound_lifecycle/78d7e7882fff47c196675f2bf1107e9e` | 60.004164s，14,369绘制帧，11次重建，12代实例，84份RID采样；首次角色/电枪skin均0，骨架RID均0。 | exit0，stderr空，native/script/cpp759均0。 |

实际摘要、报告和两组完整日志副本在 `evidence/skin-renderer-native-pair/`，comparison.json包含逐文件SHA。两组新thief/healer均按同一5秒周期交替，shadow/ground/camera/整体运动/weapon保持一致。Tree组实际存在AnimationTree，Unbound组无动画运行。没有执行old_bind，因为两组都未复现，追加一个几何不同的旧角色对照目前不能辨别这次缺陷。

这支持“孤立skin+生产Tree+合法节点退休重建在本观察量下未复现”，**不排除完整世界、远程调试、帧读回或其它未隔离的交互条件**。同一冻结757个game文件的MCP run15仍由根确认5次cpp759，且静态世界/GUI观察期也出现；运行中源热重载不是该轮的必要条件。该MCP失败保持原记录，不因最小对照无错关闭BUG-112-01。

## 插件 / 编辑器启动路径只读核查

本机GodotAI4.3.0实际代码：project_handler.gd:292调用EditorInterface.play_main_scene；不自行spawn另一renderer，也未找到设置嵌入、motion-vector或PARTICLES旗标的调用。它围绕play临时控制自动保存并暂停MCP连接处理，以避免保存缩略图的重入；不说明当前原生错误来自这个路径。

同一固定archive补提6个editor启动文件和5个embedding/scene-debugger文件，分别211,062 / 152,057bytes，均重新匹配原archiveSHA，manifest在 `artifacts/skin-renderer-research/official-editor/` 和 `official-embedding/`。

- [EditorRun::run](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/editor/run/editor_run.cpp#L49)通过OS.create_instance建立独立游戏子进程，加入--remote-debug及--editor-pid；还可转发renderer等project范围CLI参数、调试显示、断点和window placement。child实际命令行与active debug状态应单独记录，不能仅凭编辑器显示或默认renderer推断。
- [game_embed_mode定义](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/editor/settings/editor_settings.cpp#L1100)中0是Use Per-Project Configuration。本机保存设置确为0；project_metadata的game_view没有embed_on_play键。[GameView默认读取](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/editor/run/game_view_plugin.cpp#L1177)该键默认true，make_floating_on_play也默认true；实际旧editor内存状态/嵌入能力未由只读文件证明。
- [嵌入child参数](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/editor/run/game_view_plugin.cpp#L1271)仅当对应条件成立替换position/resolution/screen并加--wid；Windows不是无条件--embedded（该参数在源码为macOS条件分支）。因此新运行应读真实PID/commandline/尺寸与窗口状态来确认。
- GameHelper在游戏子进程_ready注册EngineDebugger、OS Logger；PROCESS_MODE_ALWAYS只保持日志和liveness，在debugger inactive时清掉未消费队列。正常逐帧没有更改renderer或粒子类型；截图请求会在游戏自己的viewport上执行get_texture().get_image()和编码，该路径与从不读回的最小探针不同，但未证明它致错。
- GameLogger `_log_error`接收原生location/type并转发；debugger_plugin._on_log_batch将其加入游戏buffer。editor_handler._get_game_logs的data.lines是该buffer；独立editor_errors_count/editor_errors_hint可能另附在响应，不能混同原始game lines。新的MCP对照应同时保存run_id、game lines和editor scope，确认错误所属进程。

不同OS进程有独立C++地址空间。即使旧Editor私有资源缓存异常，不能据此声称其直接污染child私有owner/flags；可能影响启动输入、共享缓存文件、GPU环境或运行消息的哪项仍需实验。当前只读检查没有根因证明；未修改插件、settings、game或原模型，也未用隐藏原生错误、禁调试等方式宣称修复。

## 更新：项目禁嵌入与完全独立 Main 均复现

根随后实际执行项目单键禁嵌入对照与恢复，不再只是准备方案。已读取正式证据 `specs/003-character-builds/evidence/2026-10-13/native-character-contrasts.md`：

| 根实际组 | 冻结/进程/覆盖事实 | 原生结果 |
| --- | --- | --- |
| 禁嵌入MCP / r26973-1 | 事务0424b26060044ef39de370ff5b1c6d9d，原项目键缺省→false，global0不变；Editor48032/child76496有remote-debug、无--wid；1280×720窗口、1600×900viewport；56.108611秒完成8项真实输入覆盖，1755个game文件（排除.godot）Changed0。 | GameLogger cpp759两条；不是clean gate。实际production_request_quit及editor正常quit后恢复原键缺省；新child --wid恢复验证仍由根后续记录。 |
| 完全独立cold Main / 最终角色driver | console58624/GUIchild35440，无Editor、remote-debug或wid，EngineDebugger.active=false；相同QA Main/最终driver、窗口/viewport/renderer；8覆盖均true，57.133796秒启动到退出请求，13,570绘制帧，production_request_quit及console exit0。 | stderr cpp759一条，script ERROR0；exit0没有覆盖原生失败。 |

因此“嵌入、MCP或远程调试是错误的必要条件”已被这些对照否定。先前两盗窃者远征60秒无错与两个孤立skin组无错覆盖较窄，不能覆盖后续疗愈者/构筑/完整场景流程；单变量禁嵌入协议保留为已执行实验的准备记录，不再作为当前优先修复建议。更早freshEditor59216 run1最终7条、run2最终1条也由根保留失败；不再把单次cold成功推为Editor生命周期归因。

## 更新：原 Player 预检与视觉提交实际最小组

按根新授权，以生产原Player/30个依赖和资产的逐文件hash副本运行独立 `actual_player_reconfigure`，没有业务源码修改。独立headless import和check-only先严格exit0 / ERROR0。随后GPU冷进程PID63828使用Mobile/Vulkan1.4.312、RTX4060 Laptop、Windows display server，60.000000秒、14,355绘制帧、原_ready一次初始化与11次完整configure_visuals预检/提交、交替两角色；输入副本前后Changed0，正常exit0、stderr空、native/script/cpp759均0。

原始目录 `artifacts/actual-player-renderer-probe/runs/actual_player_reconfigure/4c0af54f030c4ca3b90e2268016d4e5d`；完整启动参数/源SHA、日志、RID和summary副本保存在 `evidence/actual-player-native-reconfigure/`。每次原configure_visuals确实执行双角色与双武器instantiate/inspect/free，并保持实际17bind蒙皮与Tree；无假接口。合成整体移动/动画速度用于渲染暴露，未经过真实PC输入、World/Fader、GUI、自疗实际施放或战斗，不能列为这些功能验收。

这次孤立原Player预检/free与替换未复现，不能据0错误认定具体错误来源或关闭BUG。下一步应在已复现完整冷Main上隔离实际共同触发阶段或取得C++owner/base_flags观测；新增无关最小测试不会自动提供flags写入证据。
