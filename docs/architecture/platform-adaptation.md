# Android 与 Windows 平台适配规范

> 2026-10-04 确认的项目决策。本文是平台、坐标、输入和界面适配的统一规范；规范成立不代表代码已实现或验收已通过。

## 技术、共享层与阶段范围

小组项目使用 Flutter/Dart，目标平台为 Android 和 Windows。两平台共享业务逻辑、Controller、Repository 和 Storage 接口；平台适配处理窗口、输入和存储位置等差异。依赖方向：Presentation → Controller → Repository → Storage。Controller 使用 Flutter SDK 的 ChangeNotifier；模型和纯算法不得依赖页面。

第一周使用 JSON 完成**单个模型**的序列化、Repository 往返和重启读取验证，使用合成数据；异常文件、非法输入和失败反馈需检查。SQLite 是后续存储候选，不是第一周强制实现。JSON 单模型验证**不证明**任务完成、奖励记录和进度更新具备原子一致性。后续方案必须保证这些更新一致、避免重复发放，并通过重复请求、并发、故障与重启恢复测试；采用 SQLite 时再验证事务、唯一约束和迁移。

当前奖励范围为 EXP 与等级，等级由总 EXP 和版本化阈值推导；金币经济系统延期。FastAPI、PostgreSQL、账号和同步属于后续范围。

## 世界与 SceneViewport

两平台共用 **941×1672** 竖版世界、美术素材和世界坐标。Android 采用竖屏；Windows 窗口可调整大小，完整等比例显示原世界，不拉伸、不裁门、不重做横版底图。960×720、1280×800 只是窗口验收样本，不是强制默认窗口。

SceneViewport 使用扣除 SafeArea、导航及工具栏后，实际组件获得的布局约束。viewportWidth、viewportHeight 和偏移均使用 **Flutter 逻辑像素**，不是物理屏幕分辨率。测试窗口尺寸不能直接当作 SceneViewport 尺寸。

宽高必须为有限正数，计算所得 scale 也必须为有限正数，否则暂不绘制和处理场景输入；零尺寸、负尺寸、非有限尺寸不得参与除法。有效尺寸下：

```text
scale = min(viewportWidth / 941, viewportHeight / 1672)
offsetX = (viewportWidth - 941 * scale) / 2
offsetY = (viewportHeight - 1672 * scale) / 2
offset = (offsetX, offsetY)
local = offset + world * scale
world = (local - offset) / scale
sceneRect = (offsetX, offsetY, 941 * scale, 1672 * scale)
```

C 的 v1.1 交付稿采用 `footAnchor = (51, 195)` 作为角色脚底的设计参考锚点，并非精灵最低不透明像素行。角色在世界层的左上角按 `spriteTopLeftWorld = footWorld - footAnchor * (playerRenderWidth / 103)` 计算，再与背景共同应用一次场景变换；不得重复缩放锚点。这组数值仍待组长审核及工程接入验证，不能写成已最终验收。

world 是世界位置；local 是 SceneViewport 组件内的逻辑像素位置。世界配置、碰撞、门范围和角色位置使用统一世界坐标。窗口变化只重算 scale 与 offset，并由此派生 sceneRect；不得改变世界配置或角色世界位置。

全局指针位置先通过 SceneViewport 对应 RenderBox 的 globalToLocal 转为 local，再做逆变换。已是该组件 localPosition 的事件不得重复 globalToLocal。sceneRect 外的点击直接忽略，不能夹到世界边界后触发交互。门的位置、交互范围和角色位置引用同一份 `SceneGeometry` 世界配置；显示及指针坐标转换引用同一个 `SceneTransform`。窗口变化只更新变换，不复制或修改世界配置。

## HUD、留白与功能页面

HUD 属于**未缩放的 UI 层**，以 sceneRect 左上角加逻辑像素边距定位。HUD 不跟角色移动，不跟世界缩放，不锚在桌面两侧空白；窗口变化后按新 sceneRect 重定位，但文字、图标和边距不乘世界 scale。小视口须检查 HUD 溢出和遮挡。

宽窗口留白是阶段性原型限制，不代表最终美术验收通过。外景延展另行设计；本次文档任务不生成或修改美术。

学业、财务、日历等功能页面使用完整内容区域，不强制竖图比例。Dashboard 根据其可用内容宽度，以 **600 逻辑像素**为断点：小于 600 为单列，大于等于 600 为双列；内容最大宽度 **1200 逻辑像素**，居中，必要时滚动。小窗口、边界宽度和文本内容必须检查布局溢出。

## 输入和协作边界

键盘与后续移动端摇杆通过同一个 **`setMoveDirection(Offset)`** 接口驱动移动逻辑；速度按世界坐标计算，不随 scale 改变。第一周键盘实现不能作为 Android 摇杆已完成的证据；移动端摇杆和原生平台输入分别验收。

| 任务角色 | 职责与依赖 |
| --- | --- |
| C | 提供唯一的 SceneGeometry 世界配置、SceneTransform 坐标变换及共享接口 |
| D | 负责移动，消费 C 的几何与 `setMoveDirection(Offset)` 约定 |
| E | 负责门交互，消费 C 的逆变换及 D 的角色世界位置 |
| F | 负责 HUD，消费 C 的 sceneRect 和进度 Controller |

C/D/E/F 是本次明确的任务角色，不推断其与现有成员姓名的对应关系；不新增或重编成员分工。禁止复制多套世界坐标配置。文档、配置草稿和接口示例可先做；依赖代码的接入与验收等待对应共享基线实际合并。尚未合并的基线不能作为队友已能从 `main` 运行的前提。

## 状态与验收证据

2026-10-05 核对时，Flutter 工程基线已提交至 `feat/1-flutter-baseline`，Draft PR #4 包含 `frontend/`、开发环境说明和项目结构文档，尚未合并至 `main`。本规范的提交和审核记录以 PR #4 的实际文件列表为准；在基线合并前，队友不能以从 `main` 克隆即可运行基线为前提。

用户此前确认本地静态分析和 8 个 Widget 测试通过；这不是本次文档修改重新执行的结果。Windows 原生启动此前缺少 Visual Studio C++ 工具链，仍待解决；Android 原生运行和队友干净克隆仍待验证。Edge 运行、Linux CI 和 Widget 测试均不能替代 Android/Windows 原生启动证据。

| 计划检查 | 样本 / 判定 | 当前状态 |
| --- | --- | --- |
| 场景视口 | 320×640、800×600 逻辑像素；完整世界等比居中 | 未执行 |
| 窗口样本 | Windows 960×720、1280×800；记录扣除 UI 后的实际视口 | 未执行 |
| 缩放与逆变换 | 世界原点、门、边界和内部点往返一致，使用浮点容差 | 未执行 |
| 坐标来源 | globalToLocal 一次；localPosition 不重复转换 | 未执行 |
| 空白点击 | sceneRect 外输入忽略，不触发门或边界交互 | 未执行 |
| 窗口缩放 | scale/offset 重算；配置和角色世界位置不变 | 未执行 |
| 无效尺寸 | 零、负、NaN、Infinity 无除法、崩溃或场景输入 | 未执行 |
| HUD | sceneRect 左上角加固定逻辑边距；不跟移动或世界缩放 | 未执行 |
| 功能页面 | 完整内容区域；小窗口无溢出，必要时滚动 | 未执行 |
| Dashboard | 599/600/601 断点及宽于 1200 时的最大内容宽度 | 未执行 |
| 平台输入 | Windows 键盘、Android 摇杆各自驱动同一接口，世界速度一致 | 未执行 |
| JSON 单模型 | 两平台分别记录保存、重启、异常输入及文件失败 | 未执行 |
| 原生与复现 | Android、Windows 启动，队友从合并后的 `main` 干净克隆 | 待验证；Windows 工具链待解决 |

[测试计划](../testing/test-cases.md) · [开发环境与历史证据](../development/setup.md) · [待发布任务](../project-management/baseline-issues.md) · [提案补充说明](../product/proposal-platform-addendum.md)