# 局部技术门槛验收

2026-10-13，Spec Kit功能002。当前设备Windows 11、i9-14900HX、RTX4060 Laptop、约32GiB RAM；完整游戏目标保持active。

TASK-101：spec/plan/tasks/decisions/data-model/contracts/validation/checklist已有真实可追溯工件；自主规则、平台顺序、工具职责和不虚报外部验收已冻结。`verify_spec.py --feature specs/002-singleplayer-prototype`结构/依赖/工件检查通过；该检查不执行游戏测试。原始附件中的敏感字段只在内存中核对，无凭据输出或复制。

TASK-102：GodotAI官方4.3.0签名release通过已安装验证器的签名、archive SHA256和完整inventory验证；archive SHA256 `dbc3d16e1aa7a5f3ae8038a150bf4191162112f4329c79611aa6f656e3ca4e58`。安装313文件逐项SHA256一致，0缺失/差异。实际MCP会话`game@66b0f098620098c5`位于本项目`game/`，Godot4.7.2；真实scene_run/game_eval/screenshot及材质/雨粒子制作均返回有效结果。原始小型验证摘要见同目录godot-ai-*json。运行脚本修改后必须导入/scan再启动，旧运行实例不作为新源码验证。

TASK-103：固定GdUnit4 6.2.2、源码commit `0127a55f4543dfc24746f6e5c7ba6f94105d51f2`；vendor检查和实际pass/fail/zero发现门禁见[persistence-and-gdunit.md](persistence-and-gdunit.md)。预期失败和空发现的wrapper均退出非零；不凭Godot进程exit0报告成功。

TASK-104/105：独立GdUnit核心25个测试通过（成长7、远征/库存8、装备10），0failure/error/skip/flaky/orphan，见[gdunit-core-rules.xml](gdunit-core-rules.xml)。覆盖20XP成长/30封顶与储备、真实奖励事务幂等、负载/失败/结算、融合锁/成本/候选/预算/身份经历、所有合法4槽组合极值扩槽、阶级资格；24种成本矩阵、55种合法4槽组合与160个seed循环为用例内部检查，不冒充新增测试个数。实际red案例先失败后修复，报告保留在本地artifacts/core-rules-boundary-*。

TASK-111：本地ComfyMCP实际24步推理及16节点原生规范化完成，固定作者CompVis v1.4来源与权重SHA256验证，权重不入库；实际采用wet_concrete_albedo.png，SHA256 `55248ef8750451abe62a3488004904f25dbd7347735c40b74a026dceb8745dae`。512²RGB微着色样本两方向边缘最大差异0，3×3实看；原工作流/任务/作者许可全文与输出记录见[资产说明](../../../../source-assets/README.md)。未经商业注册资格证实的SD Turbo没有用于游戏产物。

上述仅验收各任务的明确局部门槛；不替代完整原型流程、视觉品质、性能、真人或Android设备结论。正在制作的额外输入/全局偏好/场景变化仍要重新测试。
