# 固定源码原生诊断运行与官方对照

2026-10-13，关联 BUG-112-01 / TASK-222。**官方固定引擎在冻结完整 Main 副本仍实际复现两条 cpp759；现有 O0 诊断引擎完整一轮没有复现，尚未取得 owner/RID/flags 根因证据，缺陷与资产品质门槛继续开放。** 不改生产 game、原 GLB/blend、正式引擎或 Spec 任务状态。

## 自身符号与副本

实际 GDB 17.2 `--version` exit0。加载 `engine-native-build.md` 记录的 O0 exe 与其自身 `.debugsymbols`，真实解析 particles 查询函数及 cpp759、Mobile cpp2653/3173地址；`particles == 0` 条件断点成功，symbols batch exit0。没有拿新构建符号匹配官方 exe。

完整 game（排除 `.godot`）1757文件逐 SHA 复制到 `artifacts/engine-native-runtime/project`。仅 QA 场景的独立存档路径与开发 SceneTree 启动器报告目的地适配；第二轮开始，启动器在结束时额外读取已经存在的 pilot results，以保存输入失败原因。生产 character driver/领域规则/原模型未改。每轮原输入副本前后 Changed0，首次诊断引擎导入和启动器 check-only 均 exit0，stderr空。

所有 GPU 组保持 Mobile/Vulkan1.4.312、RTX4060 Laptop、Windows display、1280×720窗口、1600×900 viewport，无 `--headless`/`--wid`/remote-debug，EngineDebugger active=false。使用原完整 character InputEvent driver 与 QA Main，正常 `_request_quit`退出。exit0与driver成功及无原生错误分别判定。

## 真实结果

| 构建 / run | 输入与退出事实 | 原生观察 |
| --- | --- | --- |
| O0无GDB / aab25f90b974458ab6a9c0c4b7ed71e8 | 第一盗窃远征6杀、24币/余数12成功；第二轮 `Expedition input pilot failed`，当时level10且仍在远征，driver error、八项覆盖未完成。首次未记录pilot内部具体原因，不能认定碰撞阻塞。35.386757玩法秒/8147绘制帧，进程40.202229秒正常exit0。 | stderr空、particles null 0；未完成流程不能算通过。 |
| O0无GDB / 0ff7dc2abf38415682a7c7f53cf74c80 | 原八项真实覆盖全部true，57.004378玩法秒/13163绘制帧，进程60.398658秒正常exit0。 | stderr空、particles null 0；只证明这一诊断轮无复现，不能关闭官方错误。 |
| 官方4.7.2 / 7d67193e80714deaad264ffac745e8d9 | 同冻结副本/driver，八项true，55.959010玩法秒/13238绘制帧，进程58.101235秒正常exit0。 | stderr真实两条 `Parameter "particles" is null` / particles_storage.cpp759；不是clean gate。 |
| O0自身GDB / f880a6bef01c4b8b82c715e6cb988238 | 只读Python捕获器成功安装；第一远征3杀后真实死亡，driver error、八项尚未完成；21.583333玩法秒/4580绘制帧，进程62.340622秒正常退出。 | 条件捕获0次、真实particles null 0；GDB的cpp759断点描述不是错误。stderr保留OBS graphics-hook.dll模块消息；未改OBS或其他用户程序。 |

八项true只包含已存在driver的两次盗窃远征、疗愈者切换、天赋编辑应用、疗愈者三预设、自疗、暂停冻结、标题继续冷却与真实敌伤死亡。盗窃者三预设、技能槽编辑、Android与物理手柄仍false，不能将此表扩大为feature完整验收。

## 推论边界与下一步

同副本官方再次复现支持“当前正式行为仍存在”，而 O0 与官方结果差异可能来自编译/优化、模块、时序或其他环境差异；单轮差异不区分这些原因。GDB中不完整driver也不提供完整Main的无错证据。源码可读路径仅证明 CPU owner flags bit11控制查询、PARTICLES置位路径在base_type PARTICLES分支，尚无运行时字段说明错误owner属于Mesh/MultiMesh或陈旧cache。

根已接受独立 `optimize=speed` / `debug_symbols=yes` / `separate=yes` / `dev_build=no` / `lto=none` 固定源码诊断变体。先安全保留O0 exe、匹配符号与manifest，再在独立源码路径构建。它不等于官方配置：仍非LTO，GCC/disabled D3D12、AccessKit、ANGLE、WinRT等差异明确保留。新binary先无GDB完成完整Main并复现，之后才以其自身符号捕获；不清flags，不调用inferior方法，不吞错误。

Playwright本轮实际读取固定提交 [SConstruct](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/SConstruct) DOM rawLines，确认speed为-O3、speed_trace为-O2及明确覆盖symbols/LTO选项；该源码默认editor auto使用speed_trace，故不能称speed变体已证明官方生产旗标等效。sourceware403、GNU/GDB镜像超时与错误路径404均保留失败事实，未列为已取得研究证据。原始副本、脚本、每轮完整stdio与报告在artifact；可追踪副本、派生真实错误计数和SHA目录在 [evidence/engine-native-runtime/](evidence/engine-native-runtime/)。

## speed变体实际准备与构建中状态

原O0 exe213,106,160B与自身symbols1,581,749,694B已完整复制到专用 `preserved-o0`，原 `src/bin`未动；源和副本SHA分别命中 `c306d8c207451e4137c619679266050227b800f6bbd919e0f0b7a3fc14845cf9` / `5d4babc78bd99c72ebe8d15ed8acd77739825f4b46baa3a9b048ac379c47e407`，保留原debuglink basename和构建/source/tool manifest。

固定archive再验SHA后，安全提取独立 `speed-src`，13,989个原文件345,891,694B与初次源manifest逐项完全相同；拒绝越界、链接与Windows保留名，长路径用扩展路径写入，没有全局设置修改。SCons PID65048于UTC2026-10-13T06:47:14.250620启动，-j6，参数为speed/-O3、symbols/separate、noDEV、noLTO及既有disabled组件；compiler实际进程树argv已确认-O3/-g2/-gdwarf-5/-DDEBUG_ENABLED、无DEV/LTO。当前没有构建退出、产物SHA或优化版Main结果，均不得写为通过。
