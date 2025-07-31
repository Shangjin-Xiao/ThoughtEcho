/// 同步协议常量定义
library;

/// 协议版本
const String protocolVersion = '2.1';

/// 默认端口
const int defaultPort = 53318;

/// 发现超时时间（毫秒）
const int defaultDiscoveryTimeout = 500;

/// 默认组播地址
const String defaultMulticastGroup = '224.0.0.168';

/// API路径常量
class ApiPaths {
  static const String info = '/api/localsend/v2/info';
  static const String prepareUpload = '/api/localsend/v2/prepare-upload';
  static const String upload = '/api/localsend/v2/upload';
  static const String cancel = '/api/localsend/v2/cancel';
}


