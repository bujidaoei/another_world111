# 第三方材料与分发边界

仓库包含本项目原创模型、对象动画、音频与一张本地生成的着色纹理；不包含模型权重或游戏构建二进制。素材来源和实际哈希见 `source-assets/`。

| 材料 | 来源 / 固定版本 | 许可 | 本次用途与修改 |
| --- | --- | --- | --- |
| GitHub Spec Kit脚本/模板/Codex skills/工作流 | https://github.com/github/spec-kit / commit 31a06101ef832bac32968df5e94607a51630b895 / 0.8.10.dev0 | MIT，声明见 [.specify/LICENSE](.specify/LICENSE) | 官方CLI初始化；模板追加追溯条款；统一LF/尾空白，仅格式修改；宪章为本项目内容 |
| Godot AI工程插件 | https://github.com/hi-godot/godot-ai / v4.3.0官方签名release | MIT，声明见 [game/addons/godot_ai/LICENSE](game/addons/godot_ai/LICENSE) | 编辑器/MCP开发工具；生产构建去除插件与运行调试helper |
| GdUnit4 | https://github.com/godot-gdunit-labs/gdUnit4 / 6.2.2 / commit0127a55f4543dfc24746f6e5c7ba6f94105d51f2 | MIT，声明见 [game/addons/gdUnit4/LICENSE](game/addons/gdUnit4/LICENSE) | 原始vendor文件不改；游戏测试runner门禁另写于tools；生产构建去除 |
| 本地扩散模型产物来源 | CompVis/stable-diffusion-v1-4作者仓库固定revision，详细记录见 [model-provenance.md](source-assets/licenses/model-provenance.md) | CreativeML OpenRAIL-M，原许可与限制见该记录 | 本地Comfy生成wet_concrete_albedo着色微变化；权重不分发；不称为法线/高度图 |
| 原创GLB、图集、对象动画、程序合成音频 | 本项目 source-assets/scripts 与 source-assets/audio | 项目权利人政策，未擅自授予公开许可 | 原创内容；实际源文件/资产清单/检验记录可追溯 |

视频/图片参考仅研究，没有游戏素材或源图分发授权；本地reference截图被gitignore排除。
本机引擎、Blender、Comfy与权重不复制进仓库；GdUnit仅作为开发依赖登记。
资产按data-model的AssetRecord记录来源、作者、版本、用途、修改、商用/署名/源分发和采用文件。
用户尚未指定正式项目公开许可；本文件不会擅自给原创项目选择开源许可。
