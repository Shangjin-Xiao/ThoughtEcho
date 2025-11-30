import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:thoughtecho/services/unified_log_service.dart';

/// Windows启动调试服务
/// 专门用于Windows平台的启动调试和错误诊断
class WindowsStartupDebugService {
  static const String _debugLogFileName = 'windows_startup_debug.log';
  static const String _crashReportFileName = 'crash_report.json';
  static const String _initProgressFileName = 'init_progress.json';

  static bool _isInitialized = false;
  static File? _debugLogFile;
  static final List<String> _initSteps = [];
  static final Map<String, dynamic> _debugInfo = {};

  /// 初始化调试服务
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 获取应用文档目录
      final appDir = await getApplicationDocumentsDirectory();
      final debugDir = Directory(path.join(appDir.path, 'debug'));

      // 确保调试目录存在
      if (!await debugDir.exists()) {
        await debugDir.create(recursive: true);
      }

      // 创建调试日志文件
      _debugLogFile = File(path.join(debugDir.path, _debugLogFileName));

      // 记录调试会话开始
      await _writeDebugLog('=== Windows 启动调试会话开始 ===');
      await _writeDebugLog('时间: ${DateTime.now().toIso8601String()}');
      await _writeDebugLog('Flutter版本: ${kDebugMode ? 'Debug' : 'Release'}');
      await _writeDebugLog(
        '平台: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      );
      await _writeDebugLog('进程ID: ${Platform.resolvedExecutable}');

      _isInitialized = true;
      await _writeDebugLog('调试服务初始化完成');
    } catch (e) {
      // 静默处理初始化失败
    }
  }

  /// 记录初始化步骤
  static Future<void> recordInitStep(
    String step, {
    String? details,
    bool success = true,
  }) async {
    if (!_isInitialized) await initialize();

    final timestamp = DateTime.now().toIso8601String();
    final status = success ? '✓' : '✗';
    final logEntry =
        '[$timestamp] $status $step${details != null ? ' - $details' : ''}';

    _initSteps.add(logEntry);
    await _writeDebugLog(logEntry);

    // 同时保存进度到JSON文件
    await _saveInitProgress();
  }

  /// 记录调试信息
  static Future<void> recordDebugInfo(String key, dynamic value) async {
    if (!_isInitialized) await initialize();

    _debugInfo[key] = value;
    await _writeDebugLog('调试信息[$key]: $value');
  }

  /// 记录崩溃报告
  static Future<void> recordCrash(
    String error,
    StackTrace? stackTrace, {
    String? context,
  }) async {
    if (!_isInitialized) await initialize();

    final crashReport = {
      'timestamp': DateTime.now().toIso8601String(),
      'error': error,
      'stackTrace': stackTrace?.toString(),
      'context': context,
      'initSteps': _initSteps,
      'debugInfo': _debugInfo,
      'platform': {
        'os': Platform.operatingSystem,
        'version': Platform.operatingSystemVersion,
        'locale': Platform.localeName,
      },
    };

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final debugDir = Directory(path.join(appDir.path, 'debug'));
      final crashFile = File(path.join(debugDir.path, _crashReportFileName));

      await crashFile.writeAsString(json.encode(crashReport));
      await _writeDebugLog('崩溃报告已保存: ${crashFile.path}');
    } catch (e) {
      await _writeDebugLog('保存崩溃报告失败: $e');
    }
  }

  /// 记录FFI相关信息
  static Future<void> recordFFIInfo() async {
    try {
      await recordDebugInfo('is_windows', Platform.isWindows);
      await recordDebugInfo('executable_path', Platform.resolvedExecutable);
      await recordDebugInfo(
        'environment_path',
        Platform.environment['PATH']?.substring(0, 200),
      );

      // 检查DLL文件
      final exeDir = path.dirname(Platform.resolvedExecutable);
      await recordDebugInfo('exe_directory', exeDir);

      // 检查常见的SQLite相关文件
      final sqliteFiles = ['sqlite3.dll', 'msvcp140.dll', 'vcruntime140.dll'];
      for (final fileName in sqliteFiles) {
        final file = File(path.join(exeDir, fileName));
        await recordDebugInfo('file_exists_$fileName', await file.exists());
      }
    } catch (e) {
      await recordDebugInfo('ffi_info_error', e.toString());
    }
  }

  /// 记录数据库初始化信息
  static Future<void> recordDatabaseInfo(String dbPath, {String? error}) async {
    await recordDebugInfo('database_path', dbPath);
    if (error != null) {
      await recordDebugInfo('database_error', error);
    } else {
      final dbFile = File(dbPath);
      await recordDebugInfo('database_exists', await dbFile.exists());
      if (await dbFile.exists()) {
        final stat = await dbFile.stat();
        await recordDebugInfo('database_size', stat.size);
        await recordDebugInfo(
          'database_modified',
          stat.modified.toIso8601String(),
        );
      }
    }
  }

  /// 生成诊断报告
  static Future<String> generateDiagnosticReport() async {
    if (!_isInitialized) await initialize();

    final report = StringBuffer();
    report.writeln('=== Windows 启动诊断报告 ===');
    report.writeln('生成时间: ${DateTime.now().toIso8601String()}');
    report.writeln();

    report.writeln('平台信息:');
    report.writeln('  操作系统: ${Platform.operatingSystem}');
    report.writeln('  版本: ${Platform.operatingSystemVersion}');
    report.writeln('  区域: ${Platform.localeName}');
    report.writeln('  可执行文件: ${Platform.resolvedExecutable}');
    report.writeln();

    report.writeln('初始化步骤:');
    for (final step in _initSteps) {
      report.writeln('  $step');
    }
    report.writeln();

    report.writeln('调试信息:');
    _debugInfo.forEach((key, value) {
      report.writeln('  $key: $value');
    });
    report.writeln();

    // 添加日志统计
    try {
      final logService = UnifiedLogService.instance;
      final logSummary = logService.getLogSummary();
      report.writeln('日志统计:');
      logSummary.forEach((key, value) {
        report.writeln('  $key: $value');
      });
    } catch (e) {
      report.writeln('获取日志统计失败: $e');
    }

    return report.toString();
  }

  /// 导出所有调试文件到桌面
  static Future<String?> exportDebugFiles() async {
    try {
      // 获取桌面路径
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home == null) return null;

      final desktop = Directory(path.join(home, 'Desktop'));
      if (!await desktop.exists()) return null;

      // 创建导出文件夹
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportDir = Directory(
        path.join(desktop.path, 'ThoughtEcho_Debug_$timestamp'),
      );
      await exportDir.create();

      // 复制调试日志
      if (_debugLogFile != null && await _debugLogFile!.exists()) {
        final targetFile = File(path.join(exportDir.path, _debugLogFileName));
        await _debugLogFile!.copy(targetFile.path);
      }

      // 生成诊断报告
      final diagnosticReport = await generateDiagnosticReport();
      final reportFile = File(
        path.join(exportDir.path, 'diagnostic_report.txt'),
      );
      await reportFile.writeAsString(diagnosticReport);

      // 复制日志数据库文件
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final logDbPath = path.join(appDir.path, 'databases', 'logs.db');
        final logDbFile = File(logDbPath);
        if (await logDbFile.exists()) {
          final targetLogDb = File(path.join(exportDir.path, 'logs.db'));
          await logDbFile.copy(targetLogDb.path);
        }
      } catch (e) {
        await _writeDebugLog('复制日志数据库失败: $e');
      }

      // 复制主数据库文件
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final mainDbPath = path.join(
          appDir.path,
          'databases',
          'app_database.db',
        );
        final mainDbFile = File(mainDbPath);
        if (await mainDbFile.exists()) {
          final targetMainDb = File(
            path.join(exportDir.path, 'app_database.db'),
          );
          await mainDbFile.copy(targetMainDb.path);
        }
      } catch (e) {
        await _writeDebugLog('复制主数据库失败: $e');
      }

      await _writeDebugLog('调试文件已导出到: ${exportDir.path}');
      return exportDir.path;
    } catch (e) {
      await _writeDebugLog('导出调试文件失败: $e');
      return null;
    }
  }

  /// 检查Windows运行时依赖
  static Future<void> checkWindowsRuntime() async {
    try {
      await recordInitStep('检查Windows运行时依赖');

      // 检查Visual C++ Redistributable
      final vcRedistKeys = [
        r'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
        r'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86',
      ];

      for (final key in vcRedistKeys) {
        try {
          final result = await Process.run('reg', [
            'query',
            'HKEY_LOCAL_MACHINE\\$key',
          ], runInShell: true);
          await recordDebugInfo(
            'vcredist_$key',
            result.exitCode == 0 ? 'found' : 'not_found',
          );
        } catch (e) {
          await recordDebugInfo('vcredist_check_error', e.toString());
        }
      }

      await recordInitStep('Windows运行时依赖检查完成', success: true);
    } catch (e) {
      await recordInitStep(
        'Windows运行时依赖检查失败',
        details: e.toString(),
        success: false,
      );
    }
  }

  /// 私有方法：写入调试日志
  static Future<void> _writeDebugLog(String message) async {
    try {
      if (_debugLogFile != null) {
        final timestamp = DateTime.now().toIso8601String();
        await _debugLogFile!.writeAsString(
          '[$timestamp] $message\n',
          mode: FileMode.append,
        );
      }
    } catch (e) {
      // 静默处理写入错误，避免递归
    }
  }

  /// 保存初始化进度
  static Future<void> _saveInitProgress() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final debugDir = Directory(path.join(appDir.path, 'debug'));
      final progressFile = File(
        path.join(debugDir.path, _initProgressFileName),
      );

      final progressData = {
        'timestamp': DateTime.now().toIso8601String(),
        'steps': _initSteps,
        'debugInfo': _debugInfo,
      };

      await progressFile.writeAsString(json.encode(progressData));
    } catch (e) {
      await _writeDebugLog('保存初始化进度失败: $e');
    }
  }

  /// 获取调试文件路径
  static Future<String?> getDebugLogPath() async {
    if (_debugLogFile != null) {
      return _debugLogFile!.path;
    }
    return null;
  }

  /// 创建启动指南文件
  /// 在Windows启动失败时提供用户可读的调试指南
  static Future<void> createStartupGuide() async {
    try {
      // 获取桌面路径
      final home =
          Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home == null) return;

      final desktop = Directory(path.join(home, 'Desktop'));
      if (!await desktop.exists()) return;

      // 创建启动指南文件
      final guideFile = File(
        path.join(desktop.path, 'ThoughtEcho_启动问题解决指南.txt'),
      );

      final guide =
          '''
=== ThoughtEcho 启动问题解决指南 ===
生成时间: ${DateTime.now().toLocal()}

如果 ThoughtEcho 应用无法正常启动，请按以下步骤操作：

1. 重启应用
   - 完全关闭 ThoughtEcho 应用
   - 等待 5-10 秒后重新启动
   - 如果问题持续，请继续下一步

2. 检查系统要求
   - 确保您的 Windows 系统为 Windows 10 或更高版本
   - 确认系统已安装最新的 Visual C++ Redistributable
   - 下载地址: https://aka.ms/vs/17/release/vc_redist.x64.exe

3. 清理应用数据（如果上述步骤无效）
   - 按 Win+R 打开运行对话框
   - 输入: %USERPROFILE%\\Documents
   - 找到 ThoughtEcho 文件夹
   - 将其重命名为 ThoughtEcho_backup_${DateTime.now().millisecondsSinceEpoch}
   - 重新启动应用

4. 查看调试信息
   - 调试日志路径: ${await getDebugLogPath() ?? '未找到'}
   - 如果桌面上有 ThoughtEcho_Debug_* 文件夹，请查看其中的诊断报告

5. 联系技术支持
   如果以上步骤都无法解决问题，请：
   - 保存桌面上的 ThoughtEcho_Debug_* 文件夹
   - 联系开发者并提供调试文件
   - 描述问题发生的具体情况

当前系统信息:
- 操作系统: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
- 应用版本: Flutter ${kDebugMode ? 'Debug' : 'Release'} 模式
- 生成时间: ${DateTime.now().toIso8601String()}

注意: 这是自动生成的调试指南，旨在帮助解决启动问题。
''';

      await guideFile.writeAsString(guide);
      await _writeDebugLog('启动指南已创建: ${guideFile.path}');
    } catch (e) {
      await _writeDebugLog('创建启动指南失败: $e');
    }
  }

  /// 刷新并同步所有日志到磁盘
  /// 确保在应用崩溃前所有重要日志都被保存
  static Future<void> flushLogs() async {
    try {
      await _writeDebugLog('开始刷新日志到磁盘');

      // 1. 刷新当前调试日志
      if (_debugLogFile != null) {
        // 强制刷新文件系统缓存
        await _debugLogFile!.writeAsString(
          '',
          mode: FileMode.append,
          flush: true,
        );
      }

      // 2. 保存最终的初始化进度
      await _saveInitProgress();

      // 3. 尝试刷新统一日志服务
      try {
        final logService = UnifiedLogService.instance;
        await logService.flushLogs();
        await _writeDebugLog('统一日志服务刷新完成');
      } catch (e) {
        await _writeDebugLog('统一日志服务刷新失败: $e');
      }

      // 4. 生成最终诊断报告
      try {
        final diagnosticReport = await generateDiagnosticReport();

        // 保存到应用目录
        final appDir = await getApplicationDocumentsDirectory();
        final debugDir = Directory(path.join(appDir.path, 'debug'));
        final finalReportFile = File(
          path.join(debugDir.path, 'final_diagnostic_report.txt'),
        );
        await finalReportFile.writeAsString(diagnosticReport);
        await _writeDebugLog('最终诊断报告已保存: ${finalReportFile.path}');
      } catch (e) {
        await _writeDebugLog('生成最终诊断报告失败: $e');
      }

      // 5. 记录刷新完成
      await _writeDebugLog('所有日志刷新完成');

      // 6. 最后再次强制刷新调试日志文件
      if (_debugLogFile != null) {
        await _debugLogFile!.writeAsString(
          '',
          mode: FileMode.append,
          flush: true,
        );
      }
    } catch (e) {
      // 即使刷新失败也要尝试记录
      try {
        await _writeDebugLog('日志刷新过程中发生错误: $e');
        if (_debugLogFile != null) {
          await _debugLogFile!.writeAsString(
            '',
            mode: FileMode.append,
            flush: true,
          );
        }
      } catch (_) {
        // 静默处理最后的错误
      }
    }
  }

  /// 清理旧的调试文件（可选的维护方法）
  static Future<void> cleanupOldDebugFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final debugDir = Directory(path.join(appDir.path, 'debug'));

      if (!await debugDir.exists()) return;

      final now = DateTime.now();
      final cutoffDate = now.subtract(const Duration(days: 7)); // 保留7天内的文件

      await for (final entity in debugDir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            try {
              await entity.delete();
              await _writeDebugLog('已删除旧调试文件: ${entity.path}');
            } catch (e) {
              await _writeDebugLog('删除旧调试文件失败: ${entity.path}, 错误: $e');
            }
          }
        }
      }
    } catch (e) {
      await _writeDebugLog('清理旧调试文件失败: $e');
    }
  }
}
