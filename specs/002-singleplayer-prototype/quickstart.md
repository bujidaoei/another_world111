# 运行与验证
本feature正在实施，构建/测试结果以evidence为准。
Godot项目位于game/，从编辑器打开game/project.godot。
键鼠计划：WASD移动、左键攻击、右键防御、Space闪避、Q冲击、F锚点（需二阶）、E交互、H药包、C锁镜头、滚轮缩放/中键旋转、R镜头复位、Esc暂停。
脚本runner：tools/run_gdunit.ps1 -GodotPath <本机引擎>；实际CLI已由负责代理核查。
渲染/输入/音频不由headless替代；缺实际手机和手柄时设备任务不完成。
启动失败查看logs，不能清除唯一保存；设置/启动画面显示错误恢复入口。
