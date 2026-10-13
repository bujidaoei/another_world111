# 004 原创排水维修街区：环境代表资产制作简报

2026-10-13。作为004 spec/plan/tasks的关联制作输入，不替代正式Spec Kit。根已通知“004已可实施”，当前只授权TASK-304单个A铺装/材料源与导出；B/C/D及建筑实际生产须待TASK-317真实Main首样采用门槛通过。源技术/棚内预览通过与实际Main视觉/运动/性能/最终验收分列。

## 原创设计与代表家族

地点是暴雨后仍在运转的旧市政雨水回收检修站。下层承担过滤/维修，上层小型监控间观察排水；建筑的非对称外廊、不同宽窗带、倾斜集雨檐与外露回流管共同解释用途。设计独立于参考雨庭的布局、店面/门楼、人物和标识，只对齐表面完成度、可读大中小层次、灰绿石/金属材料与湿润冷暖光。

| 资产 | 拟定原创形与用途 | 尺寸/放置合同 |
| --- | --- | --- |
| repair_paving_a | 偏置修补带、几种不同长宽维修石、窄排水边和金属补缝夹；首个4×4材料/几何样区。 | X/Z占地4×4m，脚下pivot居中，上表面接近Y0，薄底位于负Y；现有平地提供连续简化碰撞。 |
| repair_paving_b | 分段沟槽与可掀格栅，检修口旁不规则重铺带；不复制A排列。 | 同4×4接口，沟槽方向与边界接口明确。 |
| repair_paving_c | 半旧板、半补砌小石，边角崩损、浅沉积带与嵌入维修薄片。 | 同4×4接口，露底/拼接错层不可接受。 |
| repair_paving_d | 排水低洼与扇状磨损路径，主要石块、碎裂接缝与护边组织独立。 | 同4×4接口；四件可组成8×8m代表区，也可按作者区域放置。 |
| rain_reclaim_facade | 6m宽两层服务建筑，石/混凝土基础、涂漆金属检修门、上层非对称观察窗、分段集雨屋面、檐槽/回流管/附墙支架、独立侧方小平台。 | 约6m宽、3.2–4m深、6.5–7.3m高；门为封闭服务门，无虚假可进入室内。前方Godot-Z，脚下pivot。 |
| reclaim_planter/foliage | 屋面/附墙雨水蓄槽附近的当地小叶植物与垂坠枝条，按维护/水路解释生长。 | 合并/实例共享，几何叶片优先，减少半透明overdraw；不占可走空间。 |

铺装必须把原来的粗黑等宽网格改为真实尺寸不同、接缝约束明确的石/修补/排水区，不能只是随机旋转同一方砖。损伤沿边缘、维修夹附近和水路布置。连续路面起伏限制在厘米级，视觉细节不改变原有运动规则；管线支架/屋檐/排水口在远镜头仍有清楚构造。

## 源、运行和材料职责

只在`source-assets/quality-slice/`及`game/assets/quality/`新建文件，旧23件/角色资产与生产代码不改。拟定目录：

```text
source-assets/quality-slice/
  scripts/environment_factory.py       # 有ownership与路径守卫的原创源制作
  scripts/audit_environment.py         # 几何/UV/GLB/map真实审计
  blender/repair_district.blend        # 可编辑source、高细节与运行派生集合
  textures/                           # 源bake channel与采用maps
  previews/                           # 近景/玩法尺度/拼接图
  evidence/                           # 实际执行、API、hash、审计
  environment-manifest.json           # 仅记录实际产物/采用结果
game/assets/quality/
  repair_paving_a/b/c/d.glb
  rain_reclaim_facade.glb
  textures/                           # 实际使用的PBR PNG
```

旧48²恒色图集不承担精修材料。采用Blender原创程序化材质与真实UV烘焙；不新增付费生成、第三方模型或未知许可纹理。首套铺装1024²级别样区验证后，才按测得屏幕覆盖决定共享2048²atlas或独立1024²材料；最终atlas、密度/贴图数由实际审计记录，不把本简报的候选数写成已测结果。

材料族为维修石/砂浆、涂装金属、裸连接件、玻璃、植物/沉积物；建筑/铺装各保留可编辑程序节点、真实UV与独立烘焙目标。宏观变化来自分区/雨路，中层来自崩边/拼缝/涂漆磨损，细层来自毫米级矿粒/划痕，不能堆高对比噪声。底色不烘焙展示灯光。输出base-color（sRGB）、tangent normal（Non-Color）、ORM（Non-Color，R=AO/G=roughness/B=metallic），透明/发光需要则另列职责而非偷塞通道。

高细节源集合保留每石块/门窗/檐槽/支架与modifier；运行集合只保留已检查形/法线/UV/必要材料，导出GLB不携带灯光/相机/源高模。简化碰撞按可走地面、闭合建筑/柱体分别给合同，不能用精细渲染三角网格充当默认碰撞。LOD只有真实生成并检查过才出现在manifest，不能写空LOD接口。

## 实际API核验（尚无生产执行）

2026-10-13通过Blender MCP读取当前专用PID41948，Blender5.2.2 LTS、addon1.8、protocol13与server匹配，telemetry_consent=false，第三方library/generator均off。Scene为`AnotherWorld_AssetProduction`，`another_world_dedicated_session=true`，只有初始Cube/Camera/Light，尚未写文件。读操作未改变场景。

实际RNA确认`bpy.ops.object.bake`有type/pass_filter/margin/use_selected_to_active/cage/normal_space/normal_r/g/b/uv_layer；bake enum包含DIFFUSE/ROUGHNESS/NORMAL/AO/EMIT，tangent和+X/+Y/+Z存在。`uv.smart_project`有angle_limit/island_margin/correct_aspect/scale_to_bounds，margin/rotate枚举由实际RNA返回。bmesh bevel doc实际包含offset/segments/clamp_overlap/harden_normals。当前默认Principled节点输入包含Base Color/Metallic/Roughness/Normal/Emission Color/Emission Strength；节点按type查找，不按本地化显示名假定。

glTF实际operator包含use_selection/export_yup/export_texcoords/export_normals/export_tangents/export_apply/export_materials/export_animations/export_cameras/export_lights。export_format的静态RNA枚举为空，因此正式设置格式时需通过实际operator/异常枚举验证，不盲信旧文档枚举；实际GLB结果要读容器证实。这里仅证明API字段存在，不证明烘焙或导出成功。

网页/API current直接open三页遇402，真实失败保留为研究限制；官方5.2 LTS glTF手册搜索结果可读，确认ORM通道与normal tangent约定，且说明节点/UV/bake导出关系。[官方5.2 LTS glTF手册](https://docs.blender.org/manual/sl/5.2/addons/scene_gltf2.html)。实施时以已装5.2.2 RNA及实际导出二进制为准，不将5.3搜索结果当本机版本。

## 制作与验收顺序

1. 当前只建A样区与材料样本，在真实Blender相近玩法视角/近景查看结构、干湿与纹理；审查不足先修源，不扩4件。
2. 实际UV/烘焙channel/ORM接线与GLB读取审计后交根接入真实Main。TASK-317实际Main首样采用门槛通过后才扩B/C/D及8×8拼接；端面/侧面UV、边缘map padding与物理尺度一起检查。
3. 同样等待TASK-317，原创建筑才进入实际灰模+构造生产，再材料、门窗/檐槽/管线/植物，逐步在相同摄影视角查看。源码可以预备，但不执行扩族。
4. 保存可编辑.blend、源脚本、实际采用PNG和GLB。提供id/path/bounds/material/UV/pivot/真实LOD/placement/collision给根接入Main。
5. 几何/UV/map审计、Blender预览不能勾最终品质任务；实际Main同镜头、动作、雨水关系、性能和独立参考对照由根执行。

任何Heavy Cycles GPU bake/render启动前通知根，避开Comfy重GPU/真实游戏采样。CPU小样与GPU正式路径均记录device/samples/resolution/耗时；不能从shader存在或纹理文件存在认定效果达标。
