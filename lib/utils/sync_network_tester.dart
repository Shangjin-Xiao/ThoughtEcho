import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:thoughtecho/utils/app_logger.dart';

/// 同步网络连通性测试工具
/// 
/// 用于诊断网络传输功能的各个方面
class SyncNetworkTester {
  /// 测试UDP组播发现功能（增强：开启loopback并尝试接收自身广播）
  static Future<NetworkTestResult> testMulticastDiscovery() async {
    final result = NetworkTestResult('UDP组播发现测试');
    RawDatagramSocket? socket;

    try {
      logDebug('开始测试UDP组播发现...');
      // 1. 绑定任意端口
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      result.addStep('UDP套接字绑定', true, '成功绑定到端口 ${socket.port}');

      // 基础设置：TTL与回环，便于本机自检
      try {
        socket.readEventsEnabled = true;
        socket.broadcastEnabled = true;
        socket.multicastLoopback = true; // 允许本机收到自己发出的组播
        // TTL 在 Dart 原生 API 中不可直接设置，保留注释说明
        result.addStep('组播参数设置', true, '已启用loopback与broadcast');
      } catch (e) {
        result.addStep('组播参数设置', false, '设置失败: $e');
      }

      // 2. 加入所有可用接口的组播组
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

      // 3. 发送并尝试接收自身广播
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
        final group = InternetAddress('224.0.0.168');
        const port = 53318;

        // 监听接收
        bool received = false;
        final completer = Completer<void>();
        Timer? listenTimer;

        socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket!.receive();
            if (datagram != null) {
              final data = utf8.decode(datagram.data, allowMalformed: true);
              if (data.contains('NetworkTest')) {
                received = true;
                result.addStep('接收测试消息', true, '来自 ${datagram.address.address}:${datagram.port} -> $data');
                if (!completer.isCompleted) completer.complete();
              }
            }
          }
        });

        // 发送两次以提高命中率
        socket.send(messageBytes, group, port);
        socket.send(messageBytes, group, port);
        result.addStep('发送测试消息', true, '消息大小: ${messageBytes.length} 字节, 端口: $port');

        // 等待接收，最多1.5秒
        listenTimer = Timer(const Duration(milliseconds: 1500), () {
          if (!completer.isCompleted) completer.complete();
        });
        await completer.future;
        listenTimer.cancel();

        if (!received) {
          result.addStep('接收测试消息', false, '未在1.5秒内接收到组播包。可能原因：防火墙阻拦/网卡未启用组播/未在同一子网');
        }
      } catch (e) {
        result.addStep('发送/接收测试', false, '异常: $e');
      }
    } catch (e) {
      result.addStep('UDP组播测试', false, '测试失败: $e');
    } finally {
      socket?.close();
    }

    return result;
  }

  /// 测试HTTP服务器功能（内置临时服务回环）
  static Future<NetworkTestResult> testHttpServer() async {
    final result = NetworkTestResult('HTTP服务器测试');
    HttpServer? server;

    try {
      logDebug('开始测试HTTP服务器...');

      // 1. 启动
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
        final port = server.port;
        result.addStep('HTTP服务器启动', true, '成功绑定到端口 $port');

        // 2. 基本响应
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

        // 3. 客户端连接
        try {
          final client = HttpClient();
          final req = await client.get('127.0.0.1', port, '/test');
          final resp = await req.close();
          if (resp.statusCode == 200) {
            final body = await resp.transform(utf8.decoder).join();
            result.addStep('HTTP客户端连接', true, '响应: $body');
          } else {
            result.addStep('HTTP客户端连接', false, '状态码: ${resp.statusCode}');
          }
          client.close();
        } catch (e) {
          result.addStep('HTTP客户端连接', false, '连接失败: $e');
        }
      } catch (e) {
        result.addStep('HTTP服务器启动', false, '启动失败: $e');
      }
    } catch (e) {
      result.addStep('HTTP服务器测试', false, '测试失败: $e');
    } finally {
      await server?.close();
    }

    return result;
  }

  /// 测试文件传输功能（本地文件流验证）
  static Future<NetworkTestResult> testFileTransfer() async {
    final result = NetworkTestResult('文件传输测试');
    try {
      logDebug('开始测试文件传输...');
      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/sync_test_file.txt');
      final testContent = 'ThoughtEcho Sync Test File\n时间: ${DateTime.now()}\n内容大小测试: ${'A' * 1000}';

      await testFile.writeAsString(testContent);
      result.addStep('创建测试文件', true, '文件大小: ${await testFile.length()} 字节');

      try {
        final readContent = await testFile.readAsString();
        result.addStep('文件读取验证', readContent == testContent, readContent == testContent ? '内容匹配' : '内容不匹配');
      } catch (e) {
        result.addStep('文件读取验证', false, '读取失败: $e');
      }

      try {
        final stream = testFile.openRead();
        int total = 0;
        int chunks = 0;
        await for (final chunk in stream) {
          total += chunk.length;
          chunks++;
        }
        result.addStep('流式文件读取', true, '读取 $chunks 个数据块，总计 $total 字节');
      } catch (e) {
        result.addStep('流式文件读取', false, '流式读取失败: $e');
      }

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

      // 1. 接口信息
      try {
        final interfaces = await NetworkInterface.list();
        final active = interfaces.where((i) => i.addresses.any((a) => a.type == InternetAddressType.IPv4 && !a.isLoopback)).toList();
        result.addStep('网络接口检查', active.isNotEmpty, '发现 ${active.length} 个活动接口');
        for (final i in active) {
          final ipv4 = i.addresses.where((a) => a.type == InternetAddressType.IPv4 && !a.isLoopback).map((a) => a.address).join(', ');
          result.addStep('接口 ${i.name}', true, 'IP地址: $ipv4');
        }
      } catch (e) {
        result.addStep('网络接口检查', false, '检查失败: $e');
      }

      // 2. 回环连接（可能失败属正常）
      try {
        final socket = await Socket.connect('127.0.0.1', 80, timeout: const Duration(seconds: 2));
        await socket.close();
        result.addStep('本地回环连接', true, '连接成功');
      } catch (e) {
        result.addStep('本地回环连接', false, '连接失败（可能无服务）: $e');
      }

      // 3. UDP 端口绑定
      for (final port in const [53317, 53318, 0]) {
        try {
          final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
          final actual = s.port;
          s.close();
          result.addStep('UDP端口 $port', true, '成功绑定到端口 $actual');
        } catch (e) {
          result.addStep('UDP端口 $port', false, '绑定失败: $e');
        }
      }
    } catch (e) {
      result.addStep('网络连通性测试', false, '测试失败: $e');
    }
    return result;
  }

  /// 同步服务健康检查：检测 LocalSendServer 端点
  static Future<NetworkTestResult> testSyncServiceHealth({String host = '127.0.0.1', int port = 53318}) async {
    final result = NetworkTestResult('同步服务健康检查');
    try {
      logDebug('开始测试同步服务健康...');

      // 1. 检测UDP端口绑定
      try {
        RawDatagramSocket? socket;
        try {
          socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
          result.addStep('UDP端口检查', false, '端口 $port 可以绑定，表明没有服务在使用此端口');
          socket.close();
        } catch (e) {
          // 绑定失败，表明端口已被占用，这可能是好事
          result.addStep('UDP端口检查', true, '端口 $port 已被占用，可能是同步服务正在运行');
        }
      } catch (e) {
        result.addStep('UDP端口检查', false, '检查失败: $e');
      }

      // 2. 检测 /info
      try {
        final client = HttpClient();
        final req = await client.get(host, port, '/api/localsend/v2/info');
        final resp = await req.close().timeout(const Duration(seconds: 3));
        final body = await resp.transform(utf8.decoder).join();
        
        if (resp.statusCode == 200) {
          try {
            final jsonData = jsonDecode(body) as Map<String, dynamic>;
            final alias = jsonData['alias'] as String?;
            final fingerprint = jsonData['fingerprint'] as String?;
            
            result.addStep('INFO端点', true, '状态码: ${resp.statusCode}, 设备名称: ${alias ?? '未知'}, 指纹: ${fingerprint?.substring(0, fingerprint.length.clamp(0, 10)) ?? '未知'}...');
          } catch (e) {
            result.addStep('INFO端点', true, '状态码: ${resp.statusCode}, 响应解析失败: $e');
          }
        } else {
          result.addStep('INFO端点', false, '状态码: ${resp.statusCode}, 响应: ${body.substring(0, body.length.clamp(0, 256))}');
        }
        client.close();
      } catch (e) {
        result.addStep('INFO端点', false, '请求失败: $e');
      }

      // 3. 检测备用端口 (53317)
      try {
        final backupPort = 53317;
        final client = HttpClient();
        final req = await client.get(host, backupPort, '/api/localsend/v2/info');
        final resp = await req.close().timeout(const Duration(seconds: 2));
        final body = await resp.transform(utf8.decoder).join();
        
        if (resp.statusCode == 200) {
          result.addStep('备用端口检查', true, '备用端口 $backupPort 上服务正常');
        } else {
          result.addStep('备用端口检查', false, '备用端口 $backupPort 服务返回: ${resp.statusCode}');
        }
        client.close();
      } catch (e) {
        result.addStep('备用端口检查', false, '备用端口检查失败: $e');
      }

      // 4. 伪造一次 prepare-upload（空数据，检查路由/错误码）
      try {
        final client = HttpClient();
        final req = await client.post(host, port, '/api/localsend/v2/prepare-upload');
        req.headers.contentType = ContentType.json;
        
        // 创建有效的请求数据
        final requestData = {
          'info': {
            'alias': 'probe',
            'version': '2.1',
            'deviceModel': 'probe',
            'deviceType': 'desktop',
            'fingerprint': 'probe-${DateTime.now().millisecondsSinceEpoch}',
            'port': port,
            'protocol': 'http',
            'download': true
          }, 
          'files': {
            'test1': {
              'id': 'test1',
              'fileName': 'test.txt',
              'size': 100,
              'fileType': 'text/plain'
            }
          }
        };
        
        req.write(jsonEncode(requestData));
        final resp = await req.close().timeout(const Duration(seconds: 3));
        
        final body = await resp.transform(utf8.decoder).join();
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          try {
            final jsonResponse = jsonDecode(body) as Map<String, dynamic>;
            final sessionId = jsonResponse['sessionId'] as String?;
            result.addStep('PREPARE端点', true, '状态码: ${resp.statusCode}, 创建会话ID: ${sessionId?.substring(0, 8) ?? '未知'}...');
          } catch (e) {
            result.addStep('PREPARE端点', true, '状态码: ${resp.statusCode}, 但JSON解析失败: $e');
          }
        } else {
          result.addStep('PREPARE端点', resp.statusCode >= 200 && resp.statusCode < 500, 
              '状态码: ${resp.statusCode}, 响应: ${body.substring(0, body.length.clamp(0, 100))}...');
        }
        client.close();
      } catch (e) {
        result.addStep('PREPARE端点', false, '请求失败: $e');
      }

      // 5. 404 检查
      try {
        final client = HttpClient();
        final req = await client.get(host, port, '/api/localsend/v2/not-exist');
        final resp = await req.close().timeout(const Duration(seconds: 3));
        final body = await resp.transform(utf8.decoder).join();
        result.addStep('未知路由(404)', resp.statusCode == 404, 
            '状态码: ${resp.statusCode}, 响应: ${body.substring(0, body.length.clamp(0, 100))}...');
        client.close();
      } catch (e) {
        result.addStep('未知路由(404)', false, '请求失败: $e');
      }
      
      // 6. 总结服务状态
      final allSuccess = result.steps.where((s) => s.name != '未知路由(404)' && s.name != 'UDP端口检查').every((s) => s.success);
      result.addStep('服务状态总结', allSuccess, 
          allSuccess ? '同步服务工作正常' : '同步服务存在问题，建议重启应用');
      
    } catch (e) {
      result.addStep('同步服务健康检查', false, '异常: $e');
    }
    return result;
  }

  /// 执行完整的网络功能测试套件
  static Future<List<NetworkTestResult>> runFullNetworkTest() async {
    logDebug('开始执行完整网络功能测试...');

    final futures = [
      testNetworkConnectivity(),
      testMulticastDiscovery(),
      testHttpServer(),
      testFileTransfer(),
      testSyncServiceHealth(),
    ];

    final results = await Future.wait(futures);

    // 总结
    final summary = NetworkTestResult('测试总结');
    int total = 0;
    int passed = 0;
    for (final r in results) {
      for (final s in r.steps) {
        total++;
        if (s.success) passed++;
      }
    }
    final rate = total > 0 ? (passed / total * 100).toStringAsFixed(1) : '0.0';
    summary.addStep('总体测试结果', passed == total, '通过 $passed/$total 项测试 (成功率: $rate%)');

    return [summary, ...results];
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
