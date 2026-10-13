# 原创质量资产路径校验

TASK317前置准备，映射NFR301/304与AC308/311。新真实生产目录game/assets/quality需要由原WorldBuilder注册表安全接入；没有给默认世界添加尚不存在的资产。

真实业务red：3case，1failure/0error、exit100，旧验证器拒绝合法quality目录；原报告world-quality-business-red.xml。根集中目录名单、保留.glb/越界/反斜杠/外部路径拒绝；green严格3/3、failure/error/skip/flaky/orphan0、expected诊断0/未知0、exit0，见world-quality-green-summary.json/xml。夹具路径仅检验规则，不宣称该模型存在/已导入。

现有配置保持合法。该局部验证不等于A已进Main、模型品质或TASK317完成，后续必须等真实GLB/源通道/UV与实际取景观察。
