# Android开发APK

先运行 `check_android.ps1 -JdkDirectory <JDK17目录>`，保存SDK/JDK/模板/adb的真实目录、版本与设备清单。没有设备时只记构建和文件审计，不记触控、帧时间、功耗、保存恢复或手机运行通过。

```powershell
./tools/export_android.ps1 -BuildDirectory <已通过Windows构建的artifacts/builds/ID> -GodotExecutable $env:GODOT_BIN -JdkDirectory $env:JAVA_HOME
```

此管线从已验证的Windows生产source staging再次隔离复制，使用portable Godot `_sc_` / editor_data配置SDK/JDK与相同版本模板，保留live编辑器配置与GodotMCP会话。Android staging启用实际ETC2/ASTC纹理导入，并采用原创SVG应用图标；主场景与玩法源取自该Windows快照。只用builtin debug模板生成arm64-v8a开发APK，包ID为org.anotherworld.prototype.dev；源码preset不含密钥或密码。builtin模板不允许覆盖min/targetSDK，当前固定模板的实际manifest为min24/target36，设备适配仍需验证。

开发签名在LOCALAPPDATA/AnotherWorld/development-signing，首次创建RSA2048/SHA256withRSA密钥；随机密码Windows DPAPI保存，仅当前Windows用户可解密。后续构建复用同一开发签名以保留测试设备更新资格，密码通过Godot支持的进程ENV提供且日志脱敏，密钥和密码均不进入仓库、staging或APK。该签名用于本地开发，不用于商店发布。

管线逐项阻断导入/导出错误、非零退出、资源泄漏，验证apksigner实际v2/v3签名，使用SDK AAPT2解析manifest的package/debuggable/SDK/arm64和权限，读回整个APK ZIP并验证所有CRC。审计游戏assets中测试、GdUnit、GodotAI helper、开发引用及签名密钥，要求实际规则/表现配置和生产main scene存在。SDK旧AAPT在这个模板新增Vulkan feature的字符串属性处失败，失败探针保留；AAPT2实际成功解析，未修改引擎或APK字节绕过。

开发APK与许可/原创资产记录在artifacts/android-builds/<ID>/android-development，APK哈希、签名/manifest/ZIP审计与源Windows快照对应。首次构建先验证管线，使用旧冻结原型，不能替代之后的源码版本。当前实际manifest中FileProvider与AndroidX Startup provider有同值authority，后续真机安装与启动要记录实际行为；没有设备时不把结构/签名检查称为可运行验收。工具不会安装APK、发布商店或覆盖真实玩家数据。
