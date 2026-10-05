# 开发环境与运行

本页对应 Student Life RPG 共享 Flutter 工程基线（Issue #1）。应用根目录是仓库中的 `frontend/`。本周只使用 Flutter/Dart 本地工程；后端、数据库、云同步尚未接入。

## 已核实环境

- 2026-10-04 本机曾核实 Flutter 3.44.6、Dart 3.12.2；组员应在自己的电脑重新执行 `flutter --version`。
- `frontend/pubspec.yaml` 和 `frontend/pubspec.lock` 已纳入版本管理。
- Android、Windows 工程目录已创建；目录存在不等于原生启动成功。

## 获取代码与安装依赖

以下命令在 **Windows PowerShell** 中执行。首次加入项目的组员先克隆仓库；已有仓库者从进入仓库目录开始。

~~~powershell
git clone https://github.com/yian-01/student-life-rpg-abdn.git
Set-Location .\student-life-rpg-abdn
git switch main
Set-Location .\frontend
flutter --version
flutter pub get
~~~

A 的 PR 合并前，`main` 尚不包含本工程。需要提前审查 A 时，组员应切换到对应开发分支，并在记录中注明所用分支和提交；不能将其结果写作 `main` 验证。

## 分析与测试

在 `frontend/` 目录的 PowerShell 中运行：

~~~powershell
flutter analyze
flutter test
~~~

组长本机于 2026-10-05 执行：`flutter analyze` 输出 `No issues found!`，`flutter test` 输出 `All tests passed!`（8项）。这只证明当时该分支上的分析和测试结果，不代替组员本机或合并后验证。

## 启动应用

先在 `frontend/` 目录运行 `flutter doctor -v` 和 `flutter devices`，确认已安装的工具链与设备。设备 ID 以 `flutter devices` 的实际输出为准。

~~~powershell
flutter doctor -v
flutter devices
flutter run -d <实际设备ID>
~~~

Android 需要可用的模拟器或设备。Windows 原生运行需要 Visual Studio 的 C++ 桌面开发工具链。2026-10-05 时 Android 启动尚未验证，Windows 启动受缺少该工具链限制；两平台均不能填写“已通过”。

当前首页和各功能页属于工程占位界面，课程、GPA、财务、持久化等业务功能尚未接入。项目当前也没有可供验证的数据库重启保存行为。

## 提交验证记录

每次 PR 写明实际分支和提交、Flutter 版本、执行目录、命令、结果，以及未执行项和原因。CI 结果应附真实 Actions 链接；CI 通过不等于 Android 或 Windows 原生启动通过。