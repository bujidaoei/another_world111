# TEST-115 / TEST-117：Android开发构建与未验设备边界

使用godot-export Skill。真实预检 `artifacts/android-preflight/21432566576e4bc287082b788dcc9d9e`：JDK17.0.20.1、adb/platformtools可运行，Android三模板与4.7.2匹配且有SHA；物理授权设备0。35.0.1/CMake3.10.2/NDK28.1精确推荐版缺少，已有35.0.0/36.1.0、CMake3.22.1、NDK28.2替代；未仅凭版本差异推断构建结果。

已实现 `tools/export_android.ps1`、`android_dev_export.cfg`、`prepare_android_project.gd`、`inspect_apk.py`，见tools/ANDROID.md。源取旧Windows冻结快照170f92b3，Android staging真实启用ETC2/ASTC、采用原创512² SVG应用图标，未改live编辑器SDK设置。错误调试记录：显式SDK版本仅Gradle可覆写/缺ETC2导致897dfb65失败；缺项目图标导致091e3735虽产APK仍严格失败；旧AAPT在模板Vulkan feature类型处失败导致e6c8e02失败。均保留日志，随后以实际AAPT2成功解析，没有编辑引擎或APK消除错误。

真实成功构建 `artifacts/android-builds/ed8d1a63fc2049c0a9e78a15cbe89389/android-development/AnotherWorld-Development-arm64.apk`，30,439,166B，SHA256 `299D59B948428F462B3903D3EA7FA548E0698E89251E5C2E4B0156A25BD05A0F`。固定引擎4.7.2，builtin debug模板；实际manifest package org.anotherworld.prototype.dev / debuggable / min24 / target36 / arm64-v8a，网络/音频录制/相机/定位/存储权限不存在。apksigner v2/v3验证成功，真实RSA2048开发证书，368 ZIP文件全部CRC有效、270 Godot assets，libgodot_android和libc++_shared均arm64，无GodotAI/GdUnit/tests/签名密钥或开发helper引用。

开发密钥独立LOCALAPPDATA目录，随机密码通过Windows DPAPI加密保存/进程ENV传递，日志脱敏；不是商业发布签名。源SVG及制作/许可记录在source-assets/ui，runtime副本SHA与source完全一致 `6EF85F6BFB07E570C87A1C4DCA1EE1AE118B015D56B9093CB6E5209D7F8E4C7F`。Godot真实ImageLoader读回512×512、PNG预览已视觉检查，仍为原型品牌。

本目录android-old-build-summary.json、signature.log、manifest.log、apk-audit.json对应实际旧快照；依赖preflight另存。**未安装、未在手机运行、未验触控/性能/保存恢复、未商店发布。** builtin实际manifest观察到两个provider的同值authority，后续结合Android官方解析实现及真机安装/启动验证实际行为，暂不判定缺陷或断言安装失败；AAPT2和签名检查不能替代Android PackageManager/运行证据。旧Windows资源仍有已知渲染问题，当前APK只证明构建管线，不能代替新版或标TASK-117通过。
