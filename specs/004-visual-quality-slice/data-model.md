# 视觉数据模型
以下为设计合同，待真实实施验证。
VisualTarget：参考观察、原创主题、形/色/材料/光角色、镜头尺度、捕获集合与缺陷。
AssetRecord：id/职责、源.blend/脚本、GLB/maps/hash、单位/pivot/bounds、triangles/meshes/materials/texture尺寸、rig/clips、碰撞/LOD、许可，以及source/technical/engine/visual独立状态。
SurfaceFamily：五材料类共享maps，basecolor sRGB、normal/ORM linear，UV/texel密度/干湿区域/参数范围；未知路径/字段/类型拒绝。
CaptureCase：run_id/源与构建manifest/scene/相机FOV与位置/分辨率/真实玩家状态/InputEvent时间线/截图与连续动作/GPU/log/帧时。
VisualFinding：BUG/复现/严重度/根因/源修复/原复现与回归/未验范围；单轮未复现不关原bug。
QualityReview：完整集合/10维证据分数/参考逐项对照/独立审查/制作负责人结论/设备真人边界；必要项缺证据不pass。
表现配置不复制角色/奖励/生命/冷却权威，不变更存档业务版本。
