/// 统一导出 MMKVAdapter
library;
export 'mmkv_adapter_web.dart' 
    if (dart.library.io) 'mmkv_adapter_io.dart';
// 注意：我们在 mmkv_adapter_io.dart 中会根据运行时检测的设备架构
// 决定是否使用 mmkv 或 shared_preferences
