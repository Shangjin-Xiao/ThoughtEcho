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

/// 一次目录扫描的结果。
///
/// [files] 是 `(源文件绝对路径, 相对于数据目录的目标路径)`；[errors] 非空
/// 表示有文件读不到，此时必须中止迁移而不是带着缺失继续。
typedef MigrationFileScan = ({
  List<(String, String)> files,
  List<String> errors,
});

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

      // 2. 相同/祖先检查必须发生在 validateDirectory 之前：被拒绝的路径
      //    不应先触发目录创建和写权限探针等副作用。
      final pathError = validateDataDirectoryPath(
        canonicalizePath(currentPath),
        canonicalizePath(newPath),
      );
      if (pathError != null) {
        throw Exception(pathError);
      }

      // 3. 验证新目录
      if (!await validateDirectory(newPath)) {
        throw Exception('新目录不可用或没有写权限');
      }

      if (!await Directory(currentPath).exists()) {
        throw Exception('当前数据目录不存在');
      }

      onStatusUpdate?.call('正在准备迁移...');

      // 4. 迁移前确保关闭并冲刷所有数据库连接；必须在收集之前，否则收集到的
      //    -wal 文件可能在复制前被 checkpoint 掉。
      //    先标记"已尝试关闭"再调用：_closeAllDatabases 可能中途失败（如
      //    DatabaseService 已销毁后 AI/会话库关闭失败），此时也需要恢复。
      databasesCloseAttempted = true;
      await _closeAllDatabases();

      // 5. 整目录收集应用文件（数据已收敛在专属文件夹，无需维护白名单）
      // 使用 isolate 避免阻塞 UI。
      final scan = await compute(collectFilesForMigration, currentPath);

      if (scan.errors.isNotEmpty) {
        // 收集阶段有文件访问失败：继续迁移会让部分数据在新目录缺失，
        // 且配置已切换导致旧目录被"遗弃"，因此必须中止。
        throw FileSystemException(
          '收集迁移文件失败: ${scan.errors.join('; ')}',
          currentPath,
        );
      }

      if (scan.files.isEmpty) {
        logDebug('没有需要迁移的文件');
        // 即使没有文件，也继续设置新目录
      } else {
        logDebug('需要迁移 ${scan.files.length} 个文件');

        // 6. 复制文件到新目录（任一文件失败即中止）
        await copyFilesForMigration(
          scan.files,
          newPath,
          onProgress: onProgress,
          onStatusUpdate: onStatusUpdate,
        );

        // 7. 复核关键数据库，防止复制层面"成功"但内容不完整
        onStatusUpdate?.call('验证文件完整性...');
        await _verifyCriticalFiles(currentPath, newPath);
      }

      onStatusUpdate?.call('更新配置...');

      // 8. 保存新路径配置
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

  /// 把收集到的文件复制到 [newPath]，保持相对目录结构。
  ///
  /// 任一文件复制失败都会抛出并中止迁移：配置一旦切换到新目录，缺失的文件
  /// 对用户就等同于丢失。旧目录始终原样保留，用户修复后可重试。
  @visibleForTesting
  static Future<void> copyFilesForMigration(
    List<(String, String)> files,
    String newPath, {
    Function(double progress)? onProgress,
    Function(String status)? onStatusUpdate,
  }) async {
    final failures = <String>[];
    var finished = 0;
    final inProgress = <String, double>{};

    void reportProgress() {
      if (onProgress == null) return;
      final partial = inProgress.values.fold(0.0, (a, b) => a + b);
      onProgress((finished + partial) / files.length);
    }

    // 少量并发即可跑满磁盘，再高只会互相争抢。
    const concurrency = 5;
    for (var i = 0; i < files.length && failures.isEmpty; i += concurrency) {
      final end =
          i + concurrency < files.length ? i + concurrency : files.length;
      await Future.wait(files.sublist(i, end).map((entry) async {
        final (sourcePath, relativePath) = entry;
        try {
          final targetPath = path.join(newPath, relativePath);
          // 深度防御：相对路径由 basename 逐级拼接而来，正常不会越界。
          PathSecurityUtils.validateExtractionPath(targetPath, newPath);

          onStatusUpdate?.call('正在复制: $relativePath');
          // 使用 LargeFileManager 复制文件（支持大文件，自动建目标目录）
          await LargeFileManager.copyFileInChunks(
            sourcePath,
            targetPath,
            onProgress: (current, total) {
              if (total > 0) {
                inProgress[sourcePath] = current / total;
                reportProgress();
              }
            },
          );
        } catch (e, stackTrace) {
          logError('复制文件失败: $relativePath', error: e, stackTrace: stackTrace);
          failures.add('$relativePath: $e');
        } finally {
          finished++;
          inProgress.remove(sourcePath);
          reportProgress();
        }
      }));
    }

    if (failures.isNotEmpty) {
      throw Exception(
        '复制文件失败（${failures.length} 个）: ${failures.take(3).join('; ')}',
      );
    }
  }

  /// 复核关键文件在新目录中存在且大小一致。
  static Future<void> _verifyCriticalFiles(
    String currentPath,
    String newPath,
  ) async {
    const criticalFiles = [
      ['databases', 'thoughtecho.db'],
    ];

    for (final parts in criticalFiles) {
      final relPath = path.joinAll(parts);
      final sourceFile = File(path.join(currentPath, relPath));
      if (!await sourceFile.exists()) continue;

      final targetFile = File(path.join(newPath, relPath));
      if (!await targetFile.exists()) {
        throw Exception('关键文件复制失败: $relPath');
      }
      if (await sourceFile.length() != await targetFile.length()) {
        throw Exception('文件大小不匹配: $relPath');
      }
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

  /// 收集数据目录下所有待迁移的文件（[compute] 的 isolate 入口，避免阻塞 UI）。
  ///
  /// 数据目录已是应用专属文件夹，直接整目录递归收集，不再维护
  /// `databases / media / ai_analyses.db ...` 白名单，未来新增任何数据源
  /// 都会被自动迁移。
  ///
  /// 返回的 `files` 是 `(源路径, 目标相对路径)` 列表，相对路径在复制时保持
  /// 目录结构。跳过系统文件（`desktop.ini`、`thumbs.db` 等）和 SQLite 共享
  /// 内存临时文件（`-shm`）；WAL 日志保留。
  ///
  /// 数据目录内的 junction/symlink 子目录会被展开收集（文件落在链接名
  /// 对应的相对路径下），否则链接指向的数据在新目录里会整块缺失；链接指向
  /// 数据目录内部时跳过，因为真实位置的文件会被正常收集，避免重复。
  ///
  /// 不需要排除迁移目标目录：目标位于数据目录内部的情况已由
  /// [validateDataDirectoryPath] 在迁移开始前拒绝。
  static Future<MigrationFileScan> collectFilesForMigration(
    String dataDirPath,
  ) async {
    final files = <(String, String)>[];
    final errors = <String>[];

    await _collectFrom(
      Directory(dataDirPath),
      prefix: '',
      rootReal: canonicalizePath(dataDirPath),
      visitedDirs: <String>{},
      files: files,
      errors: errors,
    );

    return (files: files, errors: errors);
  }

  /// 递归收集 [dir] 下的迁移文件。
  ///
  /// [prefix] 是 [dir] 在数据目录内的相对前缀（数据目录根为 ''）。
  /// [visitedDirs] 记录已展开过的真实目录，防止链接环导致无限递归。
  static Future<void> _collectFrom(
    Directory dir, {
    required String prefix,
    required String rootReal,
    required Set<String> visitedDirs,
    required List<(String, String)> files,
    required List<String> errors,
  }) async {
    if (!visitedDirs.add(canonicalizePath(dir.path))) {
      return; // 已展开过，防止链接环
    }

    try {
      await for (final entity in dir.list(followLinks: false)) {
        try {
          final name = path.basename(entity.path);
          final relative = prefix.isEmpty ? name : path.join(prefix, name);

          if (entity is Link) {
            final target = canonicalizePath(entity.path);
            if (path.equals(target, rootReal) ||
                path.isWithin(rootReal, target)) {
              // 指向数据目录内部：真实位置的文件会被正常收集，跳过链接。
              continue;
            }
          }

          // 按真实类型处理，普通文件/目录与指向外部的 junction/symlink 一视同仁。
          switch (FileSystemEntity.typeSync(entity.path, followLinks: true)) {
            case FileSystemEntityType.file:
              if (!_isSkippedFile(name)) {
                files.add((entity.path, relative));
              }
            case FileSystemEntityType.directory:
              await _collectFrom(
                Directory(entity.path), // 列出链接时 OS 会跟随到目标
                prefix: relative,
                rootReal: rootReal,
                visitedDirs: visitedDirs,
                files: files,
                errors: errors,
              );
            default:
              break; // 悬空链接、管道等特殊类型无法迁移
          }
        } catch (e) {
          errors.add('无法访问 ${entity.path}: $e');
        }
      }
    } catch (e) {
      errors.add('无法访问目录 ${dir.path}: $e');
    }
  }

  /// 迁移时跳过的文件：系统文件与 SQLite 共享内存临时文件（`-shm`）。
  /// `-wal` 必须保留，其中可能有尚未 checkpoint 的数据。
  static bool _isSkippedFile(String fileName) {
    const systemFiles = {
      'desktop.ini',
      'thumbs.db',
      'ntuser.dat',
      '.ds_store',
    };
    final lower = fileName.toLowerCase();
    return systemFiles.contains(lower) || lower.endsWith('-shm');
  }

  /// 解析路径的真实位置（跟随 Windows junction/symlink）。
  ///
  /// 迁移目标是尚未创建的目录时，逐级解析最近已存在的祖先，剩余部分原样
  /// 拼接。这样指向当前数据目录自身的链接会被解析成同一真实路径，从而被
  /// 相同目录检查拦截，避免文件被复制进自身并截断。
  @visibleForTesting
  static String canonicalizePath(String p) {
    final normalized = path.normalize(p);
    try {
      return path.normalize(Directory(normalized).resolveSymbolicLinksSync());
    } on FileSystemException {
      final parent = path.dirname(normalized);
      if (parent == normalized) return normalized; // 已到根目录
      return path.join(canonicalizePath(parent), path.basename(normalized));
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
    return _rejectDataDirectoryTarget(
      canonicalizePath(currentPath),
      canonicalizePath(newPath),
    );
  }

  static DataDirectoryTargetRejection? _rejectDataDirectoryTarget(
    String currentPath,
    String newPath,
  ) {
    // 用 path.equals 而非 == ：Windows 路径大小写不敏感，同一目录可能有
    // 大小写不同的两种写法（如盘符）。
    if (path.equals(currentPath, newPath)) {
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
