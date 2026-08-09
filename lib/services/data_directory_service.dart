import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import '../utils/path_security_utils.dart';
import 'ai_analysis_database_service.dart';
import 'chat_session_service.dart';
import 'database_service.dart';
import 'large_file_manager.dart';

/// 迁移目标被拒绝的原因。
///
/// 供目录选择页映射为本地化文案，避免把服务内部的原始中文串直接展示给用户。
enum DataDirectoryTargetRejection {
  /// 新目录与当前数据目录相同，迁移无意义。
  sameDirectory,

  /// 新目录是当前数据目录的祖先（如 Documents 根目录），会把应用数据
  /// 重新摊在祖先目录下与用户文件混放。
  ancestorDirectory,

  /// 新目录位于当前数据目录内部，复制会把目标目录装进自己。
  nestedDirectory,
}

/// 数据目录管理服务（桌面平台专用）
/// 允许用户自定义应用数据存储位置，并处理数据迁移
class DataDirectoryService {
  static const String _customPathKey = 'custom_data_directory_path';
  static const String _isUsingCustomPathKey = 'is_using_custom_data_directory';
  static const String _legacyMigrationDoneKey = 'legacy_data_migration_done';
  static const String _appDataFolderName = 'ThoughtEcho';

  /// 获取默认的应用数据目录（Documents/ThoughtEcho）
  static Future<String> getDefaultDataDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    return path.join(docsDir.path, _appDataFolderName);
  }

  /// 获取当前使用的数据目录
  static Future<String> getCurrentDataDirectory() async {
    try {
      // 检查是否使用自定义路径
      final prefs = await SharedPreferences.getInstance();
      final isUsingCustomPath = prefs.getBool(_isUsingCustomPathKey) ?? false;

      if (isUsingCustomPath) {
        final customPath = prefs.getString(_customPathKey);
        if (customPath != null && customPath.isNotEmpty) {
          // 验证自定义路径是否仍然有效
          final customDir = Directory(customPath);
          if (await customDir.exists()) {
            return customPath;
          } else {
            // 自定义路径不存在，回退到默认路径
            logError('自定义数据目录不存在，回退到默认路径: $customPath');
            await _resetToDefaultDirectory();
          }
        }
      }

      // 使用默认路径：Documents/ThoughtEcho
      return await getDefaultDataDirectory();
    } catch (e) {
      logError('获取数据目录失败: $e', error: e);
      rethrow;
    }
  }

  /// 创建文件的父目录。
  ///
  /// 数据库类服务通过这里创建存储目录，避免各服务各自拼路径和处理
  /// 自定义数据目录策略。
  static Future<void> ensureParentDirectoryForFile(String filePath) async {
    await Directory(path.dirname(filePath)).create(recursive: true);
  }

  /// 检查并执行旧版数据迁移（从 Documents 根目录迁移到 Documents/ThoughtEcho）
  /// 这是为了兼容旧版本用户，将数据从 Documents 根目录迁移到子文件夹
  static Future<bool> checkAndMigrateLegacyData() async {
    if (kIsWeb || !Platform.isWindows) {
      return true; // 仅 Windows 需要此迁移
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查是否已经完成迁移
      if (prefs.getBool(_legacyMigrationDoneKey) ?? false) {
        return true;
      }

      // 检查是否使用自定义路径（自定义路径用户不需要迁移）
      if (prefs.getBool(_isUsingCustomPathKey) ?? false) {
        await prefs.setBool(_legacyMigrationDoneKey, true);
        return true;
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final legacyDbPath =
          path.join(docsDir.path, 'databases', 'thoughtecho.db');
      final legacyDbFile = File(legacyDbPath);

      // 检查旧版数据是否存在于 Documents 根目录
      if (!await legacyDbFile.exists()) {
        // 没有旧版数据，标记迁移完成
        await prefs.setBool(_legacyMigrationDoneKey, true);
        logDebug('没有检测到旧版数据，跳过迁移');
        return true;
      }

      // 新路径
      final newDataDir = await getDefaultDataDirectory();
      final newDbPath = path.join(newDataDir, 'databases', 'thoughtecho.db');
      final newDbFile = File(newDbPath);

      // 如果新路径已经有数据库，说明已经迁移过
      if (await newDbFile.exists()) {
        await prefs.setBool(_legacyMigrationDoneKey, true);
        logDebug('新数据目录已存在数据，跳过迁移');
        return true;
      }

      logInfo('检测到旧版数据，开始自动迁移到 $newDataDir');

      // 迁移前确保关闭并冲刷所有数据库连接
      await _closeAllDatabases();

      // 创建新目录
      await Directory(newDataDir).create(recursive: true);

      // 迁移应用相关的文件和目录
      final itemsToMigrate = [
        'databases',
        'media',
        'ai_analyses.db',
        'ai_analyses.db-wal',
        'chat.db',
        'chat.db-wal',
      ];

      for (final item in itemsToMigrate) {
        final sourcePath = path.join(docsDir.path, item);
        final targetPath = path.join(newDataDir, item);

        final sourceDir = Directory(sourcePath);
        final sourceFile = File(sourcePath);

        if (await sourceDir.exists()) {
          // 复制目录
          await _copyDirectory(sourceDir, Directory(targetPath));
          logDebug('已迁移目录: $item');
        } else if (await sourceFile.exists()) {
          // 复制文件
          await Directory(path.dirname(targetPath)).create(recursive: true);
          await sourceFile.copy(targetPath);
          logDebug('已迁移文件: $item');
        }
      }

      // 标记迁移完成
      await prefs.setBool(_legacyMigrationDoneKey, true);
      logInfo('旧版数据迁移完成');
      return true;
    } catch (e, stackTrace) {
      logError('旧版数据迁移失败: $e', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// 关闭所有正在运行的数据库并冲刷 WAL 日志，确保数据完整性。
  /// 若关闭失败则抛出异常以中止后续迁移，防止数据损坏。
  static Future<void> _closeAllDatabases() async {
    logInfo('正在关闭并冲刷所有数据库连接...');
    final List<String> failures = [];

    try {
      await DatabaseService.closeDatabase(forMigration: true);
    } catch (e, stack) {
      logError('关闭 DatabaseService 失败', error: e, stackTrace: stack);
      failures.add('DatabaseService: $e');
    }

    try {
      await AIAnalysisDatabaseService().closeDatabase();
    } catch (e, stack) {
      logError('关闭 AIAnalysisDatabaseService 失败', error: e, stackTrace: stack);
      failures.add('AIAnalysisDatabaseService: $e');
    }

    try {
      final activeInstance = ChatSessionService.activeInstance;
      if (activeInstance != null) {
        await activeInstance.close();
      }
    } catch (e, stack) {
      logError('关闭 ChatSessionService 失败', error: e, stackTrace: stack);
      failures.add('ChatSessionService: $e');
    }

    if (failures.isNotEmpty) {
      // 迁移复制的是 SQLite 主库文件。任何连接未成功 checkpoint/close
      // 都可能把 WAL 中的最近写入落在旧目录，因此这里故意硬失败。
      throw Exception('关闭数据库连接失败，已中止迁移以防数据损坏。失败详情: ${failures.join(", ")}');
    }

    logInfo('所有数据库已成功关闭并冲刷。');
  }

  /// 复制目录及其内容
  static Future<void> _copyDirectory(Directory source, Directory target) async {
    if (!await target.exists()) {
      await target.create(recursive: true);
    }

    await for (final entity in source.list(followLinks: false)) {
      final newPath = path.join(target.path, path.basename(entity.path));

      if (entity is File) {
        final fileName = path.basename(entity.path).toLowerCase();
        if (!fileName.endsWith('-shm')) {
          await entity.copy(newPath);
        }
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }

  /// 检查是否正在使用自定义数据目录
  static Future<bool> isUsingCustomDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_isUsingCustomPathKey) ?? false;
    } catch (e) {
      logError('检查自定义目录状态失败: $e', error: e);
      return false;
    }
  }

  /// 获取自定义数据目录路径（如果有）
  static Future<String?> getCustomDataDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_customPathKey);
    } catch (e) {
      logError('获取自定义目录路径失败: $e', error: e);
      return null;
    }
  }

  /// 验证目录是否可用于存储数据
  static Future<bool> validateDirectory(String dirPath) async {
    try {
      final dir = Directory(dirPath);

      // 检查目录是否存在
      if (!await dir.exists()) {
        // 尝试创建目录
        try {
          await dir.create(recursive: true);
        } catch (e) {
          logError('无法创建目录: $e', error: e);
          return false;
        }
      }

      // 检查是否有写权限
      final testFile = File(path.join(dirPath, '.write_test'));
      try {
        await testFile.writeAsString('test');
        await testFile.delete();
      } catch (e) {
        logError('目录没有写权限: $e', error: e);
        return false;
      }

      // 检查可用空间（至少需要 100MB）
      // 注意: Flutter 没有直接 API 检查磁盘空间，这里简化处理
      // 实际使用中可以集成 disk_space 插件

      return true;
    } catch (e) {
      logError('验证目录失败: $e', error: e);
      return false;
    }
  }

  /// 迁移整个数据目录到 [newPath]。
  ///
  /// 数据目录是应用专属文件夹，直接整目录复制（仅排除系统文件和 SQLite
  /// `-shm` 临时文件），因此未来新增任何数据源都无需维护迁移清单。
  /// 返回是否成功；成功后新路径写入配置，需要重启应用生效。
  static Future<bool> migrateDataDirectory(
    String newPath, {
    Function(double progress)? onProgress,
    Function(String status)? onStatusUpdate,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Web平台不支持数据目录迁移');
    }

    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      throw UnsupportedError('仅支持桌面平台');
    }

    var databasesCloseAttempted = false;
    try {
      onStatusUpdate?.call('正在验证新目录...');
      logDebug('开始迁移数据到: $newPath');

      // 1. 获取当前目录，并解析两个目录的真实路径（跟随 junction/symlink）。
      //    不解析直接比较字符串，会放过指向当前目录自身的链接，导致文件
      //    被复制进自己并截断。
      final currentPath = await getCurrentDataDirectory();
      final resolvedCurrent = await canonicalizePath(currentPath);
      final resolvedNew = await canonicalizePath(newPath);

      // 2. 相同/祖先检查必须发生在 validateDirectory 之前：被拒绝的路径
      //    不应先触发目录创建和写权限探针等副作用。
      final pathError = validateDataDirectoryPath(resolvedCurrent, resolvedNew);
      if (pathError != null) {
        throw Exception(pathError);
      }

      // 3. 验证新目录
      if (!await validateDirectory(newPath)) {
        throw Exception('新目录不可用或没有写权限');
      }

      onStatusUpdate?.call('正在准备迁移...');

      // 迁移前确保关闭并冲刷所有数据库连接。
      // 先标记"已尝试关闭"再调用：_closeAllDatabases 可能中途失败（如
      // DatabaseService 已销毁后 AI/会话库关闭失败），此时也需要恢复。
      databasesCloseAttempted = true;
      await _closeAllDatabases();

      final currentDir = Directory(currentPath);
      if (!await currentDir.exists()) {
        throw Exception('当前数据目录不存在');
      }

      // 3. 整目录收集应用文件（数据已收敛在专属文件夹，无需维护白名单）
      // 使用 isolate 避免阻塞 UI；同时传入新目录以排除自身嵌套。
      final result = await compute(_collectAppFiles, (currentPath, newPath));
      final fileEntries = (result['files'] as List).cast<(String, String)>();
      final errors = result['errors'] as List<String>;

      if (errors.isNotEmpty) {
        // 收集阶段有文件访问失败：继续迁移会让部分数据在新目录缺失，
        // 且配置已切换导致旧目录被"遗弃"，因此必须中止。
        throw FileSystemException(
          '收集迁移文件失败: ${errors.join('; ')}',
          currentPath,
        );
      }

      if (fileEntries.isEmpty) {
        logDebug('没有需要迁移的文件');
        // 即使没有文件，也继续设置新目录
      } else {
        logDebug('需要迁移 ${fileEntries.length} 个文件');

        // 4. 复制文件到新目录
        int copiedCount = 0;
        final Map<String, double> inProgressMap = {};
        const int chunkSize = 5;
        for (int i = 0; i < fileEntries.length; i += chunkSize) {
          final chunk = fileEntries.sublist(
              i,
              i + chunkSize > fileEntries.length
                  ? fileEntries.length
                  : i + chunkSize);
          await Future.wait(chunk.map((entry) async {
            final (filePath, relativePath) = entry;
            try {
              final file = File(filePath);
              final targetPath = path.join(newPath, relativePath);

              // 路径遍历防护：使用 PathSecurityUtils 深度验证
              try {
                PathSecurityUtils.validateExtractionPath(targetPath, newPath);
              } catch (e) {
                logError('路径安全检查失败，跳过: $relativePath ($e)');
                return;
              }

              onStatusUpdate?.call('正在复制: $relativePath');

              // 确保目标目录存在
              final targetDir = Directory(path.dirname(targetPath));
              if (!await targetDir.exists()) {
                try {
                  await targetDir.create(recursive: true);
                } catch (_) {
                  // 忽略并发创建目录时可能抛出的已存在异常
                }
              }

              // 使用 LargeFileManager 复制文件（支持大文件）
              await LargeFileManager.copyFileInChunks(
                file.path,
                targetPath,
                onProgress: (current, total) {
                  if (onProgress != null && total > 0) {
                    final fileProgress = current / total;
                    inProgressMap[filePath] = fileProgress;
                    final totalInProgress =
                        inProgressMap.values.fold(0.0, (a, b) => a + b);
                    final totalProgress =
                        (copiedCount + totalInProgress) / fileEntries.length;
                    onProgress(totalProgress);
                  }
                },
              );

              copiedCount++;
              inProgressMap.remove(filePath);

              if (onProgress != null) {
                final totalInProgress =
                    inProgressMap.values.fold(0.0, (a, b) => a + b);
                onProgress(
                    (copiedCount + totalInProgress) / fileEntries.length);
              }
            } catch (e) {
              logError('复制文件失败: $filePath, 错误: $e', error: e);
              // 继续复制其他文件
            }
          }));
        }

        onStatusUpdate?.call('验证文件完整性...');

        // 5. 验证关键文件是否复制成功
        final criticalFiles = [
          'databases/thoughtecho.db',
        ];

        for (final relPath in criticalFiles) {
          final sourceFile = File(path.join(currentPath, relPath));
          final targetFile = File(path.join(newPath, relPath));

          if (await sourceFile.exists()) {
            if (!await targetFile.exists()) {
              throw Exception('关键文件复制失败: $relPath');
            }

            final sourceSize = await sourceFile.length();
            final targetSize = await targetFile.length();
            if (sourceSize != targetSize) {
              throw Exception('文件大小不匹配: $relPath');
            }
          }
        }
      }

      onStatusUpdate?.call('更新配置...');

      // 6. 保存新路径配置
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customPathKey, newPath);
      await prefs.setBool(_isUsingCustomPathKey, true);

      logDebug('数据迁移成功完成');
      onStatusUpdate?.call('迁移完成');

      // 7. 提示用户重启应用
      // 注意：实际应用中，需要重启应用才能生效新路径

      return true;
    } catch (e, stackTrace) {
      // 迁移在关闭数据库之后失败时，恢复数据库服务，否则用户不重启应用
      // 后续数据库操作会持续失败。
      if (databasesCloseAttempted) {
        await _restoreDatabasesAfterFailedMigration();
      }
      logError('数据迁移失败: $e', error: e, stackTrace: stackTrace);
      onStatusUpdate?.call('迁移失败: $e');
      return false;
    }
  }

  /// 迁移失败后恢复数据库服务。
  ///
  /// `DatabaseService.closeDatabase(forMigration: true)` 会保持已销毁状态
  /// （迁移成功后本就需要重启），失败时必须重置以便后续按需重新初始化。
  /// AI 分析与会话数据库关闭后会在下次访问时惰性重开，无需额外恢复。
  static Future<void> _restoreDatabasesAfterFailedMigration() async {
    try {
      await DatabaseService.closeDatabase(forMigration: false);
    } catch (e, stackTrace) {
      logError('迁移失败后恢复 DatabaseService 失败', error: e, stackTrace: stackTrace);
    }
  }

  /// isolate 入口：收集数据目录下所有待迁移的文件（避免阻塞 UI）。
  ///
  /// 数据目录已是应用专属文件夹，直接整目录递归收集，不再维护
  /// `databases / media / ai_analyses.db ...` 白名单，未来新增任何数据源
  /// 都会被自动迁移。
  static Future<Map<String, dynamic>> _collectAppFiles(
    (String, String) args,
  ) async {
    final (currentPath, excludePath) = args;
    return collectFilesForMigration(currentPath, excludePath: excludePath);
  }

  /// 收集数据目录下所有待迁移的文件（纯逻辑，供测试直接调用）。
  ///
  /// 返回 `(源路径, 目标相对路径)` 列表，目标相对路径在复制时保持目录
  /// 结构。跳过系统文件（`desktop.ini`、`thumbs.db` 等）和 SQLite 共享
  /// 内存临时文件（`-shm`）；WAL 日志保留。
  ///
  /// 数据目录内的 junction/symlink 子目录会被展开收集（文件落在链接名
  /// 对应的相对路径下）；链接指向数据目录内部时跳过，因为真实位置的文件
  /// 会被正常收集，避免重复或错误的目标路径。
  ///
  /// 仅当 [excludePath] 位于 [currentPath] 内部（用户把新目录选在数据
  /// 目录内）时才排除其中的文件，避免把目标目录复制进自身。若
  /// [excludePath] 是 [currentPath] 的祖先或与其无关，不做排除。
  @visibleForTesting
  static Future<Map<String, dynamic>> collectFilesForMigration(
    String currentPath, {
    String? excludePath,
  }) async {
    final filesToCopy = <(String, String)>[];
    final errors = <String>[];

    final dataDirReal = _resolveRealPathSync(currentPath);
    final excludeReal =
        excludePath == null ? null : _resolveRealPathSync(excludePath);
    // 排除只在目标目录位于数据目录内部时生效。
    final excludeApplied =
        excludeReal != null && path.isWithin(dataDirReal, excludeReal);

    await _collectMigrationEntries(
      Directory(currentPath),
      prefix: '',
      dataDirReal: dataDirReal,
      excludeReal: excludeApplied ? excludeReal : null,
      visitedRealDirs: <String>{},
      filesToCopy: filesToCopy,
      errors: errors,
    );

    return {'files': filesToCopy, 'errors': errors};
  }

  /// 递归收集目录下的迁移文件（含展开外部链接）。
  ///
  /// [prefix] 是当前目录在数据目录内的相对前缀（数据目录根为 ''，外部
  /// 链接展开后为链接相对路径）。[visitedRealDirs] 记录已展开过的真实目录，
  /// 防止链接环导致无限递归。
  static Future<void> _collectMigrationEntries(
    Directory dir, {
    required String prefix,
    required String dataDirReal,
    required String? excludeReal,
    required Set<String> visitedRealDirs,
    required List<(String, String)> filesToCopy,
    required List<String> errors,
  }) async {
    final dirReal = _resolveRealPathSync(dir.path);
    if (!visitedRealDirs.add(dirReal)) {
      return; // 已展开过，防止链接环
    }

    try {
      await for (final entity in dir.list(followLinks: false)) {
        try {
          final relative = prefix.isEmpty
              ? path.basename(entity.path)
              : path.join(prefix, path.basename(entity.path));

          if (entity is File) {
            final fileName = path.basename(entity.path).toLowerCase();
            if (_isWindowsSystemFile(fileName) || fileName.endsWith('-shm')) {
              continue;
            }
            if (excludeReal != null &&
                _isUnderOrEqual(
                    excludeReal, _resolveRealPathSync(entity.path))) {
              continue;
            }
            filesToCopy.add((entity.path, relative));
          } else if (entity is Link) {
            final targetReal = _resolveRealPathSync(entity.path);
            if (path.equals(targetReal, dataDirReal) ||
                path.isWithin(dataDirReal, targetReal)) {
              // 指向数据目录内部：真实位置的文件会被正常收集，跳过链接。
              continue;
            }
            if (excludeReal != null &&
                _isUnderOrEqual(excludeReal, targetReal)) {
              continue;
            }
            final targetType =
                FileSystemEntity.typeSync(entity.path, followLinks: true);
            if (targetType == FileSystemEntityType.file) {
              final fileName = path.basename(entity.path).toLowerCase();
              if (!_isWindowsSystemFile(fileName) &&
                  !fileName.endsWith('-shm')) {
                filesToCopy.add((entity.path, relative));
              }
            } else if (targetType == FileSystemEntityType.directory) {
              await _collectMigrationEntries(
                Directory(entity.path), // 列出链接时 OS 会跟随到目标
                prefix: relative,
                dataDirReal: dataDirReal,
                excludeReal: excludeReal,
                visitedRealDirs: visitedRealDirs,
                filesToCopy: filesToCopy,
                errors: errors,
              );
            }
            // 其余目标类型（悬空链接、特殊文件等）无法迁移，跳过。
          } else if (entity is Directory) {
            final dirRealPath = _resolveRealPathSync(entity.path);
            if (excludeReal != null &&
                _isUnderOrEqual(excludeReal, dirRealPath)) {
              continue;
            }
            await _collectMigrationEntries(
              entity,
              prefix: relative,
              dataDirReal: dataDirReal,
              excludeReal: excludeReal,
              visitedRealDirs: visitedRealDirs,
              filesToCopy: filesToCopy,
              errors: errors,
            );
          }
        } catch (e) {
          errors.add('无法访问: ${entity.path}');
        }
      }
    } catch (e) {
      errors.add('无法访问目录: ${dir.path}');
    }
  }

  /// 判断 [target] 是否等于 [parent] 或位于其内部。
  static bool _isUnderOrEqual(String parent, String target) =>
      path.equals(parent, target) || path.isWithin(parent, target);

  /// 解析路径的真实位置（跟随 junction/symlink）；目录不存在时逐级向上
  /// 解析已存在的祖先，剩余部分原样拼接。
  static String _resolveRealPathSync(String p) {
    final normalized = path.normalize(p);
    try {
      return path.normalize(Directory(normalized).resolveSymbolicLinksSync());
    } on FileSystemException {
      final parent = path.dirname(normalized);
      if (parent == normalized) return normalized; // 已到根目录
      return path.join(
        _resolveRealPathSync(parent),
        path.basename(normalized),
      );
    }
  }

  /// 解析路径的真实位置（跟随 Windows junction/symlink）。
  ///
  /// 迁移目标是尚未创建的目录时，逐级解析最近已存在的祖先，剩余部分原样
  /// 拼接。这样指向当前数据目录自身的链接会被解析成同一真实路径，从而被
  /// 相同目录检查拦截，避免文件被复制进自身并截断。
  @visibleForTesting
  static Future<String> canonicalizePath(String p) async {
    final normalized = path.normalize(p);
    try {
      return path.normalize(
        await Directory(normalized).resolveSymbolicLinks(),
      );
    } on FileSystemException {
      final parent = path.dirname(normalized);
      if (parent == normalized) return normalized; // 已到根目录
      return path.join(
        await canonicalizePath(parent),
        path.basename(normalized),
      );
    }
  }

  /// 校验迁移目标与当前数据目录的关系，返回拒绝原因；合法时返回 null。
  ///
  /// [currentPath] 与 [newPath] 必须是 [canonicalizePath] 解析后的真实
  /// 路径。拒绝三种情况：同一目录（无意义）、目标位于当前目录内部（复制
  /// 会把目标目录装进自己）、目标是当前目录的祖先（会把应用数据重新摊在
  /// 祖先目录下与用户文件混放）。
  @visibleForTesting
  static String? validateDataDirectoryPath(String currentPath, String newPath) {
    return switch (_rejectDataDirectoryTarget(currentPath, newPath)) {
      DataDirectoryTargetRejection.sameDirectory => '新目录与当前数据目录相同',
      DataDirectoryTargetRejection.ancestorDirectory => '新目录不能是当前数据目录的上级目录',
      DataDirectoryTargetRejection.nestedDirectory => '新目录不能位于当前数据目录内部',
      null => null,
    };
  }

  /// 校验 [newPath] 是否可作为迁移目标（按真实路径比较）。
  ///
  /// 返回拒绝原因；合法时返回 null。供目录选择页在写权限探针
  /// （[validateDirectory]）之前调用，让被拒绝的路径（相同/祖先/嵌套）
  /// 不产生目录创建和写探针等副作用。页面负责把拒绝原因映射为本地化文案。
  static Future<DataDirectoryTargetRejection?> validateMigrationTarget(
    String newPath,
  ) async {
    final currentPath = await getCurrentDataDirectory();
    final resolvedCurrent = await canonicalizePath(currentPath);
    final resolvedNew = await canonicalizePath(newPath);
    return _rejectDataDirectoryTarget(resolvedCurrent, resolvedNew);
  }

  static DataDirectoryTargetRejection? _rejectDataDirectoryTarget(
    String currentPath,
    String newPath,
  ) {
    if (currentPath == newPath) {
      return DataDirectoryTargetRejection.sameDirectory;
    }
    if (path.isWithin(newPath, currentPath)) {
      return DataDirectoryTargetRejection.ancestorDirectory;
    }
    if (path.isWithin(currentPath, newPath)) {
      return DataDirectoryTargetRejection.nestedDirectory;
    }
    return null;
  }

  /// 检查是否是 Windows 系统文件
  static bool _isWindowsSystemFile(String fileName) {
    final systemFiles = [
      'desktop.ini',
      'thumbs.db',
      'ntuser.dat',
      '.ds_store',
    ];
    return systemFiles.contains(fileName);
  }

  /// 重置到默认数据目录
  static Future<void> _resetToDefaultDirectory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_customPathKey);
      await prefs.setBool(_isUsingCustomPathKey, false);
      logDebug('已重置到默认数据目录');
    } catch (e) {
      logError('重置数据目录失败: $e', error: e);
    }
  }

  /// 清除自定义数据目录配置（不删除文件）
  static Future<void> clearCustomDirectoryConfig() async {
    try {
      await _resetToDefaultDirectory();
      logDebug('已清除自定义数据目录配置');
    } catch (e) {
      logError('清除配置失败: $e', error: e);
      rethrow;
    }
  }

  /// 获取建议的数据目录路径（Windows）
  static Future<List<String>> getSuggestedDirectories() async {
    if (!Platform.isWindows) {
      return [];
    }

    try {
      final suggestions = <String>[];

      // 1. 当前文档目录
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        suggestions.add(docsDir.path);
      } catch (e) {
        logDebug('无法获取文档目录: $e');
      }

      // 2. 用户主目录下的 Documents/ThoughtEcho
      try {
        final homeDir = Platform.environment['USERPROFILE'];
        if (homeDir != null) {
          suggestions.add(path.join(homeDir, 'Documents', 'ThoughtEcho'));
        }
      } catch (e) {
        logDebug('无法获取用户主目录: $e');
      }

      // 3. D盘（如果存在）
      try {
        final dDrive = Directory('D:\\ThoughtEcho');
        if (await Directory('D:\\').exists()) {
          suggestions.add(dDrive.path);
        }
      } catch (e) {
        logDebug('D盘不可用: $e');
      }

      return suggestions;
    } catch (e) {
      logError('获取建议目录失败: $e', error: e);
      return [];
    }
  }

  /// 计算目录大小（用于迁移前估算）
  static Future<int> calculateDirectorySize(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (e) {
            logDebug('获取文件大小失败: ${entity.path}');
          }
        }
      }

      return totalSize;
    } catch (e) {
      logError('计算目录大小失败: $e', error: e);
      return 0;
    }
  }
}
