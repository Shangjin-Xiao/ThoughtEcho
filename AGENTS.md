# PROJECT KNOWLEDGE BASE

**Generated:** 2026-01-17T02:30:00Z
**Commit:** d00320a
**Branch:** main

## OVERVIEW

ThoughtEcho (心迹) - Flutter 3.x 跨平台笔记应用，集成 AI 分析、富文本编辑、多设备同步。本地优先存储，支持 Android/iOS/Windows/Web。

## STRUCTURE

```
ThoughtEcho/
├── lib/
│   ├── main.dart           # 入口点 + Provider 注入 + 紧急恢复
│   ├── controllers/        # UI 控制器 (search, onboarding)
│   ├── models/             # 数据模型 (Quote, NoteCategory, AISettings)
│   ├── pages/              # 页面组件 (33 files)
│   ├── services/           # 业务逻辑服务 (78 files) → 见子目录 AGENTS.md
│   ├── utils/              # 共享工具类 (50 files)
│   ├── widgets/            # UI 组件 (34 files)
│   ├── theme/              # 主题定义
│   ├── constants/          # 常量 (卡片模板, AI prompts)
│   └── gen_l10n/           # 国际化生成文件
├── test/                   # 测试 (unit/widget/integration/performance)
├── scripts/                # 构建脚本 (iOS/Windows/MSIX)
├── android/ios/web/windows/ # 平台特定代码
└── assets/                 # Lottie 动画, 图标
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| 应用初始化 | `lib/main.dart` | Provider 注入顺序关键 |
| 数据库操作 | `lib/services/database_service.dart` | 5820 行，核心 CRUD + 迁移 |
| AI 功能 | `lib/services/ai_service.dart` | 多 provider 架构，流式响应 |
| 状态管理 | Provider + ChangeNotifier | 服务层继承 ChangeNotifier |
| 富文本编辑 | `lib/pages/note_full_editor_page.dart` | FlutterQuill，双格式存储 |
| 设备同步 | `lib/services/localsend/` | LocalSend 协议实现 |
| 备份恢复 | `lib/services/backup_service.dart` | ZIP 流式压缩 |
| 主题定制 | `lib/theme/app_theme.dart` | Material 3 + 动态颜色 |
| 国际化 | `lib/l10n/*.arb` | 先改 ARB，再 `flutter gen-l10n` |

## CONVENTIONS

### UI 开发规范
- **调试功能隐身**: 所有测试按钮、调试入口必须仅在**应用内开发者模式**（通过关于页面激活）或 Debug 模式下显示，禁止在 Release 包的普通用户界面中直接暴露。
- **设计美学**: 追求极致的视觉体验，使用 Material 3 规范，注重动效和微交互。

### 状态管理
- 所有服务继承 `ChangeNotifier`，在 `main.dart` 通过 `ChangeNotifierProvider` 注入
- 写操作后**必须**调用 `notifyListeners()`
- 访问服务：`Provider.of<XxxService>(context, listen: false)`

### 国际化 (严格)
- **禁止 UI 中硬编码中文**，所有用户可见文本用 `AppLocalizations.of(context).keyName`
- 新增文案：先改 `lib/l10n/app_zh.arb` + `app_en.arb`，再 `flutter gen-l10n`

### 数据模型
- 核心模型 `Quote` 双存储：`content` (纯文本) + `deltaContent` (Quill Delta JSON)
- 模型变更：更新 `lib/models` → 处理 `DatabaseService` 迁移 → bump 数据库版本

### 平台差异
- Windows：必须 `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`
- Web：内存数据库，禁用文件 IO，禁止引用 `dart:io`
- 移动端：`sqflite` + `MMKV`；32 位 ARM 自动回退 SharedPreferences

### 大文件处理
- 使用 `LargeFileManager.encodeJsonToFileStreaming`，**禁止直接 `File.writeAsString`** (OOM 风险)
- `IntelligentMemoryManager` 动态调整批大小

## ANTI-PATTERNS (THIS PROJECT)

| 禁止 | 原因 |
|------|------|
| 硬编码 API 密钥 | 统一通过 `APIKeyManager` + flutter_secure_storage |
| 直接 `File.writeAsString` 大文件 | 使用流式处理避免 OOM |
| 忽略 `notifyListeners()` | UI 不会刷新 |
| 编辑生成文件 (`gen_l10n/`, `*.mocks.dart`) | 会被覆盖 |
| 主动运行 `flutter test` 全量测试 | 除非用户明确要求 |

## COMPLEXITY HOTSPOTS

| File | Lines | Issue |
|------|-------|-------|
| `database_service.dart` | 5820 | God class，考虑拆分 |
| `note_full_editor_page.dart` | 3083 | 过大，建议提取组件 |
| `ai_periodic_report_page.dart` | 2435 | 复杂报告逻辑 |
| `note_list_view.dart` | 1939 | 列表+筛选+交互混合 |

## DEPRECATED (待迁移)

- `AIService.generateDailyPrompt` → 使用 `streamGenerateDailyPrompt`
- `TimeUtils.formatTime` → 使用 `formatRelativeDateTime` 或 `formatQuoteTime`
- `NoteSyncService.receiveAndMerge` → 已废弃的同步逻辑

## COMMANDS

```bash
# 安装依赖
flutter pub get

# 运行应用
flutter run

# 测试 (集中入口)
flutter test test/all_tests.dart

# 代码分析
flutter analyze

# 生成国际化
flutter gen-l10n

# iOS 无签名构建
./scripts/build_ios_unsigned.sh

# Windows MSIX
pwsh ./scripts/build_msix_ci.ps1
```

## NOTES

- **紧急恢复**：数据库损坏时自动进入 `EmergencyRecoveryPage`
- **日志系统**：`UnifiedLogService.logError/Info`，可在日志页查看
- **AI 密钥调试**：`ApiKeyDebugger` 用于验证存储
- **测试 Mock**：平台特定 Mock 在 `test/test_setup.dart` 统一处理
- 现有 agent.md 和 .github/copilot-instructions.md 包含更详细的 AI 协作指南
