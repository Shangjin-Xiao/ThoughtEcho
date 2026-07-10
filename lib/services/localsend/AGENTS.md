# LocalSend 子模块

本目录实现局域网设备发现、发送、接收和协议 DTO，包含自定义轻量 Provider、HTTP 客户端与
Isolate 动作。

## 协议与状态

- 沿用 `utils/simple_provider.dart` 的 `Notifier<T>` 模式；它不是 Riverpod，不要混用 Provider
  生命周期假设。
- 设备身份由 `DeviceIdentityManager.I` 管理；端口、路由和协议常量集中在 `constants.dart` 与
  `api_route_builder.dart`，不要在调用点硬编码。
- 协议 DTO 的字段名、可空性和枚举值属于兼容边界；修改时同时检查发送端、接收端、旧版本
  兼容和测试。
- 发送/接收状态必须有清晰终态（完成、失败、取消），取消信号贯穿 HTTP 和 Isolate 操作，避免
  取消后继续写文件或发进度。

## 文件与安全

- 大文件处理沿用 `isolate/isolate_actions.dart` 和流式 I/O，避免在 UI isolate 整文件读写。
- 接收文件名、目标路径和声明大小必须校验，防止路径穿越、覆盖和资源耗尽；临时文件只在校验
  完成后原子转正，失败/取消时清理。
- 传输进度保持单调且限制更新频率，避免高频通知拖慢 UI。
- 日志可记录设备别名、阶段和大小等诊断信息，但不能记录文件内容、密钥或不必要的本机路径。
- Web 不受支持；现有 `kIsWeb` 防护不是新增 Web 协议实现的依据。

修改协议或传输状态机时，优先运行 `test/unit/services/localsend/`、
`test/unit/services/localsend_security_test.dart` 及直接相关同步测试。
