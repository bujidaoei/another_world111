# 实施与验证入口

**当前状态**：已完成主场景整合，19/25任务通过独立技术门槛，CR-003-03之前冻结源码225/225通过；当前新保存变更正待新的严格报告。真实PC部分行为和跨进程CD恢复已发生，但Native错误及完整覆盖/构建/设备/商业品质仍开放。最新结果见progress/evidence。按[tasks.md](tasks.md)推进，以下场景不能靠夹具发经验/资源冒充实际流程。

## Spec Kit

根已激活`.specify/feature.json`至`specs/003-character-builds`并实际运行setup-plan、setup-tasks、check-prerequisites，收敛计划已完整填回模板，AGENTS已更新。新检出可在单个脚本进程设置SPECIFY_FEATURE_DIRECTORY为该目录执行检查，避免codex前缀分支误识别；本地feature.json不入Git。

文档检查：`python tools/verify_spec.py --feature specs/003-character-builds --output artifacts/spec003-document-validation.json`。只证明结构/关联/状态，无游戏测试。

## 自动化

PowerShell7运行既有严格wrapper：`pwsh -File tools/run_gdunit.ps1 -GodotExecutable <固定Godot4.7.2 console绝对路径> -Suite res://tests -ReportRoot <新的独立报告绝对目录>`。运行前由实现者确认新增suite真实存在；不得把0测试、原生错误、skip或旧报告当成功。

实际新增suite包括test_character_builds、test_combat_state、test_build_migration、test_build_menu、test_build_session、test_build_presets、test_build_resonance、test_character_visuals、test_expedition_bonus，加既有progression/equipment/expedition/input/save/主场景回归。存档夹具分别使用suite声明的user://tests子目录；角色原生QA使用user://tests/character_playtest/20261013_003_b，报告使用独立artifacts，结束清理验证绝对范围和不跟随链接，不能触及正式用户存档。

## 真实PC角色流程

1. 新档确认活动盗窃者，实际移动/战斗/采集/撤离，任务币与怪币分项可查，至少两次成功远征累计10只基础2币怪；预期额外1币，余数正确。
2. 实际受伤、回营切疗愈者，确认生命比例与体力不凭切换增加；再出营自疗一次，观察35体力消耗、30%恢复与20秒共享恢复限制，药包也不能绕过。
3. 在活动遭遇查看/编辑草稿，攻击伤害仍沿旧配置；尝试应用明确拒绝。实际回营后应用两个不同构筑并观察对应攻击/防护/移速变化。
4. 分别保存每角色三预设、调换通用槽；屏障真实吸收受击，focus二阶真实伤害增量，调槽/卸装/切角仍显示原技能冷却。
5. 预设引用真实取得材料，查看融合影响后确认消耗；旧引用显示失效，尝试应用拒绝；原主装备身份与经历保持。
6. 通过真实成长获得阈值和二阶资格，检查两共鸣实际增量；未满足条件有原因，不出现三阶能力或第4链目标。
7. 正常保存退出重启，六预设、角色、资源、生命、冷却、余数一致；再做失败/中断回营核对pending余数/币丢弃、已入库余数保留。

局部fixture专门检验0/7/8点、超预算、伤害数值、100次属性往返与旧格式，并明确标注单元测试。旧v2迁移使用真实旧版本生成档和独立副本；不得覆盖本机正式存档。

## 设备/品质

PC流程、自动化、性能、真人体验是不同门槛。Android接入后执行多指/后台/返回、手柄执行焦点/死区/改键真实设备测试；当前缺事实保持未验收。原创角色和技能反馈先游戏内审查，未有可比运动/性能/真人记录不得宣称最终商业品质或优于参考。
