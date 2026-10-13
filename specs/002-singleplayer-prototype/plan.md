# Implementation Plan: 单人原型
**Branch**: codex/002-singleplayer-prototype | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)
## Summary
把阶段0规则转成真实原生游戏。核心规则/存档与场景分工并行，root持有Godot会话，资产代理独占Blender/Comfy。
先写高风险边界测试，再实现，集成实际主菜单/营地/出营/战斗/采集/目标/撤离/晋阶/培养/保存恢复。
## Technical Context
Godot4.7.2/GDScript；Mobile实验渲染；GodotAI4.3.0官方发行包、GdUnit4 6.2.2固定commit；
Blender5.2.2/MCP2.1.9、Comfy0.39.2/MCP0.10.0；版本来源沿research与第三方记录。
存档v2双有效槽，1MiB；无账号/联网/服务地址。PC当前i9/RTX4060，Android后接。
目标1080p60为实验预算，性能使用真实分位采样；本轮未凭引擎版本宣称通过。
## Constitution Check
用户授权自主决策，未决实施项已冻结。禁止假奖励/假关卡/假验收，保持设备/真人开放。
适用Skills已读，Three.js方法映射原生Godot并重核API；无付费默认或额外并行引擎。
## Project Structure
game/config/rules.json和presentation.json集中数值；
features/progression、expedition、equipment纯规则；
persistence双槽/设置；platform命名意图；presentation玩家/敌人/镜头/HUD/世界/GameSession；
assets/models和textures实际产物；source-assets源blend/工作流/记录；tests真实GdUnit；
tools/run_gdunit.ps1严格报告wrapper；artifacts本地构建和日志不提交。
## 模块依赖
表现/输入→核心规则；规则不依赖Node/UI/Input/GPU；存档仅JSON安全格式、领域合法性由各模块restore检查。
装备预览只读，确认重验环境/库存/资格，操作ID防重复；世界晋阶由守卫真实击杀证据触发。
配置设置与应用分离，营地+Ended共同条件；存档恢复活动远征回营，丢pending有反馈。
## 实施顺序
规则/存档测试与实现并行；root配置项目/输入/3D/UI；资产代理原创样本并行；
导入/脚本错误修复→GdUnit非零→MCP真实运行/动作→完整流程→PC导出/性能；
收敛后继续切片/完整角色/分支/Android；不因原型技术通过结束完整目标。
## 质量
CR-005 / BUG-112-01：真实Vulkan两次远征对照仅去除遮挡淡化时无错误，未证明C++根因。遮挡资源改为区域生命周期：首次绘制前为该区所有遮挡网格配置独立材质，期间只改透明度uniform，不反复替换surface材质/绘制pass；旧区域先detach，再释放fader引用，材质随区域销毁。验证包括同一材质身份往返/原共享GLB不变、区域释放及完整冷进程/生产Vulkan回归；增加透明pass成本必须重新测量，不凭推断关闭缺陷。
真实相机/雨水/遮挡/命中反馈，原型品质单独标识；Blender GLB样本进入实机再修订。
Godot particle/material/shader MCP作为特效制作工具，当前无用户另给特效服务URL。
存档错误测试与正式user保存目录分离。发布排除godot_ai、gdUnit开发插件与测试夹具。
CI/Actions固定版本，源码许可与资源再分发记录。人格化好玩结论须真人，不伪造。
## Complexity Tracking
没有无用途服务层或网络空API。高级视觉与性能先测后定；地图真实区域组织，不引入假开放世界。
