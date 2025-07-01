import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:thoughtecho/services/ai_analysis_database_service.dart';
import 'package:thoughtecho/services/database_service.dart';
import 'package:thoughtecho/services/media_file_service.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/utils/app_logger.dart';

/// 备份与恢复服务
///
/// 负责协调各个数据服务，将应用数据打包成一个.zip文件进行备份，
/// 或从备份文件中恢复数据。
class BackupService {
  final DatabaseService _databaseService;
  final SettingsService _settingsService;
  final AIAnalysisDatabaseService _aiAnalysisDbService;

  BackupService({
    required DatabaseService databaseService,
    required SettingsService settingsService,
    required AIAnalysisDatabaseService aiAnalysisDbService,
  }) : _databaseService = databaseService,
       _settingsService = settingsService,
       _aiAnalysisDbService = aiAnalysisDbService;

  static const String _backupDataFile = 'backup_data.json';
  static const String _backupVersion = '1.2.0'; // 版本更新，因为数据结构变化

  /// 导出所有应用数据
  ///
  /// [includeMediaFiles] - 是否在备份中包含媒体文件（图片等）
  /// [customPath] - 可选的自定义保存路径。如果提供，将保存到指定路径；否则创建在临时目录
  /// 返回最终备份文件的路径
  Future<String> exportAllData({
    required bool includeMediaFiles,
    String? customPath,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final backupId = DateTime.now().millisecondsSinceEpoch;
    final archivePath =
        customPath ??
        path.join(tempDir.path, 'thoughtecho_backup_$backupId.zip');

    try {
      final encoder = ZipFileEncoder();
      encoder.create(archivePath);

      // 1. 导出结构化数据 (笔记, 设置, AI历史) 到 JSON
      final backupData = await _gatherStructuredData(includeMediaFiles);
      final jsonData = jsonEncode(backupData);
      final jsonBytes = utf8.encode(jsonData);

      // 创建临时文件来存储JSON数据
      final jsonFile = File(path.join(tempDir.path, _backupDataFile));
      await jsonFile.writeAsBytes(jsonBytes);
      encoder.addFile(jsonFile);

      // 2. (可选) 导出媒体文件
      if (includeMediaFiles) {
        final mediaFiles = await MediaFileService.getAllMediaFilePaths();
        final appDir = await getApplicationDocumentsDirectory();

        for (final filePath in mediaFiles) {
          // 获取相对于应用文档目录的路径，以保持目录结构
          final relativePath = path.relative(filePath, from: appDir.path);
          final file = File(filePath);
          if (await file.exists()) {
            encoder.addFile(file, relativePath);
          }
        }
      }

      encoder.close();
      logDebug('数据导出成功，路径: $archivePath');
      return archivePath;
    } catch (e, s) {
      AppLogger.e('数据导出失败', error: e, stackTrace: s, source: 'BackupService');
      rethrow;
    }
  }

  /// 从备份文件导入数据
  ///
  /// [filePath] - 备份文件的路径 (.zip 或旧版 .json)
  /// [clearExisting] - 是否在导入前清空现有数据
  Future<void> importData(String filePath, {bool clearExisting = true}) async {
    // 处理旧版 JSON 备份文件
    if (path.extension(filePath).toLowerCase() == '.json') {
      logDebug('开始导入旧版JSON备份...');
      return await _handleLegacyImport(filePath, clearExisting: clearExisting);
    }

    // 处理新的 ZIP 备份文件
    final tempDir = await getTemporaryDirectory();
    final importDir = Directory(
      path.join(
        tempDir.path,
        'import_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    if (await importDir.exists()) {
      await importDir.delete(recursive: true);
    }
    await importDir.create(recursive: true);

    InputFileStream? inputStream;
    try {
      // 1. 解压备份包 - 使用流式处理优化内存使用
      inputStream = InputFileStream(filePath);
      final archive = ZipDecoder().decodeBuffer(inputStream);

      // 2. 恢复结构化数据
      final backupDataFile = archive.findFile(_backupDataFile);
      if (backupDataFile == null) {
        throw Exception('备份文件无效: 未找到 backup_data.json');
      }

      final backupData = jsonDecode(
        utf8.decode(backupDataFile.content as List<int>),
      );
      await _restoreStructuredData(backupData, clearExisting: clearExisting);

      // 3. 恢复媒体文件
      final mediaFilesExist = archive.files.any(
        (file) => file.name.contains('/'),
      );

      if (mediaFilesExist) {
        List<String>? clearedMediaPaths;

        try {
          // 清理现有的媒体文件（记录已清理的路径用于回滚）
          if (clearExisting) {
            clearedMediaPaths = await MediaFileService.getAllMediaFilePaths();
            for (final p in clearedMediaPaths) {
              await MediaFileService.deleteMediaFile(p);
            }
          }

          // 将备份中的媒体文件解压到临时目录
          for (final file in archive.files) {
            if (!file.isFile || file.name == _backupDataFile) continue;
            final targetPath = path.join(importDir.path, file.name);
            final targetFile = File(targetPath);
            await targetFile.parent.create(recursive: true);
            await targetFile.writeAsBytes(file.content as List<int>);
          }

          // 从临时目录恢复到应用目录
          final restoreSuccess = await MediaFileService.restoreMediaFiles(
            importDir.path,
          );
          if (!restoreSuccess) {
            throw Exception('媒体文件恢复失败');
          }

          logDebug('媒体文件恢复完成');
        } catch (mediaError) {
          // 媒体文件恢复失败时的错误处理
          logDebug('媒体文件恢复失败，将清理不完整状态: $mediaError');
          // 注意：这里不进行回滚，因为可能导致更复杂的状态
          rethrow;
        }
      }
    } catch (e, s) {
      AppLogger.e('数据导入失败', error: e, stackTrace: s, source: 'BackupService');
      rethrow;
    } finally {
      // 确保资源释放
      inputStream?.close();

      // 清理临时解压目录
      try {
        if (await importDir.exists()) {
          await importDir.delete(recursive: true);
        }
      } catch (cleanupError) {
        logDebug('清理临时目录失败: $cleanupError');
        // 清理失败不阻塞主流程
      }
    }
  }

  /// 验证备份文件是否有效
  Future<bool> validateBackupFile(String filePath) async {
    InputFileStream? inputStream;
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      // 验证新的 zip 格式
      if (path.extension(filePath).toLowerCase() == '.zip') {
        inputStream = InputFileStream(filePath);
        final archive = ZipDecoder().decodeBuffer(inputStream);
        // 核心验证：必须包含 backup_data.json 文件
        return archive.findFile(_backupDataFile) != null;
      }

      // 验证旧的 json 格式
      if (path.extension(filePath).toLowerCase() == '.json') {
        return await _databaseService.validateBackupFile(filePath);
      }

      return false;
    } catch (e) {
      AppLogger.e('无效的备份文件', error: e, source: 'BackupService');
      return false;
    } finally {
      // 确保流被正确关闭
      inputStream?.close();
    }
  }

  /// 聚合所有结构化数据到一个Map中
  Future<Map<String, dynamic>> _gatherStructuredData(
    bool includeMediaFiles,
  ) async {
    final notesData = await _databaseService.exportDataAsMap();
    final settingsData = _settingsService.getAllSettingsForBackup();
    final aiAnalysisData = await _aiAnalysisDbService.exportAnalysesAsList();

    // 处理笔记数据中的媒体文件路径
    Map<String, dynamic> processedNotesData = notesData;
    if (includeMediaFiles) {
      processedNotesData = await _convertMediaPathsInNotesForBackup(notesData);
    }

    return {
      'version': _backupVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'notes': processedNotesData,
      'settings': settingsData,
      'ai_analysis': aiAnalysisData,
    };
  }

  /// 从Map中恢复结构化数据
  Future<void> _restoreStructuredData(
    Map<String, dynamic> backupData, {
    bool clearExisting = true,
  }) async {
    // 如果选择清空，则先清空所有相关数据
    if (clearExisting) {
      await _databaseService.importDataFromMap({
        'categories': [],
        'quotes': [],
      }, clearExisting: true);
      await _aiAnalysisDbService.deleteAllAnalyses();
    }

    // 恢复笔记和分类
    if (backupData.containsKey('notes')) {
      Map<String, dynamic> notesData =
          backupData['notes'] as Map<String, dynamic>;

      // 检查是否包含媒体文件，如果是则转换路径
      final hasMediaFiles = await _checkBackupHasMediaFiles(backupData);
      if (hasMediaFiles) {
        notesData = await _convertMediaPathsInNotesForRestore(notesData);
      }

      await _databaseService.importDataFromMap(
        notesData,
        clearExisting: false, // 在这里总是false，因为上面已经处理过清空逻辑
      );
    }
    // 恢复设置
    if (backupData.containsKey('settings')) {
      await _settingsService.restoreAllSettingsFromBackup(
        backupData['settings'] as Map<String, dynamic>,
      );
    }
    // 恢复AI分析历史
    if (backupData.containsKey('ai_analysis')) {
      await _aiAnalysisDbService.importAnalysesFromList(
        (backupData['ai_analysis'] as List).cast<Map<String, dynamic>>(),
      );
    }
  }

  /// 处理旧版JSON备份文件的导入
  Future<void> _handleLegacyImport(
    String filePath, {
    bool clearExisting = true,
  }) async {
    final isValid = await _databaseService.validateBackupFile(filePath);
    if (!isValid) {
      throw Exception('无效的旧版备份文件。');
    }
    // 旧版备份只包含笔记和分类，直接调用databaseService导入
    await _databaseService.importData(filePath, clearExisting: clearExisting);
  }

  /// 检查备份数据是否包含媒体文件
  Future<bool> _checkBackupHasMediaFiles(
    Map<String, dynamic> backupData,
  ) async {
    // 检查版本信息和备份内容来判断是否包含媒体文件
    final version = backupData['version'] as String?;
    return version == _backupVersion;
  }

  /// 在备份时将笔记数据中的媒体文件绝对路径转换为相对路径
  Future<Map<String, dynamic>> _convertMediaPathsInNotesForBackup(
    Map<String, dynamic> notesData,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final appPath = appDir.path;

    // 深拷贝数据
    final processedData = Map<String, dynamic>.from(notesData);

    if (processedData.containsKey('quotes')) {
      final quotes = List<Map<String, dynamic>>.from(processedData['quotes']);

      for (final quote in quotes) {
        if (quote.containsKey('deltaContent') &&
            quote['deltaContent'] != null) {
          final deltaContent = quote['deltaContent'] as String;
          try {
            final deltaJson = jsonDecode(deltaContent);
            final convertedDelta = _convertDeltaMediaPaths(
              deltaJson,
              appPath,
              true,
            );
            quote['deltaContent'] = jsonEncode(convertedDelta);
          } catch (e) {
            logDebug('处理笔记 ${quote['id']} 的富文本内容时出错: $e');
            // 如果处理失败，保持原内容不变
          }
        }
      }

      processedData['quotes'] = quotes;
    }

    return processedData;
  }

  /// 在还原时将笔记数据中的媒体文件相对路径转换为当前环境的绝对路径
  Future<Map<String, dynamic>> _convertMediaPathsInNotesForRestore(
    Map<String, dynamic> notesData,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final appPath = appDir.path;

    // 深拷贝数据
    final processedData = Map<String, dynamic>.from(notesData);

    if (processedData.containsKey('quotes')) {
      final quotes = List<Map<String, dynamic>>.from(processedData['quotes']);

      for (final quote in quotes) {
        if (quote.containsKey('deltaContent') &&
            quote['deltaContent'] != null) {
          final deltaContent = quote['deltaContent'] as String;
          try {
            final deltaJson = jsonDecode(deltaContent);
            final convertedDelta = _convertDeltaMediaPaths(
              deltaJson,
              appPath,
              false,
            );
            quote['deltaContent'] = jsonEncode(convertedDelta);
          } catch (e) {
            logDebug('处理笔记 ${quote['id']} 的富文本内容时出错: $e');
            // 如果处理失败，保持原内容不变
          }
        }
      }

      processedData['quotes'] = quotes;
    }

    return processedData;
  }

  /// 递归处理 Delta JSON 中的媒体文件路径
  dynamic _convertDeltaMediaPaths(
    dynamic deltaJson,
    String appPath,
    bool toRelative,
  ) {
    if (deltaJson is Map) {
      final convertedMap = <String, dynamic>{};
      for (final entry in deltaJson.entries) {
        if (entry.key == 'insert' && entry.value is Map) {
          final insertMap = entry.value as Map;
          if (insertMap.containsKey('image') ||
              insertMap.containsKey('video')) {
            final convertedInsert = Map<String, dynamic>.from(insertMap);

            // 处理图片路径
            if (convertedInsert.containsKey('image')) {
              convertedInsert['image'] = _convertSingleMediaPath(
                convertedInsert['image'] as String,
                appPath,
                toRelative,
              );
            }

            // 处理视频路径
            if (convertedInsert.containsKey('video')) {
              convertedInsert['video'] = _convertSingleMediaPath(
                convertedInsert['video'] as String,
                appPath,
                toRelative,
              );
            }

            convertedMap[entry.key] = convertedInsert;
          } else if (insertMap.containsKey('custom')) {
            // 处理自定义embed (如音频)
            final customMap = insertMap['custom'] as Map?;
            if (customMap?.containsKey('audio') == true) {
              final convertedCustom = Map<String, dynamic>.from(customMap!);
              convertedCustom['audio'] = _convertSingleMediaPath(
                convertedCustom['audio'] as String,
                appPath,
                toRelative,
              );

              final convertedInsert = Map<String, dynamic>.from(insertMap);
              convertedInsert['custom'] = convertedCustom;
              convertedMap[entry.key] = convertedInsert;
            } else {
              convertedMap[entry.key] = entry.value;
            }
          } else {
            convertedMap[entry.key] = entry.value;
          }
        } else {
          convertedMap[entry.key] = _convertDeltaMediaPaths(
            entry.value,
            appPath,
            toRelative,
          );
        }
      }
      return convertedMap;
    } else if (deltaJson is List) {
      return deltaJson
          .map((item) => _convertDeltaMediaPaths(item, appPath, toRelative))
          .toList();
    } else {
      return deltaJson;
    }
  }

  /// 转换单个媒体文件路径
  String _convertSingleMediaPath(
    String originalPath,
    String appPath,
    bool toRelative,
  ) {
    try {
      if (toRelative) {
        // 备份时：绝对路径 -> 相对路径
        if (originalPath.startsWith(appPath)) {
          return path.relative(originalPath, from: appPath);
        }
        return originalPath; // 如果不是应用内路径，保持不变
      } else {
        // 还原时：相对路径 -> 绝对路径
        if (!path.isAbsolute(originalPath)) {
          return path.join(appPath, originalPath);
        }
        return originalPath; // 如果已经是绝对路径，保持不变
      }
    } catch (e) {
      logDebug('转换媒体文件路径失败: $originalPath, 错误: $e');
      return originalPath; // 如果转换失败，返回原路径
    }
  }
}
