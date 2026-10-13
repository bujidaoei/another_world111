# Implementation Plan: 原创视觉品质样板
**Branch**: `codex/004-visual-quality-slice` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)
## Summary
先完成真实营地/雨庭的原创视觉样板，材料→单个A样区进入真实Main→审核→环境家族/角色→原生实际尺度/动作→完整对照/生产性能依次验证；用户明确画风/完成度而非模型一致。003开放项保留，新增玩法后置。TASK-317是家族生产前置；棚内预览不能越过此门槛。

## Technical Context
**Language/Version**: 固定Godot4.7.2类型明确GDScript、Blender5.2.2 Python。
**Primary Dependencies**: 固定GodotAI4.3.0、GdUnit4 6.2.2、BlenderMCP protocol13/addon1.8、本地Comfy0.39.2/cli1.22、Playwright；不增加收费服务。
**Storage**: 原存档envelope2/domain2不变；原创.blend/脚本/maps/GLB与manifest版本1独立于业务存档。
**Testing**: 原247案例严格门槛加必要配置/资源/生命周期验证，真实InputEvent、五取景/连续动作、导出EXE正常窗口关闭、可比性能。
**Target Platform**: 当前Windows具名RTX4060/i9/32GB；AndroidMobile设计约束、设备/手柄/真人验收独立开放。
**Project Type**: 原生离线3D动作RPG视觉样板。
**Performance Goals**: 当前PC1080p60 p95≤16.7ms/p99≤33.3ms；独立生产负载/峰值内存/绘制量采样。
**Constraints**: 不造业务/不吞原生错误，不改参考模型/品牌；Mobile不支持SSR等不承诺；原始源/许可/高模与运行包分离。
**Scale/Scope**: 先1个4×4m材料/铺装样区，合格后4变体；1个6m宽两层原创检修立面/屋顶；两角色近景代表；真实营地/雨庭一套完整取景，不扩大玩法内容。
## Constitution Check
规划前后均遵循Spec Kit/真实验收/模块边界/原创源/设备事实。常规制作已授权。视觉技术产物不直接勾最终品质；旧缺陷不靠切feature关闭，无宪章例外。
## Project Structure
specs/004-visual-quality-slice含完整设计/任务/状态/evidence。
source-assets/quality-slice含art-direction.md、manifest、Blender脚本/源、materials、characters及预览；game/assets/quality含实际GLB/maps。
现有game/config/world_assets.json与presentation/world_builder.gd承担配置/场景，character_visuals配置/player/animator承担角色，HUD/Main承担表现事件；不另建业务权威。
## 实施与接口
先做一个4×4m A材料/铺装源、技术审计和导入，根把它放入真实Main的受控材料位置，固定相机/光照/步行观察并记录采用或退回源修订；该TASK-317门槛实际通过后才能生产B/C/D及完整立面家族。现有WorldBuilder注册表追加真实asset_id、bounds/简化collision/occlusion。扩路径校验支持res://assets/quality/且仍拒绝外部/越界；铺装尺寸与源一致。若四变体需要新配置，直接升级明确schema并一次更新原配置、校验、测试，不加一次性兼容分支。现有_build_floor会覆盖导入材质，因此新PBR接入必须保留真实源材质/UV，不沿用旧全表面恒色override。
新PBR：basecolor sRGB、normal/ORM线性，UV尺度来自源；高模/烘焙记录与运行tri/material/maps审计齐全。先2k环境材料与共享trim、角色2k候选，具体尺寸/运行LOD在首样实际成本后冻结；面数不能代替品质/性能。
保留原Mobile基线，在真实样区验证ReflectionProbe/LightmapGI或深度雾成本；各有源与实际资源/更新生命周期。根保持GodotMCP/Comfy，环境owner独占Blender与新资产目录，角色另分文件且不抢同Blender。
## 风险与门槛
原生粒子owner/flags缺陷、production smoke超时必须收敛；阴影/雨/透明overdraw/反射/皮肤退休有真实日志。像素对照只用相近尺度/取景，模型原创；完整10维审查和参考逐项差距通过后才恢复后继玩法。
## Complexity Tracking
不增加后端或未实现层；表现配置在原模块演进，独立资产记录用于可靠源/运行追踪，非另一个需求源。正式Spec Kit setup-plan/setup-tasks已运行，根更新AGENTS后check-prerequisites并独立分析。
