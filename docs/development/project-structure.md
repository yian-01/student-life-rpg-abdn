# 项目结构与职责

本页记录 Issue #1 工程基线实际创建的路径。`frontend/` 是 Flutter 应用根目录；仓库根目录的 `README.md`、`CONTRIBUTING.md`、`docs/`、`.github/` 继续保留。

```text
frontend/
├── pubspec.yaml
├── pubspec.lock
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── student_life_app.dart
│   │   ├── app_routes.dart
│   │   ├── app_theme.dart
│   │   └── unknown_route_page.dart
│   ├── features/
│   │   ├── bedroom/presentation/
│   │   ├── menu/presentation/
│   │   ├── schedule/presentation/
│   │   ├── gpa/presentation/
│   │   ├── finance/presentation/
│   │   └── dashboard/presentation/
│   └── shared/
│       ├── controllers/README.md
│       ├── repositories/README.md
│       └── storage/README.md
├── test/widget_test.dart
├── android/
└── windows/
```

## 当前职责

- `main.dart`：应用启动入口。
- `app/`：共享应用、主题、命名路由及未知路由页面；入口和路由由陈思翰维护。
- `features/`：按业务领域放置页面。当前页面主要是占位界面，不代表领域逻辑已完成。
- `shared/`：目前只有目录说明；公共模型、Repository 和存储契约待 B 审核后接入，不在 A 中另建一套。
- `test/widget_test.dart`：当前基线的 Widget 测试；2026-10-05 本机运行结果为 8 项通过。
- `android/`、`windows/`：Flutter 生成的平台工程；原生启动状态见 [开发环境说明](setup.md)。

后续按实际任务建立 `models`、`repositories`、`controllers`、`presentation`、`services`，不为凑目录创建空业务实现。`interaction`、`hud`、`academic` 等领域的代码由相应任务建立，不能把计划路径写成已存在文件。

## 分层与集成约定

页面使用 Controller，Controller 经 Repository 访问数据，持久化由 Storage 负责。纯模型和算法不依赖页面；依赖通过构造参数传入。跨模块共用类型由 B 的共享契约统一，业务模块不得自行复制 `TimeRange`、`ScheduleItem` 或 Repository 接口。

陈思翰统筹 `main.dart`、`app_routes.dart`、`student_life_app.dart` 的接线；领域负责人维护本人模块。卧室世界配置由 C 提供唯一的 `SceneGeometry`，视口坐标转换使用 `SceneTransform`；D、E、F 按共享接口接入，不各建一套坐标配置。C 的 v1.1 数值目前仍待组长审核及工程接入验证。

卧室世界坐标及 Android/Windows 适配遵循 [平台适配规范](../architecture/platform-adaptation.md)。在依赖该规范开展开发前，须确认它已提交并进入对应开发分支；规范本身不代表场景代码、Android 启动或 Windows 启动已经验收。