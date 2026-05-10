# LOCALSEND 子模块

LocalSend 协议实现，局域网设备发现和文件传输。

## 关键约定
- 自定义 `Notifier<T>` Provider 模式（`simple_provider.dart`），不依赖 Riverpod
- 设备身份单例：`DeviceIdentityManager.I`
- 文件操作用 `Isolate`（`isolate_actions.dart`），禁止主线程大文件操作
- 所有 HTTP 操作支持 `CancellationToken` 取消
- 传输进度通过 `Stream<double>` 发射给 UI
- 端口等常量统一在 `constants.dart`，禁止硬编码
