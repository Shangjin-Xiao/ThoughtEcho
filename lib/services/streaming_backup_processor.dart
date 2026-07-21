import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';
import '../utils/path_security_utils.dart';

/// 备份文件后台处理器
///
/// ZIP 条目使用流式磁盘 I/O，JSON 解码移至后台 isolate。
/// JSON 结果仍会完整驻留内存，不属于增量 JSON 解析。
class StreamingBackupProcessor {
  /// 在后台 isolate 解析 JSON 备份文件，避免阻塞 UI isolate。
  static Future<Map<String, dynamic>> parseJsonBackupStreaming(
    String filePath, {
    Function(String status)? onStatusUpdate,
    bool Function()? shouldCancel,
  }) async {
    onStatusUpdate?.call('正在解析备份文件...');

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('备份文件不存在: $filePath');
    }

    final fileSize = await file.length();
    logDebug('备份文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');

    if (shouldCancel?.call() == true) {
      throw Exception('操作已取消');
    }
    onStatusUpdate?.call('正在后台解析JSON数据...');

    try {
      final result = await Isolate.run(
        () async => await _decodeJsonFile(filePath),
      );
      if (shouldCancel?.call() == true) {
        throw Exception('操作已取消');
      }
      return result;
    } catch (e) {
      throw Exception('JSON解析失败: $e');
    }
  }

  static Future<Map<String, dynamic>> _decodeJsonFile(String filePath) async {
    return json.decode(await File(filePath).readAsString())
        as Map<String, dynamic>;
  }

  /// 流式处理ZIP备份文件
  static Future<Map<String, dynamic>> processZipBackupStreaming(
    String filePath, {
    Function(String status)? onStatusUpdate,
    Function(int current, int total)? onProgress,
    bool Function()? shouldCancel,
    bool extractMediaFiles = true,
  }) async {
    onStatusUpdate?.call('正在处理ZIP备份文件...');

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('备份文件不存在: $filePath');
    }

    final fileSize = await file.length();
    logDebug('ZIP备份文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');

    if (shouldCancel?.call() == true) {
      throw Exception('操作已取消');
    }
    onStatusUpdate?.call('正在后台解压并解析备份文件...');
    onProgress?.call(0, 100);

    final appDirectoryPath = extractMediaFiles
        ? (await getApplicationDocumentsDirectory()).path
        : '';
    final map = await Isolate.run(
      () => _decodeZipBackup(filePath, appDirectoryPath, extractMediaFiles),
    );

    if (shouldCancel?.call() == true) {
      throw Exception('操作已取消');
    }
    onProgress?.call(100, 100);
    return map;
  }

  static Map<String, dynamic> _decodeZipBackup(
    String filePath,
    String appDirectoryPath,
    bool extractMediaFiles,
  ) {
    final inputStream = InputFileStream(filePath);
    try {
      final archive = ZipDecoder().decodeStream(inputStream);
      ArchiveFile? dataFile;
      for (final file in archive) {
        if (file.name == 'backup_data.json' || file.name == 'data.json') {
          dataFile = file;
          break;
        }
      }
      if (dataFile == null) {
        throw Exception('备份文件中未找到数据文件 (backup_data.json 或 data.json)');
      }

      final map =
          json.decode(utf8.decode(dataFile.content as List<int>))
              as Map<String, dynamic>;

      if (extractMediaFiles) {
        for (final file in archive) {
          if (!file.isFile || file.name == dataFile.name) continue;

          try {
            final normalizedName = file.name.replaceAll('/', p.separator);
            final safeRelativePath = _normalizeSafeRelativePath(normalizedName);
            if (safeRelativePath == null) continue;

            final targetPath = p.join(appDirectoryPath, safeRelativePath);
            PathSecurityUtils.validateExtractionPath(
              targetPath,
              appDirectoryPath,
            );
            Directory(p.dirname(targetPath)).createSync(recursive: true);
            final outputStream = OutputFileStream(targetPath);
            try {
              file.writeContent(outputStream);
            } finally {
              outputStream.closeSync();
            }
          } catch (_) {
            // 单个媒体文件损坏不应阻止结构化数据还原。
          }
        }
      }
      return map;
    } finally {
      inputStream.closeSync();
    }
  }

  /// 检查备份文件类型
  static Future<String> detectBackupType(String filePath) async {
    logDebug('检测备份文件类型: $filePath');
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    final extension = filePath.toLowerCase().split('.').last;
    logDebug('文件扩展名: $extension');
    if (extension == 'zip') {
      logDebug('根据扩展名识别为ZIP文件');
      return 'zip';
    } else if (extension == 'json') {
      logDebug('根据扩展名识别为JSON文件');
      return 'json';
    } else {
      // 尝试读取文件头判断
      logDebug('扩展名未知，尝试读取文件头判断...');
      final bytes = await file.openRead(0, 4).first;
      if (bytes.length >= 4) {
        logDebug(
          '文件头字节: ${bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}',
        );
        // ZIP文件魔数: PK (0x504B)
        if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
          logDebug('根据文件头识别为ZIP文件');
          return 'zip';
        }
        // JSON文件通常以 { 或 [ 开始
        final firstChar = String.fromCharCode(bytes[0]);
        if (firstChar == '{' || firstChar == '[') {
          logDebug('根据文件头识别为JSON文件');
          return 'json';
        }
      }
    }

    throw Exception('无法识别的备份文件格式');
  }

  static String? _normalizeSafeRelativePath(String relativePath) {
    final normalized = p.normalize(relativePath);

    if (normalized.isEmpty || normalized == '.' || normalized == p.separator) {
      return null;
    }

    if (p.isAbsolute(normalized)) {
      return null;
    }

    final segments = p.split(normalized);
    if (segments.any((segment) => segment == '..' || segment.isEmpty)) {
      return null;
    }

    return normalized;
  }

  /// 验证备份文件完整性
  static Future<bool> validateBackupFile(String filePath) async {
    try {
      logDebug('开始验证备份文件: $filePath');
      final type = await detectBackupType(filePath);
      logDebug('检测到备份文件类型: $type');

      if (type == 'json') {
        // 验证JSON文件 — 对于小文件直接解析，大文件检查头部
        logDebug('验证JSON备份文件...');
        final file = File(filePath);
        final fileSize = await file.length();
        if (fileSize < 10 * 1024 * 1024) {
          // 10MB以下直接验证
          final isValid = await Isolate.run(
            () async => await _isValidJsonBackup(filePath),
          );
          logDebug('JSON备份文件验证${isValid ? '成功' : '失败'}');
          return isValid;
        } else {
          // 大文件：检查文件头是否为合法JSON
          final bytes = await file.openRead(0, 1).first;
          final firstChar = String.fromCharCode(bytes[0]);
          final isValid = firstChar == '{';
          logDebug('大JSON备份文件头部验证${isValid ? '成功' : '失败'}');
          return isValid;
        }
      } else if (type == 'zip') {
        // 轻量验证ZIP文件：仅检查结构和数据文件是否存在
        logDebug('验证ZIP备份文件...');
        final hasDataFile = await Isolate.run(
          () => _zipContainsBackupData(filePath),
        );
        logDebug('ZIP备份文件验证${hasDataFile ? '成功' : '失败：未找到数据文件'}');
        return hasDataFile;
      }

      logDebug('不支持的备份文件类型: $type');
      return false;
    } catch (e) {
      logDebug('备份文件验证失败: $e');
      return false;
    }
  }

  static Future<bool> _isValidJsonBackup(String filePath) async {
    return json.decode(await File(filePath).readAsString())
        is Map<String, dynamic>;
  }

  static bool _zipContainsBackupData(String filePath) {
    final inputStream = InputFileStream(filePath);
    try {
      return ZipDecoder()
          .decodeStream(inputStream)
          .any(
            (file) =>
                file.name == 'backup_data.json' || file.name == 'data.json',
          );
    } finally {
      inputStream.closeSync();
    }
  }

  /// 获取备份文件信息
  static Future<Map<String, dynamic>> getBackupInfo(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    final fileSize = await file.length();
    final type = await detectBackupType(filePath);
    final lastModified = await file.lastModified();

    return {
      'file_path': filePath,
      'file_size': fileSize,
      'file_size_mb': (fileSize / 1024 / 1024).toStringAsFixed(2),
      'type': type,
      'last_modified': lastModified.toIso8601String(),
      'is_large_file': fileSize > 50 * 1024 * 1024, // 50MB
    };
  }
}
