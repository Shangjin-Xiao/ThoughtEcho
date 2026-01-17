import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/storage_management_service.dart';
import '../services/weather_service.dart';
import '../services/database_service.dart';
import '../services/data_directory_service.dart';
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

/// 存储管理页面
/// 展示应用存储占用详情，提供缓存清理和数据目录管理功能
class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({super.key});

  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  StorageStats? _stats;
  bool _isLoading = false;
  bool _isClearing = false;
  bool _isMigrating = false;
  String? _appDataPath;
  bool _isUsingCustomPath = false;

  @override
  void initState() {
    super.initState();
    // 延迟加载统计信息，避免阻塞初始化
    Future.microtask(() {
      if (mounted) {
        _loadStorageStats();
      }
    });
    _loadAppDataPath();
  }

  /// 加载存储统计信息
  Future<void> _loadStorageStats() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final stats = await StorageManagementService.getStorageStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.loadStorageInfoFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  /// 加载应用数据目录路径
  Future<void> _loadAppDataPath() async {
    try {
      final path = await StorageManagementService.getAppDataDirectory();
      final isCustom = await DataDirectoryService.isUsingCustomDirectory();
      if (mounted) {
        setState(() {
          _appDataPath = path;
          _isUsingCustomPath = isCustom;
        });
      }
    } catch (e) {
      // 忽略错误
    }
  }

  /// 清理缓存
  Future<void> _clearCache() async {
    if (_isClearing) return;
    final l10n = AppLocalizations.of(context);

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearCacheConfirmTitle),
        content: Text(l10n.clearCacheConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isClearing = true;
    });

    try {
      final weatherService = Provider.of<WeatherService>(
        context,
        listen: false,
      );
      final databaseService = Provider.of<DatabaseService>(
        context,
        listen: false,
      );

      final clearedBytes = await StorageManagementService.clearCache(
        weatherService: weatherService,
        databaseService: databaseService,
      );

      if (!mounted) return;

      // 刷新统计信息
      await _loadStorageStats();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.cacheCleanedResult(StorageStats.formatBytes(clearedBytes)),
          ),
          duration: AppConstants.snackBarDurationImportant,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.clearCacheFailed(e.toString())),
          duration: AppConstants.snackBarDurationError,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  /// 清理孤儿媒体文件
  Future<void> _cleanupOrphanFiles() async {
    final l10n = AppLocalizations.of(context);
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cleanOrphanMediaConfirmTitle),
        content: Text(l10n.cleanOrphanMediaConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isClearing = true;
    });

    try {
      final orphanCount = await StorageManagementService.cleanupOrphanFiles();

      if (!mounted) return;

      // 刷新统计信息
      await _loadStorageStats();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.orphanFilesCleanedResult(orphanCount)),
          duration: AppConstants.snackBarDurationImportant,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.cleanupFailed(e.toString())),
          duration: AppConstants.snackBarDurationError,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  /// 执行数据库维护（VACUUM + ANALYZE + REINDEX）
  Future<void> _performDatabaseMaintenance() async {
    final l10n = AppLocalizations.of(context);
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.databaseMaintenanceConfirmTitle),
        content: Text(l10n.databaseMaintenanceConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.startMaintenance),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isClearing = true;
    });

    String currentProgress = l10n.preparingProgress;

    // 显示进度对话框
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    l10n.maintenanceInProgress,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Text(currentProgress),
          );
        },
      ),
    );

    try {
      final dbService = Provider.of<DatabaseService>(context, listen: false);

      final result = await dbService.performDatabaseMaintenance(
        onProgress: (progress) {
          currentProgress = progress;
          // 注意：这里无法直接更新对话框状态，但至少记录了进度
        },
      );

      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;

      // 刷新统计信息
      await _loadStorageStats();

      if (!mounted) return;

      // 显示结果
      if (result['success'] == true) {
        final durationMs = result['duration_ms'] as int;
        final spaceSaved = result['space_saved_mb'] as double;
        final dbSizeBefore = result['db_size_before_mb'] as double;
        final dbSizeAfter = result['db_size_after_mb'] as double;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    l10n.maintenanceComplete,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.maintenanceDuration(
                    (durationMs / 1000).toStringAsFixed(1),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.databaseSizeChange(
                    dbSizeBefore.toStringAsFixed(2),
                    dbSizeAfter.toStringAsFixed(2),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  spaceSaved > 0
                      ? l10n.spaceSavedMb(spaceSaved.toStringAsFixed(2))
                      : l10n.noSpaceSaved,
                  style: TextStyle(
                    color: spaceSaved > 0 ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.confirm),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.maintenanceFailed(result['message'].toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    } catch (e) {
      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.maintenanceFailed(e.toString())),
          duration: AppConstants.snackBarDurationError,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.storageManagement)),
      body: _isLoading && _stats == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 总占用空间卡片
                _buildTotalStorageCard(colorScheme, l10n),
                const SizedBox(height: 16),

                // 数据库占用详情
                _buildSectionTitle(l10n.databaseUsage),
                const SizedBox(height: 8),
                _buildDatabaseStorageCard(colorScheme, l10n),
                const SizedBox(height: 16),

                // 媒体文件占用详情
                _buildSectionTitle(l10n.mediaFilesUsage),
                const SizedBox(height: 8),
                _buildMediaStorageCard(colorScheme, l10n),
                const SizedBox(height: 16),

                // 缓存占用（Windows 平台临时目录是系统共享的，无法准确统计，因此隐藏）
                if (!Platform.isWindows) ...[
                  _buildSectionTitle(l10n.cacheUsage),
                  const SizedBox(height: 8),
                  _buildCacheStorageCard(colorScheme, l10n),
                  const SizedBox(height: 24),
                ] else
                  const SizedBox(height: 8),

                // 操作按钮
                _buildActionButtons(colorScheme, l10n),
                const SizedBox(height: 24),

                // 数据目录信息（仅桌面端）
                if (!kIsWeb &&
                    (Platform.isWindows ||
                        Platform.isLinux ||
                        Platform.isMacOS))
                  _buildDataDirectorySection(colorScheme, l10n),
              ],
            ),
    );
  }

  /// 构建总存储空间卡片
  Widget _buildTotalStorageCard(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final totalSize = _stats?.totalSize ?? 0;
    final mainDbSize = _stats?.mainDatabaseSize ?? 0;
    final logDbSize = _stats?.logDatabaseSize ?? 0;
    final aiDbSize = _stats?.aiDatabaseSize ?? 0;
    final mediaSize = _stats?.mediaFilesSize ?? 0;
    final cacheSize = _stats?.cacheSize ?? 0;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  size: 32,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.totalStorageUsage,
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        StorageStats.formatBytes(totalSize),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (totalSize > 0) ...[
              const SizedBox(height: 20),
              // 彩色分段进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      if (mainDbSize > 0)
                        Expanded(
                          flex: (mainDbSize * 1000 / totalSize).round(),
                          child: Container(color: Colors.blue),
                        ),
                      if (aiDbSize > 0)
                        Expanded(
                          flex: (aiDbSize * 1000 / totalSize).round(),
                          child: Container(color: Colors.purple),
                        ),
                      if (logDbSize > 0)
                        Expanded(
                          flex: (logDbSize * 1000 / totalSize).round(),
                          child: Container(color: Colors.orange),
                        ),
                      if (mediaSize > 0)
                        Expanded(
                          flex: (mediaSize * 1000 / totalSize).round(),
                          child: Container(color: Colors.green),
                        ),
                      if (cacheSize > 0)
                        Expanded(
                          flex: (cacheSize * 1000 / totalSize).round(),
                          child: Container(color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 图例
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  if (mainDbSize > 0)
                    _buildLegendItem(
                      l10n.notesDatabase,
                      Colors.blue,
                      mainDbSize,
                    ),
                  if (aiDbSize > 0)
                    _buildLegendItem(l10n.aiDatabase, Colors.purple, aiDbSize),
                  if (logDbSize > 0)
                    _buildLegendItem(
                      l10n.logDatabase,
                      Colors.orange,
                      logDbSize,
                    ),
                  if (mediaSize > 0)
                    _buildLegendItem(
                      l10n.mediaFilesUsage,
                      Colors.green,
                      mediaSize,
                    ),
                  if (cacheSize > 0)
                    _buildLegendItem(l10n.cacheUsage, Colors.grey, cacheSize),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建图例项
  Widget _buildLegendItem(String label, Color color, int size) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label (${StorageStats.formatBytes(size)})',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  /// 构建数据库存储卡片
  Widget _buildDatabaseStorageCard(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return Card(
      child: Column(
        children: [
          _buildStorageItem(
            icon: Icons.sticky_note_2_outlined,
            label: l10n.notesDatabase,
            size: _stats?.mainDatabaseSize ?? 0,
            color: Colors.blue,
          ),
          const Divider(height: 1),
          _buildStorageItem(
            icon: Icons.analytics_outlined,
            label: l10n.aiDatabase,
            size: _stats?.aiDatabaseSize ?? 0,
            color: Colors.purple,
          ),
          const Divider(height: 1),
          _buildStorageItem(
            icon: Icons.description_outlined,
            label: l10n.logDatabase,
            size: _stats?.logDatabaseSize ?? 0,
            color: Colors.orange,
          ),
        ],
      ),
    );
  }

  /// 构建媒体存储卡片
  Widget _buildMediaStorageCard(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final breakdown = _stats?.mediaBreakdown;

    return Card(
      child: Column(
        children: [
          _buildStorageItem(
            icon: Icons.image_outlined,
            label: l10n.images,
            size: breakdown?.imagesSize ?? 0,
            count: breakdown?.imagesCount ?? 0,
            color: Colors.green,
          ),
          const Divider(height: 1),
          _buildStorageItem(
            icon: Icons.videocam_outlined,
            label: l10n.videos,
            size: breakdown?.videosSize ?? 0,
            count: breakdown?.videosCount ?? 0,
            color: Colors.red,
          ),
          const Divider(height: 1),
          _buildStorageItem(
            icon: Icons.audiotrack_outlined,
            label: l10n.audios,
            size: breakdown?.audiosSize ?? 0,
            count: breakdown?.audiosCount ?? 0,
            color: Colors.teal,
          ),
        ],
      ),
    );
  }

  /// 构建缓存存储卡片
  Widget _buildCacheStorageCard(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return Card(
      child: _buildStorageItem(
        icon: Icons.cleaning_services_outlined,
        label: l10n.tempFilesAndCache,
        size: _stats?.cacheSize ?? 0,
        color: Colors.grey,
      ),
    );
  }

  /// 构建存储项
  Widget _buildStorageItem({
    required IconData icon,
    required String label,
    required int size,
    int? count,
    required Color color,
  }) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: count != null && count > 0 ? Text(l10n.fileCount(count)) : null,
      trailing: Text(
        StorageStats.formatBytes(size),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
    );
  }

  /// 构建操作按钮
  /// Windows 平台临时目录是系统共享的，无法准确统计和清理应用缓存
  /// 因此 Windows 端隐藏清理缓存、清理无用媒体文件和数据库维护优化功能
  Widget _buildActionButtons(ColorScheme colorScheme, AppLocalizations l10n) {
    // Windows 平台不显示操作按钮
    if (Platform.isWindows) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _isClearing ? null : _clearCache,
          icon: _isClearing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cleaning_services),
          label: Text(l10n.clearCache),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isClearing ? null : _cleanupOrphanFiles,
          icon: const Icon(Icons.delete_sweep),
          label: Text(l10n.cleanOrphanMedia),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isClearing ? null : _performDatabaseMaintenance,
          icon: const Icon(Icons.build_circle_outlined),
          label: Text(l10n.databaseMaintenance),
        ),
      ],
    );
  }

  /// 选择新的数据目录
  Future<void> _selectNewDataDirectory() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: l10n.selectNewDataDirectory,
      );

      if (result == null || !mounted) return;

      // 验证目录
      final isValid = await DataDirectoryService.validateDirectory(result);
      if (!isValid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.directoryNotAvailable),
            duration: AppConstants.snackBarDurationError,
          ),
        );
        return;
      }

      // 确认迁移
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.confirmDataMigration),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.migrationTargetPath),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  result,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              Text(l10n.migrationWarning, style: const TextStyle(fontSize: 13)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.startMigration),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      // 开始迁移
      await _performDataMigration(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.selectDirectoryFailed(e.toString())),
          duration: AppConstants.snackBarDurationError,
        ),
      );
    }
  }

  /// 执行数据迁移
  Future<void> _performDataMigration(String newPath) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isMigrating = true;
    });

    String? statusMessage;
    double progress = 0.0;

    try {
      // 显示进度对话框
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(l10n.migratingData),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 16),
                    Text(
                      statusMessage ?? l10n.preparingProgress,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      // 执行迁移
      final success = await DataDirectoryService.migrateDataDirectory(
        newPath,
        onProgress: (p) {
          if (mounted) {
            // 更新进度（通过重新构建对话框）
            Navigator.of(context).pop();
            progress = p;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => PopScope(
                canPop: false,
                child: AlertDialog(
                  title: Text(l10n.migratingData),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 16),
                      Text(
                        statusMessage ?? '${(progress * 100).toInt()}%',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        },
        onStatusUpdate: (status) {
          statusMessage = status;
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭进度对话框

      if (success) {
        // 迁移成功，提示重启
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.migrationComplete),
            content: Text(l10n.migrationCompleteMessage),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  // 可以在这里添加退出应用的逻辑
                  // 或者提示用户手动重启
                },
                child: Text(l10n.confirm),
              ),
            ],
          ),
        );

        // 刷新路径显示
        await _loadAppDataPath();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.migrationFailed),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭进度对话框
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.migrationFailedWithError(e.toString())),
          duration: AppConstants.snackBarDurationError,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isMigrating = false;
        });
      }
    }
  }

  /// 构建数据目录部分
  Widget _buildDataDirectorySection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(l10n.dataStorageLocation),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_outlined, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                l10n.currentDataDirectory,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                              if (_isUsingCustomPath) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    l10n.custom,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _appDataPath ?? l10n.loading,
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (Platform.isWindows) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Text(
                    l10n.windowsDataMigration,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.windowsDataMigrationDesc,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isMigrating || _isClearing
                          ? null
                          : _selectNewDataDirectory,
                      icon: _isMigrating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.drive_file_move_outlined),
                      label: Text(
                        _isMigrating
                            ? l10n.migrating
                            : l10n.changeDataDirectory,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建章节标题
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
