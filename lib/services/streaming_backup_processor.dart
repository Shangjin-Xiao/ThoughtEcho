import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../utils/app_logger.dart';

/// 流式备份处理器
///
/// 专门处理大备份文件的导入和导出，防止OOM
class StreamingBackupProcessor {
  /// 流式解析JSON备份文件
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

    // 对于小文件，直接读取
    if (fileSize < 10 * 1024 * 1024) {
      // 10MB以下
      onStatusUpdate?.call('读取小备份文件...');
      final content = await file.readAsString();
      return json.decode(content) as Map<String, dynamic>;
    }

    // 对于大文件，使用流式解析
    onStatusUpdate?.call('流式解析大备份文件...');
    return await _parseJsonStreaming(file, onStatusUpdate, shouldCancel);
  }

  /// 流式解析大JSON文件
  static Future<Map<String, dynamic>> _parseJsonStreaming(
    File file,
    Function(String status)? onStatusUpdate,
    bool Function()? shouldCancel,
  ) async {
    final stream = file.openRead();
    final buffer = StringBuffer();
    int processedBytes = 0;
    final totalSize = await file.length();

    await for (final chunk in stream) {
      if (shouldCancel?.call() == true) {
        throw Exception('操作已取消');
      }

      buffer.write(String.fromCharCodes(chunk));
      processedBytes += chunk.length;

      // 定期更新状态
      if (processedBytes % (1024 * 1024) == 0) {
        // 每1MB更新一次
        final progress = (processedBytes / totalSize * 100).toInt();
        onStatusUpdate?.call('解析进度: $progress%');

        // 短暂休息，让系统有机会回收内存
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    onStatusUpdate?.call('正在解析JSON数据...');

    try {
      return json.decode(buffer.toString()) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('JSON解析失败: $e');
    }
  }

  /// 流式处理ZIP备份文件
  static Future<Map<String, dynamic>> processZipBackupStreaming(
    String filePath, {
    Function(String status)? onStatusUpdate,
    Function(int current, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    onStatusUpdate?.call('正在处理ZIP备份文件...');

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('备份文件不存在: $filePath');
    }

    final fileSize = await file.length();
    logDebug('ZIP备份文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');

    // 读取ZIP文件
    final bytes = await _readFileInChunks(file, onStatusUpdate, shouldCancel);

    onStatusUpdate?.call('正在解压备份文件...');

    // 解压ZIP
    final archive = ZipDecoder().decodeBytes(bytes);

    // 查找数据文件
    ArchiveFile? dataFile;
    for (final file in archive) {
      if (file.name == 'data.json') {
        dataFile = file;
        break;
      }
    }

    if (dataFile == null) {
      throw Exception('备份文件中未找到数据文件');
    }

    onStatusUpdate?.call('正在解析备份数据...');

    // 解析JSON数据
    final jsonString = String.fromCharCodes(dataFile.content as List<int>);
    return json.decode(jsonString) as Map<String, dynamic>;
  }

  /// 分块读取文件
  static Future<Uint8List> _readFileInChunks(
    File file,
    Function(String status)? onStatusUpdate,
    bool Function()? shouldCancel,
  ) async {
    final totalSize = await file.length();
    final chunks = <Uint8List>[];
    int readBytes = 0;

    final stream = file.openRead();
    await for (final chunk in stream) {
      if (shouldCancel?.call() == true) {
        throw Exception('操作已取消');
      }

      chunks.add(Uint8List.fromList(chunk));
      readBytes += chunk.length;

      // 定期更新状态
      if (readBytes % (1024 * 1024) == 0) {
        // 每1MB更新一次
        final progress = (readBytes / totalSize * 100).toInt();
        onStatusUpdate?.call('读取进度: $progress%');

        // 短暂休息
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }

    // 合并所有块
    onStatusUpdate?.call('正在合并数据...');
    final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final result = Uint8List(totalLength);
    int offset = 0;

    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return result;
  }

  /// 检查备份文件类型
  static Future<String> detectBackupType(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    final extension = filePath.toLowerCase().split('.').last;
    if (extension == 'zip') {
      return 'zip';
    } else if (extension == 'json') {
      return 'json';
    } else {
      // 尝试读取文件头判断
      final bytes = await file.openRead(0, 4).first;
      if (bytes.length >= 4) {
        // ZIP文件魔数: PK (0x504B)
        if (bytes[0] == 0x50 && bytes[1] == 0x4B) {
          return 'zip';
        }
        // JSON文件通常以 { 或 [ 开始
        final firstChar = String.fromCharCode(bytes[0]);
        if (firstChar == '{' || firstChar == '[') {
          return 'json';
        }
      }
    }

    throw Exception('无法识别的备份文件格式');
  }

  /// 验证备份文件完整性
  static Future<bool> validateBackupFile(String filePath) async {
    try {
      final type = await detectBackupType(filePath);

      if (type == 'json') {
        // 验证JSON文件
        await parseJsonBackupStreaming(filePath);
        return true;
      } else if (type == 'zip') {
        // 验证ZIP文件
        await processZipBackupStreaming(filePath);
        return true;
      }

      return false;
    } catch (e) {
      logDebug('备份文件验证失败: $e');
      return false;
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
