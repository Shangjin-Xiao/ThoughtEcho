/// 应用全局常量配置
///
/// 包含了应用中各种时间、UI、性能相关的常量配置，
/// 方便统一管理和动态调整
class AppConstants {
  AppConstants._(); // 私有构造函数，防止实例化

  // ==================== 搜索相关常量 ====================

  /// 搜索防抖延迟时间
  /// 用于防止用户输入时频繁触发搜索请求
  static const Duration searchDebounceDelay = Duration(milliseconds: 300);

  /// 搜索最小字符数
  /// 只有当搜索内容长度达到此值时才触发实际搜索
  static const int minSearchLength = 2;

  /// 搜索超时时间
  static const Duration searchTimeout = Duration(seconds: 4);

  // ==================== 分页加载常量 ====================

  /// 默认分页大小
  static const int defaultPageSize = 20;

  /// 滚动预加载阈值（65%）
  /// 当滚动到列表的65%时开始预加载下一页
  /// 提前预加载可避免用户滚动到底部时等待加载
  static const double scrollPreloadThreshold = 0.65;

  // ==================== 动画时间常量 ====================

  /// 默认动画持续时间
  static const Duration defaultAnimationDuration = Duration(milliseconds: 300);

  /// 快速动画持续时间
  static const Duration fastAnimationDuration = Duration(milliseconds: 150);

  /// 慢速动画持续时间
  static const Duration slowAnimationDuration = Duration(milliseconds: 500);

  // ==================== UI响应时间常量 ====================

  /// SnackBar显示时间 - 普通信息
  static const Duration snackBarDurationNormal = Duration(seconds: 2);

  /// SnackBar显示时间 - 重要信息
  static const Duration snackBarDurationImportant = Duration(seconds: 3);

  /// SnackBar显示时间 - 错误信息
  static const Duration snackBarDurationError = Duration(seconds: 4);

  // ==================== 网络和IO相关常量 ====================

  /// 网络请求超时时间
  static const Duration networkTimeout = Duration(seconds: 30);

  /// 文件操作超时时间
  static const Duration fileOperationTimeout = Duration(seconds: 10);

  // ==================== 响应式设计常量 ====================

  /// 平板设备最小宽度
  static const double tabletMinWidth = 600.0;

  /// 桌面设备最小宽度
  static const double desktopMinWidth = 1024.0;

  /// 平板模式下的最大内容宽度
  static const double tabletMaxContentWidth = 800.0;

  // ==================== 内存管理常量 ====================

  /// 大文件处理阈值（10MB）
  static const int largeFileThreshold = 10 * 1024 * 1024;

  /// 分块处理大小（1MB）
  static const int chunkSize = 1024 * 1024;

  // ==================== 缓存相关常量 ====================

  /// 图片缓存过期时间
  static const Duration imageCacheExpiration = Duration(days: 7);

  /// 数据缓存过期时间
  static const Duration dataCacheExpiration = Duration(hours: 24);
}
