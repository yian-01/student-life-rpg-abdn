# Student Life RPG / 课屿

Flutter / Dart 大学生学习与生活管理应用，包含学业、日程、个人财务和 RPG 空间。

## 当前状态

本分支为 V1.1 开发候选（`1.1.0+2`），尚未正式发布。V1.0 功能基线为 `29b1bebb208fc3f2d0fd6cfe684e280eba0f7583`；本轮在预览代码 `6d1178ee3b71786e9a37fdb4559d8818f8bf0b4e` 上修复账号与同步可靠性。

已执行验证与未完成的实机事项见 [V1.1 验收矩阵](docs/v1.1-reliability.md)。不能把本地自动化通过等同于 Android、Windows 系统凭证存储或 iOS 主屏幕模式全部验收。

开发顺序：完成 V1.0 / V1.1 功能代码 → 手机与桌面 UI → 大模型功能 → 联合验收与正式发布。当前不发布安装包、不合并重要 PR、不更新正式网站。

## 已接入的功能

- 学期、课程、单次调停课、作业、考试、GPA。
- 周课表、待办、优先级、子步骤、事件、搜索、今日规划与专注计时。
- 收支、分类、月预算、统计、报销与票据。
- 完整 JSON 备份恢复、删除撤销、ICS / CSV 导出。
- 卧室场景、角色移动、交互入口与 HUD。
- Web 存储、账号注册登录、账号隔离、完整快照同步、三方合并及冲突选择。
- 退出前保存修改；断网或冲突时保留修改并阻止退出；退出清理账号文件和登录凭证，重新登录恢复云端数据。

这些条目描述源码已有能力，具体运行证据和平台差异以验收矩阵为准。现有主页属于开发中的 UI，后续完整桌面工作台和大模型功能尚未完成。

## 开发与检查

使用 Flutter 3.44.6 / Dart 3.12.2：

```sh
cd frontend
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter run -d windows
# Web 可运行 flutter run -d chrome；Android 用 flutter devices 选择设备。
```

原生同步端到端测试需要 Python，设置 `CAMPUS_SYNC_E2E=1` 后运行 `flutter test test/app/cloud/sync_e2e_test.dart`。Windows 默认调用 `python`，其他系统默认 `python3`，可通过 `PYTHON` 指定路径。

系统凭证存储回归：`flutter test integration_test/secure_session_test.dart -d windows`，需要 Windows C++ 桌面工具链与 PATH 中的 NuGet。测试使用临时凭证命名空间和临时数据目录，不读写用户的正式登录信息。Android 应使用专用测试设备；确认没有未备份的旧安装数据后，才用设备 ID 替换 `windows` 运行，避免已知的历史签名不兼容影响旧数据。

后端检查：进入 `backend`，运行 `python -m unittest -v test_sync_server`。HTTPS 部署、来源白名单和 API 配置见 [后端说明](backend/README.md)。网页、Windows、Android 可以使用不同入口，连接同一个经过认证的 API；跨域网页需要精确的 CORS 白名单，不依赖跨站 Cookie。

## 数据与目录

原生本地使用版本化 JSON 文件：`campus.json` 保存学业、事件与财务，`tasks.json` 保存任务；Web 使用 IndexedDB 文件适配层。账号私有目录独立于访客数据，凭证交给平台安全存储。后端使用 SQLite 保存账号、哈希凭证和账号快照。本地实现与早期 SQLite 设计设想有差异，应以源码为准。

| 目录 | 内容 |
| --- | --- |
| `frontend/lib/app` | 路由、装配、备份恢复、账号与同步 |
| `frontend/lib/features` | 学业、财务、日程、GPA、RPG 模块 |
| `frontend/lib/shared` | 模型、仓库契约、原生 / Web 存储 |
| `frontend/test` | 业务、存储、界面及原生 HTTP 回归 |
| `frontend/test_web` | 编译后浏览器账号回归和独立 HTTPS 夹具 |
| `backend` | 账号与快照 API、部署配置和服务测试 |
| `docs` | 历史设计、实际实现及验收记录 |

## 后续发布准备

Android release 需要配置 `frontend/android/key.properties.example` 中的密钥信息；缺少密钥时禁止隐式使用调试签名。仅临时验收可显式设置 `STUDENT_LIFE_ACCEPTANCE_SIGNING=true`。历史 APK 签名不一致且旧密钥缺失，不能保证覆盖升级。先导出旧应用的完整备份，再按后续迁移方案处理；不能通过直接卸载绕过签名不兼容。长期密钥与实际打包安排仍待后续发布准备阶段。

协作遵循 [CONTRIBUTING](CONTRIBUTING.md) 与 [Git 工作流](docs/development/git-workflow.md)。[早期文档](docs/README.md) 中尚未与源码对齐的设计不作为完成证据。
