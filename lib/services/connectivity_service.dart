import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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

  final Connectivity _connectivity = Connectivity();
  bool _isConnected = true;
  Timer? _connectivityTimer;
  Future<void>? _inFlightCheck;
  bool _isDisposed = false;

  static const Duration _defaultProbeTimeout = Duration(seconds: 3);

  /// 多域名探测列表，任一成功即视为有网
  static const List<String> _probeHosts = [
    'dns.google', // Google Public DNS
    'one.one.one.one', // Cloudflare DNS
    'api.open-meteo.com', // 天气 API
  ];

  /// 用于单元测试中精确控制网络连通状态
  @visibleForTesting
  static bool? isConnectedOverrideForTesting;

  /// 用于单元测试中注入自定义 DNS 查询函数，避免依赖真实外网
  @visibleForTesting
  static Future<List<InternetAddress>> Function(String host)?
      dnsLookupForTesting;

  /// 用于单元测试中覆盖单轮 DNS 探测超时时间
  @visibleForTesting
  static Duration? probeTimeoutOverrideForTesting;

  /// 用于单元测试中覆盖当前是否为 Windows 平台
  @visibleForTesting
  static bool? isWindowsOverrideForTesting;

  /// 用于单元测试中注入本地网卡地址列表（验证 Windows NCSI 返回 none 时的降级逻辑）
  @visibleForTesting
  static Future<List<InternetAddress>> Function()?
      localInterfaceAddressesForTesting;

  bool get isConnected => isConnectedOverrideForTesting ?? _isConnected;

  /// 供测试检查是否有活动监听器
  @visibleForTesting
  bool get hasListenersForTesting => hasListeners;

  /// 初始化连接检查
  Future<void> init() async {
    await _checkConnectivity();
    _startPeriodicCheck();
  }

  /// 启动定期检查，根据状态自适应间隔
  /// 在线时 60 秒检查一次（省电），离线时 15 秒检查一次（快速恢复）
  void _startPeriodicCheck() {
    _connectivityTimer?.cancel();
    if (_isDisposed) {
      _connectivityTimer = null;
      return;
    }
    final interval = _isConnected
        ? const Duration(seconds: 60)
        : const Duration(seconds: 15);
    _connectivityTimer = Timer.periodic(interval, (_) => _checkConnectivity());
  }

  /// 检查网络连接状态（支持测试覆盖同步应用与在飞探测复用）
  Future<void> _checkConnectivity() {
    if (isConnectedOverrideForTesting != null) {
      _applyConnectivityResult(isConnectedOverrideForTesting!);
      return Future<void>.value();
    }

    final existingCheck = _inFlightCheck;
    if (existingCheck != null) {
      return existingCheck;
    }

    late final Future<void> checkFuture;
    checkFuture = _performConnectivityCheck().whenComplete(() {
      if (identical(_inFlightCheck, checkFuture)) {
        _inFlightCheck = null;
      }
    });
    _inFlightCheck = checkFuture;
    return checkFuture;
  }

  Future<void> _performConnectivityCheck() async {
    bool nextConnected;

    try {
      if (kIsWeb) {
        // Web 平台：尝试对轻量 URL 发 HEAD 请求检测网络
        nextConnected = await _checkConnectivityWeb();
      } else {
        // 原生平台：本地连接状态短路 + 多域名并发 DNS 竞速，任一成功即判为在线
        nextConnected = await _checkConnectivityNative();
      }
    } catch (e) {
      nextConnected = false;
      logDebug('网络连接检查异常: $e');
    }

    if (isConnectedOverrideForTesting != null) {
      nextConnected = isConnectedOverrideForTesting!;
    }

    _applyConnectivityResult(nextConnected);
  }

  void _applyConnectivityResult(bool connected) {
    final wasConnected = _isConnected;
    _isConnected = connected;

    // 如果连接状态发生变化，通知监听器并调整轮询间隔
    if (wasConnected != _isConnected) {
      logDebug(
        '网络连接状态变化: ${wasConnected ? '已连接' : '未连接'} -> ${_isConnected ? '已连接' : '未连接'}',
      );
      if (!_isDisposed) {
        notifyListeners();
        // 状态变化后重新调整轮询间隔
        _startPeriodicCheck();
      }
    }
  }

  /// 原生平台：本地无连接快速短路 + 多域名并发 DNS 竞速探测
  Future<bool> _checkConnectivityNative() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.isNotEmpty &&
          results.every((result) => result == ConnectivityResult.none)) {
        final isWindows = isWindowsOverrideForTesting ?? Platform.isWindows;
        if (!isWindows) {
          return false;
        }
        // Windows 端 connectivity_plus 依赖系统 NCSI (get_IsConnectedToInternet)，
        // 当微软探测受阻但网卡实际已连接时会返回 none；仅在无非回环/非链路本地活动网卡时才直接短路离线。
        final Iterable<InternetAddress> addresses =
            localInterfaceAddressesForTesting != null
                ? await localInterfaceAddressesForTesting!()
                : (await NetworkInterface.list())
                    .expand<InternetAddress>((iface) => iface.addresses);
        final hasActiveInterface = addresses.any(
          (addr) => !addr.isLoopback && !addr.isLinkLocal,
        );
        if (!hasActiveInterface) {
          return false;
        }
      }
    } catch (_) {
      // 平台通道不可用（如未挂载 Mock 的单测环境或桌面插件异常）时安全降级至 DNS 探测
    }

    var remaining = _probeHosts.length;
    if (remaining == 0) {
      return false;
    }

    final lookup = dnsLookupForTesting ?? InternetAddress.lookup;
    final timeout = probeTimeoutOverrideForTesting ?? _defaultProbeTimeout;
    final completer = Completer<bool>();

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    for (final host in _probeHosts) {
      Future<List<InternetAddress>>.sync(() => lookup(host)).then(
        (result) {
          if (completer.isCompleted) return;
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            timer.cancel();
            completer.complete(true);
            return;
          }
          remaining -= 1;
          if (remaining == 0) {
            timer.cancel();
            completer.complete(false);
          }
        },
        onError: (Object _, StackTrace __) {
          if (completer.isCompleted) return;
          remaining -= 1;
          if (remaining == 0) {
            timer.cancel();
            completer.complete(false);
          }
        },
      );
    }

    return completer.future;
  }

  /// Web 平台：通过 NetworkService 探测
  /// Web 上 dart:io 不可用，使用已封装的 NetworkService 进行 HTTP 请求探测。
  /// 失败则假定在线（让上层按需处理错误）。
  Future<bool> _checkConnectivityWeb() async {
    try {
      final response = await NetworkService.instance.get(
          'https://api.open-meteo.com/v1/forecast?latitude=0&longitude=0&current=temperature_2m',
          timeoutSeconds: 5);
      return response.statusCode < 500;
    } catch (_) {
      // Web 探测失败，保守假定在线
      return true;
    }
  }

  /// 立即检查连接状态
  Future<bool> checkConnectionNow() async {
    await _checkConnectivity();
    return isConnected;
  }

  /// 检查当前是否为移动数据流量连接
  Future<bool> isCellularConnection() async {
    try {
      final List<ConnectivityResult> results =
          await _connectivity.checkConnectivity();
      return results.contains(ConnectivityResult.mobile);
    } catch (e) {
      logDebug('检查移动数据网络失败: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _connectivityTimer?.cancel();
    _connectivityTimer = null;
    _inFlightCheck = null;
    super.dispose();
  }
}
