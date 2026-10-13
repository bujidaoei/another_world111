# 固定源码Windows诊断构建实际记录

2026-10-13。根已在只读方案后授权实际下载/安装到专用目录并构建；BUG-112-01仍开放。本文记录初次构建/静态核验阶段：**实际构建exit0，exe/自身符号已生成并通过静态配对/源码映射；链接资源合并消息保留，未称clean构建，当时未取得Main运行或原生根因证据。** 此阶段未修改生产Godot版本锁或游戏业务源码，未运行GPU、Main或GDB。

后续真实GDB符号解析、完整Main与官方对照、O0失败及新增独立speed诊断构建见 [engine-native-runtime.md](engine-native-runtime.md)。O0完整一轮无错与同副本官方两条cpp759并存，尚无根因或修复；speed变体正在独立目录构建，不能覆盖本文静态阶段事实或冒充已交付新引擎。

专用工具根`D:/bugu_software/ai-game-toolchain/native-debug-ed1daf0bf`，实际完整源码根`.../src`；原始证据/完整日志`D:/bugu_projects/another_world/artifacts/engine-native-debug`。新venv只装固定SCons，编译进程仅对自身PATH加入MinGW bin，未改全局PATH、注册表或既有官方生产引擎。

## 已完成的实际准备

| 项目 | 真实结果 |
| --- | --- |
| WinLibs固定zip | 实际HTTP200，274,029,684B，下载23.485603秒；SHA256`c1f52294597c0b73786b2a78eb5d176d89226d2f21875eab75e783a8b1cefcc4`命中发布者。 |
| SCons4.11.1 wheel | HTTP200，4,123,659B，1.206555秒；SHA256`454cef364348053422696e3d2ecb4fa593c96a624f955842eaaea64f95c8d11d`命中PyPI；新venv执行`--no-index --no-deps`成功exit0。 |
| 安全解包/源码 | 包含范围检查、拒绝链接/路径越界/Windows保留组件。WinLibs11,869文件961,203,542B；源码13,989文件345,891,694B全部安全提取，编译前按archive逐文件SHA Changed0。 |
| 编译工具核查 | 实际Python3.13.12、SCons4.11.1、GCC/G++16.2.0，GCC-v实际POSIX/x86_64-w64-mingw32；ld/objcopy/windres版本命令均exit0，完整stdout/stderr及工具exe SHA保存。 |
| GDB | 发布者固定版本17.2，实际exe存在且保存bytes/SHA；遵循根“不跑gdb”范围，未调用包括--version在内的GDB命令，不把发布者版本写成运行时核验。 |
| 完整核心许可证 | 已保存13份177,539B的Godot/SCons MIT、Godot bundled第三方通知、GCC/GDB GPL3、GCC runtime exception3.1、MinGW14.0/winpthreads通知和包内Python/SCons通知，附来源/SHA。工具链不进入游戏分发。 |

准备中失败保留：原长源码路径触发WindowsMAX_PATH，初次提取exit1/完整stderr和partial source保留在`.../source/`，未递归删除；改用较短src并以Windows扩展路径写长文件，重新验证已有工具链zip成员CRC/size与文件SHA后完整提取exit0。没有修改全局长路径设置。

许可证原始直连raw GitHub SSL EOF、公共Contents API403 rate-limit两次失败日志保留；随后通过实际Playwright公开代码页的完整DOM rawLines取得GPL/exception/MinGW文档，仅LF换行标准化，13份完整文本与origin/hash已保存。最初Playwright误把含点的JSON字段名当嵌套路径，四次读取失败没有算成功；实际重新递归定位单一完整rawLines后保存。包内CPack.GenericLicense仅通用模板，不冒充完整CMake许可证；未使用额外CMake/Ninja等工具或再分发工具包。

## 实际构建

实际UTC开始`2026-10-13T04:17:07.164593+00:00`，SCons PID37204，以下完整argv保存在build-started.json，日志持续写build.stdout.log / build.stderr.log：

```text
platform=windows target=editor arch=x86_64 use_mingw=yes use_llvm=no
mingw_prefix=D:\bugu_software\ai-game-toolchain\native-debug-ed1daf0bf\toolchain\mingw64
windows_subsystem=console dev_build=no debug_symbols=yes separate_debug_symbols=yes
optimize=none lto=none production=no d3d12=no accesskit=no angle=no winrt=no
vulkan=yes use_static_cpp=yes module_mono_enabled=no -j6
```

保留production的DEBUG_ENABLED/非DEV行为；诊断改变是无优化/无LTO/自身符号/console子系统。d3d12/accesskit/angle/winrt附加SDK显式关闭并记录差异，Vulkan/Mobile源保留。没有修改固定引擎C++代码、吞cpp错误或将新构建冒充生产官方版本。

实际UTC结束`2026-10-13T04:30:17.284010+00:00`，SCons/Popen exit0，wall790.1194215秒（13分10秒）。stderr保留ar版本解析1条与msgfmt缺失4条（使用.po）；stdout3183保留`.rsrc merge failure: multiple non-default manifests`。exit0没有把该链接消息变成无异常，后续启动/完整图形流程仍待验证。

## 实际产物与静态检查

| 产物 | 字节 / SHA256 |
| --- | --- |
| `src/bin/godot.windows.editor.x86_64.exe` | 213,106,160B / `c306d8c207451e4137c619679266050227b800f6bbd919e0f0b7a3fc14845cf9` |
| `src/bin/godot.windows.editor.x86_64.exe.debugsymbols` | 1,581,749,694B / `5d4babc78bd99c72ebe8d15ed8acd77739825f4b46baa3a9b048ac379c47e407` |

真实objdump确认DWARF `.debug_info/.debug_abbrev/.debug_line`存在；GNU debuglink文件名正确，exe内CRC32与自身符号文件均4255632369。真实nm/addr2line将四个目标函数映射到该源码根：Particles查询cpp757、Mobile geometry_create2702/free2755/update3063。没有用另一构建的符号匹配官方生产exe。13,989个原archive文件在构建后重新逐文件SHA复核Changed0；新增generated headers/objects不混入原文件集合。

实际CIM编译命令采样还验证`-DDEBUG_ENABLED`有、`-DDEV_ENABLED`无，`-O0/-g2/-gdwarf-5`有；不能只凭顶层SCons选项推断实际编译旗标。

对链接资源消息，仅读取PE manifest资源：Win32 LoadLibraryEx flags0x22按数据/资源映射，未启动入口或imports；[官方API语义](https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-loadlibraryexw)。实际RT_MANIFEST ID1为613B，SHA`a5afce46ab0f79f53ad3f1f16d3975f026ff01e3681b0241aa52548e7c820bd1`，与固定原`platform/windows/godot.manifest`逐字节相同；ID2/3缺省。它支持主要manifest被保留，不证明所有PE资源/窗口/运行行为无差异，原链接消息保持开放说明。

初次静态检查多次启动addr2line重复解析1.58GB DWARF，已保留首次完整日志与3个已完成函数映射；为合并解析仅停止经CIM核实的本次addr2line子进程，首次检查exit1留存。随后用一次批量addr2line完成四函数/source SHA/产物哈希检查，严格exit0；未把人为终止的一轮算成功。原始nm输出195,707,360B及所有完整stdio留在artifact，不把大符号dump或编译工具/二进制放进游戏。

完整构建/静态报告、准备脚本、许可证、失败/重试日志的可追踪副本见`evidence/engine-native-build/`；原始全部记录保留在artifact。GDB运行时版本/断点可解析性、完整Main复现、错误owner/flags写入点仍由根后续协调，均未验收；不得由此关闭BUG或替换产品renderer。
