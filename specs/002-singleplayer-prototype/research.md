# 研究与路线
继承阶段0实际环境证据与官方技术资料；核心代理核实RefCounted/RNG与GdUnitAPI，存档代理核实官方runner，资产代理核实MCP连接/模型license。
Decision：Godot4.7.2原生Mobile、GLB、独立规则及双槽存档；Rationale：本机已具工具链且适合两端；Alternatives：Forward+仅PC效果实验，后端/跨端服务没有当前价值。
用户再次授权自主规则决策，已在decisions记录；没有请求重复确认。
Godot AI新项目使用官方release目录/manifest校验，不从源码快照覆盖已安装插件；现无用户已有Godot工程。
GdUnit runner可能在零发现时exit0，wrapper必须查JUnit实际tests>0；不能把空套件当通过。
商业SD Turbo要求注册及营收资格，当前主体无证据，先选原创制作/Comfy原生处理或合法替代模型。
实际来源：
- https://github.com/hi-godot/godot-ai
- https://github.com/ahujasid/mcp-for-blender
- https://github.com/Comfy-Org/Comfy-mcp
- https://github.com/godot-gdunit-labs/gdUnit4
- https://github.com/microsoft/playwright-mcp
- https://docs.godotengine.org/en/4.7/classes/class_inputevent.html
- https://docs.godotengine.org/en/4.7/classes/class_gpuparticles3d.html
Skill实际加载：root Godot节点/3D/物理/UI/镜头/测试、Threejs director；代理GDScript/resources/survival/save/export/create-game-assets与graphics。进一步VFX/动画/音频在实施时加载。

追加实装依据：Playwright实际浏览官方godot-docs输入坐标源页面（docs主站一次429，换官方GitHub源成功），区分视口与窗口缩放坐标；实际InputEvent QA需get_final_transform转换。官方GeometryInstance3D文档明确实例transparency在Mobile/Compatibility无效，因此相机遮挡采用各实例的材质副本alpha，不修改共享GLB图集资源。来源：https://github.com/godotengine/godot-docs/blob/master/tutorials/inputs/mouse_and_input_coordinates.rst 、 https://docs.godotengine.org/en/4.4/classes/class_geometryinstance3d.html 。较早文档的限制仍以当前4.7.2实际渲染验证，不假定跨版本未改。

root另已读game-feel、input-systems、godot-animation、godot-shaders、godot-audio及performance-optimization，分别落实循环动作/实际武器、命名动作和改键、弱引用生命周期、真实Shader MCP、音频停止与后续release测量。当前有代表视觉原型不等于商业品质。
