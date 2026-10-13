# 原创原型音频制作与技术验证

日期：2026-10-13（Asia/Shanghai）。关联TASK-113、TEST-113、REQ-101/108、AC-101/108。

## 真实制作

`source-assets/audio/generate_audio.py` 使用Python3.14.3标准库和固定seed20261013，实际生成15个原创WAV，无外部录音、采样包、模型输出或收费服务。源脚本、作品/用途与权利记录在 `source-assets/audio/README.md`，逐文件SHA256、格式、峰值、RMS、DC、时长及接缝数据见 `source-assets/audio/manifest.json`。

文件包括 electric/impact各两种变体、dodge/collect/confirm/hurt/pulse/anchor/failure/victory各一；12秒雨环境循环；80 BPM、D小调、8小节、24秒音乐底层与战斗层。音色/音符由本项目代码原创编写，未复制参考音频。

生成器真实重新打开全部WAV验证：单声道、44.1kHz、16bitPCM，非零RMS、0削波；3个循环首尾采样差为0。重新生成前后15个WAV的SHA256逐一一致。接缝端点一致只是技术条件，不替代声音试听。

## Godot模块

`game/presentation/game_audio.gd` 的 AWGameAudio 已实现：

- Master/Music/SFX/Ambience/UI命名bus，已存在时复用；四音量独立映射dB，UI遵循sfx_volume，0显式静音。
- 8个固定EventVoice；空闲复用，满载时按优先级和开始时间抢占；较低优先事件不抢占更重要声音。10事件即时调用，electric/impact样本变体与少量音高/衰减变化。
- 雨循环与AudioStreamSynchronized双音乐层；两层同起点，遭遇状态驱动战斗层0.9秒淡入/淡出；退出停止player并终止Tween。
- 预留主混音余量，Master没有HardLimiter时添加-1dB ceiling安全保护；全部settings音量最大时保守绝对峰值和上界约0.823。

## 实际Godot技术探针

将源 `audio_probe.gd`、当前模块和当前WAV复制到独立本地项目，固定Godot4.7.2真实import、解析并执行；未使用root的编辑器/MCP，不修改主项目存档或正式test文件。

最新54项检查通过，退出0、无脚本/引擎错误、无退出资源警告。包含总线/效果复用、设置非法拒绝、0音量静音、全部事件实际play、8并发饱和/优先级、同步层淡入淡出、雨和音乐seek至循环末端后实际越界继续；新增stop_all多次幂等、所有stream引用释放、停止时拒绝新事件和显式安全重启。

使用AudioEffectCapture读取真实Godot混音的81920帧，包含8个重叠结算音效的完整时长。最新峰值0.592209、RMS0.171183，低于-1dB ceiling；见 [实际探针报告](audio-runtime-probe.json)。音效随机微衰减会令后续采样数值变化，不改变门槛。

首次独立探针在queue_free后立即结束，Godot AudioServer下个混音周期尚未回收playback而报资源仍在使用。修正探针释放后的等待，再执行无警告/错误。后续成品首次--quit-after暴露正式关闭时同样的8个loop/playback生命周期诊断，因此实装非阻塞stop_all与主游戏统一异步关闭流程，再用实际WM_CLOSE验证零泄漏。没有屏蔽诊断来制造通过；详见Windows构建证据。

官方API依据：[AudioStreamWAV循环](https://docs.godotengine.org/en/stable/classes/class_audiostreamwav.html)、[AudioStreamSynchronized](https://docs.godotengine.org/en/stable/classes/class_audiostreamsynchronized.html)、[HardLimiter](https://docs.godotengine.org/en/stable/classes/class_audioeffecthardlimiter.html)、[AudioServer](https://docs.godotengine.org/en/stable/classes/class_audioserver.html)，并以实际当前版本运行核查。

## 验收边界

探针使用headless/Dummy音频驱动，其实际混音证据不等于耳机或扬声器试听。主游戏事件触发与可听播放、游戏音乐转场、长时间重复疲劳、移动设备输出及最终商业音频品质尚待真实集成验收，不声明通过。TASK-113记录为已制作/技术验证/待游戏试听与时序验收。
