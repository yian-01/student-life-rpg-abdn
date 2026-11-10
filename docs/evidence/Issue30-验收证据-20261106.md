# Issue #30 验收证据（2026-11-06）

## 1. 代码与基线

| 项目 | 值 |
| --- | --- |
| 统一基线（组长候选） | `e0e38b5019d76d1219b3fcd400d742417b937494`（PR #58） |
| 本次验收分支 | `followup/storage-txn` |
| 分支最新提交 | `3782ca7` |
| 工作分支历史提交 | `50940e9`（外部变更防护）、`9ff734a`（原子批量写）、`f64be2e`（ST12 全实体重开）、`ea8a4cd`、`ebaf489` |
| 自动化测试 | 全量 580 项通过（`flutter test`） |
| 静态检查 | `dart analyze lib test`，No issues found |

## 2. 构建记录

| 项目 | 值 |
| --- | --- |
| 构建方式 | GitHub Actions `Native acceptance builds` |
| 运行记录 | run `42165261175`，分支 `followup/storage-txn`，提交 `ea8a4cd` |
| Flutter / Dart | 3.44.6 stable / 3.12.2 |
| Java（Android） | 17 (temurin) |
| 构建命令 | `flutter pub get` → `flutter analyze` → `flutter test` → `flutter build windows --release` / `flutter build apk --release` |
| 应用版本 | `1.0.0+1` |
| applicationId | `com.example.student_life_rpg` |

### 产物与校验值

| 产物 | 文件 | 大小（字节） | SHA-256 |
| --- | --- | --- | --- |
| Windows 发行目录 | `build-artifacts/student-life-windows-release.zip` | 17,787,332 | `21DE014D71E281E325CFF9589AC8290712EEE7CD5B410310A37B8C488D64A068` |
| Windows 可执行文件 | `student_life_rpg.exe` | — | `D869947A716A8CAB2800B203D02ECA42FC33D3980555A44CCD6C3EF7BC53DFDE` |
| Android 安装包 | `build-artifacts/student-life-android-release.apk` | 58,641,636 | `6FA8E4AB71FDAA7B8EBCAAE87C6BD735C83E2E552069D61491EFE0ABA87651C5` |

## 3. 验收用例

结果取值：通过 / 失败 / 未测 / 不适用。

### 3.1 任务（Task）仓库：恢复契约

| 用例 | 结果 | 自动化用例 |
| --- | --- | --- |
| 单坏任务主文件不静默恢复，普通读取报错 | 通过 | `主文件损坏时普通读取只报错，显式恢复后才写盘` |
| 缺主文件但备份存在，读取报错 | 通过 | `主文件丢失且备份存在时不得当作首次运行，显式恢复后恢复旧数据` |
| 无主文件无备份（首次安装）可直接保存 | 通过 | `首次无文件时 list 返回空列表`、`首次运行无主文件无备份时仍可直接保存` |
| 坏备份被拒绝 | 通过 | `非空但非法的备份被拒绝，显式恢复也不覆盖原件` |
| 显式恢复成功并把损坏原件归档 | 通过 | `主文件损坏时普通读取只报错，显式恢复后才写盘` |
| 用户取消恢复不写盘 | 通过 | widget 用例（错误页恢复取消/继续） |
| 恢复过程写失败可重试，不丢缓存 | 通过 | `failed explicit recovery retains cache and can retry` |
| 连续/并发插入不丢记录 | 通过 | `连续插入多条记录不丢失`、`并发插入不丢记录` |
| 缓存后外部修改/删除主文件时拒绝覆盖 | 通过 | `缓存后主文件被外部删除时拒绝保存，不复活旧数据` 等 4 个用例 |
| 保存失败后队列可继续保存 | 通过 | `一次保存失败后，队列仍可继续成功保存` |

### 3.2 CampusData：迁移、引用保护与恢复

| 用例 | 结果 | 自动化用例 |
| --- | --- | --- |
| v1 → v2 自动升级，原记录逐表保留 | 通过 | `v1 文档自动升级为 v2，原记录逐表完整保留` |
| 升级后新增作业/考试/预算并重启保留 | 通过 | `升级后可插入作业/考试/预算并重启后保留` |
| 未知未来 schema / 未知顶层键拒绝 | 通过 | `未知未来 schema 与未知顶层键被拒绝` |
| 作业/考试/预算引用保护与唯一键 | 通过 | `引用保护：作业/考试必须指向已存在课程，预算必须指向支出分类` |
| 预算行 id 必须等于唯一键 | 通过 | `预算行 id 必须等于唯一键，否则拒绝加载` |
| 预算行缺 id 抛 FormatException | 通过 | `预算行缺少 id 时抛 FormatException 而不是类型错误` |
| 主文件损坏 + 有效备份：读取报错、显式恢复并归档 | 通过 | `主文件损坏且备份有效时，普通读取报错，显式恢复写回并归档原件` |
| 备份也损坏：恢复被拒绝，不覆盖、不归档 | 通过 | `备份也损坏时显式恢复被拒绝，不覆盖主文件也不产生归档` |
| 主文件缺失 + 备份：读取报错、显式恢复可用 | 通过 | `主文件缺失但备份存在时读取报错，显式恢复后才可用` |
| v1 升级写回失败保留原文件，解除后重试成功 | 通过 | `v1 升级写回失败时不改动原文件，解除阻塞后可重试` |
| 外部修改后拒绝写入，恢复后采用外部数据 | 通过 | `缓存后主文件被外部修改时拒绝写入，显式恢复采用外部数据` |
| 归档重名递增 | 通过 | `归档路径已存在时递增命名，不覆盖旧归档` |
| 原子批量写：整批成功、非法行零提交、同 id 更新、批内重复拒绝 | 通过 | `批量写入课程整批成功并持久化` 等 4 个用例 |
| 并发批量写串行执行、不丢批 | 通过 | `并发批量写入按队列串行执行，不丢任何一批` |
| ST12：八张表全部写入后退出重开完整保留 | 通过 | `全部实体写入后重新创建实例，逐表完整保留` |

### 3.3 平台运行

| 用例 | 结果 | 证据 |
| --- | --- | --- |
| Windows release 正常启动 | 通过 | `screenshots/release-20261106/windows-home.png` |
| Android 真机正常启动 | 通过 | `screenshots/release-20261106/android-home.jpg` |
| Windows 主文件损坏冷启动不崩溃并提示 | 通过 | `screenshots/d13/02_corrupt_main_still_boot.png`、`screenshots/P12_数据损坏提示.png` |
| Windows 显式恢复成功 / 无备份恢复失败提示 | 通过 | `screenshots/P13_备份恢复成功.png`、`screenshots/P14_无备份恢复失败.png` |
| Windows 完全退出后重开数据保留 | 通过 | `screenshots/release-20261106/windows-reopen-before.png`、`windows-reopen-after.png`：收支 ¥100/¥25/¥75、GPA 3.67 前后一致；任务区显示损坏文件的正常提示 |
| Android 真机完全退出后重开数据保留 | 通过 | `screenshots/release-20261106/android-reopen-before.jpg`、`android-reopen-after.jpg`：收支 ¥10/¥3/¥7、GPA 3.20 前后一致 |
| Android 主文件损坏冷启动提示 | 不适用 | 数据文件位于应用私有目录 `/data/data/com.example.student_life_rpg/files/`，需 root 或 adb 才能直接改写；该契约由 `file_task_repository_test.dart` 的单测与 Windows 冷启动实测覆盖 |

### 3.4 跨模块协作项（不计入本人独立验收）

| 项 | 结果 | 说明 |
| --- | --- | --- |
| D4 错误页「开始/仍失败/成功」三态与错误文案 | 未测 | 存储侧已提供 `FormatException`/`StateError` 契约与显式恢复入口；任务页三态由钟顺成 #62 实现，待其合入后复测 |

## 4. 待补项与说明

1. 两平台“完全退出后重开”的数据保留验证已补齐：Windows `windows-reopen-before/after.png`、Android `android-reopen-before/after.jpg`。
2. Android 冷启动坏文件提示标注为“不适用”：数据文件位于应用私有目录，需 root 或 adb 才能改写，该契约由单测与 Windows 冷启动实测覆盖。
3. 本分支已建 Draft PR #61（`feat/app-final-integration ← followup/storage-txn`），仅作留痕，待 #58 合入后再转正式 PR；其 diff 含 #58 共享基线，不代表本人全部贡献。

## 4.1 Issue #30 验收结论

- 任务仓库（Task）10 项：10 通过
- CampusData 持久化与迁移 15 项：15 通过
- 平台运行 7 项：6 通过，1 不适用
- 跨模块项 D4（任务页错误三态）：存储侧契约已就绪，UI 部分待 #62 合入后复测，不计入本人独立验收
- 自动化：`flutter test` 580 项通过，`dart analyze lib test` 无问题
- 缺陷：无遗留；D13 静默恢复问题已修复并补负向用例
- 遗留说明：Android 冷启动坏文件提示不适用（需 root/adb）；两平台“完全退出后重开”截图已归档

## 5. 可复现构建说明（D6/D7）

### 5.1 构建环境

| 项目 | 值 |
| --- | --- |
| Flutter | 3.44.6 stable |
| Dart | 3.12.2 |
| Java（Android） | Temurin 17 |
| 构建来源 | GitHub Actions run `42165261175`，分支 `followup/storage-txn`，提交 `ea8a4cd` |
| 版本号 | `1.0.0+1` |
| applicationId | `com.example.student_life_rpg` |

### 5.2 构建命令

```powershell
cd frontend
flutter --version          # 3.44.6 / Dart 3.12.2
flutter pub get
dart analyze lib test      # No issues found
flutter test               # 580 项通过
flutter build windows --release
flutter build apk --release
```

产物位置：

- Windows：`frontend/build/windows/x64/runner/Release/`（整个目录即为发行目录）
- Android：`frontend/build/app/outputs/flutter-apk/app-release.apk`

说明：Windows 构建会自动生成 `jni_plugin_registrant.cc/.h` 等插件注册文件，属于构建产物，不要提交。

### 5.3 产物校验

```powershell
Get-FileHash student-life-windows-release.zip -Algorithm SHA256
Get-FileHash student-life-android-release.apk -Algorithm SHA256
```

| 产物 | 大小（字节） | SHA-256 |
| --- | --- | --- |
| `student-life-windows-release.zip` | 17,787,332 | `21DE014D71E281E325CFF9589AC8290712EEE7CD5B410310A37B8C488D64A068` |
| `student_life_rpg.exe`（解压后） | — | `D869947A716A8CAB2800B203D02ECA42FC33D3980555A44CCD6C3EF7BC53DFDE` |
| `student-life-android-release.apk` | 58,641,636 | `6FA8E4AB71FDAA7B8EBCAAE87C6BD735C83E2E552069D61491EFE0ABA87651C5` |

### 5.4 数据文件路径（升级/恢复验证用）

| 平台 | 路径 |
| --- | --- |
| Windows | `%APPDATA%\com.example\student_life_rpg\tasks.json`、`campus.json`（备份为同目录 `.bak`，归档为 `.corrupt`） |
| Android | 应用私有目录 `/data/data/com.example.student_life_rpg/files/`，需 adb/root 才能直接修改 |

