# CONTROLLERS MODULE

## OVERVIEW
UI 控制器层，主要负责处理特定页面的业务逻辑，桥接 UI 与 Service。

## STRUCTURE
- `onboarding_controller.dart`: 引导流程控制逻辑。
- `search_controller.dart`: 全局搜索逻辑，处理筛选、排序与结果缓存。
- `weather_search_controller.dart`: 天气与城市搜索逻辑。

## CONVENTIONS
- **轻量化**: 复杂的业务逻辑（如数据库写、网络请求）应下沉到 Service 层。
- **状态管理**: Controller 通常继承 `ChangeNotifier`，并在 Page 中通过 Provider 绑定。
- **解耦**: 尽量避免 Controller 之间直接引用，通过 Service 层共享状态。
