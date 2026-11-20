# V1.0 收尾记录

2026-11-21，冻结功能提交 `29b1bebb208fc3f2d0fd6cfe684e280eba0f7583`，版本 `1.0.0+1`。本分支仅补充交付和验证材料，不混入 V1.1 账号、云同步或新版首页。

## 已执行

| 检查 | 本轮结果 |
| --- | --- |
| Flutter 3.44.6 / Dart 3.12.2，本地 Windows 全量测试 | 739 通过，0 失败 |
| `dart analyze --format machine` | 退出 0，无诊断 |
| `dart format --output=none --set-exit-if-changed lib test` | 225 文件，0 改动 |
| Windows/Android 原验收制品下载 | 已完成 |
| 制品 SHA-256 与 GitHub Actions digest 比对 | 两份均相符，ZIP CRC 校验通过 |
| APK 签名验证 | 验签通过，证书为 Android Debug，不能称为正式签名发布包 |
| 本机 Windows release 重新构建 | 已成功，418.2 秒；修复了本机 NuGet 与路径/生成文件问题 |
| 旧数据迁移、双文件恢复回滚、票据/调停课重启 | 已在上述自动化中覆盖；不代替真实设备验收 |
| 本机旧数据独立副本迁移 | schema 2 → 3 逐字段、GPA 换算、任务不变、原件备份和重开幂等均通过，原目录未修改 |

制品来自 [Actions run 43169002569](https://github.com/yian-01/student-life-rpg-abdn/actions/runs/43169002569)，Windows artifact `13921134161`、Android artifact `13922145173`。两者构建自同一冻结提交。打包脚本校验原 ZIP 的固定摘要，不重新签名 APK。

## 当前状态

可交付验收候选，不是正式稳定版。PR #68 仍为 Draft，base 为 `fix/v1-base-regression`；不能只把该 PR 合入其 base 就宣称已进入 main。应审查完整 V1 分支相对 main 的差异，并在获批准后合并。

V1.0 此候选面向 Windows 和 Android 本地使用。Web 的存储与浏览器适配在 V1.1 分支，不能将 V1.1 Web 成果归到本候选。

## 仍需实际验收

按 [功能验收表](v1-feature-acceptance.md) 逐项记录设备、操作、结果和问题。以下项目没有实机证据时不可标为通过：

- Windows 系统文件保存/选择、关闭重开、完整备份往返恢复。
- Android 真机软键盘、票据选择、重启持久化和文件选择器。
- Windows ↔ Android 完整备份双向恢复，数量、字段及票据一致。
- 旧安装升级：先导出完整备份，验证 GPA 迁移一次、未评分与零分保留。
- 华师教务真实登录及课表抓取；测试不收集用户密码。
- ICS 被第三方日历正确导入、CSV 在表格软件中可读。

Android 现有包使用 CI 调试签名。本轮下载并验证旧候选 `d1e0a1a` 与当前 `29b1bebb` 的 APK：二者包名相同，签名 SHA-256 分别为 `7187886a178b9b70613fc2077759fec83096ec7292244c62b1e1dac920fe34cb` 与 `e651bcfbacbd9da7bedb7d2ff883c7ff028d150bc53c4e2bfe54d8a3b72056c9`，证书不同，不能直接覆盖升级。禁止直接卸载旧应用解决冲突，因为卸载可能删除本地数据。正式签名密钥及升级路线需明确后再发布稳定版，不能偷偷更换 applicationId 绕过。

可复用的副本迁移检查位于 `frontend/tool/verify_v1_upgrade_test.dart`。在 `frontend/` 中设置 `V1_UPGRADE_SNAPSHOT` 为仅包含 `campus.json` 与 `tasks.json` 的独立副本目录，再执行 `flutter test tool/verify_v1_upgrade_test.dart`。它只在临时目录迁移，失败信息不打印记录内容；用户数据不得提交到仓库或附入公开验收材料。此专项 1 项通过，单独记录，不把它合并为一次全套 740 项运行。

## 打包与核验

```powershell
python tool/package_v1_acceptance.py --windows-zip <原Windows-ZIP> --android-zip <原Android-ZIP> --test-log <本轮完整测试日志> --output-dir <全新输出目录>
```

输出包括完整 Windows ZIP、APK、来源清单及 SHA256SUMS。脚本拒绝覆盖已有交付物。Windows 须解压整个 ZIP 后运行，不能单独复制 EXE。首次启动可能需要系统现有 WebView2 Runtime。

本机 Windows 构建先遇到 NuGet 缺失、中文路径和缺失的 Flutter 生成文件；工作区补齐官方 NuGet、使用临时 ASCII 盘符并从 Flutter SDK 补齐生成文件后，`flutter build windows --release --no-pub` 成功（418.2 秒）。未修改业务代码。交付仍保留已校验的原 CI 制品，便于追溯同一验收版本。

Android 本机构建因 Gradle 下载超时失败，不能冒充本轮重新构建成功；原 CI APK 已独立校验。模拟器启动尝试未得到可连接设备，不计作实机通过。上述失败和最终成功日志均需保留。

## 发布门槛

1. 实机验收表完成，问题修复后重跑适用检查。
2. Android 签名及旧版升级策略确认。
3. 完整 V1 分支审查、必要的 main 集成检查通过。
4. 用户明确批准重要 PR 合并和正式发布。

本轮不更新正式网站、不合并 PR、不将候选标为 stable。
