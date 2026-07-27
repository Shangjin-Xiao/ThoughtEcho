/// 早期错误缓冲区
///
/// 在日志服务尚未初始化时缓存捕获到的错误，待日志服务可用后统一取出记录。
/// 独立成文件以避免 services 层为取错误而反向 import main.dart。
library;

final List<Map<String, dynamic>> _deferredErrors = [];
const int _maxDeferredErrors = 100; // 设置最大容量防止无限增长

/// 安全添加延迟错误（带容量限制）
void addDeferredError(Map<String, dynamic> error) {
  if (_deferredErrors.length >= _maxDeferredErrors) {
    _deferredErrors.removeAt(0);
  }
  _deferredErrors.add(error);
}

/// 获取并清空缓存的早期错误（日志服务初始化完成后调用）
List<Map<String, dynamic>> getAndClearDeferredErrors() {
  final errors = List<Map<String, dynamic>>.from(_deferredErrors);
  _deferredErrors.clear();
  return errors;
}
