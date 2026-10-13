# 存档、设置与GdUnit技术证据

日期：2026-10-13（Asia/Shanghai）。关联 REQ-107、NFR-101/102、TASK-103/106、TEST-103/106。

## 真实交付物

- `game/persistence/save_repository.gd`：当前v2，两个槽轮换；SHA256覆盖schema、sequence和精确payload_json；最大文件1MiB、最大深度32、最多100000个值，拒绝引擎对象/非有限数/不安全整数。
- temp写入、flush、关闭、重开验证后，仅替换旧槽；再次打开已提交槽确认序号与内容一致才报告成功。进程内所有Repository实例共享互斥锁。
- 最后一个有效槽不会作为下一次写入目标；两个已存在但均损坏时拒绝写入并提示恢复，不默默新建进度。可识别的未来schema阻止加载和覆盖。
- v1是明确回归协议，没有已发布老玩家存档。迁移加入真实默认设置或验证已有设置，读取不改旧槽；后续保存到另一个槽。
- `game/persistence/game_settings.gd`：默认设置、完整验证与部分字段规范化；四音量/抖动0—1，字号0.85—1.5，真实布尔类型，zh_CN/en；未知字段拒绝。
- Save的业务字段合法性由核心restore负责；存档诊断信号仅包含component/operation/ok/code/schema/sequence，不记录路径或payload。

## 实际测试

固定 Godot `4.7.2.stable.official.ed1daf0bf`，GdUnit4 `6.2.2`，执行官方 `GdUnitCmdTool.gd`。两个suite共22个真实测试，0错误、0失败、0跳过、0flaky、0孤儿，退出0；见 [JUnit](gdunit-persistence.xml)。

17个存档测试覆盖：首次不存在、JSON往返与对象分离、连续轮换/两代有效、截断最新槽恢复、序号/校验损坏、双损坏拒写、未来schema保护、v1纯迁移/原文件保护、半写tmp恢复、真实临时文件写失败、真实提交rename失败、容量/引擎对象/非有限数拒绝、res目录拒绝、大文件坏槽恢复、迁移失败拒写、同进程双Repository序号、诊断脱敏。

5个设置测试覆盖：默认独立性、补齐缺失字段、数值边界/类型、未知/缺失/非法语言/开关拒绝、真实Repository落盘重载。

初次18测试实际发现迁移添加settings使用点语法产生StringName键，JSON安全检查拒绝保存。改成明确String键后原用例通过，再加入风险用例执行22测试通过。初失败报告保留在本地 `artifacts/gdunit/save-first-run/report_1/results.xml`，修复后报告在 `artifacts/gdunit/save-expanded-run/report_1/results.xml`。

## 测试门槛与来源

`tools/run_gdunit.ps1`从参数/环境读取Godot可执行文件，核对 `test-toolchain.lock.json`；为每次运行生成新报告目录，导入和测试任一非零退出或引擎/脚本错误均拒绝。JUnit必须真实存在、tests>0、testcase数量一致且没有失败/错误/跳过/flaky。

`tools/check_gdunit_gate.ps1`在独立本地项目里实际运行通过、故意失败和空发现。[通过fixture](gdunit-gate-pass.xml)含1个测试并退出0；[故意断言失败](gdunit-gate-fail.xml)官方runner退出100，wrapper退出1；空发现官方runner会退出0且不产出JUnit，[wrapper正确拒绝](gdunit-gate-zero.log)并退出1。最新固定版本探针见 [门槛摘要](gdunit-gate-summary.json)。故意失败fixture只在artifacts中生成，不进入游戏正式tests。

GdUnit原样复制官方addon，保留MIT许可证；605个原始文件SHA256全部一致，见 [来源校验](gdunit-vendor-verification.json)。固定提交 `0127a55f4543dfc24746f6e5c7ba6f94105d51f2`；项目增加DEPENDENCY.json，Godot导入生成的uid独立于上游源文件。

依据官方 [GdUnit4仓库](https://github.com/godot-gdunit-labs/gdUnit4) 与当前提交runner源码、Godot [FileAccess](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html) 和 [DirAccess](https://docs.godotengine.org/en/stable/classes/class_diraccess.html)，并通过真实Godot运行核对API。官方headless限制明确指出UI InputEvent不能作为headless设备验收；本次仅测纯规则/持久化。

## 尚未通过的边界

真实权限拒绝、实际磁盘空间耗尽、操作系统在写入中杀进程、电源中断与长期稳定性尚无证据。目录阻挡是实际IO失败验证；遗留半写文件是恢复场景验证，不能冒充这些外部故障实测。文件flush/rename/回读不提供操作系统fsync或硬件掉电保证。

原生主场景与GodotAI插件由root集成；本次独立suite通过不表示整个项目导入、完整UI流程、构建或真人/Android验收通过。首次严格wrapper导入正确拒绝当时不存在的game_session.gd，记录在本地 `artifacts/gdunit/eb886d7e64894367aa37850b136b1d88`；待root集成后另行通过完整门槛。

因此TASK-106保持“已实现/部分风险实测/待全部验收”，AC-107不报告整体通过。TASK-103的固定依赖及非零/失败/零发现技术门槛已有可复现证据。
