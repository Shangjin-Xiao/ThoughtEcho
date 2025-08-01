/// 同步协议常量定义
/// 基于LocalSend协议 v2.1版本
library;

/// 协议版本号
const String protocolVersion = '2.1';

/// 默认端口号
const int defaultPort = 53318;

/// 默认发现超时时间（毫秒）
const int defaultDiscoveryTimeout = 500;

/// 默认多播组地址
const String defaultMulticastGroup = '224.0.0.168';

/// API路径常量
class ApiPaths {
  /// 设备信息接口
  static const String info = '/api/localsend/v2/info';
  
  /// 准备上传接口
  static const String prepareUpload = '/api/localsend/v2/prepare-upload';
  
  /// 上传文件接口
  static const String upload = '/api/localsend/v2/upload';
  
  /// 取消传输接口
  static const String cancel = '/api/localsend/v2/cancel';
}

/// 同步状态枚举
enum SyncStatus {
  /// 空闲状态
  idle,
  
  /// 打包中
  packaging,
  
  /// 发送中
  sending,
  
  /// 接收中
  receiving,
  
  /// 合并中
  merging,
  
  /// 完成
  completed,
  
  /// 失败
  failed,
}