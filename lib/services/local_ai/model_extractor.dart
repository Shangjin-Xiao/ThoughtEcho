/// 模型解压工具
///
/// 负责根据平台提供对应实现（IO / Web Stub）
library;

export 'model_extractor_stub.dart'
    if (dart.library.io) 'model_extractor_io.dart';
