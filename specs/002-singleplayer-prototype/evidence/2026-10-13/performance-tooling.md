# TEST-115：真实 release 渲染测量机制与旧包失败证据

关联 NFR-102 / AC-110 / TASK-115。测量工具已实现；新版性能与稳定性验收保持开放。

使用 performance-optimization Skill，固定 Godot 4.7.2 实际 API 与官方源代码确认 release 模板不接受 CLI 路径覆盖。`tools/run_perf.ps1`、`measure_game.gd`、`prepare_perf_pack.gd`、`audit_perf_pack.py` 与 `PERFORMANCE.md` 构成独立 QA 管线。工具生成复制 EXE＋QA 启动 PCK；263/265 packed资源与生产逐字节 SHA256 一致，仅项目启动二键与全局类缓存对应两文件不同。外置 SceneTree、启动场景和真实输入驱动都未进入分发包，生产 EXE/PCK/ZIP 未修改。准确名称为“release运行模板／同生产游戏资源的QA测量包”。

真实旧包 `artifacts/builds/170f92b3ab4f42a88b8be23a494e7a23`：EXE SHA256 `29F45F851A2CE5BEDA1F10CCE547E01D7D24AC751D50B9B38378C18CB08600A6`，PCK `D397CFBB434BBC4A6C5DA6FC270142A836B12C128D5553C87C8CF1967E8B3694`。这不是随后偏好/场景/气候更新的构建，不能代替新版结果。

现场协调：root停止live游戏，保留编辑器/MCP；Blender/Comfy没有并行渲染/重推理。CPU i9-14900HX、24核心32逻辑线程，物理RAM 34,141,495,296B，实际 Vulkan 1.4.312／Forward Mobile／NVIDIA RTX4060LaptopGPU，Windows11 build22621，NVIDIA驱动32.0.15.8115。进程独立APPDATA/LOCALAPPDATA与存档目录。Win32在临时PerMonitorAwareV2线程上下文下读取物理client，随后恢复调用线程上下文；63次真实检查全部1920×1080、visible=true、minimized=false、DPI144。

完成5秒热身＋60.014379秒取样，共14,396实际process_frame间隔、4次经UI/InputEvents新档战斗/采集/撤离/区域重建/存档结算。P50/P95/P99为3.986/7.729/8.721ms，最大20.896ms，>33.33/50/100ms均0。OS PeakWorkingSet899,907,584B；viewport GPU计时P95 1.325ms，draw calls峰273，Godot视频分配峰459,609,760B。static memory在release不可用，报告null。Performance process/physics是引擎延迟刷新的原始monitor，不能仅凭其值推断单帧CPU瓶颈。初版viewport texture尺寸在热身前读到2304×1296，不能将其当成稳定后实际渲染分辨率；工具已补充热身后尺寸和engine_frame计数，等待新版真实复验。

**本轮失败，不能标clean验收。** 实际stderr有 `particles_get_instance_buffer_motion_vectors_offsets` 的null参数ERROR及7个Texture RID泄漏。wrapper初版还把正常结束窗口销毁而进程仍退出的短暂阶段误判无窗口；已经修为有最终测量报告后仍等待正常exit且保持ERROR/ObjectDB/Resource/RID泄漏门禁。该修正尚未用新版实际运行验证，原失败summary完整保留，没有改写成功。首次空main_scene启动错误与一次DPI虚拟化的1280×720探针也保留在artifacts/performance，不作为测量成功。

原始完整采样目录：`artifacts/performance/7194fe1c0fca423e85f991211802675b`。本目录复制 `performance-old-build-summary.json`、`-stderr.log`、`-hardware.json`、`-pack-audit.json`、`-window.json` 保持证据可追溯。runtime原日志/全部RSS样本/外置驱动源码及哈希在原目录。

固定4.7.2 main.cpp进一步确认TIME_PROCESS/TIME_PHYSICS_PROCESS是上一个约1秒窗口的最大值，并非每帧CPU值，因此会大于多数实际帧间隔。工具已明确命名process_peak_1s_ms/physics_peak_1s_ms并每秒采样一次；GPU/viewport CPU继续逐帧采样。旧证据的process_ms字段保持原样，不改写历史。

后续必须使用全部当前代码测试通过后新导出的production构建再次运行；帧计数、热身后viewport尺寸、正常close、所有ERROR/泄漏均真实复验。此短期PC原型结果不代表2小时热稳定、真人体验、Android真机、商业品质或完整游戏验收。
