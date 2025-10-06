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
    _loadStorageStats();
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
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载存储信息失败: $e'),
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

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Text('确定要清理应用缓存吗？\n\n这将清除临时文件、图片缓存等，不会删除您的笔记数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isClearing = true;
    });

    try {
      final weatherService =
          Provider.of<WeatherService>(context, listen: false);
      final databaseService =
          Provider.of<DatabaseService>(context, listen: false);

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
          content: Text('缓存清理完成，释放了 ${StorageStats.formatBytes(clearedBytes)}'),
          duration: AppConstants.snackBarDurationImportant,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清理缓存失败: $e'),
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
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理无用媒体文件'),
        content: const Text('这将删除没有被任何笔记引用的媒体文件（图片、视频、音频）。\n\n确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
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

      final message =
          orphanCount > 0 ? '清理完成，删除了 $orphanCount 个无用文件' : '没有发现无用文件';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: AppConstants.snackBarDurationImportant,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清理失败: $e'),
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
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('数据库维护优化'),
        content: const Text(
          '此操作将对数据库进行优化维护，包括：\n\n'
          '• 整理碎片空间\n'
          '• 更新统计信息\n'
          '• 重建索引\n\n'
          '维护过程可能需要几秒到几分钟，具体取决于数据量大小。\n\n'
          '确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始维护'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isClearing = true;
    });

    String currentProgress = '准备中...';

    // 显示进度对话框
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text('数据库维护中...'),
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
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Text('维护完成'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('耗时: ${(durationMs / 1000).toStringAsFixed(1)} 秒'),
                const SizedBox(height: 8),
                Text(
                    '数据库大小: ${dbSizeBefore.toStringAsFixed(2)} MB → ${dbSizeAfter.toStringAsFixed(2)} MB'),
                const SizedBox(height: 8),
                Text(
                  spaceSaved > 0
                      ? '释放空间: ${spaceSaved.toStringAsFixed(2)} MB'
                      : '未释放空间（数据库已很紧凑）',
                  style: TextStyle(
                    color: spaceSaved > 0 ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('维护失败: ${result['message']}'),
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
          content: Text('维护失败: $e'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('存储管理'),
      ),
      body: _isLoading && _stats == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 总占用空间卡片
                _buildTotalStorageCard(colorScheme),
                const SizedBox(height: 16),

                // 数据库占用详情
                _buildSectionTitle('数据库占用'),
                const SizedBox(height: 8),
                _buildDatabaseStorageCard(colorScheme),
                const SizedBox(height: 16),

                // 媒体文件占用详情
                _buildSectionTitle('媒体文件占用'),
                const SizedBox(height: 8),
                _buildMediaStorageCard(colorScheme),
                const SizedBox(height: 16),

                // 缓存占用
                _buildSectionTitle('缓存占用'),
                const SizedBox(height: 8),
                _buildCacheStorageCard(colorScheme),
                const SizedBox(height: 24),

                // 操作按钮
                _buildActionButtons(colorScheme),
                const SizedBox(height: 24),

                // 数据目录信息（仅桌面端）
                if (!kIsWeb &&
                    (Platform.isWindows ||
                        Platform.isLinux ||
                        Platform.isMacOS))
                  _buildDataDirectorySection(colorScheme),
              ],
            ),
    );
  }

  /// 构建总存储空间卡片
  Widget _buildTotalStorageCard(ColorScheme colorScheme) {
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
                        '总占用空间',
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
                    _buildLegendItem('笔记数据库', Colors.blue, mainDbSize),
                  if (aiDbSize > 0)
                    _buildLegendItem('AI数据库', Colors.purple, aiDbSize),
                  if (logDbSize > 0)
                    _buildLegendItem('日志数据库', Colors.orange, logDbSize),
                  if (mediaSize > 0)
                    _buildLegendItem('媒体文件', Colors.green, mediaSize),
                  if (cacheSize > 0)
                    _buildLegendItem('缓存', Colors.grey, cacheSize),
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
  Widget _buildDatabaseStorageCard(ColorScheme colorScheme) {
    return Card(
      child: Column(
        children: [
          _buildStorageItem(
            icon: Icons.sticky_note_2_outlined,
            label: '笔记数据库',
            size: _stats?.mainDatabaseSize ?? 0,
            color: Colors.blue,
          ),
          const Divider(height: 1),
          _buildStorageItem(
            icon: Icons.analytics_outlined,
            label: 'AI分析数据库',
            size: _stats?.aiDatabaseSize ?? 0,
            color: Colors.purple,
          ),
          const Divider(height: 1),
          _buildStorageItem(
            icon: Icons.description_outlined,
            label: '日志数据库',
            size: _stats?.logDatabaseSize ?? 0,
            color: Colors.orange,
          ),
        ],
      ),
    );
  }

  /// 构建媒体存储卡片
  Widget _buildMediaStorageCard(ColorScheme colorScheme) {
    final breakdown = _stats?.mediaBreakdown;

    return Card(
      child: Column(
        children: [
          _buildStorageItem(
            icon: Icons.image_outlined,
            label: '图片',
            size: breakdown?.imagesSize ?? 0,
            count: breakdown?.imagesCount ?? 0,
            color: Colors.green,
          ),
          const Divider(height: 1),
          _buildStorageItem(
            icon: Icons.videocam_outlined,
            label: '视频',
            size: breakdown?.videosSize ?? 0,
            count: breakdown?.videosCount ?? 0,
            color: Colors.red,
          ),
          const Divider(height: 1),
          _buildStorageItem(
            icon: Icons.audiotrack_outlined,
            label: '音频',
            size: breakdown?.audiosSize ?? 0,
            count: breakdown?.audiosCount ?? 0,
            color: Colors.teal,
          ),
        ],
      ),
    );
  }

  /// 构建缓存存储卡片
  Widget _buildCacheStorageCard(ColorScheme colorScheme) {
    return Card(
      child: _buildStorageItem(
        icon: Icons.cleaning_services_outlined,
        label: '临时文件和缓存',
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
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      subtitle: count != null && count > 0 ? Text('$count 个文件') : null,
      trailing: Text(
        StorageStats.formatBytes(size),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButtons(ColorScheme colorScheme) {
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
          label: const Text('清理缓存'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isClearing ? null : _cleanupOrphanFiles,
          icon: const Icon(Icons.delete_sweep),
          label: const Text('清理无用媒体文件'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isClearing ? null : _performDatabaseMaintenance,
          icon: const Icon(Icons.build_circle_outlined),
          label: const Text('数据库维护优化'),
        ),
      ],
    );
  }

  /// 选择新的数据目录
  Future<void> _selectNewDataDirectory() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择新的数据存储目录',
      );

      if (result == null || !mounted) return;

      // 验证目录
      final isValid = await DataDirectoryService.validateDirectory(result);
      if (!isValid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('所选目录不可用或没有写权限'),
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
          title: const Text('确认数据迁移'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('即将迁移所有应用数据到：'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  result,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '⚠️ 迁移过程可能需要几分钟，期间请勿关闭应用。\n'
                '⚠️ 迁移完成后需要重启应用才能生效。',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始迁移'),
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
          content: Text('选择目录失败: $e'),
          duration: AppConstants.snackBarDurationError,
        ),
      );
    }
  }

  /// 执行数据迁移
  Future<void> _performDataMigration(String newPath) async {
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
                title: const Text('正在迁移数据'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 16),
                    Text(
                      statusMessage ?? '准备中...',
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
                  title: const Text('正在迁移数据'),
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
            title: const Text('迁移完成'),
            content: const Text(
              '数据已成功迁移到新目录！\n\n'
              '请重启应用以使更改生效。',
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  // 可以在这里添加退出应用的逻辑
                  // 或者提示用户手动重启
                },
                child: const Text('确定'),
              ),
            ],
          ),
        );

        // 刷新路径显示
        await _loadAppDataPath();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('数据迁移失败，请查看日志了解详情'),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭进度对话框
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('迁移失败: $e'),
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
  Widget _buildDataDirectorySection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('数据存储位置'),
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
                                '当前数据目录',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.7),
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
                                    '自定义',
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
                            _appDataPath ?? '加载中...',
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
                    'Windows端数据目录迁移',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '将应用数据迁移到其他位置（如D盘），释放系统盘空间',
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
                      label: Text(_isMigrating ? '迁移中...' : '更改数据目录'),
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
