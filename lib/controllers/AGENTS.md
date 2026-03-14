# CONTROLLERS 模块

## 概览
UI 控制器层，桥接页面 UI 与 Service 层业务逻辑。控制器专注于 UI 状态管理（防抖、加载态、错误态），复杂业务下沉到 Service。

## 文件清单

| 文件 | 职责 |
|------|------|
| `onboarding_controller.dart` | 引导流程步骤控制、完成状态 |
| `search_controller.dart` | 全局搜索：防抖 500ms、版本号防竞态、5s 超时保护 |
| `weather_search_controller.dart` | 天气城市搜索与缓存 |

## 架构约定

### 标准控制器模板
```dart
class XxxController extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // 防抖 Timer（如有搜索类功能）
  Timer? _debounceTimer;

  Future<void> doAction() async {
    _isLoading = true;
    notifyListeners();
    try {
      // 调用 Service 层，不在 Controller 直接操作 DB/网络
      await _service.doSomething();
    } catch (e, stack) {
      logError('XxxController.doAction', e, stack);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
```

### 规范
- **轻量化**：Controller 只处理 UI 状态，数据库写、网络请求必须下沉到 Service
- **状态管理**：继承 `ChangeNotifier`，通过 `ChangeNotifierProvider` 在 Page 中注入
- **解耦**：Controller 之间禁止直接引用，通过 Service 层共享状态
- **防抖**：搜索类操作使用 `Timer` 防抖（参考 `search_controller.dart` 的 500ms 实现）
- **竞态防护**：异步搜索用版本号（`_searchVersion`）避免旧请求结果覆盖新结果
- **dispose**：Timer、StreamSubscription 必须在 `dispose()` 中取消

## 在 Page 中使用
```dart
// 注入（在 main.dart 或 Page 的 create 中）
ChangeNotifierProvider(create: (_) => XxxController(service)),

// 读取（不监听）
final ctrl = context.read<XxxController>();

// 监听变化
final ctrl = context.watch<XxxController>();
// 或
Consumer<XxxController>(builder: (ctx, ctrl, _) => ...)
```
