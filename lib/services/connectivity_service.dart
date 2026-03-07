import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import '../services/network_service.dart';

/// 网络连接状态检测服务
///
/// 通过多域名 DNS 探测判断联网状态，避免单一域名不可达导致误判。
/// Web 平台通过 HTTP 探测替代 DNS lookup。
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  bool _isConnected = true;
  Timer? _connectivityTimer;

  /// 多域名探测列表，任一成功即视为有网
  static const List<String> _probeHosts = [
    'dns.google', // Google Public DNS
    'one.one.one.one', // Cloudflare DNS
    'api.open-meteo.com', // 天气 API
  ];

  bool get isConnected => _isConnected;

  /// 初始化连接检查
  Future<void> init() async {
    await _checkConnectivity();
    _startPeriodicCheck();
  }

  /// 启动定期检查，根据状态自适应间隔
  /// 在线时 60 秒检查一次（省电），离线时 15 秒检查一次（快速恢复）
  void _startPeriodicCheck() {
    _connectivityTimer?.cancel();
    final interval = _isConnected
        ? const Duration(seconds: 60)
        : const Duration(seconds: 15);
    _connectivityTimer = Timer.periodic(interval, (_) => _checkConnectivity());
  }

  /// 检查网络连接状态（多域名 fallback）
  Future<void> _checkConnectivity() async {
    bool wasConnected = _isConnected;

    try {
      if (kIsWeb) {
        // Web 平台：尝试对轻量 URL 发 HEAD 请求检测网络
        _isConnected = await _checkConnectivityWeb();
      } else {
        // 原生平台：多域名 DNS 探测，任一成功即判为在线
        _isConnected = await _checkConnectivityNative();
      }
    } catch (e) {
      _isConnected = false;
      logDebug('网络连接检查异常: $e');
    }

    // 如果连接状态发生变化，通知监听器并调整轮询间隔
    if (wasConnected != _isConnected) {
      logDebug(
        '网络连接状态变化: ${wasConnected ? '已连接' : '未连接'} -> ${_isConnected ? '已连接' : '未连接'}',
      );
      notifyListeners();
      // 状态变化后重新调整轮询间隔
      _startPeriodicCheck();
    }
  }

  /// 原生平台：多域名 DNS 探测
  Future<bool> _checkConnectivityNative() async {
    for (final host in _probeHosts) {
      try {
        final result = await InternetAddress.lookup(
          host,
        ).timeout(const Duration(seconds: 3));
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          return true;
        }
      } catch (_) {
        // 当前域名失败，继续尝试下一个
      }
    }
    return false;
  }

  /// Web 平台：通过 NetworkService 探测
  /// Web 上 dart:io 不可用，使用已封装的 NetworkService 进行 HTTP 请求探测。
  /// 失败则假定在线（让上层按需处理错误）。
  Future<bool> _checkConnectivityWeb() async {
    try {
      final response = await NetworkService.instance.get(
        'https://api.open-meteo.com/v1/forecast?latitude=0&longitude=0&current=temperature_2m',
        timeoutSeconds: 5,
      );
      return response.statusCode < 500;
    } catch (_) {
      // Web 探测失败，保守假定在线
      return true;
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
