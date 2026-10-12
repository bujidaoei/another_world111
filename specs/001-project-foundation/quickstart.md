# 当前交付与恢复入口

这是阶段0研发资料，尚无游戏可启动，不提供不存在的构建或运行命令。

1. 阅读[progress.md](progress.md)、[spec.md](spec.md)、[plan.md](plan.md)、[tasks.md](tasks.md)、[decisions.md](decisions.md)与最近[evidence](evidence/2026-10-13)。
2. 当前环境验证：`python tools/verify_spec.py`（系统Python3.14，无第三方包）；非零退出代表关联或工件错误。
3. 在PowerShell执行 `.\.specify\scripts\powershell\check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks` 确认当前feature。
   本地feature.json被忽略；干净检出恢复当前feature可执行：

```powershell
Set-Content -LiteralPath '.specify/feature.json' -Encoding UTF8 -Value '{"feature_directory":"specs/001-project-foundation"}'
```

4. Spec Kit CLI固定官方源码commit，可在另一个环境复现安装：

```powershell
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@31a06101ef832bac32968df5e94607a51630b895
specify version
```

已有安装不要自动重装/升级。仓库已包含初始化产物；正常恢复不需要force init。此安装说明来自官方CLI路径，另机实际安装未验收。

5. Codex分步使用已安装 `$speckit-constitution` / `$speckit-specify` / `$speckit-clarify` / `$speckit-plan` / `$speckit-checklist` / `$speckit-tasks` / `$speckit-analyze` / `$speckit-implement`；这些是代理skills，不是shell程序。
6. 下一阶段先完成TASK-008范围冻结，再做工具兼容/输入/数值与存档规格。连接Godot前确认正确工程，切勿修改其他会话。

本机引擎：`D:\bugu_software\ai-game-toolchain\godot\Godot_v4.7.2-stable_win64_console.exe --version`。
其他设备路径不能硬编码到游戏源码；后续通过受控本地工具配置提供。
参考截图仅本地研究且被gitignore排除，不属于项目素材；GitHub检出以原视频链接复查。
