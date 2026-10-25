# ThoughtEcho AGENTS.md

## 平台与作用域

- **支持平台**：Windows、Android、iOS。**不支持 Web**：现存 `kIsWeb` / `*_web.dart` 属于历史兼容残留，禁止新增 Web 入口、实现或测试，也不要在无关任务中顺手清理。
- **指令层级**：进入含 `AGENTS.md` 的子目录时同步遵守就近子目录规则（子目录不可放宽本文件的安全、隐私与主题红线）。若本地存在 `docs/DEVICE_INFO.md`（已忽略），先读其环境约束。
- **历史沉淀优先**：改动已被深度优化过的模块（列表性能、主题、Thoughter 记忆、同步）前，先查 [`docs/INDEX.md`](docs/INDEX.md) 与 `docs/decisions.md`。`docs/squad/` 仅为历史过程档案，不作实现规范。

## 常用命令与验证

```bash
# 格式化改动文件（提交前必跑）
dart format <changed-dart-files>

# 仓库增量机械规则检查（颜色令牌、动态圆角、AppSnackBar、禁止 ThemeStyle 分支、禁止裸调 Aptabase、已删 API）
# 首次可运行 git config core.hooksPath .githooks 启用 pre-commit 自动检查
dart scripts/lint_repo_rules.dart

# 静态分析
flutter analyze --no-fatal-infos

# 运行单个测试文件或按名称过滤（默认只跑相关测试；首次冷启动慢可将超时提至 180s）
timeout 60s flutter test --reporter compact test/path/to/file_test.dart --name "用例名称"

# 重新生成 Mockito Mock
dart run build_runner build --delete-conflicting-outputs
```

- **命令行输出控制**：运行测试、分析等长输出命令时优先静默重定向（`cmd > /tmp/run.log 2>&1 || tail -n 25 /tmp/run.log`），禁止用 `gh run watch` 等持续刷新命令刷屏；`gh run view <id>` 必须带 `<id>` 避免交互挂起。
- **国际化（l10n）**：UI 层严禁硬编码用户可见文本（含 Tooltip、SnackBar、Dialog、Semantics）。日常开发只需新增中英文（`lib/l10n/app_zh.arb` 与 `lib/l10n/app_en.arb`，未翻译语言默认回退 `en`）；构建与 CI 会自动生成代码，禁止手动编辑 `lib/gen_l10n/`。

## UI 与主题令牌红线（由 `lint_repo_rules.dart` 把关）

主题风格是独立于亮暗/动态取色的第三维度：`material`（默认，`ThemeStyle.defaultStyle` 不可改）、`paper`（纸与墨）、`plain`（素笺）。动主题前先读 [`docs/paper-ink-theme-handoff-2026-07-31.md`](docs/paper-ink-theme-handoff-2026-07-31.md)，改色板必须过 `test/theme/theme_style_contrast_test.dart`（手工色板亮色路径须关 `keyColors` 与表面混合）。

- **禁在 Widget 判断 `ThemeStyle`**：边框、投影与纸纹差异全部通过 `AppShapeTokens.of(context)`（`borderWidth`、`ruleSpacing`、`cardRadius` / `buttonRadius` / `inputRadius` / `dialogRadius` / `fabRadius`）表达；禁止手写 `BorderRadius.circular(N)` 或引用静态 `AppTheme.*Radius`。
- **颜色**：状态色用 `AppSemanticColors.of(context)`（`success` / `warning` / `danger` / `info` / `favorite`），次要文字用 `colorScheme.onSurfaceVariant`，背景用 `surfaceContainer*`；禁止在 `lib/pages/` 与 `lib/widgets/` 使用 `Colors.*` 命名色或 Tailwind 十六进制字面量。
- **排版**：禁止在 Widget 写死 `fontSize:`、正文 `height:`、`fontWeight:`（纸墨横线间距由「正文字号 × 行高」推导，覆盖任一会导致文字逐行漂移；`label*` 保持系统黑体不缩放）。禁止将 `FontStyle.italic` 用作 UI 装饰（仅富文本编辑器内容、PDF 导出与 Markdown `em` 保留斜体）。
- **通用组件**：统一用 `AppSnackBar.info/success/warning/error`（禁裸调 `showSnackBar`）；加载/空态/错误态用 `AppLoadingView` / `AppEmptyView` / `AppErrorView`；开发者/实验开关统一放入设置页 `_buildLabSection`。

## 数据库与领域陷阱

- **标签命名历史陷阱**：SQL 的 `categories` 表、`category_id` 列及备份 JSON 的 `categories` 键实际存的是**标签**（Dart 侧一律用 `NoteTag` / `getTags()`，管理页为 `tag_settings_page.dart`）；API Ninjas 名言分类和 emoji 分组才是真 `category`。
- **`Quote` 双字段同步**：`Quote` 同时保存 `content`（纯文本）和 `deltaContent`（Quill Delta JSON），编辑、同步、导入恢复时必须保持一致。
- **Schema 与 SQL 安全**：Schema 真源在 `lib/services/database_schema_manager.dart`（`schemaVersion`），修改须同时覆盖新建表与旧版升级迁移（禁改已发布版本的迁移语义）。动态 `orderBy` 必须经 `sanitizeOrderBy()` 白名单处理；禁止在循环内逐条查询。
- **校验对齐与坏行隔离**：`Quote.fromJson` 与 `Quote.validationError` 校验边界必须一致；外来数据收敛仅做在导入边界（`DatabaseBackupService` → `MergeReport.sanitizedFields`）；不可逆迁移写入前必须先将整列快照至 `<列名>_backup`（遗留列清理排在建快照列之前）；查询反序列化统一走 `_parseQuoteRows` / `_tryParseQuoteRow`，且日志严禁打印含笔记正文的 `FormatException.toString()`。

## AI、Thoughter 记忆与可观测性埋点

- **AI 链路**：`MultiAISettings → AIProviderSettings → AINetworkManager / OpenAIStreamService`，API Key 仅走 `APIKeyManager`。`AIConnectionTester` 必须复用 `OpenAIStreamService → openai_dart` 真实链路，超时下沉到 client 配置而非外层 `Future.timeout`。
- **已删除 API（禁止恢复）**：`AIService.generateDailyPrompt`（改用 `streamGenerateDailyPrompt`）、`TimeUtils.formatTime`（改用 `formatRelativeDateTime` / `formatQuoteTime`）、`NoteSyncService.receiveAndMerge`。
- **Thoughter 长期记忆（`AgentMemoryService`）**：独立库 `agent_memory.db`（不进备份、不同步），只存笔记推导不出的用户画像/偏好，通过独立 user 消息经 `wrapUserProfile` 注入（禁拼 system prompt），偏好变更原位 supersede。详见 [`docs/agent-memory-research-2026-08-08.md`](docs/agent-memory-research-2026-08-08.md)。
- **新功能可观测性与隐私埋点（默认均关闭，双独立开关）**：
  - **Aptabase 匿名统计**：新增独立页面或用户显式触发的核心功能动作时，在成功触发边界调用 `AptabaseHelper.trackPageView('<snake_case_page>')` 或 `AptabaseHelper.trackEvent('feature_used', {'action': '<snake_case_action>'})`（禁裸调 `Aptabase.instance`；`props` 仅限固定枚举/布尔/数值，严禁含笔记正文、标签、搜索词或位置隐私）。
  - **Sentry 诊断与追踪**：Service 不持有 `BuildContext`；异常统一调 `logError` / `AppLogger.e`（由 `UnifiedLogService` 按开关自动上报 Sentry，不手写 `Sentry.captureException`）；重度加载/渲染链路用 `AppTracer`；**AI 请求严禁挂载 `SentryNetworkTracing`**。

## 代码卫生与 Git

- 文件与类名直指当前职责，禁止 `_v2` / `_new` / `_clean` / `_fixed` / `_wrapper` 后缀；废弃文件直接删除。
- 切分支用 `git worktree`；只用 `git add <明确文件...>`（禁 `git add .` / `-A`），保留用户未提交改动。
- **脱敏**：测试夹具、注释、提交信息与 PR 描述严禁出现真实具体地名/POI、姓名、私人路径或真实 API Key，一律用合成占位数据（如 `示例省·示例市`、`MockPOI`）。
