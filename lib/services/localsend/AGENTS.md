# LOCALSEND MODULE

## OVERVIEW

LocalSend 协议实现，支持局域网设备发现和文件传输。自定义 Provider 模式 + Isolate 并发。

## STRUCTURE

```
localsend/
├── constants.dart              # 协议常量
├── localsend_server.dart       # HTTP 服务器 + REST API
├── localsend_send_provider.dart # 发送逻辑
├── receive_controller.dart     # 接收控制器
├── api_route_builder.dart      # 路由构建
├── models/                     # DTO 模型
│   ├── device.dart             # 设备信息
│   ├── file_dto.dart           # 文件传输 DTO
│   ├── send_session_state.dart # 会话状态
│   └── ...
├── utils/                      # 工具函数
│   ├── simple_provider.dart    # 自定义 Provider 模式
│   ├── http_client.dart        # HTTP 客户端
│   └── network_interfaces.dart # 网络接口
└── isolate/
    └── isolate_actions.dart    # Isolate 后台任务
```

## WHERE TO LOOK

| Task | File | Notes |
|------|------|-------|
| 设备发现 | `localsend_server.dart` | mDNS + UDP 多播 |
| 发送文件 | `localsend_send_provider.dart` | 带进度回调 |
| 接收文件 | `receive_controller.dart` | 预审批机制 |
| 后台上传 | `isolate/isolate_actions.dart` | 不阻塞主线程 |

## CONVENTIONS

### 自定义 Provider 模式
```dart
// simple_provider.dart
class Notifier<T> {
  final _controller = StreamController<T>.broadcast();
  Stream<T> get stream => _controller.stream;
  void notify(T value) => _controller.add(value);
}
```
用于轻量级响应式状态，避免依赖完整 Riverpod。

### 设备身份单例
```dart
DeviceIdentityManager.I  // 全局访问设备指纹
```

### Isolate 并发
```dart
// isolate_actions.dart
IsolateHttpUploadAction  // 后台文件上传
```
文件操作使用 Isolate 避免 UI 卡顿。

### 取消令牌模式
所有 HTTP 操作支持 `CancellationToken` 取消。

### 进度流
文件传输发射 `Stream<double>` 用于 UI 进度条。

## ANTI-PATTERNS

| 禁止 | 原因 |
|------|------|
| 主线程大文件操作 | 使用 Isolate |
| 忽略取消令牌 | 用户可能中断传输 |
| 硬编码端口 | 使用 `constants.dart` |
