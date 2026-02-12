import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../utils/app_logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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
    final buffer = <int>[];
    int processedBytes = 0;
    final totalSize = await file.length();

    await for (final chunk in stream) {
      if (shouldCancel?.call() == true) {
        throw Exception('操作已取消');
      }

      // 修复：收集字节而不是直接转换为字符
      buffer.addAll(chunk);
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
      // 修复：使用UTF-8解码避免中文乱码
      final jsonString = utf8.decode(buffer);
      return json.decode(jsonString) as Map<String, dynamic>;
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
    bool extractMediaFiles = true,
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

    // 查找数据文件 - 修复：使用正确的文件名
    ArchiveFile? dataFile;
    logDebug('ZIP文件包含的文件列表:');
    for (final file in archive) {
      logDebug('  - ${file.name} (${file.size} bytes)');
      if (file.name == 'backup_data.json' || file.name == 'data.json') {
        dataFile = file;
        logDebug('找到数据文件: ${file.name}');
        break;
      }
    }

    if (dataFile == null) {
      throw Exception('备份文件中未找到数据文件 (backup_data.json 或 data.json)');
    }

    onStatusUpdate?.call('正在解析备份数据...');

    // 解析JSON数据 - 修复：使用UTF-8解码避免中文乱码
    final jsonBytes = dataFile.content as List<int>;
    final jsonString = utf8.decode(jsonBytes);
    final map = json.decode(jsonString) as Map<String, dynamic>;

    // 提取媒体文件到应用目录 (排除数据文件本身 & 目录)
    if (extractMediaFiles) {
      final appDir = await getApplicationDocumentsDirectory();
      for (final f in archive) {
        if (f.isFile && f.name != dataFile.name) {
          try {
            // 将 ZIP 条目名中的正斜杠转换为当前平台的路径分隔符
            // ZIP 格式标准使用正斜杠，但在 Windows 上需要转换为反斜杠
            final normalizedName = f.name.replaceAll('/', p.separator);
            final safeRelativePath = _normalizeSafeRelativePath(normalizedName);
            if (safeRelativePath == null) {
              logWarning('跳过不安全的ZIP条目: ${f.name}',
                  source: 'StreamingBackupProcessor');
              continue;
            }

            final targetPath = p.join(appDir.path, safeRelativePath);
            final targetDir = Directory(p.dirname(targetPath));
            if (!await targetDir.exists()) {
              await targetDir.create(recursive: true);
            }
            final outFile = File(targetPath);
            await outFile.writeAsBytes(f.content as List<int>, flush: true);
            logDebug('已解压媒体文件: ${f.name} -> $targetPath');
          } catch (e) {
            logWarning('媒体文件解压失败: ${f.name}, $e',
                source: 'StreamingBackupProcessor');
          }
        }
      }
      logDebug('媒体文件已解压到应用目录', source: 'StreamingBackupProcessor');
    } else {
      logDebug('仅验证ZIP结构，跳过媒体文件解压', source: 'StreamingBackupProcessor');
    }

    return map;
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
        // 验证JSON文件
        logDebug('验证JSON备份文件...');
        await parseJsonBackupStreaming(filePath);
        logDebug('JSON备份文件验证成功');
        return true;
      } else if (type == 'zip') {
        // 验证ZIP文件
        logDebug('验证ZIP备份文件...');
        await processZipBackupStreaming(filePath, extractMediaFiles: false);
        logDebug('ZIP备份文件验证成功');
        return true;
      }

      logDebug('不支持的备份文件类型: $type');
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
