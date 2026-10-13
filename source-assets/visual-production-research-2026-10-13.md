# 原创工业雨庭：高精度视觉制作研究

2026-10-13，Asia/Shanghai。此文件是根视觉规格的工艺与预算输入，不是第二套需求，也不是资产验收报告。用户要求先解决画风与精细度，再推进后续玩法；只对齐参考的视觉语言，不要求角色、建筑、布局相同。本文提出原创角色、建筑与排水维修院，未复制参考几何、布局、标志或贴图，未宣称已达到或超过参考。

已读create-game-assets及three-d/provenance参考、Three.js AAA graphics的technical-art/authoring-recipes/scorecard/shader-cookbook、既有角色与世界源脚本/清单、阶段001参考观察和当前视觉评审。Three.js材料/实例/预算原则只作为技术美术参考；本项目仍使用Godot4.7.2 Mobile，不能直接移植其Three.js API或把浏览器预算当Godot实测。

## 1. 当前证据与差距

本轮实际查看本地`specs/001-project-foundation/evidence/2026-10-13/reference-video-12s.png`与`artifacts/world-camp-v2.png`，读取`research-design.md`的OBS-I01至05、OBS-V01至04。视频原解码360×640、约15.43秒、经过实拍拍屏，只能观察灰绿工业院落、屋顶/墙/道具高度层次、湿润铺装、冷暖照明与克制动作；不能据此恢复源拓扑、贴图分辨率或参考的原生帧时间。旧营地图也不是当前完整003构建。

`character-manifest.json`实际角色2776/3164tri、17bones、一张蒙皮网格、一材质，三张48²图集；`character_factory.py`仍引用恒色PBR图集、`export_tangents=False`。源完整、可重建、动作和技术门禁有价值，但图集中心采样没有面板磨损、正常法线、湿度分区或中尺度材质变化。`district-manifest.json`同样是48²图集，`ruin_wall_full`为1424tri；现有大形与碰撞基线不能直接承担本轮精细视觉目标。

根因优先级是：真实曲面/厚度与功能结构不足；恒色表面缺乏三级变化；地面干湿、接触和排水关系不足；空间外围承接及光照缺乏层次。增加灯、发光、雨线、微小螺丝数量不能独立关闭这些问题。新样板保留可靠米制/坐标/导出/验证工艺，重新制作可编辑高模、运行低模、UV和PBR表面。

本轮读取的源SHA256：

| 文件 | SHA256 |
| --- | --- |
| character_factory.py | B3B109E0CDC1B0BE2C5F05DA8445B8ACC776F9DDE5D335F59AB00CAF5C84A132 |
| build_district_modules.py | 169B788ECC5EA083AB995A57AF1F5E0D670F2C6389951F5A730B570421FCAA86 |
| character-manifest.json | 415D3342A71B71449762BD43CFF630F668FB02AA5B1E3AEFE3730BB06FB5B88D |
| district-manifest.json | A2865991DC5A684B6DF02F1EE60ED558BB1D281184CE81704FE931CEA8D9A3C0 |

## 2. 必须落地的原创代表资产

先做一个12×10m的原创“排水维修院”完整样板。中央为斜向排水维修通道，一侧半开放检修间，另一侧低设备平台，后方两层服务建筑与可见屋顶，近景为低墙、管线和墙外服务地面。布局按玩家、危险与互动净区重新设计；这不是参考院落的复刻。样板从无菜单的实际玩法相机、受控近景相机各检查一次；扩充完整区域在它的源、引擎视觉与预算门槛通过之后。

| 代表资产 | 作者必须制作的结构与材料 | 第一轮交付范围 |
| --- | --- | --- |
| CHAR-V2-THIEF：原创回收巡行者 | 新比例的收窄胸壳、偏置低背工具仓、曲面护肩、真实转轴/关节净空、开合夹具、密封接口与柔性线束；大块壳面/中型板缝/局部磨损三级结构。延续盗窃者身份，保持持枪手与同一碰撞胶囊净空。 | 一件新高模、重拓扑低模、UV、烘焙图、骨架与Idle/Walk/持枪/受击/闪避样本；近景、游戏尺度、灰度、移动镜头。疗愈者待该材质/轮廓样板通过后制作独立躯干/肩架/维护器，不能只换色。 |
| BLD-V2-PUMPHOUSE：原创斜顶排水泵房 | 约6×3×4m，混凝土承台、金属墙板、偏置检修门、窗洞与窗框厚度、非对称檐口、雨槽/落水管、支架、可理解的设备入口。屋顶、墙、梁均有厚度，非重复盒面贴纹理。 | 一个主建筑；2m墙段、门窗段、檐段各一模块；干净/局部损坏变体由源作者设计，独立简化碰撞。 |
| SURF-V2-DRAIN：湿铺装与排水样本 | 4×4m代表区，四种非均质铺装组合、两条维修带、排水格栅、墙根沉积、脚下接触；接缝与破损有真实尺度。2m模块内部由大小不同板块组成，避免贯穿全院的均质格网。 | 四块可复用低模及高模烘焙、一道排水口、干/潮/积水三个连续区域、湿度遮罩；重复3×3及低角度实际相机检查。 |
| PROP-V2-REPAIR：检修与生活痕迹 | 工具柜带抽屉/把手，线缆盘带收放方向，阀门有管线连接，灯具有支架/保护网，苔藓集中在墙脚/背阴区。角色/箱底/管柱触地明确。 | 工具柜、阀门管段、墙灯、线缆盘、两组植被共六件；同材质家族、合理功能与尺度，组成靠墙服务区。 |

高精度支出首先用于轮廓弧度、壳面转折、结构厚度、关节与真实中尺度层次。螺纹/极小螺丝/细粒锈蚀优先烘焙到normal/roughness，不能在游戏40–80px角色上用无意义的百万面运行网格换精细度。近景还须看得见结构与材质，而实际游玩距离不能出现噪点与闪亮细线。

## 3. 可靠的Blender源、GLB、纹理工艺

每件资产独立拥有High、Low、Cage、Collision、LOD、Rig、Bake与Preview集合，保存原创`.blend`及无导入时副作用的重建脚本。现有`build_asset_family.py`顶层会删除当前专用场景对象，不能将它当高精度工厂库直接import。新工厂必须核对scene/collection所有权，输出派生网格，保存旧源与运行资产历史；原子替换运行采用物只在根批准的集成窗口执行。

1. **建模与尺度。** 单位米、脚下原点、Godot Y-up/前方-Z。静态低模应用变换，骨架源/绑定姿态/运行尺度成套固定；已有蒙皮资产不能随意Apply后导出。每个曲面按可见曲率设计段数，主轮廓用真实几何，硬边与UV切分一起管理。角色源高模首样约30万至80万tri，建筑高模约20万至60万tri，均是候选上限与烘焙输入，未执行或测量。
2. **低模与UV。** 角色LOD0候选2.4万至3.6万tri、最多2个opaque材质surface；LOD1约1.2万至1.8万、LOD2约6000至8000。建筑主模块LOD0约1.2万至2.2万tri，重复墙段约3000至6000；道具800至4000。闭合实体检查非流形/退化/负缩放/有限性；有意开放的格栅/植被片需白名单和说明。保持必要硬边、统一texel density；光照UV2单独无重叠，不覆盖角色/材质UV1。
3. **烘焙。** 先在512²或1024²代表壳板检查cage、射线距离、斜面与边缝，再做最终2k。Blender Cycles Selected-to-Active用独立cage，tangent-space normal、AO和roughness分开；base color只输出颜色，不将棚灯/阴影/高光写进材质。2k UV岛间候选16px padding，mip边缝实际检查后调整。Blender官方说明明确要求UV与活动Image Texture目标，cage决定高低模投射，边缘margin避免mip接缝。[Cycles Baking](https://docs.blender.org/manual/en/4.5/render/cycles/baking.html)
4. **PBR输出。** BaseColor与Emission为sRGB；Normal、AO、Roughness、Metallic为数据。ORM按R=AO/G=Roughness/B=Metallic打包；Normal为tangent OpenGL +X/+Y/+Z。Blender5.2 exporter识别Principled、Normal Map节点、`glTF Material Output`的Occlusion入口；其几何节点/复杂程序材质不能直接当glTF材质，必须烘焙。[Blender5.2 glTF](https://docs.blender.org/manual/en/5.2/addons/scene_gltf2.html)
5. **导出与导入。** 保存源高模/材质节点后导出低模GLB，检查skin、inverse-bind、animations、嵌入图、通道、bounds及material数。新normal-map低模应导出真实tangent或在Godot导入明确生成并对照；旧`export_tangents=False`不应不经验证直接复制到新工艺。opaque封闭材质启用backface culling；导出后做冷导入与游戏相机核查，尤其是绿通道、roughness高光和UV缝。Godot内建材质只使用normal的RG，shader不能假设压缩后B保留。[Standard/ORM材料](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html)
6. **LOD与批次。** glTF导入自动mesh LOD是已核实引擎能力；重要轮廓用人工LOD/HLOD审查，不只相信默认简化。螺丝、雨槽支架、重复铺装/植物按geometry+material共享实例，按空间分块，独立collision。一个覆盖全院的MultiMesh无法逐实例裁剪且统一选LOD，应避免形成大AABB。[Godot Mesh LOD](https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html)

建议运行纹理库分为角色独立PBR、共享工业trim、混凝土/铺装、局部污迹四组；2k是源/PC近景起点，Mobile一般1k，emission/湿度mask可512至1k。3D开启mipmaps，距离倾斜地面核查压缩和各向异性；首样先冻结ETC2与ASTC两份实际Android导入结果，再按真实设备选默认。Godot高质量压缩在Mobile使用ASTC、桌面BPTC；默认较低质量在Mobile为ETC2。分辨率不得超过设备可支持范围。[Godot图像导入](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)

预算计算须保留公式而不是PNG文件大小：2048² RGBA8一图带完整mips约21.33MiB；若实际压缩为8bit/texel则约5.33MiB。四张2k图分别约85.33MiB或21.33MiB；实际格式/normal压缩/纹理数组/探针/lightmap另计。导出GLB重复内嵌纹理与Godot实际共享情况都需核验，不能只按源材质数推断运行提交量。

## 4. Mobile可实现的湿润、接触与光照

Godot4.7官方renderer表实际确认：Mobile支持LightmapGI、ReflectionProbe、深度/高度雾、Glow；不支持SSR、SSAO、SSIL、SDFGI、VoxelGI和Volumetric Fog。Mobile是RenderingDevice路线，不等于Forward+全部效果。采用同一原生Mobile样板先建立材质品质，PC高级路线后续再单独比较，不让手机依赖专属效果。[Renderer表](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)

**湿地面。** 混凝土/石材仍为dielectric（金属度0）。候选dry roughness .65–.9、damp .3–.55、积水 .12–.25；这些是制作起点，依真实相机/环境采样调整。湿度由作者制作的排水/低洼/檐下mask控制，潮湿使基色有适度变暗、normal微观起伏减弱、反射变集中；金属锈层是非金属，露出的钢面才高metallic。避免整院变镜面或把画面压黑作为雨天。

**积水。** 首样以地面同一opaque shader的低roughness区表现浅积水，边缘沿破损与排水组织。有限的水面只做小normal流动/雨滴环，先禁screen refraction与多个叠加透明面；深水/可涉水范围若出现则必须另立视觉与物理契约。墙灯与窗框由静态探针参与反射；角色不被静态反射准确复制，不把该方式宣称实时平面反射。

**反射与光照。** 样板1个静态ReflectionProbe、Once、Box Projection，排除小型VFX/角色，先关闭探针实时shadow；需要时最多第二个探针分区且少量重叠。Once重渲染发生于移动probe，不能让它跟随玩家。官方明确Always每帧重渲染场景、Mobile每mesh最多8probe；这里的1–2是制作预算，并非引擎极限。[ReflectionProbe](https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/reflection_probes.html)

建筑静态烘焙间接与暖灯，1个动态方向光给角色与主要物件真实接触阴影。LightmapGI为动态物体配置light probes；全烘焙光不会使动态物体在烘焙静态面上自动形成正确实时阴影，需保留动态主光而非误以为贴图包办所有接触。[LightmapGI](https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/using_lightmap_gi.html) 明暗应来自壳面转折、局部粗糙度、足/箱/柱阴影和暖灯落地；AO只承担局部缝隙遮蔽，不烘成大面积黑边。

**气候和运动。** 首样深度/高度雾仅拉开远景，保留中景材质；雨线限于相机周边可见体积，雨击点有限池化，植被只做小幅与确定节奏运动。技能成功/失败仍由真实事件驱动。每个效果都有clear/owner生命周期与关闭对照，先拍无雨/无VFX材质证据，再拍同相机气候证据。

## 5. 真实预算与测量合同

下表是首样候选制作合同，不是Godot官方最大值、已实测能力或Android通过声明。Godot Mobile没有通用“几万面必然60帧”的保证。既有002 PC报告峰285 draw calls、约174MB Godot视频分配是旧制作基线，与本轮新样板源码不相同，不能继承为性能通过。

| 最坏实际游玩视图 | 当前PC试制预算 | Android待设备确认的起始预算 |
| --- | --- | --- |
| 可见运行低模三角形（单视图，不含阴影额外重复） | ≤70万 | ≤25万，主角选LOD1时≤1.8万 |
| 实际draw calls（同一Godot计数口径、含引擎记录的pass） | ≤350 | ≤150，透明额外提交≤12 |
| 唯一可见opaque材质 | ≤32 | ≤24，主角≤2surface/建筑常规模块≤2 |
| 纹理驻留估算，含全部mips | ≤256MiB | ≤128MiB，另列HDR lightmap/probe/阴影实际分配 |
| realtime shadow | 主方向光1，代表局部灯最多1 | 主方向光1；首样局部灯烘焙，不加动态shadow |
| static ReflectionProbe | 1–2，Once | 1，Once；低阶设备是否保留需实测 |
| 输出与AA | 1920×1080实际raster候选；读取稳定后的viewport尺寸 | 1280×720实际raster候选；设备支持MSAA后对照2×/4× |
| 性能门槛候选 | 实际frame interval P95≤16.67ms、P99≤20ms；长帧单列 | 同等60fps目标先测；达不到时记录成本/修改工艺，不能自行把30fps当已满足用户要求 |

样板测量同时记source SHA、renderer/backend、输出raster/client大小、GPU/CPU时间、draw/primitive数量、可见LOD、视频/纹理分配与OS峰内存。5秒warmup+至少60秒往返/跑动/技能/摄像机旋转，原始逐帧间隔保留；静帧、headless与未命名设备不提供这项证据。后续15分钟温升/稳定性及Android实机独立。Comfy/Blender烘焙不能与采样并行，原生BUG-112-01仍由根独立查因，不在此选择renderer规避后假关闭。

## 6. 本地Comfy边界与免费首样路线

本轮先调用Comfy MCP `server_info`，实际得到comfy-cli1.22.0、ComfyUI v0.39.2/commit3c1b7a17、freshness未过时、当前server.running=false、未返回远程target；硬件RTX4060 Laptop、8585740288B VRAM（约8GiB）、34141495296B RAM（约31.8GiB）。未启动服务、下载模型、安装custom node、提交生成或付费调用。当前无法读取真实空闲VRAM；生产前须重新server_info/system_stats并与根渲染窗口协调。

已读项目真实既往免费512²/24step/seed10132026工作流`comfy/wet_surface.api.json`与`texture-manifest.json`，官方CompVis v1.4源/固定revision/hash及CreativeML OpenRAIL-M许可记录存在，历史真实生成耗时8.49秒。磁盘当前默认workspace checkpoints下看见`aw_sd_v1_4.ckpt`；MCP search_models实际返回工具错误，此轮没有把文件检查扩写成完整模型库存或再次成功推理。旧镜像平均的微颗粒只作albedo草稿，不是normal/roughness/height来源；高精度样板的这些物理表面由可编辑高模/程序材质烘焙。

同时实际查询当前模板，`exclude_api=true`返回Z-Image-Turbo、Qwen Image2.1、Krea2等免费本地候选；查询被工具放宽为all-words，不能当作精准img2img能力列表。继续检查`image_z_image_turbo`得到`local_check.checked=true/runnable=false`，实际列出缺qwen_3_4b、ae、z_image_turbo_bf16三项。服务先前离线，也使该名单不能替代下一次live库存核实；本轮没有执行它。上游代码与权重卡实际标Apache-2.0，作者说6B标准模型适合16GB，并提供CPU offload/其他低显存路线，不能据此声称标准Comfy bf16图可在本机8GB直接运行。[Z-Image上游](https://github.com/Tongyi-MAI/Z-Image)、[官方模型卡](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo)

**首样默认免费可落地路线**：Blender原创高模、程序化paint/metal/concrete/湿度材料、CPU可选的低分辨率验证烘焙→审查normal/cage→最终分批2k烘焙→GLB→Godot Mobile实机样板。这条路线无需新的模型、API key、收费3D或第三方custom node。Comfy承担一件有目的的512²壳面/混凝土微变化候选、规范化与种子/工作流记录，或整理本地作者参考板；提交前验证图中没有partner/API node，再用明确prompt_id取结果。不用生成的“多视图”或纹理替代真实建模/拓扑/物理通道。

**现代本地模型第二路线**：仅在样板明确需要更强概念控制且根允许工具链独立评估时，冻结Z-Image权重/encoder/VAE各自来源、revision、hash、许可，先检查8GB offload/量化的官方或一手实现，测试单张低分辨率峰VRAM与时间。安装/量化成功、模板fetch成功或api:false标签都不能证明workflow可运行；local_check与真正的validate/run结果分别记录。不开启Manager既有bypass_ssl路径，也不把云额度/Tripo API当已批准制作成本。

## 7. 许可与再分发

原创几何、曲面、动画、布局与程序材质保存`.blend`/脚本/输入和采用hash，并按根仓库的资产许可记录发布。每个外部surface按asset ID记录作者、原始URL、获得日期、原图/许可hash、通道转换、修改与采用版本；“免费”或模板api:false都不是资产许可。

可以采用经过核实的CC0微表面作为可选原料，而非复制建筑/角色。已通过Playwright实际打开[Concrete Floor02](https://polyhaven.com/a/concrete_floor_02)、[Rust Coarse01](https://polyhaven.com/a/rust_coarse_01)，页面存在并标CC0；[Poly Haven原许可页](https://polyhaven.com/license)允许商用、修改与原资产再分发。其网站文字/商标/截图不随CC0资产一起授权。此轮未下载、采用或将它们加入项目；如采用，先读取各作者与下载通道、保存原许可记录，降分辨率/打包后的图仍保留来源。

CompVis许可有使用限制、区分模型/衍生模型/输出，不把它称无条件公共领域；输出仍需原创/商标审查。已有权重留在工具workspace，不进入游戏包或公开Git；仅输出图及工作流/模型记录随源资产管理。[CompVis原LICENSE](https://github.com/CompVis/stable-diffusion/blob/main/LICENSE) 已实际读取。现有sd_turbo商业资格证据不足的决定保持；本轮没有使用它。参考视频和截图继续仅本地研究，不进入美术包、源资产仓库或GitHub。

## 8. 执行顺序与独立验收

| 步骤 | 制作行为 | 真实验收证据；未满足则该步仍开放 |
| --- | --- | --- |
| V01 | 根把本工艺、原创方向、样板范围和预算进入Spec Kit；定两种相机：参考语言的院落视图与真实游玩视图 | 明确规格/预算/任务关联；用户从0到1原创和视觉优先要求准确，未用旧demo验收顶替 |
| V02 | 一个原创hero壳体及一块带检修门的泵房立面，512²/1k normal/ORM烘焙试样 | source/UV/cage/通道/厚度/朝向与运行低模可审查；中性与院落光照下可见物理变化 |
| V03 | 完成hero+建筑+4×4湿铺装+六道具，组合12×10完整样板 | Blender源、LOD/collision/texture/license清单、真实Godot导入；无菜单全景/近景/灰度图与转动视频 |
| V04 | 按同镜头逐项评审轮廓曲率、三级细节、材质职责、接触、冷暖、空间承接、动作 | 看见本项目原创整体与精细度；不逐像素匹配参考、不因照片拍屏限制降低本作清晰度门槛 |
| V05 | 跑真实输入与固定采样；独立记录GPU原生错误、资源生命周期、材质共享、LOD切换/脚步/武器净空 | 帧时间/内存/提交与源码hash；Android/手柄/真人未取得时明确未通过；离线渲染与headless不替代 |
| V06 | 样板达到冻结美术门槛后扩充整个原创区域与疗愈者，再恢复后续玩法内容任务 | 源与manifest/Spec Kit完成状态一致；每个新增可见surface保持样板工艺，未完成不勾选 |

当前仅完成资料读取、一手网页/API核查、本机能力读取与工艺研究，没有生产上述V2资产，没有新GLB、texture、GPU烘焙/推理或Android证据。根247/247 GdUnit与本报告的美术工艺研究分别成立；技术回归通过不证明画风/精细度通过。
