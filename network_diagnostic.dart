import 'dart:io';
import 'dart:convert';
import 'package:thoughtecho/services/localsend/constants.dart';
import 'package:thoughtecho/utils/app_logger.dart';

void main() async {
  AppLogger.i('=== ThoughtEcho 同步服务网络诊断 ===', source: 'NetworkDiagnostic');
  
  // 1. 检查基本网络接口
  AppLogger.i('\n1. 检查网络接口:', source: 'NetworkDiagnostic');
  try {
    final interfaces = await NetworkInterface.list();
    for (final interface in interfaces) {
      AppLogger.i('  接口: ${interface.name}', source: 'NetworkDiagnostic');
      for (final addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          AppLogger.i('    IPv4: ${addr.address}', source: 'NetworkDiagnostic');
        }
      }
    }
  } catch (e) {
    AppLogger.e('  错误: $e', source: 'NetworkDiagnostic');
  }
  
  // 2. 测试HTTP服务器绑定
  AppLogger.i('\n2. 测试HTTP服务器绑定:', source: 'NetworkDiagnostic');
  try {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, defaultPort);
    AppLogger.i('  ✓ 成功绑定到端口 ${server.port}', source: 'NetworkDiagnostic');
    await server.close();
  } catch (e) {
    AppLogger.e('  ❌ 绑定失败: $e', source: 'NetworkDiagnostic');
    
    // 尝试其他端口
    for (int port = defaultPort + 1; port <= defaultPort + 5; port++) {
      try {
        final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        AppLogger.i('  ✓ 成功绑定到替代端口 ${server.port}', source: 'NetworkDiagnostic');
        await server.close();
        break;
      } catch (e) {
        AppLogger.e('  ❌ 端口 $port 也失败: $e', source: 'NetworkDiagnostic');
      }
    }
  }
  
  // 3. 测试UDP组播
  AppLogger.i('\n3. 测试UDP组播:', source: 'NetworkDiagnostic');
  try {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, defaultMulticastPort);
    AppLogger.i('  ✓ 成功创建UDP套接字，端口: ${socket.port}', source: 'NetworkDiagnostic');
    
    socket.broadcastEnabled = true;
    socket.multicastLoopback = true;
    AppLogger.i('  ✓ 已启用广播和回环', source: 'NetworkDiagnostic');
    
    // 尝试加入组播组
    try {
      final interfaces = await NetworkInterface.list();
      int joinCount = 0;
      for (final interface in interfaces) {
        try {
          socket.joinMulticast(InternetAddress(defaultMulticastGroup), interface);
          joinCount++;
          AppLogger.i('  ✓ 成功加入组播组 $defaultMulticastGroup (接口: ${interface.name})', source: 'NetworkDiagnostic');
        } catch (e) {
          AppLogger.e('  ❌ 加入组播组失败 (接口: ${interface.name}): $e', source: 'NetworkDiagnostic');
        }
      }
      
      if (joinCount == 0) {
        AppLogger.w('  ❌ 警告: 未能加入任何组播组', source: 'NetworkDiagnostic');
      }
      
      // 测试发送组播消息
      final testMessage = jsonEncode({
        'alias': 'ThoughtEcho-Test',
        'version': protocolVersion,
        'fingerprint': 'test-${DateTime.now().millisecondsSinceEpoch}',
        'port': defaultPort,
        'announcement': true,
      });
      
      final messageBytes = utf8.encode(testMessage);
      final sent = socket.send(messageBytes, InternetAddress(defaultMulticastGroup), defaultMulticastPort);
      
      if (sent > 0) {
        AppLogger.i('  ✓ 成功发送组播消息，字节数: $sent', source: 'NetworkDiagnostic');
      } else {
        AppLogger.e('  ❌ 发送组播消息失败', source: 'NetworkDiagnostic');
      }
      
    } catch (e) {
      AppLogger.e('  ❌ 组播操作失败: $e', source: 'NetworkDiagnostic');
    }
    
    socket.close();
  } catch (e) {
    AppLogger.e('  ❌ UDP套接字创建失败: $e', source: 'NetworkDiagnostic');
  }
  
  // 4. 测试本地HTTP通信
  AppLogger.i('\n4. 测试本地HTTP通信:', source: 'NetworkDiagnostic');
  HttpServer? server;
  try {
    server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final port = server.port;
    AppLogger.i('  ✓ 测试服务器启动，端口: $port', source: 'NetworkDiagnostic');
    
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'alias': 'ThoughtEcho',
        'version': protocolVersion,
        'test': 'success'
      }));
      await request.response.close();
    });
    
    // 发送测试请求
    final client = HttpClient();
    try {
      final request = await client.get('127.0.0.1', port, '/api/localsend/v2/info');
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        AppLogger.i('  ✓ HTTP通信成功: $body', source: 'NetworkDiagnostic');
      } else {
        AppLogger.e('  ❌ HTTP响应错误: ${response.statusCode}', source: 'NetworkDiagnostic');
      }
    } finally {
      client.close();
    }
  } catch (e) {
    AppLogger.e('  ❌ HTTP通信测试失败: $e', source: 'NetworkDiagnostic');
  } finally {
    await server?.close();
  }
  
  AppLogger.i('\n=== 诊断完成 ===', source: 'NetworkDiagnostic');
}