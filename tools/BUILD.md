# 原型Windows生产构建

构建使用PowerShell7、固定Godot4.7.2 console可执行文件、匹配的4.7.2.stable导出模板和Python标准库。Godot完整版本由 `test-toolchain.lock.json` 校验；所有工具可执行路径通过参数/环境配置，不写死本机目录。

在仓库根运行：

```powershell
./tools/run_gdunit.ps1 -GodotExecutable $env:GODOT_BIN
./tools/export_game.ps1 -GodotExecutable $env:GODOT_BIN
```

GODOT_BIN需要指向已安装的固定版本console可执行文件，也可直接传实际路径。Python默认取PATH中第一个python；使用 `-PythonExecutable` 可指定路径。`-OutputRoot` 默认是仓库的 `artifacts/builds`，每次创建独立UUID目录，不覆盖旧构建。

`export_game.ps1` 是生产导出的入口。不要直接对开发工程按Production preset导出：开发工程的GodotAI调试autoload需要先通过生产配置转换移除，仅exclude目录会留下失效autoload。

## 构建与验证

1. 逐文件创建独立暂存快照，核对复制前/复制后/原文件SHA256，排除GodotAI、GdUnit4、tests、reports与开发导入缓存；不操作live编辑器。
2. 在独立工具工程运行 `prepare_export.gd`，使用真实ConfigFile仅清理暂存工程的调试autoload和editor_plugins；保留生产主场景和其他项目设置。开发project.godot的哈希在流程结束必须保持一致。
3. 暂存目录重新import，非零退出、脚本/引擎错误均阻断。使用Windows Production preset进行release导出；EXE与独立PCK必须存在。
4. `inspect_pck.py`读取官方v2/v3/v4目录格式，拒绝不支持的加密/稀疏包，验证每个文件的MD5和范围，检查项目配置、必需JSON/主场景、目录及配置/脚本中的调试标记。当前实际使用v4。
5. 实际启动已导出的EXE，在640×360离屏窗口、OpenGL Compatibility、Dummy音频驱动下加载主场景。只有该子进程的APPDATA/LOCALAPPDATA指向本次独立测试目录，不接触玩家或开发会话存档。
6. 只向构建进程自身的主窗口发送真实WM_CLOSE，通过exact PID和client矩形排除GL辅助窗，记录window类/标题/尺寸；验证正式幂等异步关闭流程正常退出。退出非零、引擎/脚本/资源/生命周期错误均阻断。verbose日志保留具体泄漏诊断；测试不会向用户live Godot窗口发送消息。
7. 将实际引擎MIT/第三方许可信息、资产与音频来源随包分发，创建ZIP并重新读取每个ZIP条目核对SHA256。

结果目录包含 `source-snapshot.json`、`production-config.json`、`pack-audit.json`、`build-summary.json`、独立测试数据和完整日志。`windows/` 是可运行的分发目录，ZIP包含EXE、PCK、引擎许可与来源记录；EXE和PCK必须保持同目录。

## 验收边界

这些是本地、未签名的原型release构建。启动与正常退出、包内容与文件完整性是技术验收；不代替默认Mobile渲染视觉质量、完整玩法、真实设备输入、帧时/内存/热稳定性或真人评价。

`--quit-after` 直接结束引擎，绕过项目可等待的关闭意图；初次验证实际暴露AudioServer仍在回收playback的泄漏诊断。正式UI/窗口关闭流程先停止并释放音频引用，再异步等待混音周期后退出。突然终止、掉电与长期稳定性仍单列，不通过屏蔽日志声明成功。

Android SDK/模板存在不是Android构建或设备验收。本文件没有冒充Android真机结果；后续Android构建、签名与设备流程另设规格与证据。
