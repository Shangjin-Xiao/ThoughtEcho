# CONTROLLERS 模块

UI 控制器层（3 个文件），桥接 Page 与 Service，专注 UI 状态管理。

## 规范
- **轻量化**：Controller 只管 UI 状态（加载/错误/防抖），数据库写、网络请求下沉到 Service
- **状态管理**：继承 `ChangeNotifier`，通过 `ChangeNotifierProvider` 注入
- **解耦**：Controller 之间禁止直接引用，通过 Service 共享状态
- **防抖**：搜索类操作用 `Timer` 防抖（参考 `search_controller.dart` 500ms + `_searchVersion` 防竞态）
- **dispose**：Timer、StreamSubscription 必须在 `dispose()` 中取消

## 在 Page 中使用
```dart
ChangeNotifierProvider(create: (_) => XxxController(service)),  // 注入
context.read<XxxController>(),    // 读取（不监听）
context.watch<XxxController>(),   // 监听变化
```

## 测试
- `test/unit/controllers/search_controller_test.dart`
- `test/unit/controllers/onboarding_controller_test.dart`
