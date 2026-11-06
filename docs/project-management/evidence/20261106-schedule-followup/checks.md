# 本轮自验结果

代码基线：`e0e38b5019d76d1219b3fcd400d742417b937494`；交付版本为本分支提交，精确 SHA 与 CI 链接放在 PR 正文，证据代码与该提交一致。

执行环境：Windows，Flutter 3.44.6 stable，Dart 3.12.2。北京时间2026-11-07 00:33–00:34完成最终检查。为避开中文工作区路径触发的分析服务器解析错误，`W:` 映射到本工作区，所有命令在 `W:\frontend` 执行。未升级依赖或修改 lockfile。

| 命令 | 实际结果 | 输出 |
|---|---|---|
| `flutter pub get` | 退出0，依赖解析成功 | 本轮终端记录 |
| `dart format --output=none --set-exit-if-changed lib test` | 退出0，174文件，0改动 | [format.log](format.log) |
| `flutter analyze` | 退出0，No issues found | [analyze.log](analyze.log) |
| `flutter test` | 退出0，581项通过 | [flutter-test.log](flutter-test.log) |
| `flutter build windows --no-pub` | 退出0，Release程序生成 | [windows-build.log](windows-build.log) |

首次全套测试有1项旧冲突组合测试失败：枚举增加考试后，原测试遍历所有来源却只期望旧3种来源的3对。补全考试参与的3对组合，保留原断言后重新全量执行，最终581项通过。未删除失败测试、关闭校验或删减原基线用例。

Windows正式应用操作／录屏／完全退出进程重启：未执行，由用户按本目录README补齐。Android：未执行，无设备。Widget测试、临时文件仓库重建和Windows构建均不替代原生验收。真实网址导入课表、安装升级及总览模块联动不在本轮已通过范围。
