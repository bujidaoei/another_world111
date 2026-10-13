# 独立全局设置与键位偏好

日期：2026-10-13（Asia/Shanghai）。关联REQ-102/107、TASK-106/107、NFR-101/102；root负责对应规格、UI与保存/恢复时机集成。

## 实际实现

`game/persistence/user_preferences.gd` 的 AWUserPreferences 使用现有SaveRepository，保存目录由root显式传入 `save_directory.path_join("preferences")`。偏好双槽与游戏进度双槽互相独立，共用真实v2/checksum/回读/坏槽恢复/1MiB上限机制；只存settings与input_bindings。

- `configure(directory)`：只读加载AWInputBindings默认定义，成功配置独立Repository后才替换内部服务；失败保留原配置。
- `load()`：返回经过全部AWGameSettings与AWInputBindings预检的data={settings,input_bindings}和Repository元数据；不应用InputMap，不自行创建新档或偏好槽。未找到返回not_found。
- `save(settings, input_bindings)`：严格验证完整设置与仅schema_version/bindings的键位快照，再校验现存偏好能够合法读取，最后调用Repository原子保存。未来容器或未来键位schema、全坏槽、有效checksum但领域内容非法都会拒绝覆盖。
- 只读默认配置与验证均不调用AWInputBindings.apply/restore/reset_defaults。真正应用由root在全部候选验证后执行。

非法设置/超大语言字段/未知键位字段/冲突均在写入前拒绝；所有现存文件保持原样。读取返回独立候选，调用方修改候选不会污染磁盘或服务。

## 真实测试

固定Godot4.7.2、GdUnit4 6.2.2，独立执行13个测试，13/13通过，0错误、0失败、0跳过、0flaky、0孤儿，退出0。实际 [JUnit报告](gdunit-user-preferences.xml)；完整本地输出在 `artifacts/preferences-final.log`。

每个用例的before/after均比较完整InputMap事件快照，证明configure/load/save没有污染现有映射。测试目录仅为 `user://tests/user_preferences/<独立标识>/preferences`，结束后只删除该受限测试根。

用例覆盖：

1. 首次读取不创建prefs槽或进度槽。
2. 无游戏进度时，标题设置与合法新键位实际写入、创建新服务后重开读取一致，仍没有进度槽。
3. 键位冲突拒绝且旧槽逐字节未变。
4. 超大字段、NaN与未知字段拒绝且旧槽未变。
5. 未来容器版本阻止读取/旧版本覆盖。
6. 未来键位schema阻止旧默认值覆盖。
7. 最新槽截断时恢复上一个有效偏好。
8. 全坏槽明确诊断并拒绝静默清档。
9. 有效checksum但键位冲突的文件也拒绝读取/覆盖，不应用非法数据。
10. 偏好与游戏容器命名空间独立（测试哨兵只用于文件隔离，不冒充合法游戏进度）。
11. 配置失败后仍可读取/保存原偏好目录。
12. 真实临时文件写入失败，保留原有效偏好。
13. 未配置服务明确报错；外部修改读取候选不污染持久偏好。

## 后续验收

root仍需实际集成标题设置、重绑/重置保存时机、游戏载入后最新全局偏好优先，并跑真实UI/退出/重启流程。服务测试通过不代替这些界面与游戏验收；没有虚构Android或真人结果。
