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
    List<RawDatagramSocket> testSockets = [];

    try {
      logDebug('开始测试UDP组播发现...');

      // 测试多个可能的端口
      final portsToTest = [53318, 53317, 0];
      bool anyPortBound = false;

      for (final testPort in portsToTest) {
        try {
          socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            testPort,
          );
          testSockets.add(socket);

          final actualPort = socket.port;
          result.addStep(
            'UDP套接字绑定',
            true,
            '成功绑定到端口 ${testPort == 0 ? '随机' : testPort} (实际端口: $actualPort)',
          );
          anyPortBound = true;

          // 仅使用一个成功绑定的端口
          break;
        } catch (e) {
          result.addStep('UDP套接字绑定 (端口 $testPort)', false, '绑定失败: $e');
        }
      }

      if (!anyPortBound) {
        result.addStep('UDP套接字绑定', false, '无法绑定到任何测试端口');
        return result;
      }

      // 基础设置：TTL与回环，便于本机自检
      try {
        if (socket != null) {
          socket.readEventsEnabled = true;
          socket.broadcastEnabled = true;
          socket.multicastLoopback = true; // 允许本机收到自己发出的组播
          // TTL 在 Dart 原生 API 中不可直接设置，保留注释说明
          result.addStep('组播参数设置', true, '已启用loopback与broadcast');
        } else {
          result.addStep('组播参数设置', false, '套接字为null，无法设置参数');
        }
      } catch (e) {
        result.addStep('组播参数设置', false, '设置失败: $e');
      }

      // 获取所有网络接口信息
      try {
        final interfaces = await NetworkInterface.list();
        final activeInterfaces = interfaces
            .where(
              (i) => i.addresses.any(
                (a) => a.type == InternetAddressType.IPv4 && !a.isLoopback,
              ),
            )
            .toList();

        result.addStep(
          '网络接口检查',
          activeInterfaces.isNotEmpty,
          '发现 ${activeInterfaces.length} 个活动网络接口，总共 ${interfaces.length} 个接口',
        );

        for (final i in activeInterfaces) {
          final ipv4Addresses = i.addresses
              .where((a) => a.type == InternetAddressType.IPv4 && !a.isLoopback)
              .map((a) => a.address)
              .join(', ');

          result.addStep('网络接口 ${i.name}', true, 'IP地址: $ipv4Addresses');
        }
      } catch (e) {
        result.addStep('网络接口检查', false, '检查失败: $e');
      }

      // 2. 加入所有可用接口的组播组
      try {
        final multicastAddress = InternetAddress('224.0.0.168');
        final interfaces = await NetworkInterface.list();
        bool joinedAny = false;

        if (socket != null) {
          for (final interface in interfaces) {
            try {
              socket.joinMulticast(multicastAddress, interface);
              joinedAny = true;
              result.addStep(
                '加入组播组 (${interface.name})',
                true,
                '成功加入 ${multicastAddress.address}',
              );
            } catch (e) {
              result.addStep('加入组播组 (${interface.name})', false, '失败: $e');
            }
          }
        } else {
          result.addStep('组播组加入', false, '套接字为null，无法加入组播组');
        }

        if (!joinedAny) {
          result.addStep('组播组加入', false, '无法加入任何网络接口的组播组');
        }
      } catch (e) {
        result.addStep('组播组加入', false, '加入组播组失败: $e');
      }

      // 3. 发送并尝试接收自身广播
      try {
        // 使用完整的设备信息格式
        final testMessage = jsonEncode({
          'alias': 'NetworkTest',
          'version': '2.1',
          'deviceModel': 'ThoughtEcho',
          'deviceType': 'desktop',
          'fingerprint':
              'test-fingerprint-${DateTime.now().millisecondsSinceEpoch}',
          'port': 53318,
          'protocol': 'http',
          'download': true,
          'announcement': true,
          'announce': true,
        });

        final messageBytes = utf8.encode(testMessage);

        // 尝试两个组播地址
        final multicastGroups = [
          InternetAddress('224.0.0.168'), // ThoughtEcho
          InternetAddress('224.0.0.167'), // LocalSend
        ];

        final ports = [53318, 53317];

        bool anyMessageSent = false;

        if (socket != null) {
          for (final group in multicastGroups) {
            for (final port in ports) {
              try {
                final sent = socket.send(messageBytes, group, port);
                if (sent > 0) {
                  anyMessageSent = true;
                  result.addStep(
                    '发送测试消息',
                    true,
                    '发送到 ${group.address}:$port，消息大小: $sent 字节',
                  );
                }
              } catch (e) {
                result.addStep(
                  '发送测试消息 (${group.address}:$port)',
                  false,
                  '发送失败: $e',
                );
              }
            }
          }
        } else {
          result.addStep('发送测试消息', false, '套接字为null，无法发送消息');
        }

        if (!anyMessageSent) {
          result.addStep('发送测试消息', false, '无法发送组播消息到任何组');
        }

        // 监听接收
        bool received = false;
        final completer = Completer<void>();
        Timer? listenTimer;

        if (socket != null) {
          StreamSubscription<RawSocketEvent>? subscription;

          subscription = socket.listen((event) {
            if (event == RawSocketEvent.read) {
              final datagram = socket?.receive();
              if (datagram != null) {
                try {
                  final data = utf8.decode(datagram.data, allowMalformed: true);
                  if (data.contains('NetworkTest') ||
                      data.contains('ThoughtEcho')) {
                    received = true;
                    final previewLen = data.length < 100 ? data.length : 100;
                    result.addStep(
                      '接收测试消息',
                      true,
                      '来自 ${datagram.address.address}:${datagram.port} -> ${data.substring(0, previewLen)}...',
                    );
                    if (!completer.isCompleted) completer.complete();
                  }
                } catch (e) {
                  result.addStep('解析接收数据', false, '解析失败: $e');
                }
              }
            }
          });

          // 等待接收，最多2秒
          listenTimer = Timer(const Duration(milliseconds: 2000), () {
            if (!completer.isCompleted) completer.complete();
          });
          await completer.future;
          listenTimer.cancel();
          await subscription.cancel();

          if (!received) {
            result.addStep(
              '接收测试消息',
              false,
              '未在2秒内接收到组播包。可能原因：防火墙阻拦/网卡未启用组播/未在同一子网',
            );
          }
        } else {
          result.addStep('接收测试消息', false, '套接字为null，无法监听接收');
        }
      } catch (e) {
        result.addStep('发送/接收测试', false, '异常: $e');
      }
    } catch (e) {
      result.addStep('UDP组播测试', false, '测试失败: $e');
    } finally {
      for (final s in testSockets) {
        s.close();
      }
    }

    // 返回结果前，总结测试情况
    final successSteps = result.steps.where((s) => s.success).length;
    final totalSteps = result.steps.length;
    final successRate = (successSteps / totalSteps * 100).toStringAsFixed(1);

    result.addStep(
      '组播测试总结',
      successSteps == totalSteps,
      '测试完成: $successSteps/$totalSteps 成功 ($successRate%)',
    );

    logDebug('UDP组播测试结束: $successRate% 成功率');

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
            request.response.write(
              '{"status": "ok", "message": "Server is working"}',
            );
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
      final testContent =
          'ThoughtEcho Sync Test File\n时间: ${DateTime.now()}\n内容大小测试: ${'A' * 1000}';

      await testFile.writeAsString(testContent);
      result.addStep('创建测试文件', true, '文件大小: ${await testFile.length()} 字节');

      try {
        final readContent = await testFile.readAsString();
        result.addStep(
          '文件读取验证',
          readContent == testContent,
          readContent == testContent ? '内容匹配' : '内容不匹配',
        );
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
        final active = interfaces
            .where(
              (i) => i.addresses.any(
                (a) => a.type == InternetAddressType.IPv4 && !a.isLoopback,
              ),
            )
            .toList();
        result.addStep(
          '网络接口检查',
          active.isNotEmpty,
          '发现 ${active.length} 个活动接口',
        );
        for (final i in active) {
          final ipv4 = i.addresses
              .where((a) => a.type == InternetAddressType.IPv4 && !a.isLoopback)
              .map((a) => a.address)
              .join(', ');
          result.addStep('接口 ${i.name}', true, 'IP地址: $ipv4');
        }
      } catch (e) {
        result.addStep('网络接口检查', false, '检查失败: $e');
      }

      // 2. 回环连接（可能失败属正常）
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          80,
          timeout: const Duration(seconds: 2),
        );
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
  static Future<NetworkTestResult> testSyncServiceHealth({
    String host = '127.0.0.1',
    int port = 53318,
  }) async {
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

            final fpPreviewLen = (fingerprint ?? '').length < 10
                ? (fingerprint ?? '').length
                : 10;
            result.addStep(
              'INFO端点',
              true,
              '状态码: ${resp.statusCode}, 设备名称: ${alias ?? '未知'}, 指纹: ${(fingerprint ?? '').substring(0, fpPreviewLen)}...',
            );
          } catch (e) {
            result.addStep(
              'INFO端点',
              true,
              '状态码: ${resp.statusCode}, 响应解析失败: $e',
            );
          }
        } else {
          final previewLen = body.length < 256 ? body.length : 256;
          result.addStep(
            'INFO端点',
            false,
            '状态码: ${resp.statusCode}, 响应: ${body.substring(0, previewLen)}',
          );
        }
        client.close();
      } catch (e) {
        result.addStep('INFO端点', false, '请求失败: $e');
      }

      // 3. 检测备用端口 (53317)
      try {
        const backupPort = 53317;
        final client = HttpClient();
        final req = await client.get(
          host,
          backupPort,
          '/api/localsend/v2/info',
        );
        final resp = await req.close().timeout(const Duration(seconds: 2));
        await resp.transform(utf8.decoder).join(); // 读取响应体，确保响应被完全消费

        if (resp.statusCode == 200) {
          result.addStep('备用端口检查', true, '备用端口 $backupPort 上服务正常');
        } else {
          result.addStep(
            '备用端口检查',
            false,
            '备用端口 $backupPort 服务返回: ${resp.statusCode}',
          );
        }
        client.close();
      } catch (e) {
        result.addStep('备用端口检查', false, '备用端口检查失败: $e');
      }

      // 4. 伪造一次 prepare-upload（空数据，检查路由/错误码）
      try {
        final client = HttpClient();
        final req = await client.post(
          host,
          port,
          '/api/localsend/v2/prepare-upload',
        );
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
            'download': true,
          },
          'files': {
            'test1': {
              'id': 'test1',
              'fileName': 'test.txt',
              'size': 100,
              'fileType': 'text/plain',
            },
          },
        };

        req.write(jsonEncode(requestData));
        final resp = await req.close().timeout(const Duration(seconds: 3));

        final body = await resp.transform(utf8.decoder).join();
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          try {
            final jsonResponse = jsonDecode(body) as Map<String, dynamic>;
            final sessionId = jsonResponse['sessionId'] as String?;
            final sidLen = (sessionId ?? '').length < 8
                ? (sessionId ?? '').length
                : 8;
            result.addStep(
              'PREPARE端点',
              true,
              '状态码: ${resp.statusCode}, 创建会话ID: ${(sessionId ?? '').substring(0, sidLen)}...',
            );
          } catch (e) {
            result.addStep(
              'PREPARE端点',
              true,
              '状态码: ${resp.statusCode}, 但JSON解析失败: $e',
            );
          }
        } else {
          final previewLen = body.length < 100 ? body.length : 100;
          result.addStep(
            'PREPARE端点',
            resp.statusCode >= 200 && resp.statusCode < 500,
            '状态码: ${resp.statusCode}, 响应: ${body.substring(0, previewLen)}...',
          );
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
        final previewLen = body.length < 100 ? body.length : 100;
        result.addStep(
          '未知路由(404)',
          resp.statusCode == 404,
          '状态码: ${resp.statusCode}, 响应: ${body.substring(0, previewLen)}...',
        );
        client.close();
      } catch (e) {
        result.addStep('未知路由(404)', false, '请求失败: $e');
      }

      // 6. 总结服务状态
      final allSuccess = result.steps
          .where((s) => s.name != '未知路由(404)' && s.name != 'UDP端口检查')
          .every((s) => s.success);
      result.addStep(
        '服务状态总结',
        allSuccess,
        allSuccess ? '同步服务工作正常' : '同步服务存在问题，建议重启应用',
      );
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
      total += r.steps.length;
      passed += r.steps.where((s) => s.success).length;
    }
    final passRate = (passed / total * 100).toStringAsFixed(1);
    summary.addStep(
      '整体结果',
      true,
      '共 ${results.length} 个测试，$passed/$total 步骤通过（$passRate%）',
    );

    return [...results, summary];
  }
}

class NetworkTestResult {
  final String name;
  final List<NetworkTestStep> steps = [];

  NetworkTestResult(this.name);

  void addStep(String name, bool success, String details) {
    steps.add(NetworkTestStep(name: name, success: success, details: details));
  }
}

class NetworkTestStep {
  final String name;
  final bool success;
  final String details;

  NetworkTestStep({
    required this.name,
    required this.success,
    required this.details,
  });
}
