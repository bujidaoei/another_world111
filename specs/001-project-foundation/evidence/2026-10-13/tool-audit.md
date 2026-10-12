# 工具链与 MCP 实际核查证据

- 核查日期：2026-10-13（Asia/Shanghai）。
- 关联需求与验收：REQ-001 / AC-001；本文件只记录阶段 0 的工具事实，不证明游戏功能、生产资源或平台验收完成。
- 工作范围：Godot、Blender、ComfyUI、Playwright、GdUnit4 与 Android 工具链的只读核查。Git / Spec Kit 初始化由主负责人另行记录。
- 路径表示：`TOOLCHAIN` 指实际目录 `D:\bugu_software\ai-game-toolchain`；用户目录统一写为 `%APPDATA%` / `%LOCALAPPDATA%`，不保留账户标识。下列命令仅将实际执行时的用户目录前缀脱敏，其他参数和结果保持原意。
- 状态规则：进程 exit 0、MCP 调用返回或 `isError:false` 不能独立证明业务成功；须同时读取返回正文。未执行的验证均明确保持未验证。

## 1. 调查方法与副作用

先读取完整开发要求，以 `ALL_TOOLS` 按命名筛选 Godot / Blender / ComfyUI / Playwright 注册工具，再读取少量相关工具描述及真实 schema。注册工具只证明客户端暴露了接口，不证明编辑器、服务或生产能力可用。

执行过 `Get-Command`、`rg --files`、版本命令、`Get-Content`（仅在报告中保留必要非敏感字段）、`Get-FileHash`、Python `importlib.metadata` 包元数据、SDK 已安装列表及 MCP 读操作。独立探测并行执行；未导航共享 Playwright 浏览器，视频核查由其他协作者记录。

没有启动 Godot / Blender 编辑器、ComfyUI 推理服务或 Android 模拟器，没有修改场景、安装插件/模型、下载素材、执行生成工作流或调用付费服务。运行 `--version` 只启动版本查询进程。`adb devices -l` 发现 daemon 未运行后，ADB 自动启动了本机 `tcp:5037` daemon；这是本次设备查询的实际副作用，未关闭其他进程。SDK 查询的 `JAVA_HOME` 仅在该命令进程环境内设置，未持久修改系统环境变量。

初次两条 PowerShell 枚举命令因 `foreach` 后直接管道的语法失败，exit 1；改为先赋值再管道后成功。此类调查脚本错误未记为工具不可用或检查通过。初次猜测的工具链 `README.md`、`manifest.json`、`smoke-test`、`test-project` 路径不存在，相关 `rg` 返回 exit 1；随后通过实际文件枚举定位，不使用这些猜测路径作结论。

## 2. MCP 实际调用

| 工具与实际参数 | 返回标志 | 返回正文 / 关键字段 | 能证明与不能证明的事项 |
| --- | --- | --- | --- |
| `mcp__godot_ai__session_manage({"op":"list"})` | `isError:false` | `sessions:[]`, `count:0`, `exclude_domains:[]` | 会话列表接口可响应；无连接编辑器，不能进行实际场景操作验收。 |
| `mcp__godot_ai__editor_state({})` | `isError:true` | `error.code:PLUGIN_DISCONNECTED`, `connected:false`, `retryable:true`, `reason:no_active_session` | 确认实时编辑器桥接未连接。正文提示打开对应项目并启用 Godot AI 插件后重试；本轮没有执行该启动。 |
| `mcp__blender__get_addon_status({})` | `isError:false` | `Error checking addon status: Could not connect to Blender. Make sure the Blender addon is running.` | 业务结果为连接失败，不能因包装标志为 false 宣称通过；没有取得实时 Blender/addon 状态。 |
| `mcp__comfy_mcp__server_info({})` | `isError:false` | 见下表；`server.running:false`, `server.url:null` | 环境探测成功；选定 ComfyUI 服务未运行，未证明工作流可执行。 |
| `mcp__comfy_mcp__search_models({"query":""})` | `isError:true` | `Error executing tool search_models` | 模型 API 查询失败；不能由此断言磁盘没有模型。使用官方 CLI 等效只读查询进一步确认根因。 |
| `mcp__playwright__browser_tabs({"action":"list"})` | 返回中未提供 `isError` 字段 | `0: (current) [](about:blank)` | 浏览器 MCP 实际可响应列表请求；浏览器引擎版本、网页业务流程和原生手机能力不由本次列表证明。 |

ComfyUI `server_info` 实际关键字段：

| 字段 | 返回值 |
| --- | --- |
| `python.version` | `3.13.12` |
| `python.executable` | `TOOLCHAIN\envs\comfy-mcp\Scripts\python.exe` |
| `workspace.path` / `workspace.type` | `D:\Comfy-Desktop\ComfyUI-Installs\test\ComfyUI` / `default` |
| `workspace.manager_mode` / `manager_detected` | `enable-gui` / `venv-package` |
| `server.running` / `server.url` | `false` / `null` |
| `compatibility.comfy_cli_version` | `1.22.0` |
| `compatibility.envelope_schema` / `warnings` | `envelope/1` / `[]` |
| `freshness.core.installed` / `commit` | `v0.39.2` / `3c1b7a17` |
| `freshness.core.latest` / `outdated` | `v0.39.2` / `false` |
| `freshness.packs` | `[]`；不等于所有潜在工作流依赖已满足。 |
| `freshness.checked_at` | `2026-10-12T22:54:36.871440+00:00`，即客户端时区 2026-10-13 06:54:36。 |
| `comfy_target` | 本次响应未提供该字段；本次只探测选定本地环境。 |

服务未运行时未调用依赖运行服务的重型探测或生成。MCP 暴露的脚本、场景、材质、动画、音频或生成接口仍只是声明能力；没有把接口存在写作实际操作通过。

## 3. 程序、包与插件版本

| 实际执行 / 读取 | exit / 结果 | 结论与限制 |
| --- | --- | --- |
| `Get-Command godot,godot4,blender,java,adb,sdkmanager,python` 的逐项等效查询 | 修正后的枚举 exit 0；前六项中只有 `adb` 找到，`python` 也找到 | PATH 未包含 Godot、Blender、Java、sdkmanager；不是未安装，后续已定位独立目录。PATH Python 指向 `C:\Python314\python.exe`（未单独执行其版本查询），MCP 各自隔离环境实际报告为 3.13.12。 |
| `& 'TOOLCHAIN\godot\Godot_v4.7.2-stable_win64_console.exe' --version` | exit 0：`4.7.2.stable.official.ed1daf0bf` | 已执行引擎版本探测；没有导入、运行、渲染或导出项目。`official` 是程序报告字符串，未另外验证发行包签名。 |
| `& 'TOOLCHAIN\blender\blender-5.2.2-windows-x64\blender.exe' --version` | exit 0：`Blender 5.2.2 LTS`；build hash `d13f752e3b9c`，build date `2026-09-15` | 程序能执行版本探测；建模、UV、动画、glTF 导出与 Godot 导入均未执行。 |
| `& 'TOOLCHAIN\java\jdk-17.0.20.1+1\bin\java.exe' -version` | exit 0：OpenJDK `17.0.20.1` / Temurin `17.0.20.1+1` | JDK 已存在且版本可执行；未证明 Android 项目构建成功。 |
| 三个 `TOOLCHAIN\envs\{godot-ai,blender-mcp,comfy-mcp}\Scripts\python.exe` 执行 `importlib.metadata.version(...)` | 命令批次 exit 0；全部 Python `3.13.12` | Godot AI `4.3.0` / MCP `2.2.0`；Blender MCP `2.1.9` / MCP `1.30.0`；Comfy MCP `0.10.0`、comfy-cli `1.22.0` / MCP `2.3.0`。实际安装包版本，不只读取源码版本。 |
| 读取 `TOOLCHAIN\plugin-release\addons\godot_ai\plugin.cfg` | `version="4.3.0"` | 插件发行目录存在，与已安装 Godot AI 包版本相同；未证明当前游戏项目已安装/启用插件。 |
| 读取 `TOOLCHAIN\sources\gdUnit4\addons\gdUnit4\plugin.cfg` | `version="6.2.2"` | GdUnit4 仅在外部工具链源码中确认存在；未在当前项目集成，也未运行项目测试。 |
| 读取 `TOOLCHAIN\playwright-mcp\node_modules\@playwright\mcp\package.json` | MCP `0.0.83`，Node 要求 `>=18` | 已安装包元数据。 |
| 读取同目录 `playwright\package.json`；执行 `node --version` | Playwright `1.64.0-alpha-1790635538000`，Node 要求 `>=20`；Node `v24.14.0`，版本查询 exit 0 | Node 满足该已安装包版本要求；Playwright 是 alpha，需固定并验证，不能假定与稳定版完全一致。 |

Blender 插件文件核查：

- `%APPDATA%\Blender Foundation\Blender\5.2\scripts\addons\blender_mcp.py` 存在。
- 该文件与已安装 Python 包 `TOOLCHAIN\envs\blender-mcp\Lib\site-packages\blender_mcp\bundled\addon.py` 的 `Get-FileHash -Algorithm SHA256` 完全一致：`EB0FACF69781A30E69792532087D8D41C6A14FCD323353250ABE7988EE297FA5`；哈希命令 exit 0。
- 文件内部 `bl_info.version` 为 `(1, 8)`，不能将这个字段混同 Python 包 `2.1.9` 的版本号。
- 外部工具链源码 `sources\blender-mcp\addon.py` 哈希为 `A1EDBDCCBCE1844CFBE7848374522BF6B9BD97C0A0D9F25D6EA278B39474616A`，与安装包 bundled 文件不同。使用安装包与已匹配用户插件作为当前事实，不用源码文件冒充已加载插件。
- 实时连接仍失败；未实际加载插件、调用 bpy、保存或导出任何资产。

只读 `git -C <外部工具源码目录> rev-parse HEAD` 得到以下版本定位，不涉及当前游戏仓库 Git 核查：

| 外部工具源码 | HEAD |
| --- | --- |
| GdUnit4 | `0127a55f4543dfc24746f6e5c7ba6f94105d51f2` |
| Godot AI | `b82b5c519b1b17228f70d8effce1626f391bd1dd` |
| Blender MCP | `7a0373ec9199183cb460068c4f96aed9c579fb4f` |
| Comfy MCP | `1bbf3bb4487ced43d9dc9097d107cf86638cbbcc` |

上述 SHA 命令均输出了有效 SHA；其合并命令最终 exit 1 来自随后尝试读取不存在的 debug keystore 文件，不能把整个批次报为完全成功。后续以单独 `Test-Path`（exit 0、返回 false）明确核验 keystore 缺失。

## 4. 导出模板与 Android 设备 / 工具链

`Get-ChildItem '%APPDATA%\Godot\export_templates\4.7.2.stable'` 与读取 `version.txt` 成功，实际存在以下模板；本轮未导出产物。

| 文件 | 字节数 |
| --- | ---: |
| `android_debug.apk` | 127260725 |
| `android_release.apk` | 104803333 |
| `android_source.zip` | 214418211 |
| `icudt_godot.dat` | 4797472 |
| `windows_debug_x86_64_console.exe` | 188928 |
| `windows_debug_x86_64.exe` | 103176704 |
| `windows_release_x86_64_console.exe` | 188928 |
| `windows_release_x86_64.exe` | 109268480 |

`version.txt` 返回 `4.7.2.stable`。已枚举目录未包含 iOS / macOS / Linux / Web 模板；不据此宣称任何平台导出通过。

实际命令：

```powershell
adb version
adb devices -l
# 本条 SDK 查询只在当前命令进程设置 JAVA_HOME，未持久修改系统设置。
$env:JAVA_HOME = 'D:\bugu_software\ai-game-toolchain\java\jdk-17.0.20.1+1'
& "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" --list_installed --sdk_root="$env:LOCALAPPDATA\Android\Sdk"
```

- ADB 查询批次 exit 0；版本 `1.0.41` / `36.0.2-14143358`，Windows 内核版本报告 `10.0.22621`。
- `adb devices -l` 返回 `List of devices attached` 后无设备；查询时自动启动 daemon 的信息已在第 1 节记录。没有获得 Android 手机或模拟器的运行验收证据。
- `sdkmanager --list_installed` exit 0，实际返回：

| SDK 包 | 版本 |
| --- | --- |
| `build-tools;35.0.0` / `build-tools;36.1.0` | 35.0.0 / 36.1.0 |
| `platforms;android-33` / `android-35` / `android-36` / `android-36.1` | revision 3 / 2 / 2 / 1 |
| `platform-tools` | 36.0.2 |
| `cmdline-tools;latest` | 20.0 |
| `cmake;3.22.1` | 3.22.1 |
| `ndk;28.2.13676358` | 28.2.13676358 |
| `emulator` | 36.4.9 |
| `extras;google;Android_Emulator_Hypervisor_Driver` | 2.2.0 |
| `system-images;android-36.1;google_apis_playstore;x86_64` | revision 4 |

未保存环境与编辑器配置原文；只保留以下非敏感事实：

- 查询进程开始时 `JAVA_HOME` / `ANDROID_HOME` / `ANDROID_SDK_ROOT` 均为空。
- Godot 编辑器 `export/android/android_sdk_path` 已指向 `%LOCALAPPDATA%\Android\Sdk`，`export/android/java_sdk_path` 为空。
- Godot `filesystem/import/blender/blender_path` 为空；可执行文件不在默认 PATH，直接 `.blend` 导入尚未配置验证。
- Godot 已配置的 `%APPDATA%\Godot\keystores\debug.keystore` 文件不存在。未创建、读取或验证发布签名材料，不报告发布签名已就绪。
- 没有执行 APK / AAB 构建、安装、运行、生命周期、触控、GPU、音频或热稳定性测试。

## 5. ComfyUI 查询失败根因、资源与硬件

为诊断 MCP 模型查询错误，读取已安装工具的官方源码调用路径后，执行其等效只读 CLI：

```powershell
& 'D:\bugu_software\ai-game-toolchain\envs\comfy-mcp\Scripts\comfy.exe' models list-folders
```

实际 exit 1；envelope 返回 `ok:false`, `error.code:server_not_running`，请求本机 `http://127.0.0.1:8188/models` 时发生 `WinError 10061` 连接拒绝。同时提示复数命令 `comfy models` 已弃用，使用 `comfy model`；本次使用的是当前 MCP 源码的实际调用形式，未自行替换成未经验证的语法。

只读磁盘枚举进一步确认：

- 选定 workspace 的 `models` 目录中，`.safetensors/.ckpt/.pt/.pth/.bin/.gguf/.onnx` 权重文件计数为 0。
- `extra_model_paths.yaml` 存在，配置共享模型根目录 `D:\Comfy-Desktop\ComfyUI-Shared\models`。
- 共享目录中上述扩展名文件计数为 1：`checkpoints\sd_turbo.safetensors`，5,214,561,328 bytes。
- 选定 workspace 的 `custom_nodes` 中仅有示例文件、`websocket_image_save.py` 与缓存目录；未发现额外生产节点包。
- 文件名不能证明模型来源、完整性、许可或可用性。未核验该权重哈希、供应方模型卡/许可、加载、输入依赖、推理结果或输出质量；未运行生产工作流。

以下硬件来自 Comfy MCP 自身 `server_info.hardware`，并非推测或独立 shell GPU 探测：

| 字段 | 返回值 |
| --- | --- |
| OS / architecture | Windows 11 / AMD64 |
| CPU 描述 | Intel64 Family 6 Model 183 Stepping 1, GenuineIntel；未据此推断商品型号 |
| RAM | 34,141,495,296 bytes，约 31.8 GiB |
| GPU | NVIDIA GeForce RTX 4060 Laptop GPU |
| VRAM | 8,585,740,288 bytes，约 8 GiB |
| unified_memory | false |

这是容量报告，不是实时剩余 VRAM、游戏性能或推理性能测试。服务未运行，本轮未调用 `system_stats`，未取得运行中可用显存。8 GiB 下图像样本可以列为后续受控验证候选，视频/重型模型及与游戏并发的内存、时间和品质成本均未测量。

## 6. 官方资料核对与技术影响

以下资料于本轮实际打开读取；仅使用项目维护方或引擎官方资料。资料支持的最低版本与本机实际操作通过分别记录。

| 官方来源 | 已核对内容 | 本项目影响 / 尚需验证 |
| --- | --- | --- |
| [Godot AI 官方 README](https://github.com/hi-godot/godot-ai) | v4 要求 Godot 4.7+；通过启用项目插件建立编辑器连接。GDScript 支持解析验证等操作，C# 工具写文本但不负责 .NET 构建/编译诊断。 | 4.7.2 满足最低版本；当前无 session，实际场景/脚本/测试能力仍未通过。类型明确的 GDScript 可继续作为方案候选。 |
| [Blender MCP 官方 README](https://github.com/ahujasid/mcp-for-blender) | 最低 Blender 3.0、Python 3.10；MCP 连接 Blender addon 后才执行 live bpy / 视图检查。生成/素材接口可能访问外部供应方。 | 本机最低版本满足、插件文件匹配；不能以此替代实时连接和实际资产验收。外部生成的成本与许可需单列。 |
| [Comfy MCP 官方仓库](https://github.com/Comfy-Org/Comfy-mcp) | 通过 comfy-cli 驱动用户本地 ComfyUI；工作流执行前需核验节点/模型依赖；partner/API 节点会使用外部服务并可能收费。 | 环境查询可用、服务未运行。未授权本轮生成；不能把本地 MCP 当作免费本地推理或完整媒体生产能力的保证。 |
| [GdUnit4 v6.2.2 官方 README](https://raw.githubusercontent.com/godot-gdunit-labs/gdUnit4/v6.2.2/README.md) | 对应版本兼容表列出 Godot 4.7 / 4.7.1；提供命令行、场景测试、JUnit/HTML 报告等。 | 表中未明确列出 4.7.2；不能据最低版本推断本机组合已通过，需固定 6.2.2 并执行实际导入/非零测试。 |
| [Godot 4.7 Android 导出文档](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html) | 推荐 JDK 17；列出 Platform-Tools 35+、Build-Tools 35.0.1、Platform 35、CMake 3.10.2.4988404、NDK 28.1.13356709，并配置 Java / Android SDK 路径。APK 与 Gradle/AAB 路线有不同依赖。 | 指定的 Build-Tools / CMake / NDK 版本本机未装，现有替代版本不能未经构建宣称兼容。按选定导出方式分别核验，不将 NDK/CMake 差异直接断言为所有 APK 导出必定失败。 |
| [Godot 4.7 渲染器比较](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) | Mobile 适合手机和桌面；SSR、体积雾、SDFGI 在该渲染器不可用。Forward+ 主要面向桌面。 | 参考图的积水反射/雾气需设计双端实现并对照实机验证；桌面效果不能直接作为手机已达目标。选择渲染器的性能与可读性尚未实测。 |
| [Godot 4.7 3D 资源格式文档](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html) | 推荐 glTF 2.0；`.blend` 导入通过调用 Blender 转 glTF，依赖 Blender 安装和路径，Android/Web 编辑器不能直接执行外部 Blender。 | 建议保留 `.blend` 原创源工程和明确导出的 GLB/glTF，分别检验材质、骨骼、动画与引擎导入；本轮未导出或导入。 |
| [Godot 4.7 iOS 导出文档](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html) | 需要 macOS 与 Xcode；iOS 模拟器仅支持 Compatibility 渲染器。 | 当前 Windows 环境不具备 iOS 本地导出条件；iOS 是后续候选，未纳入本轮平台验收。 |
| [Playwright MCP 官方 README](https://github.com/microsoft/playwright-mcp) | MCP 网页自动化需要 Node 18+，通过浏览器结构/交互工作。 | 本机 Node 满足本地两个包的要求；网页设备仿真不证明原生 Android 的触控、音频、GPU、后台/温升或真人体验。 |

GdUnit4 文档主页初次请求以及 GitHub tag 页面请求失败，未当作已读取；随后实际读取上述 `v6.2.2` raw README 成功。当前 main 的兼容表已经包含其他版本，故本文件以固定 6.2.2 文档为依据。

## 7. 保持未完成的验证与风险

1. Godot AI 对当前项目连接、脚本解析、场景操作、日志、运行与测试接口；Blender addon 实时连接和 view/bpy/导出/导入链路。
2. 当前项目安装固定 GdUnit4、Godot 4.7.2 兼容性、非零规则与场景测试；外部工具链历史日志不能证明本游戏通过。
3. ComfyUI 本地服务、模型来源/许可/哈希、实际节点依赖、可运行工作流、输出质量与性能；没有动画/音效/音乐/配音生产证据。
4. Android Java 路径、目标导出方式所需 SDK 版本、debug/release 签名、实际构建/安装与干净环境复现。
5. 原生 Android 设备、触控/生命周期/性能/音频/存档、至少规定时长的热稳定性和连续运行；当前设备列表为空。
6. Playwright alpha 依赖固定与测试；本次列表响应不证明视频可观看或 Web 业务流程通过。
7. 本机渲染器驱动、实际游戏 GPU/CPU 帧时、内存/包体/加载及双端画质比较；未运行游戏，不报告任何 FPS 或优于参考的结论。
8. 官方下载包签名/哈希、资产再分发许可、发布密钥与商用模型许可等；未验证项继续开放，不能用文件存在替代。

阶段 0 已完成的是调查与证据整理。上述功能、资源生产、平台运行、真机与真人验收均未在本文件中标记通过；由 Spec Kit 的计划/任务继续追踪。
