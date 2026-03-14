# PROJECT KNOWLEDGE BASE

**项目**: ThoughtEcho (心迹) — Flutter 3.x 跨平台笔记应用
**技术栈**: Flutter + Dart + SQLite + Provider + FlutterQuill + AI 多 Provider

---

## 目录结构

```
ThoughtEcho/
├── lib/
│   ├── main.dart           # 入口 + Provider 注入 + 紧急恢复 (1354 行)
│   ├── controllers/        # UI 控制器 → 见子目录 AGENTS.md
│   ├── models/             # 数据模型 → 见子目录 AGENTS.md
│   ├── pages/              # 页面组件 → 见子目录 AGENTS.md
│   ├── services/           # 业务服务 → 见子目录 AGENTS.md
│   ├── utils/              # 工具类 → 见子目录 AGENTS.md
│   ├── widgets/            # UI 组件 → 见子目录 AGENTS.md
│   ├── theme/              # Material 3 主题
│   ├── constants/          # 常量 (卡片模板, AI prompts)
│   ├── config/             # Lottie/引导页配置
│   ├── extensions/         # Dart 扩展方法
│   ├── l10n/               # ARB 源文件 (修改此处)
│   └── gen_l10n/           # 国际化生成文件 (禁止手动编辑)
├── test/                   # 单元/Widget/集成/性能测试
├── .github/workflows/      # CI: test.yml / flutter-release-build.yml / build-windows.yml / ios-build.yml
├── scripts/                # iOS 无签名构建 / Windows MSIX 脚本
├── android/ ios/ web/ windows/  # 平台原生代码
└── assets/                 # Lottie 动画, 图标, 用户文档
```

---

## 常用命令

```bash
# 安装依赖
flutter pub get

# 运行应用
flutter run

# 代码格式化 (CI 强制检查)
dart format --set-exit-if-changed .

# 静态分析
flutter analyze --no-fatal-infos

# 运行所有测试 (集中入口)
flutter test test/all_tests.dart

# 运行单个测试文件
flutter test test/unit/models/quote_model_test.dart

# 运行单个测试用例 (按名称匹配)
flutter test test/unit/models/quote_model_test.dart --name "测试用例名称"

# 生成国际化代码 (修改 ARB 后必须执行)
flutter gen-l10n

# 生成 Mock (修改接口后)
dart run build_runner build --delete-conflicting-outputs

# iOS 无签名构建
./scripts/build_ios_unsigned.sh

# Windows MSIX
pwsh ./scripts/build_msix_ci.ps1
```

---

## 代码风格规范

### 导入顺序 (严格遵循，dart format 自动排序)
```dart
// 1. dart:* 标准库
import 'dart:async';
import 'dart:io';

// 2. package:flutter/* 框架
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// 3. package:第三方包 (按字母序)
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

// 4. package:thoughtecho/* 项目内部 (按字母序)
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/services/database_service.dart';
```

### 命名规范
| 类型 | 规范 | 示例 |
|------|------|------|
| 类/枚举 | UpperCamelCase | `DatabaseService`, `NoteCategory` |
| 方法/变量 | lowerCamelCase | `getQuotes()`, `isLoading` |
| 常量 | lowerCamelCase | `defaultCategoryId` |
| 私有成员 | `_` 前缀 | `_database`, `_isInitialized` |
| 文件名 | snake_case | `database_service.dart` |
| 测试文件 | `*_test.dart` | `quote_model_test.dart` |

### 类型与 Null Safety
- 优先使用具体类型，避免 `dynamic`
- 可空类型明确标注 `?`，不可空不省略断言
- 使用 `late` 声明延迟初始化的非空字段
- 模型类提供 `copyWith()` 做不可变更新

### 格式化
- 缩进：2 空格（Dart 默认）
- 行宽：80 字符（`dart format` 默认）
- 尾随逗号：Widget 参数列表必须加，便于 `dart format` 格式化
- 禁止提交未格式化代码（CI 会检查 `dart format --set-exit-if-changed .`）

### 注释规范
- 代码注释可用中文
- 公共 API 用 `///` 文档注释
- 临时调试注释在提交前删除

---

## 架构约定

### 状态管理
- 所有服务继承 `ChangeNotifier`，在 `main.dart` 通过 `ChangeNotifierProvider` 注入
- 写操作后**必须**调用 `notifyListeners()`
- 访问服务（不监听）：`Provider.of<XxxService>(context, listen: false)`
- 访问服务（监听变化）：`context.watch<XxxService>()` 或 `Consumer<XxxService>`

### 服务层模式
```dart
class XxxService extends ChangeNotifier {
  Future<void> doSomething() async {
    try {
      // 业务逻辑
      notifyListeners(); // 写操作后必须调用
    } catch (e, stack) {
      logError('XxxService.doSomething', e, stack);
      rethrow;
    }
  }
}
```

### 模型模式
- 必须提供 `toMap()` / `fromMap()` 用于数据库持久化
- 必须提供 `copyWith()` 做不可变状态更新
- 核心模型 `Quote` 双存储：`content`（纯文本）+ `deltaContent`（Quill Delta JSON）

### 国际化 (严格)
- **禁止 UI 层硬编码任何用户可见文本（含中文）**
- 新增文案流程：`lib/l10n/app_zh.arb` → `lib/l10n/app_en.arb` → `flutter gen-l10n`
- 带占位符使用 ARB `{placeholder}` 语法并声明 `placeholders` 元数据
- 注释和日志可用中文；SnackBar/Dialog/Tooltip/按钮文案必须国际化

### 错误处理
- 异常先记录 `UnifiedLogService.logError()`，再 rethrow 或降级处理
- 网络错误走 `dio_network_utils.dart` 的 retry 逻辑
- 页面级操作用 try-catch 包裹，不让异常裸露给用户

---

## 平台差异

| 平台 | 特殊处理 |
|------|----------|
| Windows | `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`；数据目录在 Documents/ThoughtEcho |
| Web | 禁用文件 IO，禁止 `import 'dart:io'`；内存数据库；键值走 SharedPreferences |
| iOS | 需无签名构建脚本；键值走 MMKV |
| Android | 移动端用 sqflite + MMKV；32 位 ARM 自动回退 SharedPreferences |

---

## 禁止事项 (Anti-Patterns)

| 禁止 | 原因 | 替代方案 |
|------|------|----------|
| 硬编码 API 密钥 | 安全风险 | `APIKeyManager` + flutter_secure_storage |
| `File.writeAsString` 写大文件 | OOM | `LargeFileManager.encodeJsonToFileStreaming` |
| 忽略 `notifyListeners()` | UI 不刷新 | 每次写操作后调用 |
| 编辑 `gen_l10n/` 或 `*.mocks.dart` | 会被覆盖 | 修改源文件后重新生成 |
| 服务层 `import 'package:flutter/widgets.dart'` | 关注点分离 | 用 `flutter/scheduler.dart` |
| 单文件超过 500 行（新增/重构时） | 维护困难 | 拆分为独立组件/Mixin/part 文件 |
| 重复逻辑超过 3 处 | 维护困难 | 提取共享方法或工具类 |
| 未读代码直接优化 | 易误判 | 先读实现，确认问题存在 |
| 移除 SQL 查询字段前未检查 UI 依赖 | 运行时崩溃 | 检查所有使用处后再删除 |
| 调试按钮暴露在正式版 UI | 用户体验 | 限定在开发者模式或 kDebugMode |
| 主动运行全量 `flutter test` | CI 超时风险 | 仅在用户明确要求时运行 |

---

## 复杂度热点 (修改前必读)

| 文件 | 行数 | 说明 |
|------|------|------|
| `lib/services/database_service.dart` | 5820+ | God class，通过 part/mixin 拆分为 11 个文件 |
| `lib/pages/note_full_editor_page.dart` | 3083+ | 富文本编辑器，拆分有 `note_editor/` 子目录 |
| `lib/pages/ai_periodic_report_page.dart` | 2680+ | 报告页，拆分有 `ai_report/` 子目录 |
| `lib/services/smart_push_service.dart` | 2560+ | 拆分有 `smart_push/` 子目录 |
| `lib/widgets/note_list_view.dart` | 2100+ | 拆分有 `note_list/` 子目录 |

---

## 快速定位

| 任务 | 位置 |
|------|------|
| 数据库 CRUD | `lib/services/database_service.dart` + `lib/services/database/` |
| AI 请求 | `lib/services/ai_service.dart` → `lib/utils/ai_request_helper.dart` |
| API 密钥管理 | `lib/services/api_key_manager.dart` |
| 状态管理入口 | `lib/main.dart` Provider 树 |
| 富文本编辑器 | `lib/pages/note_full_editor_page.dart` + `lib/pages/note_editor/` |
| 设备同步 | `lib/services/note_sync_service.dart` + `lib/services/localsend/` |
| 备份恢复 | `lib/services/backup_service.dart` |
| 主题 | `lib/theme/app_theme.dart` |
| 国际化源文件 | `lib/l10n/app_zh.arb` / `app_en.arb` |
| 测试入口 | `test/all_tests.dart` |
| 测试 Mock 配置 | `test/test_setup.dart` |

---

## AI 服务配置

AI 架构链路：
```
MultiAISettings → AIProviderSettings → AINetworkManager → APIKeyManager
                                             ↓
                               _requestHelper.makeStreamRequestWithProvider
```

支持服务商：OpenAI / OpenRouter / SiliconFlow / DeepSeek / Anthropic / Ollama (本地) / LMStudio (本地)

新增 AI Provider 步骤：
1. `AIProviderSettings.getPresetProviders()` 添加预设
2. 实现 `buildHeaders()` + `adjustData()`
3. 在 `lib/pages/ai_settings_page.dart` 添加配置 UI

---

## 废弃 API (禁止使用)

- `AIService.generateDailyPrompt` → 改用 `streamGenerateDailyPrompt`
- `TimeUtils.formatTime` → 改用 `formatRelativeDateTime` 或 `formatQuoteTime`
- `NoteSyncService.receiveAndMerge` → 已废弃的同步逻辑

---

## 开发者模式

**激活**：设置 → 关于心迹 → 连续点击应用图标 3 次

开发者专属功能（仅此模式可见）：日志中心 / 本地 AI 设置 / 存储管理 / 数据库调试

---

## 文档维护

| 文档 | 位置 |
|------|------|
| 用户手册 (双语) | `docs/USER_MANUAL.md` |
| 中文用户手册 | `assets/docs/user_manual_zh.md` |
| 英文用户手册 | `assets/docs/user_manual_en.md` |
| 项目网站 | `res/index.html` |

**规范**：新增功能后必须同步更新用户手册；禁止在文档中编造未实现的功能。
