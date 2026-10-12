# 卧室场景坐标设计（SceneGeometry）

- 版本：v1.2（按组长补充意见修订：sceneRect 公共接口、边界策略、新增测试 ⑥⑦⑧、
  数学脚本入库、环境状态按本机实际路径记录）
- 负责人：廖梦溪（Issue C / 对应 BASE-04 素材与坐标约定部分）
- 状态：**草稿，待组长审核冻结**。所有数值与 v1 一致，未改任何配置数值。
- 共用方：D（移动，廖梦溪）、E（交互/Menu 入口，黎宇轩）、F（HUD 定位）。
  D/E/F 必须读取唯一配置 `SceneGeometry` / `SceneTransform`，禁止复制坐标数值。

## 1. 素材清单（用户提供，未做任何修改/裁剪/生成）

| 文件 | 尺寸 / 模式 | 用途 | 已知视觉问题（本周不修图） |
| --- | --- | --- | --- |
| bedroom_world_v1.png | 941×1672 RGB | **运行底图**，一切坐标测量基准 | 无 alpha；与参考图非像素级叠加（见下） |
| bedroom_scene_v1.png | 941×1672 RGB | 合成参考（构图/层级），**不能当世界底图** | 与 world 底图全图平均像素差 ≈126/765，坐标不可互用 |
| player_idle_down.png | 103×205 RGBA | 角色精灵（idle 朝下） | alpha 二值硬边；脚底自带椭圆阴影 |
| player_status_hud_static.png | 296×235 RGBA | HUD 静态参考（F 使用） | 13.8% 半透明像素，边缘抗锯齿 |

运行素材原样存放，标注与测量图均为独立副本，不改动原图。

## 2. 坐标系与缩放规则（场景组件局部坐标）

- **world**：以 bedroom_world_v1.png 左上角为 (0,0)，x 向右、y 向下，单位原图像素。
- **local**：卧室场景组件内部坐标（Flutter 逻辑像素）。viewport 是组件**实际可用
  布局宽高**——若 SafeArea、导航栏或工具栏占用空间，使用扣除后组件的实际约束，
  不直接使用整屏尺寸。
- 等比缩放居中，互逆换算：

  ```
  scale  = min(viewportW / 941, viewportH / 1672)
  offset = ( (viewportW - 941*scale)/2, (viewportH - 1672*scale)/2 )
  local  = offset + world * scale
  world  = (local - offset) / scale
  ```

- 指针事件：事件若提供 globalPosition，先经场景 `RenderBox.globalToLocal` 转为
  local（只转一次）；若已取得 localPosition 不得重复转换。几何计算与交互距离
  **始终用 world 坐标**。
- 组件尺寸变化时只重算 scale/offset，**世界顶点常量不变**。
- 非正或非有限的视口尺寸不参与除法，直接抛 `ArgumentError`。

### 2.1 sceneRect 公共接口（v1.2 新增）

`SceneTransform.sceneRect` = `(offsetX, offsetY, 941*scale, 1672*scale)`
（Dart 中为 `Rect.fromLTWH`），是场景在组件内的实际显示区域。

- **F（HUD/覆盖层）** 以此为场景边界定位 HUD，不得自行推算缩放；
- **指针处理** 以此判断点击是否落在场景内（见 2.2）；
- 等比居中后视口两侧/上下可能留有空白（letterbox），空白不属于 sceneRect。

### 2.2 边界策略：场景外点击拒绝，不 clamp（v1.2 新增）

- 推荐入口 `SceneTransform.localToWorldChecked(local)`：点在 sceneRect 内返回
  world 坐标；**在场景外（如宽窗口两侧空白）返回 null，拒绝该次点击，
  不做 clamp**（不投影到最近边界点，避免"点空白却触发门"的假象）。
- `localToWorld` 保留为**纯数学换算、不做范围判断**；调用方必须先经
  `containsLocal` / `localToWorldChecked` 确认范围，再使用换算结果。
- 点击落在 sceneRect 内但落在可行走区外，是合法 world 坐标，由 D 的移动约束
  （脚底点不出 walkablePolygon）处理，不属于本边界策略。

## 3. 唯一配置常量（v1 数值全部保留）

| 常量 | 值 | 依据 |
| --- | --- | --- |
| worldWidth × worldHeight | 941 × 1672 | 底图实际像素 |
| playerSpriteSize | 103 × 205 | 角色图实际像素 |
| playerRenderWidth | 103（1:1） | 参考图中角色约为原始尺寸；spriteScale=1.0 |
| playerFootAnchor | **(51, 195)** 设计锚点 | 见 3.1 |
| playerStart | (360, 1160) | 走廊中央净空，见第 4 节 |
| walkablePolygon | (240,960)→(590,960)→(555,1010)→(550,1060)→(550,1385)→(75,1385) | 见第 5 节 |
| menuInteractionPoint / Radius | (200, 1170) / 70 | 见第 6 节 |

### 3.1 playerFootAnchor 是设计锚点，不是"最低不透明行"

- x=51 取双脚中心附近；y=195 取**主要鞋底接地参考线**（设计参考点）。
- alpha>128 包围盒覆盖 x=8..94、y=8..196，**第 196 行仍有左脚不透明像素**；
  首版允许少量脚尖低于参考线，最终贴地效果以叠图确认为准。
- 精灵定位公式：`spriteTopLeftWorld = footWorld − playerFootAnchor × spriteScale`；
  之后角色与背景共用同一次场景变换，**锚点不重复缩放**。
- 若后续改为 y=196，须同步更新唯一配置、标注、本文档与测试，并经组长确认。

## 4. playerStart (360, 1160)

- 位于主走廊中央净空；在 walkablePolygon 内（数学核查 ③ PASS）。
- 与 menuInteractionPoint 距离 160.31 > 70，**初始位置不出现交互提示**。
- 存在完全处于区域内的直线路径抵达 menuInteractionPoint（核查 ④ PASS，
  采样 2001 点 + 精确线段-边求交）。

## 5. walkablePolygon（首版保守版）

只圈确认安全的地板走廊，顺时针：

| 顶点 | 坐标 | 依据 |
| --- | --- | --- |
| P0/P1 | (240,960)→(590,960) | 上界：床脚板下沿 y=960（crop-bedfoot.png） |
| P2/P3 | (555,1010)→(550,1060) | 右上过渡：床脚右缘到书桌左缘 |
| P3/P4 | (550,1060)→(550,1385) | 右界：书桌/椅子左缘 x=550（crop-desk.png） |
| P4/P5 | (550,1385)→(75,1385) | 下界：底部木栅栏上沿 y=1385（crop-bottom.png） |
| P5/P0 | (75,1385)→(240,960) | 左界：左墙踢脚线斜边（crop-door.png / world-grid.png） |

- 排除：床、床头柜、书桌、椅子、墙体与栅栏。
- **只约束脚底点**，不构成完整人物轮廓/家具碰撞证明；角色上身可能视觉上
  探入家具上方，属预期。
- 边界由逐行地板掩膜 + 放大网格图校正；测量证据见
  `docs/development/scene-geometry-measurement/`（world-grid 总网格、crop-door、
  crop-bedfoot、crop-desk、crop-bottom 五张）。
- **v1.2 复核结论：家具/墙边界与图像一致，未发现需改值处**；若后续发现不符，
  列出具体坐标与图像证据交组长确认后再改。

## 6. Menu 交互点 (200, 1170)，半径 70

- 门体绿色门板范围约 x 130..250、y 720..1225，门底中心约 (190,1180)；
  交互点取门前地板 (200,1170)，半径约一格地砖宽。
- E 的距离判定：欧氏距离 ≤ 70 可触发。核查点（y=1170）：
  x=269 → dist 69.00 **可触发**；x=270 → dist 70.00 **可触发**；
  x=271 → dist 71.00 **不可触发**。
- **E（黎宇轩）的 InteractionTarget 直接引用
  `SceneGeometry.menuInteractionPoint / menuInteractionRadius`，不另定门位置。**

## 7. 标注图

`docs/development/images/scene-geometry-v1.2.png`：在 world 原图副本上标注
P0–P5 坐标、闭合可行走区、playerStart、r=70 交互圈、起点→Menu 路径、
精灵包围盒（含锚点）与核查点 269/270/271。

## 8. 验证

### 8.1 数学核查（已执行，全部 PASS）

脚本：`docs/development/scene-geometry-check.py`（纯标准库）。
本机执行命令与结果：

```
$ python docs/development/scene-geometry-check.py
[PASS] ③④⑤ 区域/路径/半径；初始距离 160.31 > 70
[PASS] 核查点 269/270/271 -> 可触发/可触发/不可触发（69.00/70.00/71.00）
[PASS] ① local→world→local 最大误差 0.00e+00（<=0.01）
[PASS] ② world→local→world 最大误差 2.27e-13（<=0.01）
[PASS] 非法视口 (0/-5/NaN/Inf) 全部拒绝
[PASS] ⑥ 宽窗口两侧/窄窗口上侧空白点击拒绝
[PASS] ⑦ 场景内点往返（world=(200.0011,1169.9987)）
[PASS] ⑧ 窗口变化后变换结果与世界常量不变
结果：全部检查通过。
```

执行环境（本机实际路径）：
`C:\Users\liaoliao\.workbuddy\binaries\python\envs\default\Scripts\python.exe`
（Python 3.13.12 venv）。

### 8.2 两种视口预期计算（已记录）

| 视口（逻辑像素） | scale | offset | playerStart local | menu local | 交互圈屏幕半径 |
| --- | --- | --- | --- | --- | --- |
| 320×640 | 0.3400638 | (0, 35.7067) | (122.423, 430.181) | (68.013, 433.581) | 23.804 |
| 800×600 | 0.3588517 | (231.1603, 0) | (360.347, 416.268) | (302.931, 419.856) | 25.120 |

800×600 的 sceneRect = (231.1603, 0, 337.6794, 600)，左侧 x<231.16 与
右侧 x>568.84 为空白区，点击须拒绝（测试 ⑥）。

### 8.3 Dart 测试（用例已就绪，**未执行**）

`docs/development/drafts/scene_geometry_test.dart`（BASE-01 合并后移入
`frontend/test/bedroom/`）。覆盖 ①–⑤ 及 v1.2 新增：
⑥ 宽窗口两侧空白点击拒绝（含 320×640 上侧空白）；⑦ 场景内点击接受 +
local↔world 往返 ≤0.01；⑧ 窗口变化后世界常量与同一视口变换结果不变。
注意：Dart 侧 `_segmentInsidePolygon` 仅做密集采样，精确求交在 8.1 脚本。

**未执行原因**：本机无 Flutter SDK；BASE-01 工程基线未合并（仓库无
frontend/、无 pubspec.yaml）。包名 `student_life_rpg` 为占位假设，
BASE-01 合并后须按 pubspec.yaml 的 name 核对 import（测试文件内已标 TODO）。
就绪后执行 `flutter test test/bedroom/scene_geometry_test.dart`，
结果回填本节。

### 8.4 未执行项汇总（如实记录）

| 项目 | 状态 | 原因 |
| --- | --- | --- |
| flutter test / dart format / flutter analyze | 未执行 | 本机无 Flutter SDK（`where flutter/dart` 无结果） |
| 运行截图（两平台） | 未执行 | 无 Flutter 工程可运行（BASE-01 未合并） |
| 路径核对（frontend/lib/... 实际落位） | 未执行 | 仓库 project-structure.md 路径栏**故意留空**，待 BASE-01 |
| 推送分支与开 PR | 未执行 | 本机无 gh CLI、无 git 凭据（无法非交互推送） |

### 8.5 环境状态（本机实际路径，v1.2 记录）

- 团队仓库检出：`C:\Users\liaoliao\Projects\student-life-rpg-abdn`
  （main @ 2b2baf0，仅 docs + 模板；**无 frontend/、无 pubspec.yaml →
  BASE-01 未合并**；个人项目 `D:\Projects\student-life-rpg` 未触碰）
- Git：`C:\Users\liaoliao\.workbuddy\binaries\PortableGit\versions\1.2.0\mingw64\bin\git.exe`
  （user.name=LMX817；无 credential helper）
- Python：`C:\Users\liaoliao\.workbuddy\binaries\python\envs\default\Scripts\python.exe`
- Flutter/Dart SDK：未安装

## 9. C/D/E/F 共用配置确认状态

- 唯一来源：`docs/development/drafts/scene_geometry.dart`（BASE-01 后移入
  `frontend/lib/features/bedroom/models/`）。
- **待组长审核冻结**（本 PR 即审核入口）。
- 待黎宇轩确认 E 引用 menuInteractionPoint/Radius（第 6 节）。
- F 引用 sceneRect（2.1 节）——本次新增，需在评审中知会 F 负责人。
- D 的移动约束复用 walkablePolygon（第 5 节），D 开发不早于配置冻结。

## 10. 限制清单（如实声明）

1. 可行走区为保守首版，只约束脚底点，不含人物轮廓/家具碰撞证明。
2. 坐标全部以 world 原图实测为准；scene 参考图与底图非像素级叠加，不可互用。
3. 素材未做任何修改；已知视觉问题（硬边、脚底阴影、HUD 半透明）本周不修。
4. 锚点 y=195 为设计参考点，贴地效果以叠图确认为准。
5. 本版本不含移动、导航、奖励任何实现（属 D/E 及后续 Issue）。

## 11. 待确认事项

1. 组长：审核并冻结全部配置数值（本 PR）。
2. 组长/全员：确认锚点维持 y=195（改 196 的代价见 3.1）。
3. 黎宇轩：确认交互点/半径引用方式（第 6 节）。
4. F 负责人：知悉 sceneRect 公共接口（2.1 节）。
5. BASE-01 合并后：核对包名 import、移入 Dart 草稿、执行 flutter test 并回填 8.3。
