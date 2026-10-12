# 阶段 0 环境、技术与集成研究

日期：2026-10-13，Asia/Shanghai。证据：[tool-audit.md](evidence/2026-10-13/tool-audit.md)、[Spec Kit核查](evidence/2026-10-13/speckit-audit.md)、[设计/视频核查](research-design.md)。

## 工程与设备事实

- 初始目录只有`.git`，没有`project.godot`、源码、资产、Spec Kit或项目AGENTS文件；无未提交业务工作需要迁移。
- 初始`git status --short --branch`为`No commits yet on main...origin/main [gone]`；`git log`因未有提交失败。
  `git ls-remote --heads origin`exit0且无heads；不是拉取失败，也不假设存在远端main历史。
- origin匹配用户仓库`https://github.com/bujidaoei/another_world.git`。用`codex/001-project-foundation`建立首个功能分支；不强推。
- Windows11专业工作站版10.0.22621/x64，i9-14900HX 24核32线程，RTX4060 Laptop，约8GiB显存、31.8GiB RAM；当前2560×1600。
  这是开发/首个PC验收设备，不代表最低配置。Android尚未连接，用户明确后续接入；手柄尚未实际查验。
- Git2.56.0.windows.1、Git LFS3.8.0、系统Python3.14、uv工具环境Python3.12.13；无gh可执行文件。
  使用现有Git安全认证，认证写权限以实际推送结果为准，未使用聊天密码。

## Spec Kit 正式集成

Decision：沿用本机已安装CLI，不无理由升级开发版；固定实际源码commit和模板来源，按Codex skills分步执行。

Rationale：`specify version`真实返回0.8.10.dev0；安装元数据direct_url.json指向官方
`https://github.com/github/spec-kit.git` / `31a06101ef832bac32968df5e94607a51630b895`。
`specify init --help`同时暴露新`--integration codex`与旧选项，实际初始化用
`specify init --here --integration codex --script ps --force --no-git`，exit0。
force前已核对目录只有Git；no-git用于保留已有仓库，CLI提示其将弃用；没有套用不存在的选项。

正式产物包含`.specify`脚本/模板/宪章/manifest、9个Codex skills和speckit工作流。
`specify integration list`确认codex installed(default)；`specify check`确认Git和Codex可用。
这是实际集成，不是仅创建同名Markdown。

[官方Core](https://github.github.com/spec-kit/reference/core.html)、[Integrations](https://github.github.com/spec-kit/reference/integrations.html)、
[流程](https://github.github.com/spec-kit/reference/agentic-sdd.html)已浏览：过程命令由代理执行，不能当终端程序。
本机使用`$speckit-constitution`等skills内容；plan/tasks/checklist/analyze的PowerShell前置脚本实际运行。
core specify新流程将feature目录与Git分支独立，通过`.specify/feature.json`选择当前规格。
脚本输出BRANCH为feature逻辑名称时，不能把它误称真实Git分支；真实分支以git branch确认。

重要限制：已安装bundle workflow的requires.integrations.any仅列copilot/claude/gemini，未列codex，
也不含constitution/clarify/checklist/analyze/converge全链；本轮没有声称`specify workflow run`成功。
实际按已安装各skill分步完成阶段0，implementation只交付治理/验证脚本。
官方未来版本文档不是本机执行证据；本机未装converge，采用独立收敛审查+状态检查等效流程。
本项目仅向spec/plan/tasks模板附加追溯/证据条款，修改受版本管理；后续升级必须审查差异。
本机版本未自动建立feature.json忽略规则，主代理已加入根.gitignore；不把当前官方文档描述冒充本机产物。
提交检查发现官方初始化文件也有尾空白，已只作LF/尾空白格式规范化；manifest保留原始安装哈希以便后续升级识别本地修改。

## 引擎、资产与测试路线

Decision：优先Godot4.7.2+GDScript、GLB交付及GdUnit4固定候选；Mobile优先实验，桌面Forward+作质量成本对照。

Rationale：Godot/Blender实际可执行，导出模板匹配；Godot AI最低4.7符合，但当前无连接会话。
GdUnit4源候选6.2.2文档列4.7/4.7.1，不能预先把4.7.2认定测试通过；TASK-009/011先实际兼容探针。
Mobile不支持SSR/体积雾/SDFGI，必须用支持的探针/材质/雾层和受控水反射路径实现手机预算。
官方：[渲染器对照](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)、
[GLTF/Blender导入](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)、
[GdUnit4 v6.2.2](https://raw.githubusercontent.com/godot-gdunit-labs/gdUnit4/v6.2.2/README.md)。

Alternatives：Unity/Unreal不是因质量不足被否定，而是当前已有工具链和优先方向Godot，迁移会增加生产和测试成本；
只有实测证明双端品质预算无法满足时才另立引擎ADR。C#目前MCP不编译.NET，类型明确GDScript更直接。
自研网络服务没有当前价值，保持离线；浏览器/Three.js路线不符合当前原生优先和工具协同，无需引入。

## MCP与工具实际状态

| 工具 | 核查 | 能确认什么 | 仍未验证 |
| --- | --- | --- | --- |
| Godot4.7.2 | --version exit0 | 引擎可执行，Windows/Android模板文件存在 | 游戏导入/运行/导出 |
| Godot AI4.3.0 | session_manage空；editor_state PLUGIN_DISCONNECTED | MCP响应但无编辑器会话 | 场景/材质/动画/运行操作 |
| Blender5.2.2 LTS / MCP2.1.9 | --version exit0；get_addon_status正文连接失败 | 程序和匹配addon存在 | 实时连接、建模/骨骼/GLB导出导入 |
| ComfyUI0.39.2 / MCP0.10.0 / CLI1.22.0 | server_info running=false | 安装与workspace存在 | 权重来源/许可、加载、图像/音频/动画工作流 |
| Playwright MCP0.0.83 | tabs list和参考页面/视频真实调用成功 | 网页研究能力可用 | 原生游戏/Android触控/GPU/声音/温升 |

Comfy模型查询失败根因为server_not_running，不代表没有权重；本地发现sd_turbo.safetensors只证明文件存在。
模型未核来源/许可/哈希，生产未运行。API节点可能收费，未开启；不能把本地MCP等同无成本本地推理。
Blender返回isError=false但正文失败，不能把工具包装当业务成功。
Playwright1.64.0-alpha-1790635538000/Node24.14.0为本机环境事实，不自动成为游戏CI依赖。

## Android差异与风险

JDK17.0.20.1+1实跑；SDK列出build-tools35.0.0/36.1.0、platforms33/35/36/36.1、
CMake3.22.1和NDK28.2.13676358。ADB36.0.2列无设备，查询启动daemon5037，未启动模拟器。
官方[Android导出](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html)列
build-tools35.0.1/CMake3.10.2.4988404/NDK28.1.13356709，本机这些指定版本未装。
不能仅凭更高版本断言兼容；预编译APK、Gradle/native路径分别确认依赖及实测构建。
JAVA_HOME/ANDROID_HOME/ANDROID_SDK_ROOT为空，Godot Java路径为空；SDK路径已设，debug keystore文件不存在。
不把缺debug key夸大为没有任何安全认证；发布签名尚未要求或检查内容。

## Skills核查与采用

root实际读取router与godot-gdscript；设计研究代理实际读取input-systems/create-game-assets。
Spec Kit正式初始化后读取本机constitution/specify/clarify/plan/checklist/tasks/analyze skills并执行职责；
实现治理脚本前读取implement。所有路径均实际存在；引擎API以实际版本官方资料优先于技能基线。
Godot本轮没有写GDScript；对应场景/音频/测试/export Skills在进入实际任务时再读，不批量加载无关技能。
Three.js专属Skills未采用。缺少工具会话不表示插件文件没安装，连接与产物操作分别验证。

## 阶段0结论

有条件沿Godot单人路线进入下一阶段，先冻结可玩范围/规则并做工具兼容探针。
目前没有游戏代码、构建、FPS、真人或Android结果；所有这些验收任务未完成。
预算/人力/日期、数值/失败规则、手柄、Android设备、双端视觉与长期稳定性是后续门槛，见decisions/tasks。
