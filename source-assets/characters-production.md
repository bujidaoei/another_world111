# 003角色代表样本：真实生产记录

2026-10-13，关联TASK-222，用户自主制作授权与根协调激活003后执行。这里交付代表机械角色和动作源，不宣称最终商业品质、真人体验或Android通过。

## 文件与指标

| 资产 | 真实GLB | 源tri / 顶点 | GLB拆分顶点 | 文件大小 | 动作 |
| --- | --- | --- | --- | --- | --- |
| 盗窃者 | game/assets/models/thief_robot.glb | 2776 / 1500 | 5614 | 358736 B | Idle2s、Walk.4s |
| 疗愈者 | game/assets/models/healer_robot.glb | 3164 / 1704 | 6264 | 413468 B | Idle2s、Walk.4s、SelfHeal1s |

两件各1网格、1primitive、1材质、1真实skin、17joint及3张48²内嵌PBR图。拆分顶点数量来自glTF NORMAL/UV边界，不把源顶点数当作GPU提交顶点数。当前主体opaque，角色没有自带碰撞、奖励或治疗业务。刚性机械岛分别以1.0权重绑定骨，归一误差实测0；源非有限/退化/非流形/孤立指标均0。

源文件 `blender/characters-v1.blend`仅保存 `AnotherWorld_CharacterIdentities` 独立场景及实际依赖；517816 B，三图全部packed，源UV与PaletteUV分离。`scripts/character_factory.py`无导入副作用，执行main(['thief'])/main(['healer'])只重建拥有标记匹配的对应新角色；检查场景/对象共享，拒绝修改非项目对象。旧23GLB在生产前后逐件SHA256相同，见 `evidence/character-original-family-preserved.json`。

thief hash：`d768cfb93981971d2926776d338fe59c9c1bc4494c3105afcf4f4d3552d8ed73`。

healer hash：`7bc6753a8e968c088c9f3be0c6900acdae25e2b29548fbc68eb574286ab00039`。

Godot米制bind bounds为：thief min(-.5825,0,-.4395)，max(.565,2.277271,.4635)；healer min(-.5875,0,-.4395)，max(.565,2.265,.484)。0.76统一缩放后含头高度约1.7307/1.7214m；实际互动胶囊仍半径.38、高1.7，不能用视觉AABB替代判定。

## 动作与真实检查

17关节是Pelvis、Spine、Head、左右Clavicle/UpperArm/Forearm/Hand/Thigh/Shin/Foot。腿的两段固定长度IK确定足/膝姿势，导出的是实际骨关键帧；左右足分别有站立与摆动，不以全体摇晃冒充步态。右腕保持源局部(.46,.28,1.15)附近稳定持枪，左腕进行少量走路反向运动；疗愈者SelfHeal只抬左腕到胸部，保持站立足。

源求值与独立GLB二进制skin求值分别读取所有121/25/61样本：Walk足前后跨度约.68m、抬足约.16m、膝前后跨度约.4296m；模型最低脚地面误差约-4e-7m，loop顶点端点误差约1.3e-16m。SelfHeal左腕上移约.39m、横移约.40m，右持枪腕仅浮点误差变化。门禁是1–2mm/明确关节跨度，不能把这些数学值当作真人“自然动作”评价。

初轮MCP逐帧审查观察到冻结首姿势，保留 `evidence/thief-motion-defect-action-evaluation.json`。动作生成已改为暂时detach action、求完整骨局部姿势、恢复action后写keys；即时NLA预览求值还存在导出后缓存读回边界，最终审计采用明确action/slot和独立evaluated depsgraph。第一次恒姿势读回报告不是最终验收报告。最终源/二进制/实际Godot骨pose三份结果均确认非恒定动作，避免仅检查clip名字或通道数假通过。

最初导出曾出现“Armature must be parent”警告，已把蒙皮网格真正parent到其Armature，最终导出无该警告。现仍有原图集多个image node共用sampler警告，全部同Closest、最终三图与尺寸/PBR职责实际检查通过；不把已知警告隐藏为无日志。

固定Blender5.2.2导出器把不变化的骨translation/scale通道优化为2样本STEP，其余运动通道为LINEAR。独立审计显式处理STEP/LINEAR和旋转SLERP，而不是擅自把STEP当作损坏，数学按[Khronos官方skin说明](https://github.khronos.org/glTF-Tutorials/gltfTutorial/gltfTutorial_020_Skins.html)使用joint-global×inverse-bind；NumPy2.5.2版本记录在结果中。

## 分层证据

- `evidence/character-container-validation.json`：实际GLB容器、hash、无外部资源、PBR图、动作名与源几何记录。
- `evidence/character-source-motion.json`：Blender evaluated skin/足膝腕姿势、贴地/loop/span实测。
- `evidence/character-glb-motion.json`：二进制accessor、joint/weight/逆bind/UV/normal/triangle及独立CPU skin运动实测。
- `evidence/character-source-file-validation.json`：干净background Blender复读独立源scene、17骨、armature parent、双UV、三packed图。
- `evidence/character-godot-import.json`：实际Godot4.7.2 headless导入两PackedScene，Skeleton17bone、Skin17bind、Mesh1surface，AnimationPlayer seek后足交替抬/移与SelfHeal腕到胸，issues0。
- `previews/characters/`：17张真实原生PBR预览，含两正/背、四步态帧及五SelfHeal帧；已查看代表角度与关键姿态。这些是源审查图，不是活动游戏截图。

图集、几何和动画均为本项目原创，无付费模型/外部mesh/来源不明图片。沿原图集使用，未调用Comfy重复生产；权重/模型服务没有进入角色文件。最终源权利沿项目政策，此记录不替权利人新增许可证。

## 主工程集成合同与开放门槛

身份thief/healer映射到真实thief_robot/healer_robot路径，统一scale.76，前方-Z，脚原点0；同库存原电枪与当前WeaponMount(.42,1.15,-.28)合同，不能切角色赠武器。两角色源形状/设备只表达怪币回收与专属维护自疗，没有隐身/偷窃攻击或群疗表现。

Idle/Walk设LOOP_LINEAR，SelfHeal设LOOP_NONE并仅在真实能力成功后play。SelfHeal不是业务事件，不产生生命或重置冷却；持续20秒恢复/专属资格由CombatState唯一决定。动作进行时，移动Idle/Walk不能逐帧抢占同AnimationPlayer；返回移动与取消规则由场景实际状态负责，不能暂停物理来凑动画。

Walk源周期.4s，固定scale.76时名义前进速度2.584m/s；按实际水平速度/2.584匹配播放速率，并检查实际前/后/侧向移动。当前只有向前Walk，侧移/倒走还缺专用源clip或混合，不能宣称全向落脚无滑步。原型move_speed5.2时比例约2.012，速度增益也需跟随实际值；高频机械步态的最终自然度需活动画面/真人反馈。

下一验收：1280×720同位无菜单两身份/同敌人对照、实际持枪/闪避/防御与SelfHeal成功/失败/重启资格、受击材质不污染原共享atlas、动作交接与取消、生产Vulkan资源释放/性能增量、设备与真人。头less骨pose通过不证明GPU蒙皮渲染或最终商业美术。TASK-222保持相应游戏内/品质门槛开放，根协调将真实证据同步Spec Kit。
