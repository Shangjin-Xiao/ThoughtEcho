import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';

/// 网络连接状态检测服务
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  bool _isConnected = true;
  Timer? _connectivityTimer;

  bool get isConnected => _isConnected;

  /// 初始化连接检查
  Future<void> init() async {
    await _checkConnectivity();
    _startPeriodicCheck();
  }

  /// 启动定期检查（每30秒检查一次）
  void _startPeriodicCheck() {
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkConnectivity(),
    );
  }

  /// 检查网络连接状态
  Future<void> _checkConnectivity() async {
    bool wasConnected = _isConnected;

    try {
      if (kIsWeb) {
        // Web平台假设有网络连接
        _isConnected = true;
      } else {
        // 通过ping一个可靠的服务器来检查网络连接
        final result = await InternetAddress.lookup(
          '8.8.8.8',
        ).timeout(const Duration(seconds: 5));
        _isConnected = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      }
    } catch (e) {
      _isConnected = false;
      logDebug('网络连接检查失败: $e');
    }

    // 如果连接状态发生变化，通知监听器
    if (wasConnected != _isConnected) {
      logDebug(
        '网络连接状态变化: ${wasConnected ? '已连接' : '未连接'} -> ${_isConnected ? '已连接' : '未连接'}',
      );
      notifyListeners();
    }
  }

  /// 立即检查连接状态
  Future<bool> checkConnectionNow() async {
    await _checkConnectivity();
    return _isConnected;
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }
}
