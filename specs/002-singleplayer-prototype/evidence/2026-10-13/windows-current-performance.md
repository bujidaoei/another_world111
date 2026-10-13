# TEST-115：冻结002生产构建与真实Mobile/Vulkan采样

关联TASK-115、NFR-101/102、AC-109/110；本轮技术证据通过，TASK-115整体及设备/真人/长稳门槛保持开放。

生产快照 `artifacts/builds/abd86f0482134dd18b8553c77d5806e2` 严格通过。来源是先冻结的e0f1715368644e8f8e22b109446d0014源清单：278文件逐一核对原SHA256后重建verified-source，再完整import/export；未取随后003新增代码。root后来只规范化game_session和输入driver结尾，当前物理源码字节与冻结产物区别如实保留。原开发project.godot SHA256为2058010191612F83202FB8A8D6BCB5C398B872E3ABA8601A8F4FFBBF9307C1DD；只清暂存debugautoload及editor plugins。Godot固定4.7.2.stable.official.ed1daf0bf，import2.898101秒、export2.716848秒。

EXE109,171,712B，SHA256 `50FA1736CBEEF195857D62BDFB87BFAF1070F0C2D667028F4D5BFF443631B51B`；PCK2,552,228B，SHA256 `2C6AA3FCF54EE79BEC8D8357FC2A6C1EB236827203C96A2049DE340A71A6CAEE`。282包文件MD5/范围/路径、project.binary和compiled脚本debug标记排除检查通过；GodotAI/GdUnit/tests及测量脚本不在生产包。ZIP41,193,213B，SHA256 `E7BAF10E17E869453D8419FB1357ED87A55CF87763139CCF773243331E64D49D`；7个分发条目重新读取并与目录SHA256全匹配。许可和原创来源已随包分发。本地未签名原型，不是商店发行。

启动烟测仍只是离屏640×360 Compatibility/Dummy。工具最初枚举到GL辅助窗口，8个ObjectDB警告导致严格失败；已按exact PID和主窗client矩形选择真正Engine窗口，保留窗口类/标题/尺寸日志。冻结EXE独立verbose探针及正式重导烟测均经真实WM_CLOSE、正式异步关闭exit0且零ERROR/ObjectDB/RID；没有屏蔽警告。另一次冷clone import在palette纹理处重复reimport，300秒超时被严格拒绝，原记录在58cf8a149780402d9db210e173f8d3b7，根因仍未确定。其后的全278原字节重建独立import2.9秒通过，不能把失败记录改写成功。

正式性能目录 `artifacts/performance/9dd871aca9fb458c887d80d4fca8945f`。准确方式为“release运行模板／同生产游戏资源的QA测量包”：EXE与生产相同，仅project.binary的两个启动项和全局类缓存改变；280/282游戏packed资源逐字节一致。外置SceneTree、启动场景、真实InputEvent driver与logger适配不进入分发包；无授予金币、直接杀怪或瞬移。独立APPDATA/LOCALAPPDATA/存档。parent停止live游戏，未与Comfy推理/Blender渲染争用GPU。

真实设备i9-14900HX、24核心32线程、RAM34,141,495,296B、Windows11 build22621、RTX4060LaptopGPU、驱动32.0.15.8115。Godot Windows display、release=true/debug=false、Mobile/Vulkan1.4.312；62次Win32物理client检查1920×1080、visible=true/minimized=false、DPI144。240Hz显示，VSync enabled，Engine.max_fps=0。稳定后viewport texture仍2304×1296：这是1080p客户端窗口下当前生产缩放设置的实际渲染尺寸，不称1080p raster，不降低质量或按比例外推。

5秒warmup＋60.009081秒取样，14,389帧间隔，与Engine实际帧计数对应；4次真实完整战斗/采集/目标/撤离/区域重建/存档结算。Time.get_ticks_usec相邻process_frame最近秩P50/P95/P99为2.641/8.310/11.371ms，最大20.232ms；>33.33/50/100ms均0。OS PeakWorkingSet905,555,968B（约863.61MiB），100ms采样峰905,400,320B；GPU timestamp P95 2.060ms，viewport CPU P95 0.314ms，draw calls峰285，Godot视频分配峰174,224,928B。release静态内存debug-only，报告null；Godot视频分配不是独占显卡驱动总显存。process/physics monitor是前约一秒窗口最大值，并非逐帧CPU时间。

wrapper严格通过：exit0、forced_termination=false、runtime_errors=false；stderr为空（仅换行）、未见particles null、ERROR、ObjectDB、resource/RID leak。正式AWGameSession._request_quit先保存/停音频再等待退出；没有用--quit-after绕过生命周期。

本目录保存small summary、构建hash/源清单、包差异audit、hardware/window记录和stderr；全部帧间隔、RSS样本、输入覆盖及完整日志在上述artifacts目录。60秒代表场景通过不能代替2小时热稳定、全部成败恢复、真人体验或Android/物理手柄验收；不标整项TASK-115/117完成，不宣称商业品质。

同一Windows冻快照已于本轮真实导出Android development debug APK：artifacts/android-builds/1ef7c968909e490ba9edac9812417623，30,518,401B，SHA256 `988449713942A4D23763657BF01699F997D4B6A8D9D2914DEAA9FFDD5206F55E`。原local DPAPI/RSA开发签名v2/v3验证通过；AAPT2实际package org.anotherworld.prototype.dev、min24/target36、debuggable、arm64，零uses-permission。382 ZIP条目CRC全有效、284Godot assets无debug/test/helper/key；仅arm64两native库。small签名/manifest/verification在本目录，APK/key没有复制进仓库。未安装或启动手机，仍非设备或商店验收。
