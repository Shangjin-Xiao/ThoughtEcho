# ThoughtEcho 测试文档

## 测试结构

本项目采用分层测试策略，确保代码质量和应用稳定性：

```
test/
├── README.md                 # 测试文档（本文件）
├── unit/                     # 单元测试
│   ├── services/            # 服务层单元测试
│   ├── models/              # 数据模型测试
│   └── utils/               # 工具类测试
├── widget/                   # Widget测试
│   ├── pages/               # 页面组件测试
│   └── widgets/             # 自定义组件测试
├── integration/              # 集成测试
│   ├── app_test.dart        # 应用启动测试
│   ├── core_workflow_test.dart # 核心功能流程测试
│   └── ai_integration_test.dart # AI功能集成测试
└── mocks/                    # Mock文件
    ├── mock_database_service.dart
    ├── mock_ai_service.dart
    ├── mock_location_service.dart
    └── mock_weather_service.dart
```

## 测试类型

### 1. 单元测试 (Unit Tests)
测试单个函数、方法或类的功能，与外部依赖隔离。

**覆盖范围：**
- 数据库服务 (DatabaseService)
- AI服务 (AIService)
- 位置服务 (LocationService)
- 天气服务 (WeatherService)
- 设置服务 (SettingsService)
- 数据模型验证
- 工具类函数

### 2. Widget测试 (Widget Tests)
测试UI组件的渲染和交互行为。

**覆盖范围：**
- 主页面 (HomePage)
- 编辑页面 (EditPage)
- 设置页面 (SettingsPage)
- 洞察页面 (InsightsPage)
- 自定义组件

### 3. 集成测试 (Integration Tests)
测试完整的应用功能流程，包括多个组件的协同工作。

**覆盖范围：**
- 应用启动和初始化
- 笔记的创建、编辑、删除流程
- AI分析功能
- 数据导入导出
- 设置更改和持久化

## 运行测试

### 前置条件
```bash
# 安装依赖
flutter pub get

# 生成Mock文件
flutter packages pub run build_runner build
```

### 运行所有测试
```bash
flutter test
```

### 运行特定类型测试
```bash
# 单元测试
flutter test test/unit/

# Widget测试
flutter test test/widget/

# 集成测试
flutter test integration_test/
```

### 运行特定测试文件
```bash
flutter test test/unit/services/database_service_test.dart
```

### 生成测试覆盖率报告
```bash
# 运行测试并生成覆盖率
flutter test --coverage

# 查看HTML格式报告
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## Mock使用指南

### 创建Mock服务
```dart
import 'package:mockito/mockito.dart';
import 'package:thoughtecho/services/database_service.dart';

// 生成Mock类
@GenerateMocks([DatabaseService])
void main() {
  // 在测试中使用
}
```

### Mock数据库操作
```dart
void main() {
  late MockDatabaseService mockDb;

  setUp(() {
    mockDb = MockDatabaseService();
  });

  test('should return user quotes', () async {
    // Arrange
    final expectedQuotes = [Quote(id: '1', content: 'Test quote')];
    when(mockDb.getUserQuotes()).thenAnswer((_) async => expectedQuotes);

    // Act
    final result = await mockDb.getUserQuotes();

    // Assert
    expect(result, equals(expectedQuotes));
    verify(mockDb.getUserQuotes()).called(1);
  });
}
```

## 测试最佳实践

### 1. 测试命名
- 使用描述性的测试名称：`should_return_error_when_network_unavailable`
- 遵循AAA模式：Arrange（准备）、Act（执行）、Assert（断言）

### 2. Mock策略
- 只Mock外部依赖和复杂的服务
- 保持Mock简单和可维护
- 验证重要的交互调用

### 3. 测试数据
- 使用工厂模式创建测试数据
- 避免使用生产数据
- 测试边界条件和异常情况

### 4. 异步测试
- 正确处理Future和Stream
- 使用`pumpAndSettle()`等待异步操作完成
- 测试错误处理和超时情况

## CI/CD集成

测试将在以下情况自动运行：
- Pull Request创建或更新
- 代码推送到主分支
- 发布版本构建

GitHub Actions工作流配置包含：
- 多平台测试（Linux, Windows, macOS）
- 代码覆盖率报告
- 测试结果可视化
- 性能回归检测

## 故障排除

### 常见问题

1. **Mock生成失败**
   ```bash
   flutter packages pub run build_runner clean
   flutter packages pub run build_runner build --delete-conflicting-outputs
   ```

2. **测试超时**
   - 增加测试超时时间
   - 检查异步操作是否正确完成
   - 验证Mock是否正确配置

3. **Widget测试失败**
   - 确保TestWidgetsFlutterBinding.ensureInitialized()被调用
   - 检查Provider是否正确提供
   - 验证测试环境中的依赖注入

4. **集成测试失败**
   - 确保应用在测试环境中能正常启动
   - 检查测试设备或模拟器状态
   - 验证权限和存储配置

## 贡献指南

添加新功能时，请确保：
1. 为新的服务类添加单元测试
2. 为新的UI组件添加Widget测试
3. 更新相关的集成测试
4. 保持测试覆盖率在80%以上
5. 更新本文档以反映测试变更

更多信息请参考项目的[开发指南](../README.md)。