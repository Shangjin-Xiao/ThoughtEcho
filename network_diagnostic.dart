import 'dart:io';
import 'dart:convert';
import 'package:thoughtecho/services/localsend/constants.dart';

void main() async {
  print('=== ThoughtEcho 同步服务网络诊断 ===');
  
  // 1. 检查基本网络接口
  print('\n1. 检查网络接口:');
  try {
    final interfaces = await NetworkInterface.list();
    for (final interface in interfaces) {
      print('  接口: ${interface.name}');
      for (final addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          print('    IPv4: ${addr.address}');
        }
      }
    }
  } catch (e) {
    print('  错误: $e');
  }
  
  // 2. 测试HTTP服务器绑定
  print('\n2. 测试HTTP服务器绑定:');
  try {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, defaultPort);
    print('  ✓ 成功绑定到端口 ${server.port}');
    await server.close();
  } catch (e) {
    print('  ❌ 绑定失败: $e');
    
    // 尝试其他端口
    for (int port = defaultPort + 1; port <= defaultPort + 5; port++) {
      try {
        final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        print('  ✓ 成功绑定到替代端口 ${server.port}');
        await server.close();
        break;
      } catch (e) {
        print('  ❌ 端口 $port 也失败: $e');
      }
    }
  }
  
  // 3. 测试UDP组播
  print('\n3. 测试UDP组播:');
  try {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, defaultMulticastPort);
    print('  ✓ 成功创建UDP套接字，端口: ${socket.port}');
    
    socket.broadcastEnabled = true;
    socket.multicastLoopback = true;
    print('  ✓ 已启用广播和回环');
    
    // 尝试加入组播组
    try {
      final interfaces = await NetworkInterface.list();
      int joinCount = 0;
      for (final interface in interfaces) {
        try {
          socket.joinMulticast(InternetAddress(defaultMulticastGroup), interface);
          joinCount++;
          print('  ✓ 成功加入组播组 $defaultMulticastGroup (接口: ${interface.name})');
        } catch (e) {
          print('  ❌ 加入组播组失败 (接口: ${interface.name}): $e');
        }
      }
      
      if (joinCount == 0) {
        print('  ❌ 警告: 未能加入任何组播组');
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
        print('  ✓ 成功发送组播消息，字节数: $sent');
      } else {
        print('  ❌ 发送组播消息失败');
      }
      
    } catch (e) {
      print('  ❌ 组播操作失败: $e');
    }
    
    socket.close();
  } catch (e) {
    print('  ❌ UDP套接字创建失败: $e');
  }
  
  // 4. 测试本地HTTP通信
  print('\n4. 测试本地HTTP通信:');
  HttpServer? server;
  try {
    server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final port = server.port;
    print('  ✓ 测试服务器启动，端口: $port');
    
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
        print('  ✓ HTTP通信成功: $body');
      } else {
        print('  ❌ HTTP响应错误: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  } catch (e) {
    print('  ❌ HTTP通信测试失败: $e');
  } finally {
    await server?.close();
  }
  
  print('\n=== 诊断完成 ===');
}