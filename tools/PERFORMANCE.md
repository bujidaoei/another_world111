# Windows release 渲染测量

`run_perf.ps1` 对 `export_game.ps1` 已通过并有哈希记录的 Windows 构建运行真正的 Mobile/Vulkan。运行在当前 Windows 电脑的 1920×1080 可见窗口，必须非最小化；测量前停止其他游戏渲染与资产渲染任务，保留编辑器连接。

```powershell
./tools/run_perf.ps1 -BuildDirectory <artifacts/builds/构建ID> -GodotExecutable $env:GODOT_BIN -PrepareOnly
./tools/run_perf.ps1 -BuildDirectory <artifacts/builds/构建ID> -GodotExecutable $env:GODOT_BIN
```

官方 4.7.2 release 模板禁用了 `--script`、`--path` 和 `--main-pack` 路径覆盖。工具复制原 release EXE，并在独立 QA PCK 中只修改 `project.binary` 的 `application/run/main_scene` / `application/run/main_loop_type`，以及全局类缓存中外置 SceneTree 的注册。非空main_scene是引擎启动要求，指向包外qa-main.tscn启动壳；外置主循环随后移除该壳并装配生产main scene。`audit_perf_pack.py` 校验两包 MD5、路径集合、游戏资源逐字节 SHA256 和所有其他 project setting 的原始 Variant 字节一致。原分发 EXE/PCK/ZIP 不修改；报告名称为“release 运行模板／同生产游戏资源的 QA 测量包”。测量脚本、原输入驱动和日志继承适配在包外，以 SHA256 固定。适配仅将驱动日志留在内存，避免原开发驱动写 `res://../artifacts`；动作、寻路和业务行为继承原驱动。

外置主循环实例化生产 main scene，先指定独立存档目录，再加入 SceneTree；进程独立 APPDATA/LOCALAPPDATA 隔离 Godot 数据与着色器缓存。只经真实 UI 命中和 InputEventKey/MouseMotion/MouseButton 启动新旅程、移动、瞄准、攻击、真实采集与撤离，重复至少两次。不赋予经验、战利品或伤害。测量排除 5 秒热身，至少 60 秒，继续至至少两轮击杀、目标采集、结算与区域重建完成；600 秒未满足覆盖或驱动失败则报告失败。正常关闭调用生产 `_request_quit()`，等待生产存档与音频生命周期；异常超时时发送真实 WM_CLOSE，强制终止另行记录且不能通过。

每帧 `Time.get_ticks_usec()` 的实际间隔记录 P50/P95/P99、最大值和 >33.33/50/100ms 长帧，并保存完整原始间隔及分阶段统计和Engine frame计数。Performance 的 process/physics、draw calls、objects、primitives、视频/纹理/缓冲分配量，以及 viewport CPU/GPU 渲染计时同步采样。部分 Performance 项刷新慢于帧，不能把重复观测当成独立测量；MEMORY_STATIC/STATIC_MAX 在 release 不可用，固定为 null，GPU 无正值也为 null。视频分配量不是整卡实际物理使用量。PowerShell 每约 100ms 采样进程工作集和 private bytes，另记录 OS 原生 PeakWorkingSet。每秒独立 Win32 GetClientRect/IsIconic/IsWindowVisible 验证实际 1920×1080物理client size；临时设置调用线程PerMonitorAwareV2，读取后恢复，避免Windows显示缩放虚拟化。

报告记录原构建、QA PCK、外置脚本 SHA、固定引擎版本、Vulkan/GPU 实际名称和 API 版本、VSync、屏幕和 viewport 尺寸、CPU/RAM/GPU 驱动/OS 与并发渲染程序。原始日志、输入状态和结算记录、窗口检查、进程采样及全部哈希保存在 `artifacts/performance/<ID>/`，无零帧或无覆盖的成功结果。

QA 驱动、测量与 GPU timestamp 有额外开销，报告不扣减、不推算；短时间 PC 结果不等于两小时热稳定、Android 真机或商业品质验收。冻结旧构建只验证机制，更新生产构建后必须重测，不能引用旧包数值验收新版。

API/格式依据：[4.7.2 main.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp)、[ProjectSettings binary reader/writer](https://github.com/godotengine/godot/blob/4.7.2-stable/core/config/project_settings.cpp)、[Performance](https://docs.godotengine.org/en/stable/classes/class_performance.html)、[RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html)。运行前以固定 4.7.2 引擎的实际 method list 验证 viewport/rendering adapter API。
