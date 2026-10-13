# 实际Comfy油漆研究样本

2026-10-13。prompt_id bb5533a8-6fd6-4bfc-be31-70b6ef53124a，本地Comfy0.39.2/cli1.22、RTX4060约8GB、实际live节点库存核验，validate valid=true/errors0/warnings0/partner_nodes空/spends_credits=false。真实提交→completed→fetch_outputs，输出outputs/bb5533a8_000.png，512×512、488936B、SHA256 71BACEEAD5C544982968BDB07628AEA0B2C400CA5CAC201BEF87ED936230F23D。完整workflow SHA256 0C1363625265332FAC03E2055217E08AF6F315C6833B26FFA017F07D6C520E0D。

模型使用已有固定CompVis v1.4官方revision/hash，来源与许可在source-assets/licenses/model-provenance.md；sd_turbo当前商业资格未证明，未采用或运行。不增加模型或付费调用。

根实际看过像素：漆面微颗粒、低饱和灰橄榄和细锈点存在，但固定硬板缝、明显边缘阴影/高光不适合作无缝运行贴图。保留为颜色与磨损分布研究，未装入运行材质；不从这幅图伪推导normal/ORM/height。004材料仍需要原创高模/程序材质与真实UV/烘焙，游戏内品质门槛未通过。
