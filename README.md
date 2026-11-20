# Student Life RPG

大学生学习与生活管理工具，使用 Flutter / Dart 开发。V1.0 提供学业、日程、个人财务和本地 RPG 空间。

## 当前交付状态

V1.0 功能冻结提交：`29b1bebb208fc3f2d0fd6cfe684e280eba0f7583`，版本 `1.0.0+1`。

2026-11-21 在 Windows 独立复核：739 项 Flutter 测试通过，静态分析无诊断，格式检查 225 文件、0 改动。同提交 Windows/Android CI 验收制品已校验，当前状态是**验收候选，尚未发布正式稳定版**。PR #68 仍待审查和批准。

详见 [V1.0 收尾记录](docs/project-management/v1-closeout.md) 和 [功能验收表](docs/project-management/v1-feature-acceptance.md)。

## 功能

- 学期、课程、作业、考试、GPA 和课程单次调停课。
- 日程、周课表、待办、任务优先级与子步骤、事件、跨模块搜索。
- 收支账目、分类、分类月预算、统计、报销与票据。
- 完整备份恢复、删除撤销、任务/事件/账目复制。
- 今日规划、专注计时、周课表 ICS 与账目 CSV 导出。
- 卧室场景、角色移动、交互入口和 HUD。

V1.0 此候选支持 Windows 和 Android 本地使用。Web 存储适配、账号与云同步在 V1.1 独立分支；本分支不把后续实现算作已交付能力。

## 运行与检查

要求 Flutter 3.44.6、Dart 3.12.2。

```sh
cd frontend
flutter pub get
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test
flutter run -d windows
# 或连接 Android 设备后，通过 flutter devices 选择设备运行。
```

Windows 构建需要 Visual Studio 的 C++ 桌面工具链以及 PATH 中的 NuGet；Android 需要 Android SDK、受 Flutter/Gradle 支持的 JDK 和可访问的 Gradle/Maven 仓库。安装包构建命令：

```sh
flutter build windows --release
flutter build apk --release
```

Windows 应完整分发 `build/windows/x64/runner/Release/`，不能只复制 EXE。Android release 必须先按 `frontend/android/key.properties.example` 配置真实签名密钥；未配置会拒绝打包。仅生成验收 APK 时，可显式设置环境变量 `ORG_GRADLE_PROJECT_studentLifeAcceptanceSigning=true` 后构建，产物使用本机调试签名，不能作为正式稳定版或保证兼容旧安装。

本轮已核实两轮历史 V1.0 APK 签名不同。不要直接卸载仍存有未导出数据的旧应用。长期签名及旧安装迁移方式确认前，不发布新的稳定 APK。

## 数据与代码结构

Native 数据保存在应用支持目录的版本化 JSON 文件：`campus.json` 保存学业、事件及财务，`tasks.json` 保存任务。CampusData schema v3 支持旧格式迁移；备份恢复对两份文件做完整回滚保护。这里的实际实现不是早期设计文档中设想的 SQLite。

| 目录 | 内容 |
| --- | --- |
| `frontend/lib/app` | 路由、业务装配、备份与恢复 |
| `frontend/lib/features` | 学业、财务、日程、GPA、RPG 等模块 |
| `frontend/lib/shared` | 模型、仓库契约及持久化 |
| `frontend/test` | 单元、仓库、界面与迁移回归 |
| `docs` | 产品、设计、架构、测试及验收记录 |
| `tool/package_v1_acceptance.py` | 冻结制品校验与交付打包 |

更新旧安装前先从“总览 → 备份与恢复”导出完整 JSON。真实设备升级、系统文件选择器、跨平台备份往返和教务登录仍需按验收表记录结果。

开发遵循 [CONTRIBUTING](CONTRIBUTING.md) 与 [Git 工作流](docs/development/git-workflow.md)。早期设计保存在 [文档索引](docs/README.md)，实现状态以源码、具体提交和执行证据为准。
