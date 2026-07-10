# ThoughtEcho 项目指南

## 项目概览

- **项目**：ThoughtEcho（心迹），Flutter 3.x 跨平台笔记应用
- **支持平台**：Windows、Android、iOS
- **不支持平台**：Web。不要新增 Web 入口、Web 专用实现、Web 构建或 Web 测试；仓库中
  现存的 `kIsWeb`、`*_web.dart` 和 Web 依赖属于历史兼容代码，不代表支持 Web，也不要在
  无关任务中顺手清理。
- **主要技术**：Flutter、Dart、SQLite、Provider、FlutterQuill、多 AI Provider

## 指令作用域

- 本文件适用于整个仓库；进入含有 `AGENTS.md` 的子目录后，还必须遵守距离目标文件最近的
  子目录指令。
- 子目录文件用于补充局部约定，不能放宽本文件中的平台、安全、隐私和 Git 约束。
- 用户当前请求优先于仓库工作流偏好；如果请求与安全、隐私或数据完整性约束冲突，先说明
  风险并请求确认。
- 修改前先阅读目标实现、相邻测试和对应子目录 `AGENTS.md`。不要仅凭文件名或旧文档推断。

## 目录结构

```text
ThoughtEcho/
├── lib/
│   ├── main.dart           # 应用入口、Provider 注入、启动恢复
│   ├── controllers/        # 页面级 UI 状态与编排
│   ├── models/             # 领域、持久化和展示模型
│   ├── pages/              # 页面及页面级 part 拆分
│   ├── services/           # 数据、网络、AI、同步等业务能力
│   ├── utils/              # 可复用工具和平台适配
│   ├── widgets/            # 可复用 UI 组件
│   ├── constants/          # 应用常量、卡片模板、AI Prompt
│   ├── theme/              # Material 3 主题
│   ├── config/             # 动画和引导配置
│   ├── extensions/         # Dart 扩展
│   ├── l10n/               # ARB 国际化源文件
│   └── gen_l10n/           # 生成的国际化代码，禁止手动编辑
├── test/                   # 单元、Widget、集成、性能测试
├── assets/                 # 应用图标、Lottie、SVG 等应用资源
├── docs/                   # 用户手册等项目文档
├── res/                    # 网站、营销和展示资源
├── scripts/                # 构建及维护脚本
├── .github/workflows/      # CI 与发布流程
└── android/ ios/ windows/  # 平台原生工程
```

主要拆分：`services/database/`（12 个 mixin）、`pages/note_editor/`（10 个 part）、
`pages/ai_report/`（4 个 part）、`services/smart_push/`（6 个 part）、
`widgets/note_list/`（4 个 part + 1 个独立辅助文件）。

## 常用命令

```bash
# 安装依赖
flutter pub get

# 运行应用
flutter run

# 格式化本次修改的 Dart 文件
dart format <changed-dart-files>

# 只检查格式，不改文件
dart format --output=none --set-exit-if-changed <changed-dart-files>

# 静态分析
flutter analyze --no-fatal-infos

# 运行相关测试文件（默认做法）
timeout 60s flutter test --reporter compact test/path/to/file_test.dart

# 按名称运行单个用例
timeout 60s flutter test --reporter compact test/path/to/file_test.dart --name "用例名称"

# 全量聚合测试（仅在用户明确要求时）
timeout 180s flutter test --reporter compact test/all_tests.dart

# 修改 ARB 后生成国际化代码
flutter gen-l10n

# 修改 Mockito 接口或注解后重新生成 Mock
dart run build_runner build --delete-conflicting-outputs

# 平台构建
./scripts/build_ios_unsigned.sh
pwsh ./scripts/build_msix_ci.ps1
```

测试冷启动可能超过 60 秒；首次卡在 `loading` 时可预热或将单次超时提高到 180 秒。输出过多
时先定位编译/分析错误，不要反复运行长输出命令。

## 工作方式

1. 先确认请求范围和验收标准，再检查 `git status --short`，保留用户已有改动。
2. 用 `rg` / `rg --files` 查找定义、调用方、测试和文档；修改复杂文件前阅读其拆分文件。
3. 做最小且完整的改动。修 Bug 时优先添加能复现问题的回归测试；新增逻辑补相应测试。
4. 只格式化和验证相关文件。除非用户明确要求，不主动运行全量测试或全仓库格式化。
5. 完成前检查 diff、相关测试和静态分析结果；无法执行的验证要明确说明，不能声称已通过。

涉及第三方库、Flutter/Dart SDK、平台 API、AI 服务协议或 GitHub Actions 时，先用 Context7
查询当前官方文档（`resolve-library-id` → `get-library-docs`）；Context7 不可用或无对应资料时，
再查官方文档。纯项目内重构、业务调试、格式化和 ARB 文案调整无需查询。

## Dart 与 Flutter 规范

- 遵循 `analysis_options.yaml` 和 `dart format`；不要假设格式化器会自动整理 import。
- import 分组依次为 `dart:`、Flutter SDK、第三方 package、`package:thoughtecho/`，组内按字母序。
- 使用具体类型和 null safety，避免无边界的 `dynamic`、不必要的 `!` 和宽泛类型转换。
- 类/枚举使用 `UpperCamelCase`，成员使用 `lowerCamelCase`，私有成员加 `_`，文件使用
  `snake_case.dart`，测试使用 `*_test.dart`。
- 公共 API 使用 `///`；注释解释原因、约束或不直观行为，不复述代码。提交前删除临时日志和
  调试注释。
- 新增或重构时避免继续扩大超大文件；优先按职责抽取 Widget、helper、mixin 或子目录。
  “500 行”是需要评估拆分的信号，不是为了达标而机械切文件的硬门槛。
- 重复逻辑达到三处时评估抽取；只有在共享概念确实稳定时才抽象。

## 架构约定

### 状态管理

- 可观察的应用/UI 状态使用 `ChangeNotifier` 并由 Provider 注入；纯计算、文件工具和无状态服务
  不需要为了统一形式继承 `ChangeNotifier`。
- 只有可观察状态实际变化后才调用 `notifyListeners()`；只读操作或无状态 Service 不要空通知。
- 不监听时使用 `context.read<T>()` 或 `Provider.of<T>(context, listen: false)`；需要重建时使用
  `context.watch<T>()`、`select` 或 `Consumer<T>`，避免扩大重建范围。
- Controller 管页面状态和交互编排，持久化、网络及可复用业务规则下沉到 Service。

### 服务与错误处理

- Service 不持有页面 `BuildContext`。现有 Service 如需调度帧，优先依赖
  `package:flutter/scheduler.dart`，不要新增 `flutter/widgets.dart` 依赖来耦合 UI。
- 异常应带操作上下文记录到 `UnifiedLogService` 或项目日志封装，再向上抛出或采用明确的降级
  策略；禁止静默吞错。
- 页面级用户操作用 `try/catch` 转成国际化、可理解的反馈，不向用户裸露堆栈或密钥。
- 网络重试、超时和取消沿用现有网络工具；不要在调用点各自实现无限重试。

### 模型与富文本

- 需要持久化的模型提供与其存储格式匹配的序列化接口（如 `toMap/fromMap` 或
  `toJson/fromJson`）；不可变模型提供 `copyWith()`。
- `Quote` 同时保存 `content`（纯文本）和 `deltaContent`（Quill Delta JSON）；编辑、同步、
  导入和恢复时必须保持两者一致。
- 模型新增持久化字段时，同时检查 schema、迁移、备份/恢复、同步、`copyWith`、序列化和测试。

### 国际化与主题

- UI 层禁止硬编码任何用户可见文本，包括按钮、菜单、Tooltip、Dialog、SnackBar、空状态和
  无障碍标签。
- 新文案依次修改 `lib/l10n/app_zh.arb` 与 `lib/l10n/app_en.arb`，占位符声明元数据，然后运行
  `flutter gen-l10n`；禁止手动编辑 `lib/gen_l10n/`。
- 颜色和文字样式优先来自 `Theme.of(context)` / `ColorScheme`。只有品牌色、数据可视化语义色
  或平台明确要求的颜色可集中定义，不在页面散落 `Color(0x...)`。
- 异步间隔后使用 `context` 或更新 State 前检查 `mounted` / `context.mounted`。

## 数据库与批量数据

- Schema 真源位于 `lib/services/database_schema_manager.dart`，版本为
  `DatabaseSchemaManager.schemaVersion`；`database_migration_mixin.dart` 处理运行期数据迁移和
  维护，不是 schema 版本升级的唯一位置。
- Schema 变更必须同时更新新建表结构、追加新的版本升级分支、递增 `schemaVersion`，并覆盖
  新安装与旧版本升级两条路径。禁止改写已发布版本的迁移语义。
- SQL 值使用参数绑定；动态 `orderBy` 必须经过 `sanitizeOrderBy()` 白名单处理。表名、列名等
  无法绑定的标识符也必须来自内部白名单。
- 禁止列表循环内逐条查询、计数、全文搜索或加载关联表。批量场景优先 `IN (...)`、事务、
  `Batch`、批量 SQL 或预加载 Map。
- 大文件和大 JSON 使用流式工具（如 `LargeFileManager`），不要用一次性
  `File.writeAsString` / 全量内存编码。
- 删除 SQL 查询字段前全局检查模型、UI、导入导出和同步依赖，避免运行期缺列或类型错误。

## AI 服务

主要链路：

```text
MultiAISettings → AIProviderSettings → AINetworkManager / OpenAIStreamService
                                      ↓
                                APIKeyManager
```

- API 密钥只能通过 `APIKeyManager` / 安全存储读写，禁止进入源码、日志、测试夹具、截图或
  错误信息。
- 新增 Provider 时至少检查预设、请求头、请求体适配、流式协议、设置 UI、连接测试、密钥存储
  和相关单元测试；先查服务商当前官方协议。
- 支持的预设以 `AIProviderSettings.getPresetProviders()` 为准，不在文档中复制易过期的名单。
- 使用现有流式 API。已删除的 `AIService.generateDailyPrompt` 不得恢复，使用
  `streamGenerateDailyPrompt`。

## 平台与文件组织

| 平台 | 约定 |
|---|---|
| Windows | SQLite 使用 FFI；数据目录逻辑由 `DataDirectoryService` 和现有初始化代码负责 |
| Android | 使用 sqflite/MMKV；保留现有 32 位 ARM 回退策略 |
| iOS | 使用 MMKV；无签名构建走 `scripts/build_ios_unsigned.sh` |
| Web | 不支持；不得新增或扩展 Web 功能 |

- `.py`、`.sh`、`.bat`、`.ps1` 等维护脚本放在 `scripts/`，不要放仓库根目录。
- 应用图标放 `assets/`，Lottie 放 `assets/lottie/`，SVG 放 `assets/svg/`，营销/网站资源放
  `res/`。
- 不提交 `.gradle/`、`.dart_tool/`、`build/`、`node_modules/`、`.metadata` 等生成物或本机状态。
- 生成文件（`lib/gen_l10n/`、`*.mocks.dart`、平台插件注册文件）不得手动编辑；是否提交遵循
  当前 `.gitignore` 和仓库既有跟踪状态，不要一概删除或强行加入。

## 复杂度热点

修改前先查找父文件的 `part` 声明、相关 mixin 和测试：

| 区域 | 说明 |
|---|---|
| `lib/services/database_service.dart` + `services/database/` | 数据库接口、12 个 mixin、缓存与查询 |
| `lib/services/database_schema_manager.dart` | 建表、版本升级、修复和迁移，数据风险高 |
| `lib/pages/home_page.dart` | 主页面状态与多类交互 |
| `lib/widgets/add_note_dialog.dart` | 超大新增笔记流程，另有 parts 文件 |
| `lib/pages/settings_page.dart` | 设置入口与多 Service 交互 |
| `lib/pages/note_sync_page.dart` | 设备发现、传输和合并状态 |
| `lib/pages/annual_report_page.dart` | 报告聚合和复杂展示 |
| `lib/pages/note_full_editor_page.dart` + `pages/note_editor/` | Quill 编辑、媒体、元数据和草稿 |
| `lib/pages/ai_assistant_page.dart` + `pages/ai_assistant/` | Agent 会话、工作流与流式 UI |
| `lib/services/smart_push_service.dart` + `services/smart_push/` | 调度、权限、通知和内容选择 |
| `lib/widgets/note_list_view.dart` + `widgets/note_list/` | 分页、过滤、滚动定位和条目构建 |
| `lib/constants/card_templates.dart` | 大量卡片模板，改动需验证渲染与国际化 |

## 已删除 API

- `AIService.generateDailyPrompt` → 使用 `streamGenerateDailyPrompt`
- `TimeUtils.formatTime` → 使用 `formatRelativeDateTime` 或 `formatQuoteTime`
- `NoteSyncService.receiveAndMerge` → 不得重新引入，沿用当前同步/合并流程

## 文档维护

- 开发者文档：`AGENTS.md`、各子目录 `AGENTS.md`、`README.md`
- 双语用户手册：`docs/USER_MANUAL.md`
- 应用内手册：`assets/docs/user_manual_zh.md`、`assets/docs/user_manual_en.md`
- 网站：`res/index.html`、`res/user-guide.html`

只有用户可见行为变化时才同步用户文档，并同时维护中英文内容；纯内部重构只更新确实受影响
的开发者文档。禁止描述尚未实现的功能，除非明确标为路线图。

## Git、隐私与提交

- 开始和结束时检查 `git status --short` 与 `git diff`，不要覆盖、回滚或格式化用户的无关改动。
- 切换其他分支或排查其他分支时使用 `git worktree`，不要在当前工作区直接切分支。
- 提交时只用 `git add <明确文件...>`；禁止 `git add .` 和 `git add -A`。
- 未经用户要求不要 amend、rebase、force-push、删除分支或创建远程 PR。
- 提交前检查 staged diff，不得包含真实 API 密钥、令牌、个人数据、私密路径、含隐私截图或
  本机缓存。
- 提交信息应概括实际改动；只有验证通过或明确记录未执行项后，才能宣称完成。
