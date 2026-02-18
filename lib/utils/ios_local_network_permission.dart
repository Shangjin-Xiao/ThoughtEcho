import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// iOS 本地网络权限管理工具
///
/// iOS 14+ 引入了本地网络权限，只有在应用尝试**发送**网络流量时才会触发权限对话框。
/// iOS 16+ 严格执行 UDP 组播权限 - 如果用户未授权，发送 UDP 组播会失败（errno=65）。
///
/// 此工具在应用启动时主动触发权限对话框，确保用户有机会授权。
class IOSLocalNetworkPermission {
  static final IOSLocalNetworkPermission _instance =
      IOSLocalNetworkPermission._internal();
  factory IOSLocalNetworkPermission() => _instance;
  IOSLocalNetworkPermission._internal();

  static IOSLocalNetworkPermission get I => _instance;

  bool _hasTriggered = false;
  bool _permissionGranted = false;

  /// 是否已尝试触发权限
  bool get hasTriggered => _hasTriggered;

  /// 权限是否可能已授权（基于发送成功判断）
  bool get permissionLikelyGranted => _permissionGranted;

  /// 触发本地网络权限对话框
  ///
  /// 通过向本地网络发送一个小 UDP 包来触发权限对话框。
  /// 这是 Apple 推荐的触发权限的方式。
  ///
  /// 返回 true 表示发送成功（权限可能已授予），false 表示失败。
  Future<bool> triggerPermissionDialog() async {
    if (kIsWeb) {
      debugPrint('IOSLocalNetworkPermission: Web 平台不需要触发');
      return true;
    }

    if (!Platform.isIOS && !Platform.isMacOS) {
      debugPrint('IOSLocalNetworkPermission: 非 Apple 平台不需要触发');
      return true;
    }

    if (_hasTriggered && _permissionGranted) {
      debugPrint('IOSLocalNetworkPermission: 已经触发过且成功，跳过');
      return true;
    }

    _hasTriggered = true;
    logInfo('ios_network_permission_trigger_start', source: 'IOSNetwork');

    try {
      // 方法 1: 尝试 UDP 组播发送（最可靠的触发方式）
      final multicastResult = await _triggerViaMulticast();
      if (multicastResult) {
        _permissionGranted = true;
        logInfo(
          'ios_network_permission_granted_multicast',
          source: 'IOSNetwork',
        );
        return true;
      }

      // 方法 2: 尝试 UDP 广播发送
      final broadcastResult = await _triggerViaBroadcast();
      if (broadcastResult) {
        _permissionGranted = true;
        logInfo(
          'ios_network_permission_granted_broadcast',
          source: 'IOSNetwork',
        );
        return true;
      }

      // 方法 3: 尝试连接到网关地址
      final gatewayResult = await _triggerViaGateway();
      if (gatewayResult) {
        _permissionGranted = true;
        logInfo('ios_network_permission_granted_gateway', source: 'IOSNetwork');
        return true;
      }

      logWarning(
        'ios_network_permission_all_methods_failed',
        source: 'IOSNetwork',
      );
      return false;
    } catch (e) {
      logError(
        'ios_network_permission_trigger_error error=$e',
        source: 'IOSNetwork',
      );
      return false;
    }
  }

  /// 通过 UDP 组播触发权限
  Future<bool> _triggerViaMulticast() async {
    RawDatagramSocket? socket;
    try {
      debugPrint('IOSLocalNetworkPermission: 尝试 UDP 组播触发...');

      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );

      socket.broadcastEnabled = true;
      socket.multicastLoopback = true;

      // 发送到标准组播地址
      final multicastAddress = InternetAddress('224.0.0.170');
      final testMessage =
          'LNP_TRIGGER_${DateTime.now().millisecondsSinceEpoch}';
      final bytes = testMessage.codeUnits;

      final result = socket.send(bytes, multicastAddress, 53317);

      if (result > 0) {
        debugPrint('IOSLocalNetworkPermission: 组播发送成功, 字节=$result');
        return true;
      } else {
        debugPrint('IOSLocalNetworkPermission: 组播发送返回 $result');
        return false;
      }
    } on SocketException catch (e) {
      // errno = 65 表示 "No route to host" - 通常是权限未授予
      // errno = 1 表示 "Operation not permitted"
      debugPrint('IOSLocalNetworkPermission: 组播失败 - ${e.message}');
      if (e.osError?.errorCode == 65 || e.osError?.errorCode == 1) {
        logWarning(
          'ios_network_permission_denied errno=${e.osError?.errorCode}',
          source: 'IOSNetwork',
        );
      }
      return false;
    } catch (e) {
      debugPrint('IOSLocalNetworkPermission: 组播异常 - $e');
      return false;
    } finally {
      socket?.close();
    }
  }

  /// 通过 UDP 广播触发权限
  Future<bool> _triggerViaBroadcast() async {
    RawDatagramSocket? socket;
    try {
      debugPrint('IOSLocalNetworkPermission: 尝试 UDP 广播触发...');

      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );

      socket.broadcastEnabled = true;

      // 发送广播包
      final broadcastAddress = InternetAddress('255.255.255.255');
      final testMessage =
          'LNP_TRIGGER_${DateTime.now().millisecondsSinceEpoch}';
      final bytes = testMessage.codeUnits;

      final result = socket.send(bytes, broadcastAddress, 53317);

      if (result > 0) {
        debugPrint('IOSLocalNetworkPermission: 广播发送成功, 字节=$result');
        return true;
      } else {
        debugPrint('IOSLocalNetworkPermission: 广播发送返回 $result');
        return false;
      }
    } on SocketException catch (e) {
      debugPrint('IOSLocalNetworkPermission: 广播失败 - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('IOSLocalNetworkPermission: 广播异常 - $e');
      return false;
    } finally {
      socket?.close();
    }
  }

  /// 通过连接网关触发权限
  Future<bool> _triggerViaGateway() async {
    Socket? tcpSocket;
    try {
      debugPrint('IOSLocalNetworkPermission: 尝试网关连接触发...');

      // 尝试常见的局域网网关地址
      final gatewayAddresses = [
        '192.168.1.1',
        '192.168.0.1',
        '10.0.0.1',
        '172.16.0.1',
      ];

      for (final gateway in gatewayAddresses) {
        try {
          // 短超时，只是为了触发权限对话框
          tcpSocket = await Socket.connect(
            gateway,
            80,
            timeout: const Duration(milliseconds: 500),
          );
          debugPrint('IOSLocalNetworkPermission: 网关连接成功 $gateway');
          tcpSocket.destroy();
          return true;
        } on SocketException {
          // 连接失败是预期的，但权限对话框应该已经触发
          continue;
        } on TimeoutException {
          // 超时也是预期的，权限对话框可能已触发
          continue;
        }
      }

      // 即使所有连接都失败，只要没有 errno=65，权限对话框可能已触发
      debugPrint('IOSLocalNetworkPermission: 网关连接尝试完成');
      return true;
    } catch (e) {
      debugPrint('IOSLocalNetworkPermission: 网关触发异常 - $e');
      return false;
    } finally {
      tcpSocket?.destroy();
    }
  }

  /// 检查 UDP 组播是否可用
  ///
  /// 用于诊断权限状态。如果返回 false，用户可能需要在设置中手动启用权限。
  Future<MulticastDiagnosticResult> diagnoseMulticastCapability() async {
    if (kIsWeb) {
      return MulticastDiagnosticResult(
        canBind: false,
        canSend: false,
        canReceive: false,
        errorMessage: 'Web 平台不支持 UDP',
      );
    }

    if (!Platform.isIOS && !Platform.isMacOS) {
      return MulticastDiagnosticResult(
        canBind: true,
        canSend: true,
        canReceive: true,
        errorMessage: null,
      );
    }

    bool canBind = false;
    bool canSend = false;
    bool canReceive = false;
    String? errorMessage;

    RawDatagramSocket? socket;
    try {
      // 测试绑定
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      canBind = true;

      socket.broadcastEnabled = true;
      socket.multicastLoopback = true;

      // 测试加入组播组
      try {
        socket.joinMulticast(InternetAddress('224.0.0.170'));
        canReceive = true;
      } catch (e) {
        errorMessage = '无法加入组播组: $e';
      }

      // 测试发送
      try {
        final result = socket.send(
          'TEST'.codeUnits,
          InternetAddress('224.0.0.170'),
          53317,
        );
        canSend = result > 0;
        if (!canSend) {
          errorMessage = '发送返回 0 字节';
        }
      } on SocketException catch (e) {
        if (e.osError?.errorCode == 65) {
          errorMessage = '本地网络权限未授予 (errno=65)';
        } else if (e.osError?.errorCode == 1) {
          errorMessage = '操作不被允许 (errno=1)';
        } else {
          errorMessage = 'Socket 错误: ${e.message}';
        }
      }
    } on SocketException catch (e) {
      errorMessage = '无法绑定 Socket: ${e.message}';
    } catch (e) {
      errorMessage = '诊断异常: $e';
    } finally {
      socket?.close();
    }

    return MulticastDiagnosticResult(
      canBind: canBind,
      canSend: canSend,
      canReceive: canReceive,
      errorMessage: errorMessage,
    );
  }
}

/// 组播诊断结果
class MulticastDiagnosticResult {
  final bool canBind;
  final bool canSend;
  final bool canReceive;
  final String? errorMessage;

  MulticastDiagnosticResult({
    required this.canBind,
    required this.canSend,
    required this.canReceive,
    this.errorMessage,
  });

  bool get isFullyFunctional => canBind && canSend && canReceive;

  /// 生成用户友好的状态描述
  String get userFriendlyStatus {
    if (isFullyFunctional) {
      return '网络权限正常，设备发现功能可用';
    }
    if (!canBind) {
      return '无法创建网络连接，请检查网络设置';
    }
    if (!canSend) {
      return '无法发送网络数据，其他设备可能无法发现此设备。请前往 设置 → 隐私与安全性 → 本地网络 中启用本应用的权限';
    }
    if (!canReceive) {
      return '无法接收网络数据，可能无法发现其他设备';
    }
    return errorMessage ?? '未知网络问题';
  }

  @override
  String toString() {
    return 'MulticastDiagnostic(bind=$canBind, send=$canSend, recv=$canReceive, err=$errorMessage)';
  }
}
