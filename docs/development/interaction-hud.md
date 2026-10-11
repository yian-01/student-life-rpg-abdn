# Issue 13 交互与 HUD 首批交付

负责人：黎宇轩。采用冻结契约 v1.0 §8、§9、§15。

本批实现交互控制器、目标校验、可更新 HUD 与未缩放覆盖层。**保持 Draft**：
#8 的 PR #16 尚未合并，#15 的实际卧室输入/素材/组合接线尚未完成。
当前 main 不含移动和几何源码，不能直接编译本批交互模块。
不复制生产替身，不修改 A 的路由或 D 的页面，不将隔离测试称为联调。

## 实际基线与材料

- main：`aa64f1f41f9801b5882d6dd2b99837d795c0df4c`。
- 分支：`feat/13-interaction-hud`，从该 main 创建。
- Flutter 3.44.6 stable / Dart 3.12.2，未升级依赖，pubspec 和 lock 保持不变。
- 原 checkout 为 `D:\Projects\student-life-rpg-abdn`；原 main 有三个 Windows
  generated plugin 文件修改，保留原目录，在隔离副本开发。
- 已读取五份附件、Issue #13 全文及两条评论、#8/#15 及其评论、PR #16、
  README、CONTRIBUTING、冻结契约、平台规范、pubspec/lock、公共类型、路由及基线测试。
- 附件中的旧 `lib/game/`、屏幕左上锚点及远期奖励范围，以冻结契约覆盖。
  本批 HUD 仅呈现外部数据，不发 EXP、不升级、不持久化。

## 接口与接线

```dart
import 'package:student_life_rpg/app/app_routes.dart';
import 'package:student_life_rpg/features/bedroom/controllers/player_movement_controller.dart';
import 'package:student_life_rpg/features/bedroom/models/scene_geometry.dart';
import 'package:student_life_rpg/features/interaction/models/interaction_target.dart';
import 'package:student_life_rpg/features/interaction/controllers/interaction_controller.dart';
import 'package:student_life_rpg/features/hud/models/hud_view_data.dart';
import 'package:student_life_rpg/features/hud/presentation/player_status_hud_overlay.dart';

// 由 A 在持有场景状态的 State.initState 中创建一次。context 不进入 Controller。
final movement = PlayerMovementController();
final interaction = InteractionController(
  movement: movement,
  target: InteractionTarget(
    id: 'menu',
    label: '进入菜单',
    routeName: AppRoutes.menu,
    worldPoint: SceneGeometry.menuInteractionPoint,
    radius: SceneGeometry.menuInteractionRadius,
  ),
  navigate: (routeName) async {
    await Navigator.of(context).pushNamed<void>(routeName);
  },
);
```

`InteractionTarget` 及 `HudViewData` 使用命名 required 参数，字段 final。
非法构造值抛 ArgumentError，字符串保留原值。
`canInteract` 在导航中或 dispose 后为 false，其他时候由当前 world 脚底位置计算。
`triggerInteraction()` 再次校验范围。失败保留原始 `Object? error` 并通知 UI；
下一次合法重试先清除 error。锁在第一段同步执行中取得，覆盖整个 route Future。
导航前 pause/clearInput，finally clearInput/resume，不 reset、不重建 movement。
dispose 解除监听、清空输入，不销毁外部 movement；若仍在导航，保持暂停，
避免 Menu 未退出就恢复已离开的场景。后续 Future 完成不再访问 movement。
销毁顺序为 interaction，然后 movement；若所有者确需复用 movement，应在确认旧
路由结束且场景重新激活后显式 clearInput/resume。普通返回仍由 finally 清输入并恢复。

A/D 的正式 SceneViewport 接线要求：

1. 使用同一 movement、同一 C 配置、同一 SceneTransform。不能复制世界尺寸或门坐标。
2. 范围内显示 Windows “按 E 进入菜单”和按钮；Android 显示触摸按钮。
   E 的 KeyDown、按钮鼠标/触摸都调用 `triggerInteraction()`；重复键事件无需另开导航。
3. 若支持点击世界门，GestureDetector 在 SceneViewport 接收 localPosition 后调用：
   `interaction.triggerAtLocalPosition(localPosition: details.localPosition, transform: transform)`。
   已局部坐标不要再 globalToLocal；全局事件只在页面转换一次。
   该适配先拒绝留白、非目标点，再进入相同距离/锁保护入口。
4. 页面通过 ListenableBuilder 监听 interaction，显示 error 与重试入口。
   Ticker 更新和键盘/摇杆消费在 isNavigating 或失焦/离页时停止；清空页面自己的按键集合，
   不能仅清 Controller 后又把旧集合送回。返回后重新获取焦点并等新的移动输入。
5. 无效视口不构造变换、不接收场景输入。resize 只重算 transform，不改 movement。

HUD 由 A 维护外部演示状态并标注“演示数据”：

```dart
var hud = HudViewData(
  displayName: 'Demo Player', level: 1, exp: 0, expToNextLevel: 100,
);
// A 的明确演示按钮中通过 setState 或其状态管理更新：
hud = HudViewData(
  displayName: 'Demo Player', level: 2, exp: 25, expToNextLevel: 100,
);

// 位于同一个 SceneViewport Stack 的未缩放 UI 层：
// 世界 Transform 与本 Overlay 是并列 children，不能包住 Overlay。
PlayerStatusHudOverlay(data: hud, sceneRect: transform.sceneRect);
```

Overlay 左上为 sceneRect 左上 + 12 逻辑像素，宽度至多 280 且不超过 sceneRect.width-24。
无效或可用宽/高<=0 不布局。名称、等级、原始 EXP 使用换行且无固定文字高度，
有限高度由 PlayerStatusHud 自身通过垂直滚动访问全部内容，Overlay 不再额外套滚动。
极小宽度不足一个字形时启用水平滚动，保持用户字体大小；普通宽度仍换行。
进度 0..1，语义标签包含名称、等级与原始经验。
字体/边距不乘 world scale。只有外部输入决定显示，不自行改变等级。

## 验收和真实结果

2026-10-11，Windows x64，使用 SDK 绝对路径执行。E/F 共新增 34 项测试
（首批 29 + 本次审查 5），基线 15 项保留。

隔离验证目录使用 main 的已有工程与 **PR #16 固定 SHA
`87a3d54edcf31cd856b0a14c452549de413130c2` 的三个正式源码文件**：
player_movement_controller.dart、scene_geometry.dart、walkable_area.dart。
它们通过 GitHub connector 获取，未合并/提交到 #13 分支。测试用显式位置与导航回调；
Widget 测试使用单独 TestScene，标注“测试位置，未联调”，并调用已有 AppRoutes/Menu。
这不代表提供方已合并、素材叠图、实际 BedroomPage 接线或原生输入验收。

| 检查 | main + 本批 E/F | 隔离加入 PR #16 的三个正式源码 |
| --- | --- | --- |
| flutter pub get | 通过，无依赖版本变动 | 通过 |
| dart format --output=none --set-exit-if-changed lib test | 通过，26 文件无变化 | 通过，29 文件无变化 |
| flutter analyze | 失败：正式移动/几何 import 缺失及派生错误 | 通过，No issues found |
| flutter test --reporter expanded | 失败：交互 controller/navigation 测试无法加载 | 49 项全部通过（15 基线 + 34 本批） |
| 独立测试（基线、HUD、目标模型） | 34 项全部通过 | 已含于 49 项 |

| 需求 | 证据 | 状态 |
| --- | --- | --- |
| 范围内/等于/外，trigger 再校验 | interaction_controller_test / interaction_target_test | 隔离通过 |
| 连触 10 次、pop 后再进入、同步/异步异常与重试 | controller_test / navigation_test | 隔离通过 |
| 返回保位置，清除停留期间输入；监听释放，待完成 Future 的 dispose | controller_test | 隔离通过 |
| 留白、右/下边界、非目标点击、指针不能绕过玩家距离 | controller_test | 隔离通过 |
| ratio 0/.25/1/1、阈值 0 拒绝、外部状态同时更新 | hud_view_data_test / player_status_hud_test | 通过 |
| 长名称、26/80/160/320 宽、文字放大、resize、world Transform 独立 | player_status_hud_test | Widget 通过 |
| 无效 sceneRect、不布局；可读语义标签 | player_status_hud_test | Widget 通过 |
| 正式 Bedroom/Menu/演示按钮接线、素材与输入、Windows 录屏 | 待 #8 合并、#15 组装 | 未完成，未验收 |
| Android 原生触摸 | doctor 未找到 Android SDK，devices 无 Android | 未执行 |

本次 Windows `flutter run -d windows --no-pub`：原生 Debug 构建和启动成功（23.2 秒），
产生 Dart VM Service；随后关闭本次隔离目录的应用。当前 `lib/main.dart` 显示基线
占位页面，不呈现本批 E/F，未进行原生键盘/鼠标交互回归，不计 E/F 验收通过。
Windows doctor 检测 Visual Studio/Windows SDK 可用；Flutter/Dart 不在当前 PATH，
以已安装 SDK 的绝对路径调用。Maven 网络检查仍超时；本次明确允许 SDK
缓存访问后正常执行检查，授权网络环境下 git fetch 已成功，main 仍为 aa64f1f。
原生启动记录另附于交付 PR；基线占位页启动不能作为 E/F 原生联调证据。
未提供 E/F 原生截图/录屏，未执行 Actions。没有奖励链路、没有新增持久化声明。

## 后续负责人

- 陈思翰审核；先合并/确认 #8 PR #16 的正式源码，然后同步 main 并重跑完整检查。
- #15 与 #8/#13 协调真实 SceneViewport 素材、Ticker/键盘/摇杆、门按钮和 HUD demo 接线。
- Windows 录屏及 Android 原生验证分别补齐，所有未验收项保持未勾选。
- 首批使用 Refs #13，不自动关闭 Issue，不自行合并。

## 本次独立审查与修复

- 修复 dispose 在导航未结束时立即 resume 的问题。旧实现的回归测试显示，
  Menu 覆盖期间销毁交互控制器后输入可使玩家从 (200,1170) 移到 (206,1170)。
- 修复独立 PlayerStatusHud 在 160×40 约束下的 RenderFlex 溢出，
  旧实现溢出 396 像素。新测试滚动到底并验证 EXP 进度条确实位于可视区域。
- 26 像素 sceneRect 扣边距后只剩 2 像素，换行不足以完整访问字形；
  增加水平滚动并验证滚动位置实际改变。该极端尺寸可读性仍有限。
- 原 late Future 测试仅使用正式 movement，而其 clearInput/resume 不检查
  disposed，可能漏报迟到访问。测试改用正式类的监测子类，明确断言调用次数。
- 新增页面级失败提示与重试测试；它属于隔离 TestScene，不能冒充正式 Bedroom。
- 修复前四项针对性回归均失败，修复后全套通过；原有正常 push/pop、
  同步/异步错误、范围、留白、HUD 更新/定位等测试继续保留。
- 重新读取五份原始附件的相关正文与当前 GitHub 正文/评论；
  原附件的 lib/game、远期奖励/持久化范围继续服从已合并契约。
