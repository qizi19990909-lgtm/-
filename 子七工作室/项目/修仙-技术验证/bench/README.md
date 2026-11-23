最小压测/导出验证项目（2026-11-19，非正式开发）。
- 运行：godot --headless --frame-delay 0 --path . -- mode=skel|anim|spine n=60
- spine 模式需先把 spine-godot GDExtension（4.3 / Godot 4.7.2）的 bin/ 放到项目根目录，并把官方示例 spineboy-pro.skel / spineboy-pma.atlas / .png 放到 spine/，仅用于评估。
- 结果见 ../../修仙小队游戏-技术方案.md 第 5 节。
