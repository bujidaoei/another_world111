# 本地图像模型来源与采用决定

调查日期：2026-10-13。只使用官方发布主体/模型代码仓库和真实本地核验；镜像站许可标签不单独作为采用证据。

## sd_turbo：不用于当前商业资产

既有共享权重 `sd_turbo.safetensors`，5,214,561,328 bytes，本地 SHA256 `3f067a1b943cf162f2b8f8588f6cf5824bd5b4c7d1d88d87164b9ca123616549`，与 [Stability AI 官方模型目录](https://huggingface.co/stabilityai/sd-turbo/tree/main) 的 LFS SHA256 完全一致。

[官方模型卡](https://huggingface.co/stabilityai/sd-turbo) 指向商业许可。[该模型 LICENSE.md](https://huggingface.co/stabilityai/sd-turbo/raw/main/LICENSE.md) 的 Community License 包含商业主体注册和营收资格要求；当前 [官方许可说明](https://stability.ai/license) 也说明商业注册适用。项目没有这些已完成证据，决定不把模型用于本轮商业资产；未执行该模型推理，也未生成待发布产物。

## CompVis Stable Diffusion v1.4：固定官方来源

SD1.5 当前常见 HF 仓库明确自称非 Runway 关联镜像，不能把它当官方发布主体。因此选用原始作者 [CompVis 官方 v1.4 仓库](https://huggingface.co/CompVis/stable-diffusion-v-1-4-original)，固定 revision `f0bb45b49990512c454cf2c5670b0952ef2f9c71`，文件 `sd-v1-4.ckpt`，4,265,380,512 bytes，官方 LFS SHA256 `fe4efff1e174c627256e44ec2991ba279b3816e364b49f9be2abc0b3ff3f8556`。官方 API 元数据留存在 `../evidence/sd-v1-4-source.json`。

[作者代码仓库 LICENSE](https://raw.githubusercontent.com/CompVis/stable-diffusion/main/LICENSE) 是 CreativeML OpenRAIL-M，允许使用/销售而附使用限制，未设置商业注册或营收门槛；许可不替代输出本身的原创审查。保存全文于 `CreativeML-OpenRAIL-M.txt`。本轮只以抽象湿金属/石材表面为生成目标，不生成真实人物、商标、角色模仿或敏感内容。

权重下载由 Comfy MCP `download_model` 在本机工具链后台执行；采用前必须实际重算 SHA256 与以上一致。现有 ComfyUI `comfy/utils.py` 的非 safetensors 路径使用 `torch.load(..., weights_only=True)`，保持安全加载；若安全加载失败，不关闭检查，不采用不受限 pickle。

模型仅用于本地离线创作，不嵌入游戏、不公开模型服务、不把权重提交到 Git。任何图像只有通过输出/尺寸/可平铺/许可/实机审查才进入游戏。当前下载和推理状态以 `../evidence/comfy-production.json` 的实际记录为准；此文件的选择说明不是完成声明。
