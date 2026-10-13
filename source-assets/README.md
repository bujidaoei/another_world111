# 原创资产制作与证据

此目录是 Spec Kit 当前游戏规格所引用的源资产记录。资产数量或工具成功不等于游戏验收；完成状态以当前 `spec.md`、`plan.md`、`tasks.md` 和 `progress.md` 为准。

2026-10-13 的第一族交付为原创硬表面原型：维修机器人、近战回收机、重装守卫、远程发射机、两阶闪电枪、导电锚点、物资箱、掩体与泵站。通过专用 Blender MCP 实时会话建模、导出与查看；没有使用外部模型、图像或付费 3D 生成。

## 技术约定

- 源工程：`blender/asset_family.blend`；重建脚本：`scripts/build_asset_family.py`。
- 运行资产：`../game/assets/models/*.glb`。GLB 为 glTF 2.0，米制、Y 向上、前方 -Z、地面附近原点。角色原始高度含天线 2.36m，实体碰撞独立配置；视觉子节点可按统一角色身高缩放。
- 角色有 `Idle`、`Walk` 对象关节动画。六个活动网格保留独立关节；其余静态资产合并为一个网格。角色每件约 2,424–3,172 三角形，整族 14,756；无外部文件依赖。
- 原创 48×48 PBR 图集内嵌于 GLB：基础色与发光采用 sRGB、金属/粗糙度采用非颜色数据；九种职责置于 16×16 恒色单元并从中心采样。每件只有 1 材质、3 张小纹理，角色 6 primitive、静态 1 primitive；与第一轮角色约 23 primitive 相比保留外观并减少提交。原 UV 保留在源工程中，图集 UV 单列。实际游戏 GPU 帧时与显存仍需测量。
- 九种共享材质职责：石墨结构、金属连接、暖橙外壳、米白绝缘、青色功能灯、琥珀危险灯、锈红敌人外壳、混凝土与植被。颜色不能单独承担敌我辨识；守卫弧形护罩、发射机圆形机体和近战双爪提供轮廓区分。
- 静态模型没有自动生成详细碰撞网格；逻辑实体使用简化胶囊、圆柱、球或盒体，碰撞与视觉分开。

`manifest.json` 记录每件资产的用途、碰撞角色、尺寸、三角形、网格、材质、SHA256、源文件、动画与状态。`evidence/glb-validation.json` 由 `scripts/validate_glb_family.py` 从实际 GLB 读取；检查容器长度、嵌入文件、校验、动画名、PBR 图集尺寸/通道和几何门禁。此报告不证明 Godot 导入、动画播放或设备性能。

源 `.blend` 打包全部三张原创图集并保留相对路径；运行 GLB 导出使用派生网格，只保留运行所需图集 UV，原编辑 UV 保留在源网格。重建几何和导出结构已经实际比较，但不宣称逐字节重建一致：早期两 UV 导出观察到 UV 浮点低位约 `5.96e-8` 的变化；最终两次重建 4/10 文件 hash 相同，详见 `evidence/rebuild-consistency.json`。每次发布采用实际产物的独立 SHA256，不把历史 hash 作为新构建假通过。

## 视觉审查

代表性机器人经 Blender MCP 的正面与四分之三视角查看；四帧步行检查可以辨认交替腿臂动作。已保存逐件 PBR 预览和 `previews/asset_family_sheet.png`。当前审查支持“可辨识原创硬表面原型”，不支持最终商业品质或优于参考的结论。

已发现并修复：薄圆柱 bevel 比厚度大导致接近退化三角形，改为受厚度/半径限制后实际门禁为 0 非有限顶点、0 退化三角形。全族检查到 0 非流形边、0 孤立顶点、无负缩放/未应用 modifier，并保留原 UV 和图集 UV 两层。图集导出有重复纹理节点共享 sampler 的警告；全部节点均使用相同 Closest 设置，实际 GLB 保留基础色、金属粗糙度、发光三张嵌入图，仍需 Godot 视觉复核。

下一质量门槛：Godot 真实导入、角色前方/尺寸/动画、敌人和互动识别、武器升级可读性、地面接触、与实际雨雾/灯光材质关系、遮挡、性能采样、Android 真机。源资产需继续细化比例、功能细节、磨损、材质层次和动作；截图不能替代这些门槛。

## 本地 ComfyUI 职责

MCP 在本机 `127.0.0.1:8188` 启动并验证本地 ComfyUI 0.39.2；硬件是 RTX 4060 Laptop GPU 8GB、32GB RAM。没有配置远程目标、API 节点或信用额度消费。

`comfy/normalize_preview.api.json` 是原生 `LoadImage → ImageScale(lanczos, 512×512) → SaveImage` 工作流。已用真实 Blender 机器人预览提交，任务 `c273e74a-44c7-448a-97b2-0dfbcbcf15a2` 完成并取回 `previews/comfy/c273e74a_000.png`；依赖验证 0 错误/警告，partner_nodes 为空。此职责是本地图像规范化，不能称为扩散生成。

模型/扩散素材采用与许可单列于 `licenses/model-provenance.md`。既有 sd_turbo 权重来源通过哈希核对，但商业主体注册与资格未证明，因此没有用它生产或分发资产。官方 CompVis v1.4 已通过 MCP 下载、实际 SHA256 匹配、保持 weights_only 安全加载并完成本地 512×512 / 24 步推理；首个任务服务器记录耗时 8.49 秒。

`comfy/wet_surface.api.json` 保留固定模型、种子、提示、采样与原生后处理节点。任务 `20adb553-ac83-4d5f-ad92-17adf95d8da0` 完成后取回单色着色样本，复制到 `../game/assets/textures/wet_concrete_albedo.png`；原图、规范化图、3×3 重复预览和 `texture-manifest.json` 均已保存。左右/上下边缘实际 8bit 差异最大与均值均为 0，三个颜色通道一致；明度范围 78–119、标准差 4.50。已查看重复预览，细微颗粒没有可见拼缝。此图只表达着色微变化，不能当作高度/法线或真实雨水粗糙度；镜像平均的对称性与最终游戏效果仍需实机审查。

`scripts/validate_texture_sample.py <图像路径>` 是可重复使用的只读尺寸/边缘/通道核验和重复预览工具，依赖 Pillow。ComfyUI 生成完成后已卸载模型并复核约 7.38GB 显存空闲；游戏性能采样不能与重型图像生产并发。

现有 ComfyUI-Manager 的 `bypass_ssl=true` 已在调查中发现；本轮不用 Manager 安装/更新/下载第三方包。模型由固定 HTTPS 官方路径和实际哈希核验取得，无安全检查关闭或未校验动态代码执行。

## 重建与许可

先启动新的专用 Blender：`--factory-startup --python source-assets/scripts/start_blender_session.py`；脚本只启用本机已安装 Blender MCP，关闭本会话 telemetry 并加专用场景标记。不存在专用标记时，建模脚本拒绝替换场景。不要在已有用户场景中执行建模脚本。

随后通过 Blender MCP 执行保存的 `build_asset_family.py` 和 `render_asset_previews.py`；最后运行 `validate_glb_family.py`。源脚本只依赖 Blender 标准 `bpy`/`mathutils` 与 Python 标准库；预览拼图工具另依赖 Pillow。

此族几何与材质由本项目制作，无第三方源素材。项目最终版权/开源授权由仓库自身政策确定；此记录不替权利人授予新许可。模型权重仅存在本机工具链，不包含在游戏、源库或构建中。

## 庭院模块与场景接入

第二族为 13 个原创静态模块：完整/破损墙段、闭合导体门楼、2m 石板组合、工业后街楼体、可进入维护棚、管道组、灯柱、带不透明闭合叶片的植被箱、排水格栅、通风设备、储液罐和地面碎物。全部通过专用 Blender MCP 场景制作，源工程为 `blender/district_modules.blend`，不替换第一族场景或用户原有工程。代表墙/门楼先导出并查看，再扩展同族。

`scripts/mesh_authoring.py` 提供受专用会话标记保护的原生建模、图集合并、几何审计与 GLB 导出；`scripts/build_district_modules.py` 是各模块的可编辑设计。九种材质职责沿用 `art-palette.json`。13 件合计 14,676 三角形，每件 1 网格、1 primitive、1 材质与 3 张内嵌 48² PBR 图；源几何非有限/退化三角形/非流形边/孤立顶点均为 0。逐件原生预览位于 `previews/district/`，总览为 `previews/district_module_sheet.png`。这些预览证明可审查源资产，不证明实际游戏构图或最终品质。

`district-manifest.json` 记录每件的真实尺寸、`collision_shapes_godot_m` 的盒尺寸及局部偏移、可行走意图、SHA256 和几何门禁。碰撞配置区分闭合楼体与可进入棚：维护棚只有四个立柱、后板和柜体阻挡，内部中央可走；门楼有实体闭合门板，不表现为可以穿过的开口。`evidence/district-glb-validation.json` 是真实 GLB 容器与嵌入地图检查。

实际 Godot 导入进一步发现源清单的边界计算需要刷新依赖图：合并后旋转网格的 `matrix_world` 在未刷新时可产生错误边界，碎物被误记为高约 1.27m。已修 `mesh_authoring.py`，通过 Blender MCP 从当前源顶点重新记录全部 13 件边界，未改写 GLB。`scripts/probe_world_geometry.gd` 在固定 Godot 4.7.2 中逐个读取 23 件真实导入网格与层级矩阵；`evidence/godot-model-bounds.json` 记录所有边界与源清单在 5mm 容差内吻合。泵站实际宽 7.26m、高含天线 5.16m、深含檐 5.02m；阻挡盒为 7.26×3.60×4.80m，局部偏移 `(0,1.8,0)`，作为闭合维修楼体使用。

`scripts/generate_world_assets_config.py` 将测量记录与设计布局生成到 `../game/config/world_assets.json`。运行时只读取这份配置，不依赖源工程、许可文件或源清单。配置包含 23 个模型、71 个共用场景实例、雨庭 11 个和导体工场 13 个独有实例、每区三个无阴影区域灯、灯光/雾/地面色、种子、地面和边界尺寸及原互动锚点。所有路径限定本地资源，实例标识/正尺寸/有限数/整数预算/材料类型在建造前验证，导入缺失时拒绝建立世界。

`../game/presentation/world_builder.gd` 用实际 GLB 建设庭院：侧墙与北侧门楼朝内、后街楼体分层、维护棚移到左侧、泵站后移以保留资源通路，中央保留主要战斗和撤离净区。高墙/楼体/棚加入 `camera_occluders`，对应实体碰撞体记录视觉弱引用 `occlusion_visual`，供相机遮挡渐隐与物理审查。原营地 `(0,0,12)`、维护台 `(-3,0,12)`、撤离 `(0,0,9)`、信标 `(0,0,-13)` 及四个资源坐标保持。

石板通过 256 实例 MultiMesh 提交；物理地面是连续无可见网格的盒体，顶面 Y=0。源石板最高维修片实际为 .134m，放置偏移由清单计算为 -.134m，可见底座另置于 -.136m，避免不透明物理地面网格盖掉所有石板。Godot headless 的 Dummy RenderingServer 对 MultiMesh 变换读回 identity / 空 buffer，因此 headless 测试只证明真实导入顶点与配置对齐以及物理面高度，GPU 实例的显示与脚部接触仍由实际渲染验证；不会把 dummy 读回当作渲染证据。

`../game/tests/test_world_builder.gd` 的 6 项 GdUnit4 专项在固定工具链严格门禁中真实通过：配置拒绝无界/错误输入、两区布局与资源类型不同、导入石板与物理平面高度、泵站尺寸/视觉关联/可进入棚、资源及互动通路、闭合四边，以及导体工场中央通路。最新专项 XML 为 `../artifacts/world-builder-verified/80f1726614554062805219792b4a2294/report_1/results.xml`；它不代替修改后的完整输入回归、画面验收或设备性能检查。场景 API 与截图审查要求见 `world-layout.md`。
