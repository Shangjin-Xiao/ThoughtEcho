// ASR 服务入口（按平台条件导出）。
//
// - Web：导出占位实现，避免引入 dart:io / record / sherpa_onnx
// - 非 Web（dart.library.io）：导出真实实现
//
// 同时导出共享类型定义（`asr_types.dart`）。
export 'asr_types.dart';
export 'asr_service_web.dart' if (dart.library.io) 'asr_service_io.dart';
