# Controllers 模块

本目录包含页面级 UI 控制器。当前主要有新增笔记、主页编排、全屏编辑器状态、引导、搜索和天气
搜索控制器。

## 职责边界

- Controller 管理加载、错误、选择、输入、防抖等 UI 状态，并编排一个用户操作。
- 数据库写入、网络请求、文件处理和可复用业务规则放在 Service；Controller 不直接拼 SQL，
  也不复制 Service 的缓存。
- Controller 之间不直接依赖。需要共享的数据通过明确的 Service 或上层组合传递。
- 只有需要被 UI 监听的 Controller 才继承 `ChangeNotifier`；状态实际变化后再通知。
- 复杂页面按状态所有权组合多个窄模块；不要在页面 State 或 `part` extension 中为模块字段建立
  一整套透传别名。

## 异步与生命周期

- 搜索类请求沿用 `search_controller.dart` 的防抖和版本号/请求序号模式，防止旧响应覆盖新结果。
- `Timer`、`StreamSubscription`、controller 和其他可释放资源必须在 `dispose()` 中取消或释放。
- 异常记录操作上下文，并暴露可供页面转成国际化提示的状态；不要把堆栈或敏感信息直接交给 UI。
- 对可能在 `dispose()` 后完成的异步任务，通知前检查控制器是否仍有效。

## Provider 使用

```dart
ChangeNotifierProvider(create: (_) => XxxController(service))
context.read<XxxController>()
context.watch<XxxController>()
```

优先将 Controller 作用域限制在使用它的页面。测试路径镜像本目录，参考
`test/unit/controllers/`；新增状态分支时覆盖成功、失败、竞态和 dispose 场景。
