# Windows原型release生产构建

日期：2026-10-13（Asia/Shanghai）。关联TASK-115、TEST-115、NFR-101/102、AC-109/110。

已交付 `game/export_presets.cfg`、`tools/export_game.ps1`、`tools/prepare_export.gd`、`tools/inspect_pck.py` 与 [构建说明](../../../../tools/BUILD.md)。Godot完整版本固定 `4.7.2.stable.official.ed1daf0bf`，实际使用匹配的Windows x86_64 release模板；没有使用debug模板冒充release。

## 生产配置隔离

开发工程实际含 `_mcp_game_helper=*res://addons/godot_ai/runtime/game_helper.gd` autoload，不能只exclude插件目录。构建创建独立快照、校验源文件复制一致性，使用Godot真实ConfigFile删除仅暂存配置的debug autoload与editor_plugins，再独立import与release export。

开发project.godot SHA256仍为 `C9E62B0997AC881DFC522B3E1DA03ADF4FB1D626D0B9499C25D5CD38A347EEE1`，没有关闭或修改live Godot会话。实际清理结果见 [production-config](windows-production-config.json)。

## 实际成品与完整性

最新本地完整结果：`artifacts/builds/170f92b3ab4f42a88b8be23a494e7a23/`。

- Windows EXE：109127680 bytes，SHA256 `29F45F851A2CE5BEDA1F10CCE547E01D7D24AC751D50B9B38378C18CB08600A6`。
- 独立PCK：2405172 bytes，format v4，265个实际文件，265个MD5全部重新计算一致。
- ZIP：41083546 bytes，SHA256 `DAC64B95928593210559178AC42A4934AA3633A2AB0CB0CC4F9F4869A8D5A252`；六个ZIP条目重新解压到流并核对实际分发文件SHA256，全一致。
- 分发包含EXE、PCK、实际Godot MIT/第三方引擎许可及本项目资产/音频来源记录。

审计真实PCK目录、project.binary及配置/脚本payload：没有GdUnit4、GodotAI、game_helper、tests、reports路径或调试配置标记。必需rules.json、presentation.json与生产main场景存在。详细文件列表/哈希见 [包审计](windows-pack-audit.json)，构建与时间见 [摘要](windows-build-summary.json)。

## 真实启动与关闭

实际执行导出的EXE，在独立子进程APPDATA/LOCALAPPDATA中加载完整main场景，640×360离屏、OpenGL Compatibility、Dummy音频驱动；源码 [OS_Windows.get_data_path](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/platform/windows/os_windows.cpp)核实该固定版本从APPDATA定位user目录，未触碰用户/开发存档。

只向该构建PID的实际窗口发送WM_CLOSE；项目统一关闭流程先禁止输入、停止并释放音频，再异步等待混音周期后退出。结果exit0，0脚本/资源加载/引擎错误，0ObjectDB或资源泄漏警告，见 [实际运行输出](windows-smoke.log)。GPU实际为RTX4060 Laptop，Compatibility驱动NVIDIA581.15；这只是启动/关闭技术运行，不能作为默认Mobile渲染或视觉性能验收。

第一次实际成品使用--quit-after240，日志真实报8个音频loop/playback实例仍在回收，严格管线拒绝通过；失败日志保留在 `artifacts/builds/434ff5c815e446a8aaf413ff815638a6/logs/`。随后按根因实装stop_all和正常关闭生命周期，再以真实WM_CLOSE重新导出运行；没有忽略警告或只凭退出0宣称成功。--quit-after突然引擎退出与强制终止/掉电仍有独立限制。

## 依据与边界

Windows选项依据固定版本 [官方export_plugin.cpp](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/platform/windows/export/export_plugin.cpp)；PCK格式依据 [pck_packer.cpp](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/io/pck_packer.cpp) 与 [file_access_pack.cpp](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/io/file_access_pack.cpp)，均以实际产物验证。

这是未签名、本地原型release构建。构建可复现指固定工具、完整快照和步骤可重复执行；没有宣称ZIP或全部二进制跨机器逐字节确定性。完整合法玩家流程、视觉、分位帧时/峰值内存、长期稳定、真人及Android设备验收沿独立证据继续，TASK-115整体门槛不由此技术构建自动满足。
