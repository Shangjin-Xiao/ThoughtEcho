# TEST 模块

## 概览
测试套件（60+ 文件），覆盖单元测试、Widget 测试、集成测试和性能测试。

## 目录结构

```
test/
├── all_tests.dart              # 聚合入口，所有测试从这里运行
├── test_setup.dart             # 平台 Mock 统一配置（必读）
├── test_setup.mocks.dart       # 生成的 Mock（禁止手动编辑）
├── test_helpers.dart           # 通用测试辅助函数
├── test_config.dart            # 测试配置常量
│
├── unit/                       # 单元测试
│   ├── models/                 # quote_model_test.dart / note_category_test.dart
│   ├── services/               # database_service_test / settings_service_test
│   │                           # weather_service_test / clipboard_service_test
│   │                           # ai_analysis_database_service_test / ...
│   ├── utils/                  # time_utils_test / motion_photo_utils_test
│   └── widgets/                # motion_photo_preview_page_test
│
├── widget/                     # Widget 测试
│   ├── pages/                  # home_page_test.dart
│   └── note_sync_page_test.dart
│
├── integration/                # 集成测试
│   └── app_flow_test.dart
│
├── performance/                # 性能基准测试
│   ├── add_note_dialog_performance_test.dart
│   ├── ai_analysis_import_benchmark_test.dart
│   ├── tag_migration_benchmark_test.dart
│   └── ui_performance_benchmark.dart
│
├── bug_fixes/                  # Bug 修复验证
└── debug/                      # 调试用临时测试
```

## 运行测试

```bash
# 运行所有测试（集中入口）
flutter test test/all_tests.dart

# 运行单个测试文件
flutter test test/unit/models/quote_model_test.dart

# 按名称匹配运行特定用例
flutter test test/unit/models/quote_model_test.dart --name "Quote.copyWith 测试"

# 运行某个目录下所有测试
flutter test test/unit/services/

# 带超时限制（防止 CI 挂起）
flutter test test/all_tests.dart --timeout 240s

# 生成覆盖率
flutter test --coverage test/all_tests.dart
```

> **注意**：CI 中全量测试因挂起问题已被暂时禁用（见 `.github/workflows/test.yml`）。
> 本地运行测试前请确认具体测试文件不依赖真实数据库或网络。

## Mock 配置

所有平台相关的 Mock 在 `test_setup.dart` 中统一注册：
```dart
// test_setup.dart 提供的 Mock 包括：
// - MethodChannelMock for sqflite
// - MethodChannelMock for path_provider
// - MethodChannelMock for MMKV
// - SharedPreferences.setMockInitialValues

// 测试文件中调用
import '../test_setup.dart';

void main() {
  setUp(() async {
    await setupTestEnvironment(); // 初始化所有 Mock
  });
  ...
}
```

## 生成/更新 Mock

```bash
# 修改被 Mock 的接口后执行
dart run build_runner build --delete-conflicting-outputs
```

禁止手动编辑 `*.mocks.dart` 文件，它们由 build_runner 自动生成。

## 编写规范

### 测试文件命名
- 文件名格式：`<被测文件名>_test.dart`
- 放置位置与 `lib/` 目录结构镜像（如 `lib/models/quote_model.dart` → `test/unit/models/quote_model_test.dart`）

### 测试结构
```dart
void main() {
  group('ClassName', () {
    late XxxService sut; // System Under Test
    late MockYyyService mockYyy;

    setUp(() async {
      await setupTestEnvironment();
      mockYyy = MockYyyService();
      sut = XxxService(mockYyy);
    });

    tearDown(() async {
      await sut.dispose();
    });

    group('methodName', () {
      test('描述正常情况', () async {
        // Arrange
        when(mockYyy.getData()).thenReturn([]);
        // Act
        final result = await sut.methodName();
        // Assert
        expect(result, isNotNull);
      });

      test('描述异常情况', () async {
        when(mockYyy.getData()).thenThrow(Exception('error'));
        expect(() => sut.methodName(), throwsException);
      });
    });
  });
}
```

### Widget 测试
```dart
testWidgets('描述 Widget 行为', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...],
      child: MaterialApp(home: XxxWidget()),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('预期文本'), findsOneWidget);
});
```

## 注意事项
- 集成测试和数据库测试在 CI 中可能导致挂起，本地运行时注意超时设置
- 性能测试文件仅在需要基准对比时运行，不纳入日常 CI
- `bug_fixes/` 和 `debug/` 中的文件需要在 `all_tests.dart` 中注册才会被 CI 执行
