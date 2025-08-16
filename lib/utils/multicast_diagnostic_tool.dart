import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:thoughtecho/services/localsend/utils/network_interfaces.dart';

/// UDP组播诊断工具
/// 用于测试和诊断设备发现功能的网络连接问题
class MulticastDiagnosticTool {
  static const String _testMessage = 'THOUGHTECHO_MULTICAST_TEST';

  /// 执行完整的组播诊断
  static Future<MulticastDiagnosticResult> runFullDiagnostic() async {
    final result = MulticastDiagnosticResult();

    debugPrint('=== 开始UDP组播诊断 ===');

    // 1. 网络接口检查
    await _checkNetworkInterfaces(result);

    // 2. UDP套接字绑定测试
    await _testUdpSocketBinding(result);

    // 3. 组播发送测试
    await _testMulticastSending(result);

    // 4. 组播接收测试
    await _testMulticastReceiving(result);

    // 5. 端口可用性测试
    await _testPortAvailability(result);

    debugPrint('=== UDP组播诊断完成 ===');
    debugPrint('总体结果: ${result.isSuccess ? "成功" : "失败"}');

    return result;
  }

  /// 检查网络接口
  static Future<void> _checkNetworkInterfaces(
      MulticastDiagnosticResult result) async {
    try {
      debugPrint('--- 检查网络接口 ---');
      final interfaces =
          await getNetworkInterfaces(whitelist: null, blacklist: null);

      result.networkInterfaceCount = interfaces.length;
      result.addStep(
          '网络接口检查', interfaces.isNotEmpty, '发现 ${interfaces.length} 个网络接口');

      for (final interface in interfaces) {
        final ipv4Addresses = interface.addresses
            .where((a) => a.type == InternetAddressType.IPv4)
            .map((a) => a.address)
            .toList();

        debugPrint('接口: ${interface.name}');
        debugPrint('  IPv4地址: ${ipv4Addresses.join(", ")}');
        debugPrint('  支持组播: true'); // 假设支持组播

        if (ipv4Addresses.isNotEmpty) {
          result.availableInterfaces.add({
            'name': interface.name,
            'addresses': ipv4Addresses,
            'supportsMulticast': true, // 假设支持组播
          });
        }
      }
    } catch (e) {
      result.addStep('网络接口检查', false, '检查失败: $e');
      debugPrint('网络接口检查失败: $e');
    }
  }

  /// 测试UDP套接字绑定
  static Future<void> _testUdpSocketBinding(
      MulticastDiagnosticResult result) async {
    debugPrint('--- 测试UDP套接字绑定 ---');

    // 测试组播端口
    await _testPortBinding(result, 'UDP组播端口', defaultMulticastPort);

    // 测试HTTP服务器端口
    await _testPortBinding(result, 'HTTP服务器端口', defaultPort);

    // 测试动态端口
    await _testPortBinding(result, '动态端口', 0);
  }

  /// 测试特定端口绑定
  static Future<void> _testPortBinding(
      MulticastDiagnosticResult result, String portName, int port) async {
    try {
      final socket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      final actualPort = socket.port;
      socket.close();

      result.addStep('$portName绑定', true, '成功绑定到端口 $actualPort');
      debugPrint('✓ $portName ($port) 绑定成功，实际端口: $actualPort');
    } catch (e) {
      result.addStep('$portName绑定', false, '绑定失败: $e');
      debugPrint('❌ $portName ($port) 绑定失败: $e');
    }
  }

  /// 测试组播发送
  static Future<void> _testMulticastSending(
      MulticastDiagnosticResult result) async {
    debugPrint('--- 测试组播发送 ---');
    // Web 平台不支持 RawDatagramSocket，直接跳过
    if (kIsWeb) {
      result.addStep('组播发送测试', false, 'Web 平台不支持 UDP 组播，测试跳过');
      debugPrint('⚠ Web 平台跳过组播发送测试');
      return;
    }

    RawDatagramSocket? socket;
    try {
      try {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      } on SocketException catch (se) {
        result.addStep('组播发送测试', false, '套接字绑定失败(Socket): ${se.message}');
        debugPrint('❌ 组播发送套接字绑定失败(SocketException): ${se.message}');
        return;
      }
      try {
        socket.broadcastEnabled = true; // 可能在部分平台抛出异常
      } catch (e) {
        debugPrint('⚠ 设置 broadcastEnabled 失败: $e');
      }

      final testData = utf8.encode(_testMessage);
      final multicastAddress = InternetAddress(defaultMulticastGroup);

      int bytesSent = 0;
      try {
        bytesSent = socket.send(testData, multicastAddress, defaultMulticastPort);
      } catch (e) {
        result.addStep('组播发送测试', false, '发送调用失败: $e');
        debugPrint('❌ 组播发送调用失败: $e');
        return; // 直接返回，finally 负责关闭资源
      }

      if (bytesSent > 0) {
        result.addStep('组播发送测试', true, '成功发送 $bytesSent 字节');
        debugPrint('✓ 组播发送成功: $bytesSent 字节');
      } else {
        result.addStep('组播发送测试', false, '发送失败，返回 $bytesSent');
        debugPrint('❌ 组播发送失败: $bytesSent');
      }
    } catch (e) {
      result.addStep('组播发送测试', false, '套接字绑定失败: $e');
      debugPrint('❌ 组播发送套接字绑定失败: $e');
    } finally {
      try {
        socket?.close();
      } catch (_) {}
    }
  }

  /// 测试组播接收
  static Future<void> _testMulticastReceiving(
      MulticastDiagnosticResult result) async {
    debugPrint('--- 测试组播接收 ---');
    // Web 平台不支持 UDP 组播
    if (kIsWeb) {
      result.addStep('组播接收测试', false, 'Web 平台不支持 UDP 组播，测试跳过');
      debugPrint('⚠ Web 平台跳过组播接收测试');
      return;
    }

    RawDatagramSocket? socket;
    Timer? timeoutTimer;
    bool messageReceived = false;

    try {
      try {
        socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4, defaultMulticastPort);
      } on SocketException catch (se) {
        result.addStep('组播接收测试', false, '套接字绑定失败(Socket): ${se.message}');
        debugPrint('❌ 组播接收套接字绑定失败(SocketException): ${se.message}');
        return;
      }
      try {
        socket.readEventsEnabled = true;
        socket.broadcastEnabled = true;
        socket.multicastLoopback = true;
      } catch (e) {
        debugPrint('⚠ 设置套接字属性失败: $e');
      }

      // 尝试加入组播组
      try {
        final interfaces =
            await getNetworkInterfaces(whitelist: null, blacklist: null);
        for (final interface in interfaces) {
          try {
            socket.joinMulticast(
                InternetAddress(defaultMulticastGroup), interface);
            debugPrint('✓ 成功加入组播组 (接口: ${interface.name})');
          } catch (e) {
            debugPrint('❌ 加入组播组失败 (接口: ${interface.name}): $e');
          }
        }
      } catch (e) {
        debugPrint('❌ 获取网络接口失败: $e');
      }

      // 设置接收监听
      final completer = Completer<void>();

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket!.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            debugPrint('收到组播消息: $message');
            if (message.contains(_testMessage)) {
              messageReceived = true;
              completer.complete();
            }
          }
        }
      });

      // 发送测试消息
      final testData =
          utf8.encode('$_testMessage-${DateTime.now().millisecondsSinceEpoch}');
      try {
        socket.send(testData, InternetAddress(defaultMulticastGroup),
            defaultMulticastPort);
      } catch (e) {
        debugPrint('❌ 发送测试消息失败: $e');
      }

      // 等待接收或超时
      timeoutTimer = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      await completer.future;

      if (messageReceived) {
        result.addStep('组播接收测试', true, '成功接收到测试消息');
        debugPrint('✓ 组播接收成功');
      } else {
        result.addStep('组播接收测试', false, '未接收到测试消息（可能是防火墙阻止）');
        debugPrint('❌ 组播接收失败');
      }
    } catch (e) {
      result.addStep('组播接收测试', false, '接收异常: $e');
      debugPrint('❌ 组播接收异常: $e');
    } finally {
      timeoutTimer?.cancel();
      try {
        socket?.close();
      } catch (_) {}
    }
  }

  /// 测试端口可用性
  static Future<void> _testPortAvailability(
      MulticastDiagnosticResult result) async {
    debugPrint('--- 测试端口可用性 ---');

    final portsToTest = [
      defaultMulticastPort,
      defaultPort,
      53317, // 原版LocalSend端口
      53321, // 备用端口
    ];

    for (final port in portsToTest) {
      try {
        final socket =
            await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
        socket.close();
        result.addStep('端口 $port 可用性', true, '端口可用');
        debugPrint('✓ 端口 $port 可用');
      } catch (e) {
        result.addStep('端口 $port 可用性', false, '端口被占用或无法绑定');
        debugPrint('❌ 端口 $port 不可用: $e');
      }
    }
  }
}

/// 诊断结果类
class MulticastDiagnosticResult {
  final List<DiagnosticStep> steps = [];
  int networkInterfaceCount = 0;
  final List<Map<String, dynamic>> availableInterfaces = [];

  void addStep(String name, bool success, String message) {
    steps.add(DiagnosticStep(name, success, message));
  }

  bool get isSuccess => steps.every((step) => step.success);

  int get successCount => steps.where((step) => step.success).length;
  int get totalCount => steps.length;

  String get summary {
    return '诊断完成: $successCount/$totalCount 项通过\n'
        '网络接口: $networkInterfaceCount 个\n'
        '可用接口: ${availableInterfaces.length} 个';
  }
}

/// 诊断步骤
class DiagnosticStep {
  final String name;
  final bool success;
  final String message;

  DiagnosticStep(this.name, this.success, this.message);

  @override
  String toString() => '${success ? "✓" : "❌"} $name: $message';
}
