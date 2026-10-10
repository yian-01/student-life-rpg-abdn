# Student Life App 开发统一契约 v1.0

决策日期：2026-10-10。
适用项目：课程小组项目 Student Life App，仓库 student-life-rpg-abdn。
技术栈：Flutter/Dart；目标平台：Android、Windows。

本文固定本阶段的字段、接口、职责、依赖和验收要求。旧草稿与本文冲突时，以本文为准。规范中的待开发接口不代表代码已经存在；接口变更须由组长统一修订并通知消费方。

## 1. 当前基线与阶段范围

截至 2026-10-10，已核实：

- PR #4 工程基线已合并。
- PR #5 共享时间、日程和仓库契约已合并。
- 本地 main 与 origin/main 均位于提交 5a15983。
- PR #5 的代码提交为 f5f95c6；该提交本地 flutter analyze 无问题，15 项测试通过，其中包含原有 8 项测试。
- 合并后的 main 已在组长电脑完成 Windows 原生构建和启动。
- 组长人工确认：功能页面入口、返回及缩小窗口检查全部通过。
- 上述证据不代表组员环境均已通过，也不代表 Android 原生启动已通过。
- 当前页面为工程基线占位页面；美术场景、移动、业务逻辑和持久化仍需按任务实现。
- 本文发布不自动关闭任何开发 Issue。

本阶段优先完成：

1. 统一模型、Repository 和模块接口。
2. 各模块实现与单元测试。
3. Task 单模型 JSON 保存、读取、重启恢复和失败反馈。
4. Windows 集成演示及必要的 Android 原生验证。
5. 开发、测试、运行和演示证据归档。

SQLite 为后续候选，不要求本阶段强制实现。
FastAPI、PostgreSQL、账号、同步、金币经济系统延期。
自动 EXP 奖励、奖励账本和跨文件事务延期；HUD 本阶段可使用明确标注的演示数据。

单模型 JSON 验证不能证明任务完成、奖励和进度更新具备跨文件原子一致性。

## 2. 分层、职责与目录

依赖方向：

Presentation → Controller → Repository → Storage

- Controller 使用 Flutter SDK ChangeNotifier。
- 模型和纯算法不依赖 Widget、BuildContext 或页面。
- 跨模块依赖通过构造参数注入。
- 陈思翰负责组合根、应用入口、路由接线和集成审核。
- 业务负责人维护本人模块。
- 禁止复制公共模型、仓库接口和世界配置。

以下 lib 路径均相对 frontend/；.github 和 docs 位于仓库根目录。

| 成员 | 任务 | 负责路径 |
| --- | --- | --- |
| 陈思翰 | A、集成审核与 Q 材料 | lib/main.dart、lib/app/、docs/ |
| 李雨真 | B/O/P：公共契约、存储、CI | lib/shared/models/、lib/shared/repositories/、lib/shared/storage/、.github/workflows/ |
| 廖梦溪 | C/D：世界几何、移动 | lib/features/bedroom/models/、controllers/、services/、presentation/ |
| 黎宇轩 | E/F：门交互、HUD | lib/features/interaction/controllers/、models/；lib/features/hud/presentation/、models/ |
| 蒋子康 | G：学术模型、课次展开 | lib/features/academic/models/、repositories/、services/ |
| 钟顺成 | H/I：任务、事件、日程 | lib/features/schedule/models/、repositories/、services/、controllers/、presentation/ |
| 郝文聪 | J/K：GPA、时间冲突 | lib/features/gpa/models/、services/；lib/features/schedule/services/conflict_detector.dart |
| 吴昕玥 | L/M：财务模型、仓库、汇总 | lib/features/finance/models/、repositories/、services/ |
| 龙梓瑄 | N：Dashboard | lib/features/dashboard/models/、services/、controllers/、presentation/ |

G 的学术模型放 academic；日程 UI 保留在 schedule。
根目录 README.md、CONTRIBUTING.md、docs/、.github/ 保留。
已有等价代码由负责人和组长完成路径映射，不建立第二套同名实现。

## 3. 已合并的公共契约

实际公共文件：

- frontend/lib/shared/models/time_range.dart
- frontend/lib/shared/models/schedule_item.dart
- frontend/lib/shared/repositories/entity_repository.dart

下面为接口示意，业务模块必须导入实际公共文件。

```dart
class TimeRange {
  TimeRange({
    required DateTime start,
    required DateTime end,
  });

  final DateTime start;
  final DateTime end;

  Map<String, dynamic> toJson();

  factory TimeRange.fromJson(Map<String, dynamic> json);
}

enum ScheduleSourceType { course, event, task }

class ScheduleItem {
  ScheduleItem({
    required String id,
    required String sourceId,
    required ScheduleSourceType sourceType,
    required String title,
    required TimeRange range,
  });

  final String id;
  final String sourceId;
  final ScheduleSourceType sourceType;
  final String title;
  final TimeRange range;
}

abstract interface class EntityRepository<T> {
  Future<List<T>> list();
  Future<T?> getById(String id);
  Future<void> insert(T entity);
  Future<void> update(T entity);
  Future<bool> remove(String id);
}
```

统一行为：

- ID 和标题不得为空或全为空白。
- ID 保留原值，不通过 trim 改变身份。
- list 返回不可变列表副本。
- getById 查询不存在的 ID 返回 null。
- remove 删除不存在的 ID 返回 false。
- insert 遇到重复 ID 抛出 StateError。
- update 遇到不存在的 ID 抛出 StateError。
- ID 参数为空白时抛出 ArgumentError。
- 实体 copyWith 不提供修改 id 的能力。
- ScheduleItem 是展示派生数据，不作为主实体保存。
- 存储失败不得伪装为成功、空列表或不存在。

统一错误类型：

| 场景 | 错误类型 |
| --- | --- |
| 模型构造或纯函数收到非法参数 | ArgumentError |
| JSON 缺字段、错误类型、错误枚举、错误版本或错误实体类型 | FormatException |
| JSON 中领域值非法 | FormatException，解码层转换构造校验错误 |
| 重复 ID、未知更新、引用删除保护 | StateError |
| 文件故障 | 保留 FileSystemException 或注入的原始存储异常 |

Controller 捕获错误并提供可见反馈，不将错误转换成空数据。
本阶段不新增另一套自定义错误类型层级。

## 4. 时间、日期和 JSON

### 4.1 时间规则

- DateTime 使用本地民用时间，isUtc=false。
- TimeRange 必须 start < end。
- 时间区间为半开区间 [start, end)。
- 两个区间首尾相接不算冲突。
- 日期查询使用当天本地午夜至次日本地午夜。
- 月份查询使用本月首日至下月首日。
- 不以固定 24 小时或 30 天代替日历边界。

日期字段：

- Dart 使用本地午夜 DateTime。
- JSON 使用 YYYY-MM-DD。
- 不引入未实现的 LocalDate 类型。

完整时间字段：

- JSON 使用本地 ISO 格式。
- 不包含 Z 或时区偏移。
- 保留秒、毫秒和微秒精度。
- 解码必须拒绝非法日期、时间及自动归一化后的无效输入。
- 例如 2026-02-29、24:00:00、分钟 60 不得被静默接受。

### 4.2 文档结构

持久化文档最外层恰有三个字段：

```json
{
  "schemaVersion": 1,
  "entityType": "Task",
  "records": []
}
```

规则：

- schemaVersion 为整数 1；其他版本拒绝。
- entityType 大小写敏感。
- 本阶段实体名为 Semester、Course、Task、Event、Assignment、Exam、FinanceCategory、FinanceRecord。
- 枚举 JSON 值使用小写。
- 一个文件只保存一种实体。
- records 必须为数组。
- 顶层、模型和嵌套对象均拒绝未知字段。
- 非空字段必须存在。
- 可空字段 toJson 必须写入 null。
- fromJson 允许缺少可空字段，按 null 处理。
- 不将旧 done/deadline 字段静默迁移为新 Task 字段。
- 模型负责单条记录的 toJson/fromJson。
- O 负责顶层文档封装与校验。
- 读取失败禁止自动写回覆盖原件。

本阶段预算通过配置注入，不要求 MonthlyBudget 模型、CRUD 或持久化。

## 5. G：学术模型与课次展开

| 模型 | 字段 |
| --- | --- |
| Semester | String id、name；DateTime startDate、endDate、week1Monday |
| Course | String id、semesterId、name；double credits；double? gradePoint；List<CourseSlot> slots |
| CourseSlot | int weekday、startMinute、endMinute；List<int> weeks |
| Assignment | String id、courseId、title；DateTime dueAt；String? description |
| Exam | String id、courseId、title；TimeRange range；String? location |

校验规则：

- Semester 起止日期包含首尾，startDate 不晚于 endDate。
- week1Monday 必须为周一，作为第一周计算锚点。
- 创建 Course 时，semesterId 必须引用已存在学期。
- 有课程引用的学期禁止删除。
- Course.slots 可以为空；演示用课程至少有一个时间段。
- weekday 为 1 至 7。
- 0 <= startMinute < endMinute <= 1440。
- weeks 非空，元素为严格递增的正整数。
- 重复或未排序 weeks 拒绝。
- credits 必须为有限正数。
- gradePoint 为 null 或有限数，范围为 0 至调用方传入的 scoreScaleMax。
- 演示使用 scoreScaleMax=4.0，明确标注为演示规则，不代表学校官方 GPA 制度。

课次算法接口：

```dart
List<ScheduleItem> occurrencesForDate(
  Course course,
  Semester semester,
  DateTime date,
);
```

行为：

- 输入日期归一到本地日期。
- course.semesterId 与 semester.id 不一致时拒绝。
- 日期在学期外、星期不匹配、周次不在 weeks 时返回空列表。
- 根据日期日历差和 week1Monday 计算周次。
- 不使用 UTC 秒差推断周次。
- 0 分钟合法；1440 分钟表示次日 00:00。
- 输出 sourceType=course。
- sourceId 保留课程原始 ID。
- ID 格式为 course:<Uri.encodeComponent(courseId)>:<slotIndex>:YYYYMMDD。
- slotIndex 使用课程 slots 列表中的索引。
- slots 变更后允许重新生成派生课次 ID。

G 提供 Semester/Course 内存 Repository。
Assignment/Exam 本阶段完成模型、JSON 和校验，不扩展完整管理页面。

## 6. H/I：Task、Event 和日程

| 模型 | 字段 |
| --- | --- |
| Task | String id、title；int estimatedMinutes；bool isCompleted；DateTime? dueAt；TimeRange? scheduledRange |
| Event | String id、title；TimeRange range；String? description |

规则：

- estimatedMinutes 必须大于 0。
- Task 构造时 isCompleted 默认 false。
- JSON 中 isCompleted 必填且必须为 bool。
- 禁止另建 done、deadline、status、scheduleStart 等生产字段别名。
- Task 的 dueAt 与 scheduledRange 可为空。

```dart
abstract interface class TaskRepository
    implements EntityRepository<Task> {
  Future<void> setCompleted(String id, bool isCompleted);
}

typedef CourseOccurrencesForDate =
    Future<List<ScheduleItem>> Function(DateTime date);

abstract interface class DayScheduleLoader {
  Future<DaySchedule> loadDay(DateTime date);
}

// 构造接口示意：
DayScheduleService({
  required EntityRepository<Task> taskRepository,
  required EntityRepository<Event> eventRepository,
  required CourseOccurrencesForDate courseOccurrencesForDate,
});
```

setCompleted：

- 对同一任务重复设置相同值保持幂等。
- 不存在的任务抛出 StateError。
- 不产生自动 EXP 或奖励副作用。

DaySchedule 字段：

- DateTime date
- List<ScheduleItem> items
- List<Task> unscheduledTasks
- Set<String> completedTaskIds

已有 dayStart/dayEnd、isCrossDay/isCompletedTask 辅助能力可保留，但必须基于上述字段派生，不新增另一份主数据。

日程规则：

- G 的同步单课程算法由 A/I 组合适配为异步回调。
- 组合适配读取学期和课程，逐课程展开，汇总后返回 Future<List<ScheduleItem>>。
- 当天 items 包含与当天时间区间相交的课程、事件和已安排任务。
- 跨日项目保留原始完整 range，不因展示某天而截断源范围。
- items 按 start、end、来源 course/event/task、id 排序。
- 已完成的已安排任务仍可显示，并通过 completedTaskIds 标记。
- unscheduledTasks 包含所有未完成且 scheduledRange=null 的任务。
- 未安排任务列表不等同于 Dashboard 今日待办。
- Event/Task 派生 ID 必须包含编码后的 sourceId 及开始时间。
- 时间小数部分使用 millisecond*1000+microsecond，补齐六位。
- sourceId 属性保留原 ID，只有拼接到派生 ID 时使用 Uri.encodeComponent。
- 同一秒内不同毫秒或微秒的开始时间不得生成相同 ID。

## 7. J：GPA；K：时间冲突

```dart
class GpaResult {
  final double? value;
  final double gradedCredits;
  final int gradedCourseCount;
  final int missingCount;
}

class GpaCalculator {
  GpaResult calculate(
    List<Course> courses, {
    required double scoreScaleMax,
  });
}

bool overlaps(TimeRange a, TimeRange b);

List<ConflictPair> findConflicts(List<ScheduleItem> items);

class ConflictPair {
  final String firstId;
  final String secondId;
  final TimeRange overlapRange;
}
```

### 7.1 GPA

- 调用方先按学期筛选课程，再调用算法。
- GPA = sum(credits * gradePoint) / sum(graded credits)。
- null 绩点不进入分子和分母，计入 missingCount。
- 0 绩点是有效成绩，进入分母。
- 无有效成绩时 value=null。
- 所有输入和 scoreScaleMax 必须有限。
- credits>0，scoreScaleMax>0。
- gradePoint 在 0 至 scoreScaleMax 之间。
- 重复课程 ID 拒绝。
- 非有限的乘法或求和结果拒绝。
- 不修改输入。
- 算法不提前 round；显示层决定小数位。
- 测试使用浮点容差 1e-9。

可提供 GpaController：

- 构造注入 EntityRepository<Course> 和 scoreScaleMax。
- load({String? semesterId})。
- retry()。
- result、isLoading、error。

首次演示明确注入 demo 4.0。
Dashboard 消费 GpaResult，不复制 GPA 算法。

### 7.2 时间冲突

- 严格相交条件：a.start < b.end && b.start < a.end。
- 首尾相接不冲突。
- 重复 ScheduleItem.id 拒绝。
- 每对冲突只输出一次。
- firstId 为两个 ID 中较小者。
- overlapRange 为 max(start) 至 min(end)。
- 输出按 firstId、secondId 排序。
- 空列表和单项列表返回空列表。
- 本阶段 O(n²) 实现可接受。

K 始终为时间冲突检测，不改为成长或奖励模块。

## 8. C/D：世界几何与移动

### 8.1 唯一配置

两平台共用 941×1672 世界坐标。
C 提供唯一 SceneGeometry 配置；SceneTransform 负责其视口变换。
禁止业务模块复制另一套坐标、门位置或变换公式。

阶段原型配置：

- playerStart = Offset(360, 1160)
- playerFootAnchor = Offset(51, 195)
- menuInteractionPoint = Offset(200, 1170)
- menuInteractionRadius = 70

可行走多边形顶点依次为：

1. Offset(240, 960)
2. Offset(590, 960)
3. Offset(555, 1010)
4. Offset(550, 1060)
5. Offset(550, 1385)
6. Offset(75, 1385)

上述为阶段候选配置，须结合实际素材完成原生叠图和碰撞检查，不能仅凭坐标计算宣称美术验收通过。

### 8.2 视口变换

viewportWidth、viewportHeight 来自 SceneViewport 实际布局约束，已扣除 SafeArea、导航和工具栏。

所有视口尺寸、偏移和事件局部坐标使用 Flutter 逻辑像素。

```text
scale = min(viewportWidth / 941, viewportHeight / 1672)
offsetX = (viewportWidth - 941 * scale) / 2
offsetY = (viewportHeight - 1672 * scale) / 2
local = offset + world * scale
world = (local - offset) / scale
sceneRect = (offsetX, offsetY, 941 * scale, 1672 * scale)
```

- 宽高和计算出的 scale 必须有限且大于 0。
- 使用运行时判断，不仅依赖 assert。
- 无效布局暂不绘制场景、不处理场景输入。
- 窗口变化只重算变换，不改变角色世界位置或世界配置。
- 全局指针先经 SceneViewport RenderBox.globalToLocal，再做逆变换。
- 已是对应组件 localPosition 的事件不重复转换。
- sceneRect 外点击直接忽略，不夹到世界边界。
- 点击矩形左、上包含，右、下排除。
- 可行走多边形边界包含；它与视口点击边界规则分别处理。
- 所有门命中使用同一变换。

Android 竖屏；Windows 窗口可缩放，完整等比例显示世界，不拉伸、不裁门。
960×720、1280×800 是窗口验收样本，不是固定默认窗口。
窗口尺寸不能直接充当扣除 UI 后的场景尺寸。

### 8.3 移动接口

```dart
PlayerMovementController({Offset? start});

Offset get footPosition;
bool get isPaused;
bool get isMoving;

void setMoveDirection(Offset direction);
void setPressedKeys(Set<MoveDirection> keys);
void setJoystickVector(Offset vector);
void update(double dt);
void pause();
void resume();
void clearInput();
void reset();
```

行为：

- Controller 使用 ChangeNotifier。
- 键盘和摇杆适配到同一方向字段。
- direction 必须有限。
- 非零有效方向归一化；斜向不加速。
- 摇杆死区为 0.15。
- speed=120 世界坐标单位/秒，不随视口 scale 改变。
- dt=0 合法；负数或非有限 dt 拒绝。
- 单次 update 的有效 dt 最大为 0.05 秒。
- 碰撞子步长度不超过 2 世界坐标单位。
- 整步不可行时依次尝试 x/y 滑动。
- 离开页面或失去输入焦点清空方向。
- 进入 Menu 时 pause 并 clearInput。
- 普通返回时 clearInput 并 resume，保留位置。
- 不允许返回后自动续走。
- reset 仅用于明确重新开始。

Windows 键盘与 Android 摇杆分别验收；键盘通过不证明摇杆已完成。

## 9. E/F：门交互与 HUD

```dart
typedef NavigateToRoute =
    Future<void> Function(String routeName);

class InteractionTarget {
  final String id;
  final String label;
  final String routeName;
  final Offset worldPoint;
  final double radius;
}

InteractionController({
  required PlayerMovementController movement,
  required InteractionTarget target,
  required NavigateToRoute navigate,
});

bool get canInteract;
bool get isNavigating;
Object? get error;
Future<void> triggerInteraction();

class HudViewData {
  final String displayName;
  final int level;
  final int exp;
  final int expToNextLevel;
}

PlayerStatusHud({required HudViewData data});
```

门交互：

- target 从 C 的唯一配置构建。
- Menu routeName 使用 A 的 /menu 路由。
- target 的 ID、名称、路由非空；坐标有限；radius 为有限正数。
- Controller 监听 movement，范围变化时通知页面。
- dispose 解除监听，不销毁外部注入的 movement。
- 距离 <= radius 时可交互。
- triggerInteraction 再次验证范围。
- 导航锁覆盖进入页面至 pop 返回的完整过程。
- navigate 必须等待 Navigator.pushNamed 对应 Future 完成。
- 导航前 pause+clearInput。
- finally 中 clearInput+resume，释放锁并保留位置。
- 导航失败提供 error。
- BuildContext 只用于页面的 navigate 闭包，不进入 Controller。

HUD：

- displayName 非空。
- level>=1，exp>=0，expToNextLevel>0。
- 进度 ratio 限制在 0 至 1。
- 文本不得因固定高度被截断。
- HUD 位于未缩放 UI 层。
- Overlay 与 sceneRect 使用同一 SceneViewport 局部坐标容器。
- 以 sceneRect 左上角加固定逻辑像素边距定位。
- 字体、图标和边距不乘世界 scale。
- 不跟随角色移动，不锚在桌面两侧留白。
- 小视口收紧或换行，避免负宽度、溢出和遮挡。
- 可用宽度<=0 时不布局 HUD。

演示可由外部输入将状态从 level=1、exp=0、expToNextLevel=100 改为 2、25、100。
必须标注演示数据，不宣称自动奖励链路已完成。

## 10. L/M：财务

```dart
enum FinanceType { income, expense }

int parseAmountMinor(String input, {bool allowZero = false});

String formatAmountMinor(int amountMinor);

class FinanceCategory {
  final String id;
  final String name;
  final FinanceType type;
}

class FinanceRecord {
  final String id;
  final String categoryId;
  final FinanceType type;
  final int amountMinor;
  final DateTime occurredAt;
  final String? note;
}

class CategoryExpense {
  final String categoryId;
  final String categoryName;
  final int amountMinor;
}

class MonthlyFinanceTotals {
  final int incomeMinor;
  final int expenseMinor;
  final int balanceMinor;
  final int? budgetMinor;
  final int? remainingBudgetMinor;
}

class FinanceCalculator {
  MonthlyFinanceTotals calculate(
    List<FinanceRecord> records, {
    int? budgetMinor,
  });
}

class MonthlyFinanceSummary {
  final DateTime month;
  final int incomeMinor;
  final int expenseMinor;
  final int balanceMinor;
  final int? budgetMinor;
  final int? remainingBudgetMinor;
  final List<CategoryExpense> expenseByCategory;
}

FinanceSummaryService({
  required EntityRepository<FinanceRecord> records,
  required EntityRepository<FinanceCategory> categories,
  required Future<int?> Function(DateTime month) loadBudget,
});

Future<MonthlyFinanceSummary> loadMonth(DateTime month);
```

L：

- 实现分类与记录仓库。
- 记录仓库增加 Future<List<FinanceRecord>> listForMonth(int year, int month)。
- 月查询按 occurredAt、id 排序。
- 新建、更新记录必须引用存在的分类。
- category.type 与 record.type 一致。
- 已被引用的分类禁止删除或修改 type。

金额：

- 程序内部以整数“分”存储。
- 记录 amountMinor>0。
- 预算允许 0，null 表示未设置。
- 安全金额上限为 2147483647 分。
- 解析和聚合超限时拒绝，不回绕。
- parse 输入先 trim，仅接受数字及至多两位小数。
- 拒绝负数、指数、空字符串和其他非法格式，抛出 FormatException。
- parse 默认拒绝 0；预算输入使用 allowZero=true。
- 不使用 double 进行金额累加。
- formatAmountMinor(-5000) 返回 -50.00。

M：

- FinanceCalculator 为纯算法，不在内部筛选月份。
- Service 按 [月首, 下月首) 过滤记录，再调用算法。
- Service 归一 month 至本地月首。
- loadBudget 由组合根注入；本阶段不要求预算 CRUD。
- balanceMinor=incomeMinor-expenseMinor。
- remainingBudgetMinor=budgetMinor-expenseMinor。
- 收入不抵消预算支出。
- 未设置预算时 budgetMinor、remainingBudgetMinor 均为 null。
- 超预算时保留负的 remainingBudgetMinor。
- 分类聚合只统计 expense。
- 分类按金额降序，同金额按 categoryId 升序。
- 分类金额合计必须等于 expenseMinor。
- 历史数据存在分类名称缺失时显示“未分类”，保留金额并记录诊断。
- 新建和更新不能制造悬空引用。

## 11. N：Dashboard

```dart
enum SectionStatus {
  loading,
  ready,
  notIntegrated,
  error,
}

class SectionState<T> {
  final SectionStatus status;
  final T? data;
  final Object? error;
}

class TaskMetrics {
  final int totalCount;
  final int completedCount;
  final int todayPendingCount;
  final double? completionRate;
}

class DashboardData {
  final DateTime today;
  final DateTime month;
  final SectionState<TaskMetrics> tasks;
  final SectionState<DaySchedule> activities;
  final SectionState<GpaResult> gpa;
  final SectionState<MonthlyFinanceSummary> finance;
}

DashboardService({
  Future<List<Task>> Function()? loadTasks,
  Future<DaySchedule> Function(DateTime)? loadDay,
  Future<GpaResult> Function()? loadGpa,
  Future<MonthlyFinanceSummary> Function(DateTime)? loadFinance,
});

Future<DashboardData> load({
  required DateTime today,
  required DateTime month,
});

DashboardController({required DashboardService service});

Future<void> load({
  required DateTime today,
  required DateTime month,
});

Future<void> retry();

DashboardData? get data;
bool get isLoading;
Object? get error;
```

接入和状态：

- 回调为 null，对应区块为 notIntegrated，显示“未接入”。
- 各区块独立捕获错误。
- 一个区块失败不阻止其他成功区块显示。
- Controller.error 用于整次参数或基础加载失败。
- ready 可以包含合法的 0 或领域结果中的 null。
- 空记录不能伪装为“未接入”。
- 多次加载仅最新请求可以更新状态。
- retry 使用上一次明确传入的 today/month。
- GPA 使用 J 的 GpaResult，不重新计算。
- 财务使用 M 的摘要，不重新聚合。

指标：

- totalCount 为全部当前任务数。
- completedCount 为其中已完成数。
- completionRate=completedCount/totalCount。
- totalCount=0 时 completionRate=null，显示“暂无任务”。
- todayPendingCount 仅统计未完成任务。
- scheduledRange 与当天相交，或 dueAt 在当天，即计入今日待办。
- 同时满足两个条件时按 id 去重。
- 无安排且无当天截止时间的任务不计入今日待办。
- 今日活动使用 I 的 items。
- 不将 unscheduledTasks 当作当天活动。
- 财务金额以 *Minor 字段传递，展示时转换为元。
- 本阶段不实现学习时长、GPA 趋势和财务趋势。

布局：

- 使用功能页面完整可用内容区域，不套竖版世界比例。
- 组件内容宽度<600 逻辑像素时一列。
- >=600 时两列。
- 内容最大宽度为 1200，居中。
- 必要时滚动。
- 测试 599、600、601 及宽于 1200 的布局。
- 长标题、小窗口不得产生溢出。

## 12. O：JSON 存储

```dart
abstract interface class JsonDocumentStore {
  Future<String?> readDocument(String path);
  Future<void> writeDocument(String path, String content);
}
```

目录和职责：

- Store 读写原始 UTF-8 文档。
- 文件不存在时 readDocument 返回 null。
- 零字节、空白和损坏文档不视为不存在。
- A 组合根注入 Windows/Android 应用数据绝对目录。
- 应用数据目录通过 AppDataDirectoryProvider 或等价平台适配封装获取。
- 各 Repository 选择固定文件名。
- 页面不直接传入任意存储路径。
- 测试使用临时目录和注入故障，不操作用户真实数据。

演示：

- 首次优先持久化 Task 单模型。
- 其他内存 Repository 明确标注重启不保留。
- 不宣称全部模型已持久化。

写入流程：

1. 在串行操作队列中读取当前状态。
2. 校验操作和新快照。
3. 持久化新快照。
4. 成功后提交内存状态。
5. 失败保留旧内存状态，向调用方抛出错误。
6. 后续请求仍能继续执行。

串行范围覆盖完整读、校验、写入与提交过程，不仅排队 write。

文件保存：

1. 校验当前有效文档和新文档。
2. 写临时文件并 flush。
3. 将上一有效主文件保留为 .bak。
4. 按平台可用的安全方式替换主文件。
5. 替换成功后返回成功。

- .bak 保留上一有效版本。
- 不在成功后将新主文件覆盖为备份。
- 不用“rename 在两平台均原子”代替实际故障验证。
- 损坏读取保留原件，阻止常规写入。
- 恢复 .bak 前验证 schemaVersion、entityType 和 records。
- 恢复必须明确提示，不静默吞错。

必测：

- 首次无文件。
- 正常保存与读取。
- 完全关闭应用后重新打开。
- 有效 records=[]。
- 零字节、空白和损坏 JSON。
- 版本、实体类型和记录字段错误。
- 保存失败时内存保留旧状态。
- 连续操作不丢记录。
- 临时文件写入失败。
- 备份后、替换前故障。
- 主文件替换失败。
- 成功后重启。
- 最后有效数据可恢复。

单模型存储不承诺跨文件奖励事务。

## 13. P：CI

工程根目录为 frontend/，Flutter 检查必须在该目录运行。

CI 至少包含：

1. checkout。
2. 安装团队约定的固定 Flutter 版本。
3. flutter pub get。
4. dart format --output=none --set-exit-if-changed lib test。
5. flutter analyze。
6. flutter test。

要求：

- 从实际 frontend/pubspec.yaml 读取项目和依赖情况。
- 不对不存在的目录运行命令。
- 不将占位 workflow 写成已经执行成功。
- 提交 PR 后提供实际 Actions 链接与结果。
- CI 失败先定位和修复，再申请合并。
- Linux CI 和 Widget 测试不能替代 Windows/Android 原生启动。

Flutter 版本以团队环境确认后固定的版本为准；成员不得自行升级项目 SDK 或依赖。

## 14. 协作、开发与合并顺序

### 14.1 开发放行

每位成员报告：

- 姓名。
- 当前 main 提交 SHA。
- Flutter 版本。
- flutter doctor 中本人目标平台工具链结果。
- flutter pub get 结果。
- flutter analyze 结果。
- flutter test 数量与结果。
- 原生运行平台及结果。
- “采用统一契约 v1.0”。
- 阻塞项；未执行的检查明确写“未执行”。

不得将未回复成员写成环境已通过。

组员可以在统一接口和本人开发平台环境确认后开始独立模块开发。
不要求全员先解决 Android 模拟器；Android 原生验证由明确负责人推进。

### 14.2 可并行部分与真实依赖

| 模块 | 可独立推进 | 接入依赖 |
| --- | --- | --- |
| B/O/P | 存储实现、故障测试、CI | 已合并公共类型、实际工程 |
| C/D | 世界配置、变换、移动和碰撞测试 | 素材与页面接线由 A 协调 |
| E/F | 交互、HUD 与注入替身测试 | C 配置、D 移动接口、A 路由 |
| G | 学术模型、内存仓库、课次展开 | 公共 TimeRange、ScheduleItem、Repository |
| H/I | Task/Event、仓库、日程及页面 | 公共类型；课程接入依赖 G；持久化依赖 O |
| J/K | GPA、冲突算法和测试 | G Course；公共 TimeRange、ScheduleItem |
| L/M | 财务模型、仓库、汇总和测试 | 公共 Repository |
| N | 区块状态、布局、指标及替身测试 | H/I、J、M 的真实回调由 A 接线 |
| A | 组合根、路由、证据、集成计划 | 各模块实际可编译提交 |

测试替身只用于开发验证，正式演示需清楚区分真实数据接入和未接入区块。

### 14.3 合并顺序

按实际依赖分批合并：

1. 公共契约基线：已完成。
2. G、H 模型和仓库；C/D；L/M；O/P 等各自独立且检查通过的基础模块。
3. E/F 接入 C/D；I 接入 G/H；J/K 接入对应模型。
4. N 接入 I/J/M；Task 仓库接入 O。
5. A 完成组合根、路由、原生验证和演示闭环。

互不依赖的模块可并行审核和合并，不强制排成单一串行队列。
尚未合并的依赖不能当作 main 中已存在的代码。

### 14.4 每人开发流程

1. 确认工作区状态，保存或提交本人已有工作。
2. 同步 main。
3. 从约定基线创建本人功能分支。
4. 阅读本文和本人 Issue。
5. 在本人负责路径实现代码和必要测试。
6. 使用真实公共类型，不复制同名接口。
7. 运行格式化、静态分析和测试。
8. 提交并推送功能分支。
9. 建立 PR，关联本人 Issue。
10. PR 写明改动、依赖、测试数量、原生运行证据和未完成项。
11. 由陈思翰审核；修改继续提交到同一 PR。
12. 合并后消费方同步 main，完成真实接入。

本人任务可统一放在一个 Issue 内，通过检查项记录子任务；实现提交可以分批 PR。
不得把未完成项全部勾选，也不得仅交规范文档宣称功能开发完成。

## 15. 构造、不可变与交付约定

- 本文代码块为接口示意，不是完整可编译实现。
- 模型构造器由提供方实现。
- 除明确默认值和可空规则外，字段使用命名 required 参数。
- 结果模型中的可空字段允许显式传 null。
- List/Set 在构造时复制并设为不可变。
- 消费方使用冻结字段，不发明同义字段。
- SectionState.ready 必须携带 data。
- SectionState.error 必须携带 error。
- loading/notIntegrated 不携带伪造数据。
- ChangeNotifier 修改可观察状态后通知监听者，并正确释放本人持有的资源。

每个模块交付：

1. 实际代码和测试。
2. PR 链接与关联 Issue。
3. 格式化、静态分析、测试结果。
4. 需要 UI 的模块提供实际运行截图。
5. 需要持久化的任务提供重启和失败反馈证据。
6. 明确已完成、未完成、使用替身或演示数据的部分。
7. 说明消费方如何构造和调用该模块。

本文件提交和合并后，所有成员在本人 Issue 中确认采用 v1.0。
后续问题优先在开发 Issue 内修复，不再循环提交另一套互不兼容的规范。