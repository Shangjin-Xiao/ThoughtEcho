# LOCALSEND MODULE

## 概览
LocalSend 协议实现，支持局域网设备发现和文件传输。自定义 Provider 模式 + Isolate 并发。

## 目录结构

```
localsend/
├── constants.dart                # 协议常量（端口、超时等）
├── localsend_server.dart         # HTTP 服务器 + REST API（13k+ 行）
├── localsend_send_provider.dart  # 发送逻辑（16k+ 行）
├── receive_controller.dart       # 接收控制器（13k+ 行）
├── api_route_builder.dart        # 路由构建
├── models/                       # DTO 模型
│   ├── device.dart                   # 设备信息（6k+ 行）
│   ├── file_dto.dart                 # 文件传输 DTO
│   ├── file_status.dart              # 文件状态枚举
│   ├── file_type.dart                # 文件类型枚举
│   ├── info_register_dto.dart        # 注册信息 DTO
│   ├── multicast_dto.dart            # 多播 DTO
│   ├── prepare_upload_request_dto.dart # 上传请求 DTO
│   ├── prepare_upload_response_dto.dart  # 上传响应 DTO
│   ├── send_session_state.dart       # 发送会话状态
│   ├── sending_file.dart             # 发送中文件
│   └── session_status.dart           # 会话状态枚举
├── utils/                        # 工具函数
│   ├── simple_provider.dart          # 自定义 Provider 模式（Notifier<T>）
│   ├── http_client.dart              # HTTP 客户端
│   ├── network_interfaces.dart       # 网络接口检测
│   ├── file_size_helper.dart         # 文件大小格式化
│   ├── ip_helper.dart                # IP 地址工具
│   ├── user_agent_analyzer.dart      # UA 解析
│   └── sleep.dart                    # 异步延迟工具
└── isolate/
    └── isolate_actions.dart          # Isolate 后台任务
```

## 快速定位

| 任务 | 文件 | 说明 |
|------|------|------|
| 设备发现 | `localsend_server.dart` | mDNS + UDP 多播 |
| 发送文件 | `localsend_send_provider.dart` | 带进度回调 |
| 接收文件 | `receive_controller.dart` | 预审批机制 |
| 后台上传 | `isolate/isolate_actions.dart` | 不阻塞主线程 |
| 协议常量 | `constants.dart` | 端口、超时等配置 |
| 设备模型 | `models/device.dart` | 设备指纹与信息 |
| 传输状态 | `models/send_session_state.dart` | 会话状态管理 |

## 约定

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

## 禁止事项

| 禁止 | 原因 |
|------|------|
| 主线程大文件操作 | 使用 Isolate |
| 忽略取消令牌 | 用户可能中断传输 |
| 硬编码端口 | 使用 `constants.dart` |
