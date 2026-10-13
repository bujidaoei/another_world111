# 固定4.7.2原生 owner/flags 调试准备

2026-10-13，BUG-112-01仍开放。本文保留只读准备阶段方案；当时未安装编译器、SCons或调试器，未下载工具链二进制，未编译引擎，也未启动GPU。之后根已授权实际准备/编译，实际构建另见 [engine-native-build.md](engine-native-build.md)，真实GDB符号解析与完整Main运行/官方对照另见 [engine-native-runtime.md](engine-native-runtime.md)，不能把本文准备快照误读为当前从未构建或运行。此前实际对照结果已同步到 `character-renderer-investigation.md`：项目禁嵌入仍2条cpp759，完全独立Main仍1条；孤立Skin/Tree、原Player预检/替换各60秒没有复现，不能覆盖完整Main或关闭缺陷。

## 符号与当前主机事实

通过Playwright实际打开[官方4.7.2发布页](https://github.com/godotengine/godot/releases/tag/4.7.2-stable)，DOM读到34个上传资产；页面显示36包括两种自动源码下载。该清单没有Windows PDB、DWARF或Windows debug-symbol包，只有Android native_debug_symbols两包。结论限于该实际资产清单，不声称所有Godot渠道都不存在符号服务器。记录 `evidence/engine-debug-research/release-assets-dom.json`。

当前工具目录未找到`.pdb/.dbg/.sym/.map`；本机PATH也没有cl/clang/gcc/g++/scons/gdb/lldb/windbg/cdb。PATH缺失不能证明整盘不存在工具。i9-14900HX为24核/32逻辑线程，物理内存34,141,495,296B，D盘可用218,150,371,328B（采样时约203.17GiB）。Python3.13.12已存在于独立Comfy环境，其包环境不得为引擎构建而更改。

已有官方完整源码archive：提交`ed1daf0bf001b61586d9930840f2f1394092c079`，archive71,921,164B，SHA256`e607e9985e1c201bc9cdc1aec8a120f0c3f53b9603f1f828e2b748534a2471ef`。只读tar成员统计13,989个普通文件合计345,891,694B，不含文件系统簇开销。当前只额外提取构建/RID相关12个小文件197,486B；未展开全引擎构建目录。

官方发布二进制与自行编译二进制的地址/优化/链接布局不同。相同源码提交不意味着符号可交叉加载；不得拿新构建的PDB或DWARF给既有官方exe作匹配符号。后续应保存exe与其自身符号、源码SHA、编译选项/完整构建log和工具版本，并先在该诊断exe中复现完整Main。

## 便携依赖决策

选独立POSIX MinGW-w64/GCC/GDB工具链与隔离SCons。Godot官方[Windows构建文档](https://github.com/godotengine/godot-docs/blob/4.7/engine_details/development/compiling/compiling_for_windows.rst)支持MinGW POSIX、Python3.9+、SCons4.4+，并说明Windows官方包用MinGW构建。Playwright访问docs站遇429，随后成功读官方GitHub镜像；没有把429页算成功证据。

固定提交自身还验证：SConstruct:168/178/179定义dev_build/debug_symbols/separate_debug_symbols；Windows detect:224/227/228/233定义subsystem/use_mingw/use_llvm/static_cpp；SConstruct:742拒绝win32线程MinGW。对GCC16的既有警告处理位于SConstruct:989，说明不能仅凭GCC新版本名称认定不兼容，实际编译兼容性仍待验证。

| 依赖 | 固定候选与真实来源/下载体量 | 采用限制 |
| --- | --- | --- |
| WinLibs独立包 | [发布者release](https://github.com/brechtsanders/winlibs_mingw/releases/tag/16.2.0posix-14.0.0-ucrt-r1)，GCC16.2.0/GDB17.2/MinGW-w6414.0.0/UCRT/POSIX/SEH/x86_64；`.zip`页面261MB，SHA256`c1f52294597c0b73786b2a78eb5d176d89226d2f21875eab75e783a8b1cefcc4`。Playwright经页面可见expanded_assets读取14项资产，未点下载。 | 候选未下载/执行/验收；未来先验zipSHA、安全展开、读gcc -v实际线程模型与gdb --version。用zip避免另装解压器。 |
| SCons4.11.1 | [官方包页](https://pypi.org/project/SCons/4.11.1/#files)，wheel4,123,659B，SHA256`454cef364348053422696e3d2ecb4fa593c96a624f955842eaaea64f95c8d11d`；实际只读PyPIJSON已确认URL/size/hash。 | 新专用venv安装已验hash的本地wheel，`--no-index --no-deps`；不改Comfy环境、系统PATH或Python全局包。 |
| 可替代的scons-local | [SCons官方下载页](https://scons.org/pages/download.html)支持local zip/pyz无需安装。 | 官方列出4.11.1，但本轮未得到local包独立hash；因此已取得hash的wheel+独立venv更容易固定供应链。 |
| 已有源码/Python | 上述固定archive与既有Python3.13.12。 | 未来仅在新artifact目录安全展开源码；没有Git子模块追加下载需求被本轮执行验证，不能声称已经编译成功。 |

WinLibs是Godot官方支持的MinGW类别的第三方便携发行版，并非Godot官方工具链包。MSVC+Windows SDK+匹配PDB可作备选，但当前缺工具，其安装体量/系统更改远大于上述路线，本轮不选择安装。LLVM-MinGW也是官方支持路线；本机无clang/LLDB，当前无需同时引入第二工具链。Make/CMake/Ninja虽在候选包内，SCons正常直接调用编译器，不是本轮新增必需安装项。

## 未来构建步骤与边界

新目录建议固定在`artifacts/native-debug-ed1daf0bf/`，生产Godot目录/发布renderer、全部game业务源码保持原样。未来执行前只在该目录准备依赖、完整源码和独立副本项目。每份文件验hash，禁止对原资产/源码执行修补；保留完整stdout/stderr与非零退出事实。

1. 下载候选zip与SCons wheel至专用目录并验上述SHA；安全解包，确认实际`mingw64/bin/gcc.exe`、`g++.exe`、`gdb.exe`、`windres.exe`、`objcopy.exe`存在。记录`gcc -v`为POSIX、目标x86_64及实际版本。只对本次构建进程设置路径。
2. 用已有Python创建`artifacts/native-debug-ed1daf0bf/build-venv`；使用该venv的python，`-m pip install --no-index --no-deps`固定本地wheel。保存python/SCons/compiler/binutils/GDB版本。若新venv无法正常创建，报告失败，不能改Comfy原环境来掩盖。
3. 校验现有archive后安全提取到专用`source/`；源码生成版本会显示custom_build（tar无.git），实际commit由固定archive/逐文件manifest证明，不改version.py冒充官方exe。
4. 初次诊断构建保留`dev_build=no`以避免额外DEV行为；启用自身DWARF符号、无优化/无LTO。不安装D3D12、AccessKit、ANGLE、WinRT附加SDK；显式关闭这些构建组件并记录与生产包差异，Vulkan/Mobile保留。Windows SDK不为MinGW再装。诊断构建不是分发构建或正式产品renderer变更。

仅供后续执行的精确SCons参数，已逐项核对固定源码，尚未运行：

```powershell
$awNativeBase = 'D:/bugu_projects/another_world/artifacts/native-debug-ed1daf0bf'
$awSource = "$awNativeBase/source/godot-ed1daf0bf001b61586d9930840f2f1394092c079"
$awMingw = "$awNativeBase/toolchain/mingw64"
$awScons = "$awNativeBase/build-venv/Scripts/scons.exe"
& $awScons -C $awSource platform=windows target=editor arch=x86_64 use_mingw=yes use_llvm=no "mingw_prefix=$awMingw" windows_subsystem=console dev_build=no debug_symbols=yes separate_debug_symbols=yes optimize=none lto=none production=no d3d12=no accesskit=no angle=no winrt=no vulkan=yes use_static_cpp=yes -j8
```

固定`platform_windows_builders.py:7–12`证明GCC使用`--only-keep-debug`与`--add-gnu-debuglink`，实际单独符号名是exe后缀`.debugsymbols`，不是PDB或猜测的`.debug`。即使separate=false，只要exe≥2,040,109,465B也强制分离。检查实际exe文件名与debuglink对应文件，再以`info sources`/`info functions`/cpp759可解析性验证符号；不能只看“文件生成”称可调试。使用`-j8`是32GiB机器的初始资源决策，实际峰值RAM/时间需测；不启用约30GiB峰值的full LTO路线。

已知下载约265MB（页面261MB+4.1MB，单位由发布页标注），已有源码不重复下载。解压工具链约1–2GiB、对象/符号/诊断副本约5–12GiB、总建议预留20GiB，均是未下载/未编译的**容量估计**，不是实測；初次编译30–120分钟同样仅工程估计，受温度/磁盘/并行度影响。实际tar普通文件330MiB是已测数据。与已有约203GiB空闲相比有容量余量，但不承诺耗时或成功。未来构建应与性能采样分开；本轮没有编译占用。

## 精确原生捕获

先在诊断exe、不挂调试器情况下跑根保存的完整角色输入流程；使用新的诊断项目副本、独立QA存档/报告目录，保留生产逻辑SHA和完整输入证据，不能复用原报告路径覆盖既有失败。启动前后确认窗口/viewport/Mobile/Vulkan、无headless与正常生产退出。`artifacts/standalone_character_probe.gd`是已真实使用的SceneTree启动器，但其报告/QA存档路径固定，未来须在诊断副本中仅更换隔离路径后使用。仅打开Main不会自动完成最终driver，不能混算相同覆盖。

若诊断exe未复现，不能取得官方exe的匹配符号，也不能认定修复。若复现，再使用它自己的GDB/DWARF运行同一副本流程，并保存中断带来的行为/帧时序扰动。这是诊断，不作产品性能或正常QA时间门槛。

已准备、未运行的两份命令文件在`artifacts/skin-renderer-research/native-owner-trap.gdb`与`native-owner-fields.gdb`。第一份在固定 `particles_storage.cpp:759` 且局部`particles==0`才停止，保存thread/backtrace/p_particles原始RID；不调用C++方法或改业务变量。第二份须按真实backtrace选择`RenderForwardMobile::_render_list_template`栈帧后加载，输出surface、owner、data地址及base_flags/base_type/baseRID、skeletonRID、mesh_instanceRID、uniformset、count/trail、cache链、surface flags和局部/参数。模板PassMode来自实际函数实例名称；`p_pass_mode`并非该函数现成局部变量，不能打印虚构参数。

| 固定源码位置 | 捕获目的 |
| --- | --- |
| particles_storage.cpp:757–759 | ParticlesStorage查询为null；错误是无particles owner，并不等于“运动buffer缺失”。保存`p_particles._id`与this地址。 |
| forward_mobile.cpp:2653–2654 | 调用条件是CPU owner.base_flags bit11；同时取得surf、owner、data、base_type、baseRID、模板PassMode。 |
| forward_mobile.cpp:2702–2710 | geometry创建时记录分类、baseRID、ginstance地址；2710写base_type。 |
| forward_mobile.cpp:3152 /3173 | 清flags与唯一PARTICLES置位路径，记录ginstance/base_type/RID；不能把surface particle_trails旗标当同一字段。 |
| forward_mobile.cpp:2755–2770 / `_mark_dirty`:2837 | owner/data及surface cache退休/重建，校核错误surface是否仍属于合法当前owner，不能凭地址相同判断代际相同。 |
| renderer_geometry_instance.cpp:33 | skeleton字段独立setter，仅作RID关系对照；正常路径没有设置PARTICLES。 |

建议初次只用null条件断点，避免每draw停住。从错误栈已知owner后，重复同一创建/退休流程，绑定该**实例生命周期内**的hardware watchpoint `watch -l $aw_owner->base_flags`，并监测`data->base_type/base`、几何free与cache链接来源。owner在free后必须删除或重绑watchpoint，内存池地址复用不是同实例；硬件watchpoint数量/对齐有平台限制。必要时先依baseRID在创建/更新位置取得新owner，不能跨进程沿用ASLR地址。这里只设置调试器便利变量，禁止清flags、改base_type或吞掉错误来伪装修复。[GDB断点命令](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Break-Commands.html)、[watchpoint规则](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Set-Watchpoints.html)。

RID内部字段已从固定`core/templates/rid.h:40`实读为uint64 `_id`。将完整64位RID与现有GDScript `get_base()`/Mesh/SkinReference RID采样映射，而非只比较低32位index。owner注册状态可只读检查`particles_owner.alloc`的max_alloc/chunks/elements_in_chunk/validator（rid_owner.h:192–245）；索引越界或validator不匹配保持原观察，不执行get_or_null/owns等inferior方法来扰动线程。C++堆所有权/越界写/陈旧cache三者尚无证据区分，必须以栈、字段和生命周期捕获结果再决策。

## 本轮交付与后续门槛

原始网页/主机/archive/PyPI元数据副本与逐文件hash在`evidence/engine-debug-research/`，固定源码小文件及其manifest、未执行GDB脚本在artifacts。无安装、无新二进制下载、无GPU运行、无game业务变更。后续门槛依次为供应链验hash→实际编译/符号可解析→诊断二进制完整Main复现→取得真实owner/RID/flags写入证据；此处仅准备工作已完成，没有把这些门槛标记通过。
