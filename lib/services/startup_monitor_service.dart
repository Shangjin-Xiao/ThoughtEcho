import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../utils/app_logger.dart';

/// 启动监控服务
/// 监控应用启动过程，检测CPU和内存使用情况，帮助诊断启动问题
class StartupMonitorService {
  static const String _monitorLogFileName = 'startup_monitor.log';
  static const int _maxPerformanceDataSize = 1000; // 限制性能数据最大条数
  static bool _isMonitoring = false;
  static File? _monitorLogFile;
  static Timer? _monitorTimer;
  static DateTime? _startupTime;
  static final List<Map<String, dynamic>> _performanceData = [];

  /// 开始监控启动过程
  static Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    _startupTime = DateTime.now();
    _isMonitoring = true;

    try {
      // 创建监控日志文件
      await _createMonitorLogFile();

      // 记录启动开始
      await _logMonitorData('启动监控开始', {
        'timestamp': _startupTime!.toIso8601String(),
        'platform': Platform.operatingSystem,
        'version': Platform.operatingSystemVersion,
      });

      // 启动性能监控定时器
      _startPerformanceMonitoring();

      // 设置启动超时检测
      _setupStartupTimeout();
    } catch (e) {
      logError('启动监控初始化失败: $e', error: e, source: 'StartupMonitor');
    }
  }

  /// 停止监控
  static Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;

    _isMonitoring = false;
    _monitorTimer?.cancel();

    if (_startupTime != null) {
      final duration = DateTime.now().difference(_startupTime!);
      await _logMonitorData('启动监控结束', {
        'duration_ms': duration.inMilliseconds,
        'success': true,
      });
    }

    // 生成启动报告
    await _generateStartupReport();
  }

  /// 记录启动步骤
  static Future<void> recordStep(String step,
      {Map<String, dynamic>? data}) async {
    if (!_isMonitoring) return;

    final stepData = {
      'step': step,
      'timestamp': DateTime.now().toIso8601String(),
      ...?data,
    };

    if (_startupTime != null) {
      stepData['elapsed_ms'] =
          DateTime.now().difference(_startupTime!).inMilliseconds;
    }

    await _logMonitorData('启动步骤', stepData);
  }

  /// 创建监控日志文件
  static Future<void> _createMonitorLogFile() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final debugDir = Directory(path.join(appDir.path, 'debug'));

      if (!await debugDir.exists()) {
        await debugDir.create(recursive: true);
      }

      _monitorLogFile = File(path.join(debugDir.path, _monitorLogFileName));

      // 清空之前的监控日志
      await _monitorLogFile!.writeAsString('');
    } catch (e) {
      logError('创建监控日志文件失败: $e', error: e, source: 'StartupMonitor');
    }
  }

  /// 记录监控数据
  static Future<void> _logMonitorData(
      String event, Map<String, dynamic> data) async {
    try {
      final logEntry = {
        'event': event,
        'timestamp': DateTime.now().toIso8601String(),
        'data': data,
      };

      _performanceData.add(logEntry);

      // 限制性能数据大小，防止内存泄漏
      if (_performanceData.length > _maxPerformanceDataSize) {
        _performanceData.removeAt(0); // 移除最旧的条目
      }

      if (_monitorLogFile != null) {
        final logLine =
            '${logEntry['timestamp']} [$event] ${data.toString()}\n';
        await _monitorLogFile!.writeAsString(logLine, mode: FileMode.append);
      }
    } catch (e) {
      // 静默处理日志写入错误
    }
  }

  /// 启动性能监控
  static void _startPerformanceMonitoring() {
    _monitorTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!_isMonitoring) {
        timer.cancel();
        return;
      }

      try {
        // 获取内存使用情况（简化版本）
        final memoryData = await _getMemoryUsage();

        await _logMonitorData('性能数据', {
          'memory_mb': memoryData['memory_mb'],
          'elapsed_ms': _startupTime != null
              ? DateTime.now().difference(_startupTime!).inMilliseconds
              : 0,
        });
      } catch (e) {
        // 静默处理性能监控错误
      }
    });
  }

  /// 获取内存使用情况
  static Future<Map<String, dynamic>> _getMemoryUsage() async {
    try {
      if (Platform.isWindows) {
        // 尝试使用更可靠的wmic命令获取内存使用
        try {
          final wmicResult = await Process.run('wmic', [
            'process',
            'where',
            'ProcessId=$pid',
            'get',
            'WorkingSetSize',
            '/format:value'
          ]);

          if (wmicResult.exitCode == 0) {
            final output = wmicResult.stdout.toString();
            final match = RegExp(r'WorkingSetSize=(\d+)').firstMatch(output);
            if (match != null) {
              final memoryBytes = int.tryParse(match.group(1)!) ?? 0;
              final memoryMB = (memoryBytes / (1024 * 1024)).round();
              return {'memory_mb': memoryMB};
            }
          }
        } catch (wmicError) {
          logDebug('WMIC命令获取内存失败，尝试tasklist: $wmicError');
        }

        // 备用方案：使用改进的tasklist命令解析
        final result = await Process.run(
            'tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH']);

        if (result.exitCode == 0) {
          final output = result.stdout.toString().trim();
          if (output.isNotEmpty) {
            // 更健壮的CSV解析，处理不同语言环境
            final lines = output.split('\n');
            for (final line in lines) {
              if (line.trim().isNotEmpty) {
                // 使用正则表达式提取内存值，避免依赖CSV格式
                final memoryMatch = RegExp(r'[\d,]+\s*K').firstMatch(line);
                if (memoryMatch != null) {
                  final memoryStr = memoryMatch
                      .group(0)!
                      .replaceAll(RegExp(r'[^\d]'), ''); // 只保留数字
                  final memoryKB = int.tryParse(memoryStr) ?? 0;
                  if (memoryKB > 0) {
                    return {'memory_mb': (memoryKB / 1024).round()};
                  }
                }
              }
            }
          }
        } else {
          logDebug(
              'tasklist命令执行失败，退出码: ${result.exitCode}，错误: ${result.stderr}');
        }
      }
    } catch (e) {
      logDebug('获取内存使用情况失败: $e');
    }

    logDebug('无法获取内存使用情况，返回未知状态');
    return {'memory_mb': -1}; // 返回-1表示获取失败，而不是0
  }

  /// 设置启动超时检测
  static void _setupStartupTimeout() {
    Timer(const Duration(seconds: 30), () async {
      if (_isMonitoring) {
        await _logMonitorData('启动超时警告', {
          'timeout_seconds': 30,
          'message': '应用启动时间超过30秒，可能存在问题',
        });

        // 生成紧急报告
        await _generateEmergencyReport();
      }
    });
  }

  /// 生成启动报告
  static Future<void> _generateStartupReport() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final debugDir = Directory(path.join(appDir.path, 'debug'));
      final reportFile = File(path.join(debugDir.path, 'startup_report.txt'));

      final buffer = StringBuffer();
      buffer.writeln('=== ThoughtEcho 启动性能报告 ===');
      buffer.writeln('生成时间: ${DateTime.now().toLocal()}');
      buffer.writeln('');

      if (_startupTime != null) {
        final totalDuration = DateTime.now().difference(_startupTime!);
        buffer.writeln('总启动时间: ${totalDuration.inMilliseconds}ms');
        buffer.writeln('');
      }

      buffer.writeln('性能数据:');
      for (final data in _performanceData) {
        buffer
            .writeln('${data['timestamp']} [${data['event']}] ${data['data']}');
      }

      await reportFile.writeAsString(buffer.toString());

      // 如果是Windows平台，也在桌面创建报告
      if (Platform.isWindows) {
        await _createDesktopReport(buffer.toString());
      }
    } catch (e) {
      logError('生成启动报告失败: $e', error: e, source: 'StartupMonitor');
    }
  }

  /// 生成紧急报告
  static Future<void> _generateEmergencyReport() async {
    try {
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home == null) return;

      final desktop = Directory(path.join(home, 'Desktop'));
      if (!await desktop.exists()) return;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final emergencyFile =
          File(path.join(desktop.path, 'ThoughtEcho_启动超时报告_$timestamp.txt'));

      final buffer = StringBuffer();
      buffer.writeln('=== ThoughtEcho 启动超时紧急报告 ===');
      buffer.writeln('生成时间: ${DateTime.now().toLocal()}');
      buffer.writeln('');
      buffer.writeln('警告: 应用启动时间超过30秒，可能存在以下问题:');
      buffer.writeln('1. 系统资源不足');
      buffer.writeln('2. 数据库初始化卡住');
      buffer.writeln('3. 网络服务初始化超时');
      buffer.writeln('4. Flutter引擎初始化失败');
      buffer.writeln('');
      buffer.writeln('建议解决方案:');
      buffer.writeln('1. 重启应用');
      buffer.writeln('2. 检查系统内存使用情况');
      buffer.writeln('3. 暂时断开网络连接后重试');
      buffer.writeln('4. 查看详细日志文件');
      buffer.writeln('');

      if (_performanceData.isNotEmpty) {
        buffer.writeln('最近性能数据:');
        final recentData = _performanceData.take(10);
        for (final data in recentData) {
          buffer.writeln(
              '${data['timestamp']} [${data['event']}] ${data['data']}');
        }
      }

      await emergencyFile.writeAsString(buffer.toString());
    } catch (e) {
      // 静默处理紧急报告生成错误
    }
  }

  /// 在桌面创建报告
  static Future<void> _createDesktopReport(String content) async {
    try {
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home == null) return;

      final desktop = Directory(path.join(home, 'Desktop'));
      if (!await desktop.exists()) return;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final desktopFile =
          File(path.join(desktop.path, 'ThoughtEcho_启动报告_$timestamp.txt'));

      await desktopFile.writeAsString(content);
    } catch (e) {
      // 静默处理桌面报告创建错误
    }
  }
}
