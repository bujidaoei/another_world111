# BUG-112-01 渲染空粒子RID调查

2026-10-13；状态仍开放，根因未证实。此记录区分根任务实际Vulkan执行与代理只读研究；代理未启动GPU、未使用Godot MCP、未修改game。统一GdUnit104/104是其它技术证据，不能覆盖此原生渲染缺陷。

## 当前实测矩阵

固定Godot4.7.2.stable `ed1daf0bf001b61586d9930840f2f1394092c079`、Mobile/Vulkan1.4.312、RTX4060 Laptop，独立存档和真实InputEvent两次远征；实验副本移除表现只用于诊断，不是产品修复。

| 根执行 / artifacts日志 | 暴露量 / 结果 | 能说明的边界 |
| --- | --- | --- |
| render-probe-multimesh.log | 256实例含阴影，1151帧，相关错误0 | 正常孤立MultiMesh没有必现。 |
| render-probe-rain.log | 当前ShaderRain，1174帧，相关错误0 | 当前雨shader孤立运行没有必现。 |
| render-probe-world.log | 原创WorldBuilder，1155帧，相关错误0 | 孤立静态世界没有必现。 |
| render-probe-world-rebuild.log | 根记录4次重建、1133帧，相关错误0 | 单独世界重建没有必现；不能直接归罪queue_free。 |
| render-probe-full.log | 14328帧、真实2远征，cpp759错误2 | 完整流程仍复现。 |
| render-probe-full-no-effects.log | 14335帧、真实2远征，cpp759错误2 | 关闭运行特效未消除。 |
| render-probe-full-no-rain.log | 14321帧、真实2远征，cpp759错误2 | 关闭雨未消除。 |
| render-probe-full-no-occlusion.log | 当前已结束日志14333帧、真实2远征，相关错误0 | 相同范围本次禁遮挡渐隐不复现；应继续隔离Fader操作，不足以确定根因或长期关闭。 |

旧release性能失败日志仍保留：`artifacts/performance/7194fe1c0fca423e85f991211802675b/runtime.stderr.log`。其中7个Texture RID泄漏是另一个BUG-115-01，不和本空粒子RID混同。MCP run11/run12错误次数由根现场记录，冷CLI文件为本矩阵的独立可复查依据；不得过滤引擎错误或改日志级别报通过。

## 固定源码事实

官方提交的完整`servers/rendering`310常规文件安全提取并检索；原归档71,921,164bytes，SHA256 `e607e9985e1c201bc9cdc1aec8a120f0c3f53b9603f1f828e2b748534a2471ef`，检索证据在`artifacts/renderer-full-ed1daf0bf001b61586d9930840f2f1394092c079/search-summary.json`。该范围不含drivers/scene；没有宣称全引擎所有内存写入均已证明。

- [ParticlesStorage.cpp:757](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/storage_rd/particles_storage.cpp#L757)：输入RID查particles_owner为空就触发759；表示对象查找失败，不是“运动矢量buffer没有生成”。
- [Mobile.cpp:2653](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp#L2653)：pipeline有效后查CPU base_flags；有PARTICLES位查ParticlesStorage，否则MULTIMESH位查MeshStorage。此段并未只限运动矢量pass，单关运动矢量不能据此保证绕过。
- [Mobile.h:454](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.h#L454)：PARTICLES位11、MULTIMESH12、COLOR14、CUSTOM15；[更新:3152](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp#L3152)先清0再按base_type赋位，仅粒子类型分支置PARTICLES。
- [共享几何setter](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/renderer_geometry_instance.cpp#L92)：layer_mask、shader_uniforms_offset、材质引用各自独立字段。全量base_flags赋值25处含默认1、Mobile12、Clustered11、CopyEffects无关局部变量1，没发现这些正常setter串写PARTICLES。surface pass flags与geometry base_flags是不同字段，不能因某位数值相同就视为类型混用。
- motion offsets全域只有声明/定义/Mobile/Clustered各一处；Canvas无此调用。透明shader只改变surface队列，不能从静态源码推出它必然把MultiMesh改成粒子。

本地23个GLB JSON解析：skins全部0、材质alphaMode全部OPAQUE；三角色有节点动画，不能把当前资产当skinning场景。证据`artifacts/renderer-glb-inspection.json`。当前Torus/Cylinder运行特效也是opaque MeshInstance3D，Fader、雨和湿面才包含透明相关路径。

## 官方问题记录边界

[PR65833](https://github.com/godotengine/godot/pull/65833)历史上区分实例化粒子与MultiMesh，修的是粒子误查MultiMesh；[PR100283](https://github.com/godotengine/godot/pull/100283)引入Mobile运动矢量；[PR109556](https://github.com/godotengine/godot/pull/109556)修previous-frame矩阵；[PR108664](https://github.com/godotengine/godot/pull/108664)修透明pass运动矢量输出。它们不能作为当前particles-owner查空的已修证据。[Issue122005](https://github.com/godotengine/godot/issues/122005)需要GPUParticles、报失效uniform set，与当前函数空对象也不能直接等同。尚未找到可匹配的官方修复版本，不因此自动升级/降级。

## 下一轮判别与关闭条件

### CR-005实际修订与局部回归
在两个角色/场景规则完全相同的冷进程对照中，仅去除Fader材料替换路径后60秒两远征无错；noRain/noEffects仍各2错误。当前实现将该区域所有可遮挡网格材质在首次绘制前建立为独立实例，之后只更新该材质的alpha值；不反复替换/还原surface材质。旧区域先detach，然后清空fader缓存，材质随区域节点释放，避免对退休网格继续写材质。

新增两个真实GdUnit回归：40次淡入淡出保持材质身份、共享源材质不变；旧区域退休再绑新区的引用与新透明度正确。统一106项全部通过，[XML](gdunit-unified-106.xml)。修订后冷完整原生Mobile/Vulkan运行60秒、14,323帧、两次新档合法远征完成，正常退出0ERROR/0资源泄漏，[运行log](renderer-cold-lifecycle.log)。这不是release性能分位或真人体验，禁止用帧数推断稳定FPS预算已验收。

这为游戏层可重复触发路径和针对性资源生命周期修订提供证据；没有C++断点数据，不宣称已证明flags的具体错误写入点。生产包/更长完整晋阶及相机来回遮挡回归仍继续，未由单次短运行关闭整个TASK-112/114/115。

依据no_occlusion区别点，先在独立副本复测两远征，再拆分Fader的prepare安装surface override、逐帧albedo alpha变更、restore移除override三操作；对照保留材质只作颜色变化、仅反复安装/移除override，并包括节点退休时的清理。所有对照保持伤害/奖励/输入、观察时长和资源构造相同，不以禁效果作为最终修复。

如仍不能确定，需要固定提交开发符号构建或调试器在Mobile2653/Particles759记录`p_pass_mode`、frame、surf/owner地址、base_type、base_flags、base RID、ParticlesStorage和MeshStorage的owner注册状态、C++调用栈，并映射实际GeometryInstance实例RID与mesh/multimesh base RID。GDScript的节点类型与shader编译成功不足以给该C++参数定责。

只有重现→根因→针对性修复→原问题与相关真实完整流程回归→当前release正常退出/性能记录全部对应，才关闭BUG-112-01。当前保留开放缺陷checkpoint，003的独立角色/规则实施继续，不伪称002渲染/商业品质验收通过。
