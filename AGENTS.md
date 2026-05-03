# Repository Guidelines

## Project Structure & Module Organization

ThoughtEcho 是一款 Flutter 3.x 跨平台笔记应用（Android, iOS, Windows — **不支持 Web**）。

```
lib/
  main.dart              # 入口 + Provider 注入 + 紧急恢复 (1354 行)
  controllers/           # UI 控制器 (3 个)
  models/                # 数据模型 (25 个)
  pages/                 # 页面组件 (35+ 文件)
  services/              # 业务服务 (65+ 文件，ChangeNotifier)
  utils/                 # 工具类 (70+ 文件)
  widgets/               # UI 组件 (50+ 文件)
  theme/                 # Material 3 主题 (app_theme.dart)
  constants/             # 常量 (card_templates, ai_card_prompts, app_constants)
  config/                # Lottie/引导页配置
  extensions/            # Dart 扩展方法
  l10n/                  # ARB 源文件 (编辑此处)
  gen_l10n/              # 生成文件 (禁止手动编辑)
test/                    # 单元/Widget/集成/性能测试
```

大文件通过 `part`/mixin 或子目录拆分：`database/`(12 mixin)、`note_editor/`(10)、`ai_report/`(6)、`smart_push/`(6)、`note_list/`(5)。

## Build, Test, and Development Commands

```bash
flutter pub get                                      # 安装依赖
flutter run                                          # 运行应用
dart format --set-exit-if-changed .                  # 格式化检查 (CI 强制)
flutter analyze --no-fatal-infos                     # 静态分析
flutter test test/all_tests.dart                     # 全量测试入口
flutter test test/unit/models/quote_model_test.dart  # 单文件测试
flutter test test/unit/services/                     # 目录测试
flutter gen-l10n                                     # 生成国际化 (改 ARB 后必须执行)
dart run build_runner build --delete-conflicting-outputs  # 重新生成 Mock
```

## Coding Style & Naming Conventions

- **缩进**: 2 空格，80 字符行宽，Widget 参数列表尾随逗号
- **命名**: `UpperCamelCase`(类/枚举)、`lowerCamelCase`(方法/变量)、`snake_case`(文件)
- **导入顺序**: `dart:*` → `package:flutter/*` → 第三方包 → `package:thoughtecho/*`（dart format 自动排序）
- **格式化**: `dart format` 强制执行，未格式化代码 CI 报错
- **Lint**: `package:flutter_lints/flutter.yaml`
- **私有成员**: `_` 前缀
- **类型**: 优先具体类型，不使用 `dynamic`；可空类型标 `?`；延迟初始化用 `late`

## Testing Guidelines

- 入口: `test/all_tests.dart`
- Mock 生成: `test/test_setup.dart` 统一注册平台 Mock；`*.mocks.dart` 禁止手动编辑
- 目录镜像 `lib/` 结构: `test/unit/models/`、`test/unit/services/`、`test/unit/controllers/`、`test/unit/utils/`
- 按名称运行: `flutter test <file> --name "用例名"`
- **不要主动运行全量测试**（CI 超时风险），仅在明确要求时运行

## Commit & Pull Request Guidelines

- 提交信息可加 emoji 前缀: `🧪`(test), `🧹`(cleanup), `⚡`(perf), `🎨`(UI)
- 也使用 conventional 前缀: `perf:`, `chore:`, `test:`, `style:`
- PR 引用 issue 编号，推送前执行 `dart format` 和 `flutter analyze`

## Key Architecture Rules

- **状态管理**: 所有 Service 继承 `ChangeNotifier`，`main.dart` 中 `ChangeNotifierProvider` 注入；写操作后**必须** `notifyListeners()`
- **国际化**: 禁止硬编码用户可见文本 → `app_zh.arb` / `app_en.arb` → `flutter gen-l10n`
- **错误处理**: `logError('类.方法', e, stack)` 先记录再 rethrow/降级
- **No Web**: 禁止添加任何 Web 兼容代码
- **500 行上限**: 新增/重构文件超过此限制必须拆分
- **废弃 API**: `AIService.generateDailyPrompt` → `streamGenerateDailyPrompt`; `TimeUtils.formatTime` → `formatRelativeDateTime`; `NoteSyncService.receiveAndMerge` → 已废弃

## 快速定位

| 任务 | 位置 |
|------|------|
| 数据库 CRUD | `services/database_service.dart` + `services/database/database_*_mixin.dart` |
| AI 流式请求 | `services/ai_service.dart` → `utils/ai_request_helper.dart` |
| API 密钥 | `services/api_key_manager.dart` |
| 富文本编辑器 | `pages/note_full_editor_page.dart` + `pages/note_editor/` |
| 备份恢复 | `services/backup_service.dart` |
| 设备同步 | `services/note_sync_service.dart` + `services/localsend/` |
| 智能推送 | `services/smart_push_service.dart` + `services/smart_push/` |
| 主题 | `theme/app_theme.dart` |
| 日志 | `services/unified_log_service.dart` + `services/log_database_service.dart` |
| 大文件 | `services/large_file_manager.dart` |
