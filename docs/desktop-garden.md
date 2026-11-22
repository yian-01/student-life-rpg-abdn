# 桌面像素庭院接入记录

2026-11-22，分支 `codex/pixel-garden-desktop`，基于 `fix/v1.1-reliability` 的 `cc2848f68e39301f122ab0dd21040b76a8bd15c7`。此记录对应真实 Flutter 源码，不是历史 HTML 设计原型。

## 交付范围

- 宽度达到 1000 逻辑像素时启用全宽桌面布局；优先按 1440 × 900 验证。窄屏保留原移动端导航与业务页面，手机新版设计尚未进行。
- 首页只放日期、简短标语和樱花；学业、日程、财务、更多分为四个简洁入口页，共 19 个业务入口。原有日程手账、RPG 场景、今日规划、备份恢复、搜索和账号入口均保留。
- 左侧小字号纯文字导航默认隐藏，左边缘悬停或点击 KEYU 呼出；浅色 / 深色主题切换不重置当前业务页面。圆点只在横向切页时出现，首尾不循环。
- 横向手势按一次完整惯性流消费，阈值 96 像素，静默 320ms 后才接受下一次；输入框、弹窗、互动设置阻止误切页。保留方向键切页。
- 业务页复用原持久仓库和编辑器。新增跨课程作业 / 考试入口、周课表入口、分类 / 预算入口和票据筛选路由；待办聚合页补上真实新增任务操作。
- 全局账号状态切换同时替换 Navigator key，避免沿用上一账号的表单。原有同步、退出保护、图片缓存清理和移动端账号流程继续复用。

主要实现位于 `frontend/lib/app/garden`、`student_life_app.dart`、`app_routes.dart`。没有引入 WebView 或用假数据替换业务。测试中的内存仓库和临时账号只属于测试夹具。

## 素材与互动

按项目所有者明确选择，樱花、灌木、枫树沿用 Pixel Play 的像素图层及骨架数据；银杏、竹丛与花枝 Logo 使用项目生成的素材。来源及许可状态记录在 `frontend/assets/garden/PROVENANCE.txt`。参考站素材的正式再分发使用许可尚未核实，不能将引用来源当作已取得许可的证明。

运动与绘制由 Flutter CustomPainter 独立实现，包括分层摇曳、拖拽回弹、点击落叶、完整叶片轮廓、长叶恢复、骨架查看、风向、阵风、微风 / 风暴及三株并置。并未复制参考站的运行引擎，不能声称逐像素逐物理行为完全一致。Web 音效在用户主动启用后用本地 Web Audio 合成，隐藏页面静音；原生平台目前只保留系统点击音，没有完整风声合成。

动画限约 30fps，遵循系统减少动画设置，独立重绘区域避免每帧重建业务页面。宋体来自 Noto Serif SC，子集字体、来源与 OFL 见 `frontend/assets/fonts`。视觉偏好目前只在本次应用运行内保留，刷新重置；不纳入账号云端快照。

## 验证与限制

Flutter 全量回归 **758 项通过**（开启 `CAMPUS_SYNC_E2E=1`），包含原有业务 / 账号回归及新增桌面布局、任务创建、主题、滑动流测试。260 个 Dart 文件格式检查通过，Dart 静态分析无诊断。Web release 编译通过。

浏览器测试用实际编译后的 Flutter、临时独立 HTTPS API 和全新 Chrome context，不写正式服务。脚本：

- `frontend/test_web/account_sync.cjs`：存储适配、跨来源认证、退出清理、桌面恢复与刷新、390px 手机端同账号恢复。
- `frontend/test_web/desktop_garden.cjs`：真实入口、学期新增、任务持久化与刷新、票据、深浅主题、横向惯性及浏览器异常。

这两套编译后浏览器脚本本地均通过：账号恢复覆盖 1440px 与 390px 两个独立 context；桌面脚本通过 7 项检查，实际新增学期与任务、读取 IndexedDB 确认任务写入，并刷新页面确认恢复，浏览器无未处理异常。后端账号与 CORS 回归 9 项通过。

实际 Flutter 截图见 [浅色首页](ui/garden-home-light.png)、[学业入口](ui/garden-study.png)、[深色更多](ui/garden-more-dark.png)。Windows / Android 新界面安装包、本机触控板实操、Safari / iOS 主屏幕及独立公网 API 的验收仍待执行；不能用 Chrome 自动化代替全部平台实机验收。

## 预览与部署

`.github/workflows/desktop-garden-preview.yml` 只运行检查、隔离浏览器测试和构建 artifact，只有 `contents: read` 权限，不发布 Pages、不部署 keyulife.cn、不合并 PR。

构建生产配置的网页：

```sh
cd frontend
flutter pub get
flutter build web --release --no-web-resources-cdn --pwa-strategy=none
# 独立 API 可加 --dart-define=CAMPUS_SYNC_URL=https://api.example.com
python tool/verify_web_bundle.py build/web --reject-test-api > build/web-manifest.json
```

未指定 API 时 Web 使用当前网站来源。独立 API 需要配置该网页的精确 CORS 来源，仍须 Bearer 身份认证；Windows / Android 不要求与网页共用前端域名。预览需放在独立环境，不能复用临时测试 API 作为用户数据服务。

`web-account-check` 构建固定了回环测试地址，只用于自动化，**不能发布到公网**。最终预览构建须使用 `build/web` 的同源 / 明确 API 配置，并核对 manifest 与校验值。正式网站切换、重要 PR 合并与安装包发布另行进行。

本机 Windows 的 build 目录通过 Junction 放在 D 盘时，默认相对输出曾出现编译报告成功而主程序文件被清理的情况。本地交付改用没有目录链接的绝对输出目录，随后执行上述完整性检查；不要仅根据 Flutter 的 Built 提示上传文件。CI 使用常规检出目录，也在上传前执行相同检查。
