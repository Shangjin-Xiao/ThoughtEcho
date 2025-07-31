import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:thoughtecho/utils/app_logger.dart';

/// 同步网络连通性测试工具
/// 
/// 用于诊断网络传输功能的各个方面
class SyncNetworkTester {
  /// 测试UDP组播发现功能
  static Future<NetworkTestResult> testMulticastDiscovery() async {
    final result = NetworkTestResult('UDP组播发现测试');
    
    try {
      logDebug('开始测试UDP组播发现...');
      
      // 1. 测试组播地址绑定
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      result.addStep('UDP套接字绑定', true, '成功绑定到端口 ${socket.port}');
      
      // 2. 测试组播组加入
      try {
        final multicastAddress = InternetAddress('224.0.0.168');
        final interfaces = await NetworkInterface.list();
        bool joinedAny = false;
        
        for (final interface in interfaces) {
          try {
            socket.joinMulticast(multicastAddress, interface);
            joinedAny = true;
            result.addStep('加入组播组 (${interface.name})', true, '成功加入 ${multicastAddress.address}');
          } catch (e) {
            result.addStep('加入组播组 (${interface.name})', false, '失败: $e');
          }
        }
        
        if (!joinedAny) {
          result.addStep('组播组加入', false, '无法加入任何网络接口的组播组');
        }
      } catch (e) {
        result.addStep('组播组加入', false, '加入组播组失败: $e');
      }
      
      // 3. 测试消息发送
      try {
        final testMessage = jsonEncode({
          'alias': 'NetworkTest',
          'version': '2.1',
          'deviceType': 'desktop',
          'fingerprint': 'test-fingerprint',
          'port': 53318,
          'announcement': true,
        });
        
        final messageBytes = utf8.encode(testMessage);
        socket.send(messageBytes, InternetAddress('224.0.0.168'), 53318);
        result.addStep('发送测试消息', true, '消息大小: ${messageBytes.length} 字节');
      } catch (e) {
        result.addStep('发送测试消息', false, '发送失败: $e');
      }
      
      socket.close();
      
    } catch (e) {
      result.addStep('UDP组播测试', false, '测试失败: $e');
    }
    
    return result;
  }

  /// 测试HTTP服务器功能
  static Future<NetworkTestResult> testHttpServer() async {
    final result = NetworkTestResult('HTTP服务器测试');
    
    try {
      logDebug('开始测试HTTP服务器...');
      
      // 1. 测试服务器启动
      HttpServer? server;
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
        final port = server.port;
        result.addStep('HTTP服务器启动', true, '成功绑定到端口 $port');
        
        // 2. 测试基本HTTP响应
        server.listen((request) async {
          if (request.uri.path == '/test') {
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType.json;
            request.response.write('{"status": "ok", "message": "Server is working"}');
            await request.response.close();
          } else {
            request.response.statusCode = 404;
            await request.response.close();
          }
        });
        
        // 3. 测试HTTP客户端连接
        try {
          final client = HttpClient();
          final request = await client.get('127.0.0.1', port, '/test');
          final response = await request.close();
          
          if (response.statusCode == 200) {
            final responseBody = await response.transform(utf8.decoder).join();
            result.addStep('HTTP客户端连接', true, '响应: $responseBody');
          } else {
            result.addStep('HTTP客户端连接', false, '状态码: ${response.statusCode}');
          }
          
          client.close();
        } catch (e) {
          result.addStep('HTTP客户端连接', false, '连接失败: $e');
        }
        
      } catch (e) {
        result.addStep('HTTP服务器启动', false, '启动失败: $e');
      } finally {
        await server?.close();
      }
      
    } catch (e) {
      result.addStep('HTTP服务器测试', false, '测试失败: $e');
    }
    
    return result;
  }

  /// 测试文件传输功能
  static Future<NetworkTestResult> testFileTransfer() async {
    final result = NetworkTestResult('文件传输测试');
    
    try {
      logDebug('开始测试文件传输...');
      
      // 1. 创建测试文件
      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/sync_test_file.txt');
      final testContent = 'ThoughtEcho Sync Test File\n时间: ${DateTime.now()}\n内容大小测试: ${'A' * 1000}';
      
      await testFile.writeAsString(testContent);
      result.addStep('创建测试文件', true, '文件大小: ${await testFile.length()} 字节');
      
      // 2. 测试文件读取
      try {
        final readContent = await testFile.readAsString();
        final isContentMatch = readContent == testContent;
        result.addStep('文件读取验证', isContentMatch, 
          isContentMatch ? '内容匹配' : '内容不匹配');
      } catch (e) {
        result.addStep('文件读取验证', false, '读取失败: $e');
      }
      
      // 3. 测试流式文件处理
      try {
        final stream = testFile.openRead();
        final chunks = <List<int>>[];
        await for (final chunk in stream) {
          chunks.add(chunk);
        }
        
        final totalBytes = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
        result.addStep('流式文件读取', true, '读取 ${chunks.length} 个数据块，总计 $totalBytes 字节');
      } catch (e) {
        result.addStep('流式文件读取', false, '流式读取失败: $e');
      }
      
      // 4. 清理测试文件
      try {
        await testFile.delete();
        result.addStep('清理测试文件', true, '文件已删除');
      } catch (e) {
        result.addStep('清理测试文件', false, '删除失败: $e');
      }
      
    } catch (e) {
      result.addStep('文件传输测试', false, '测试失败: $e');
    }
    
    return result;
  }

  /// 测试网络接口和连通性
  static Future<NetworkTestResult> testNetworkConnectivity() async {
    final result = NetworkTestResult('网络连通性测试');
    
    try {
      logDebug('开始测试网络连通性...');
      
      // 1. 检查网络接口
      try {
        final interfaces = await NetworkInterface.list();
        final activeInterfaces = interfaces.where((i) => 
          i.addresses.any((addr) => addr.type == InternetAddressType.IPv4 && !addr.isLoopback)
        ).toList();
        
        result.addStep('网络接口检查', activeInterfaces.isNotEmpty, 
          '发现 ${activeInterfaces.length} 个活动接口');
        
        for (final interface in activeInterfaces) {
          final ipv4Addresses = interface.addresses
              .where((addr) => addr.type == InternetAddressType.IPv4 && !addr.isLoopback)
              .toList();
          
          result.addStep('接口 ${interface.name}', true, 
            'IP地址: ${ipv4Addresses.map((a) => a.address).join(', ')}');
        }
      } catch (e) {
        result.addStep('网络接口检查', false, '检查失败: $e');
      }
      
      // 2. 测试本地回环连接
      try {
        final socket = await Socket.connect('127.0.0.1', 80, timeout: const Duration(seconds: 2));
        await socket.close();
        result.addStep('本地回环连接', true, '连接成功');
      } catch (e) {
        // 这个测试可能失败，因为本地80端口可能没有服务
        result.addStep('本地回环连接', false, '连接失败（正常情况）: $e');
      }
      
      // 3. 测试UDP套接字绑定到不同端口
      final testPorts = [53317, 53318, 0]; // 0表示系统分配
      for (final port in testPorts) {
        try {
          final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
          final actualPort = socket.port;
          socket.close();
          result.addStep('UDP端口 $port', true, '成功绑定到端口 $actualPort');
        } catch (e) {
          result.addStep('UDP端口 $port', false, '绑定失败: $e');
        }
      }
      
    } catch (e) {
      result.addStep('网络连通性测试', false, '测试失败: $e');
    }
    
    return result;
  }

  /// 执行完整的网络功能测试套件
  static Future<List<NetworkTestResult>> runFullNetworkTest() async {
    logDebug('开始执行完整网络功能测试...');
    
    final results = <NetworkTestResult>[];
    
    // 并行执行多个测试
    final futures = [
      testNetworkConnectivity(),
      testMulticastDiscovery(),
      testHttpServer(),
      testFileTransfer(),
    ];
    
    final testResults = await Future.wait(futures);
    results.addAll(testResults);
    
    // 生成总结报告
    final summary = NetworkTestResult('测试总结');
    int totalTests = 0;
    int passedTests = 0;
    
    for (final result in results) {
      for (final step in result.steps) {
        totalTests++;
        if (step.success) passedTests++;
      }
    }
    
    final successRate = totalTests > 0 ? (passedTests / totalTests * 100).toStringAsFixed(1) : '0.0';
    summary.addStep('总体测试结果', passedTests == totalTests, 
      '通过 $passedTests/$totalTests 项测试 (成功率: $successRate%)');
    
    results.insert(0, summary);
    
    logDebug('网络功能测试完成，成功率: $successRate%');
    return results;
  }
}

/// 网络测试结果
class NetworkTestResult {
  final String testName;
  final List<TestStep> steps = [];
  final DateTime timestamp = DateTime.now();

  NetworkTestResult(this.testName);

  void addStep(String stepName, bool success, String message) {
    steps.add(TestStep(stepName, success, message));
  }

  bool get isSuccess => steps.every((step) => step.success);
  
  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('=== $testName ===');
    buffer.writeln('时间: ${timestamp.toIso8601String()}');
    buffer.writeln('总体结果: ${isSuccess ? "✅ 成功" : "❌ 失败"}');
    buffer.writeln();
    
    for (final step in steps) {
      buffer.writeln('${step.success ? "✅" : "❌"} ${step.name}: ${step.message}');
    }
    
    return buffer.toString();
  }
}

/// 测试步骤
class TestStep {
  final String name;
  final bool success;
  final String message;

  TestStep(this.name, this.success, this.message);
}
