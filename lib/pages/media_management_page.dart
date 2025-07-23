import 'package:flutter/material.dart';
import '../services/media_cleanup_service.dart';
import '../services/media_reference_service.dart';
import '../services/temporary_media_service.dart';
import '../utils/app_logger.dart';

/// 媒体文件管理页面
///
/// 提供媒体文件的统计、清理、维护等功能
class MediaManagementPage extends StatefulWidget {
  const MediaManagementPage({super.key});

  @override
  State<MediaManagementPage> createState() => _MediaManagementPageState();
}

class _MediaManagementPageState extends State<MediaManagementPage> {
  bool _isLoading = false;
  Map<String, dynamic>? _mediaStats;
  String? _lastOperation;
  Map<String, dynamic>? _lastOperationResult;

  @override
  void initState() {
    super.initState();
    _loadMediaStats();
  }

  Future<void> _loadMediaStats() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final stats = await MediaCleanupService.getMediaStats();
      setState(() {
        _mediaStats = stats;
      });
    } catch (e) {
      logDebug('加载媒体统计信息失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载统计信息失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _performOperation(
      String operation, Future<Map<String, dynamic>> Function() action) async {
    setState(() {
      _isLoading = true;
      _lastOperation = operation;
      _lastOperationResult = null;
    });

    try {
      final result = await action();
      setState(() {
        _lastOperationResult = result;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$operation 完成'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // 重新加载统计信息
      await _loadMediaStats();
    } catch (e) {
      logDebug('$operation 失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$operation 失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体文件管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadMediaStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsSection(),
                  const SizedBox(height: 24),
                  _buildActionsSection(),
                  const SizedBox(height: 24),
                  if (_lastOperationResult != null) _buildResultSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsSection() {
    if (_mediaStats == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('无法加载统计信息'),
        ),
      );
    }

    final stats = _mediaStats!;
    final tempStats = stats['tempFiles'] as Map<String, dynamic>? ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '媒体文件统计',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStatRow('总文件数', '${stats['totalFiles'] ?? 0}'),
            _buildStatRow('被引用文件数', '${stats['referencedFiles'] ?? 0}'),
            _buildStatRow('孤儿文件数', '${stats['orphanFiles'] ?? 0}'),
            _buildStatRow('总引用数', '${stats['totalReferences'] ?? 0}'),
            const Divider(),
            _buildStatRow('总大小',
                '${(stats['totalSizeMB'] ?? 0.0).toStringAsFixed(2)} MB'),
            _buildStatRow('图片大小',
                '${(stats['imagesSizeMB'] ?? 0.0).toStringAsFixed(2)} MB'),
            _buildStatRow('视频大小',
                '${(stats['videosSizeMB'] ?? 0.0).toStringAsFixed(2)} MB'),
            _buildStatRow('音频大小',
                '${(stats['audiosSizeMB'] ?? 0.0).toStringAsFixed(2)} MB'),
            const Divider(),
            const Text(
              '临时文件',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _buildStatRow('临时文件数', '${tempStats['totalFiles'] ?? 0}'),
            _buildStatRow('过期文件数', '${tempStats['expiredFiles'] ?? 0}'),
            _buildStatRow('临时文件大小',
                '${(tempStats['totalSizeMB'] ?? 0.0).toStringAsFixed(2)} MB'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '清理操作',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              '清理过期临时文件',
              '删除超过24小时的临时文件',
              Icons.cleaning_services,
              () => _performOperation(
                '清理过期临时文件',
                () async {
                  final count = await TemporaryMediaService
                      .cleanupExpiredTemporaryFiles();
                  return {'cleanedFiles': count};
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              '清理孤儿文件',
              '删除没有被任何笔记引用的媒体文件',
              Icons.delete_sweep,
              () => _performOperation(
                '清理孤儿文件',
                () async {
                  final count =
                      await MediaReferenceService.cleanupOrphanFiles();
                  return {'cleanedFiles': count};
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              '完整清理',
              '清理所有临时文件和孤儿文件',
              Icons.cleaning_services_outlined,
              () => _performOperation(
                '完整清理',
                () => MediaCleanupService.performFullCleanup(),
              ),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              '迁移现有笔记',
              '重新建立现有笔记的媒体文件引用关系',
              Icons.sync,
              () => _performOperation(
                '迁移现有笔记',
                () => MediaCleanupService.migrateExistingNotes(),
              ),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              '验证文件完整性',
              '检查媒体文件引用的完整性',
              Icons.verified,
              () => _performOperation(
                '验证文件完整性',
                () => MediaCleanupService.verifyMediaIntegrity(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultSection() {
    final result = _lastOperationResult!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$_lastOperation 结果',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            for (final entry in result.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatKey(entry.key)),
                    Text(
                      _formatValue(entry.value),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatKey(String key) {
    switch (key) {
      case 'cleanedFiles':
        return '清理文件数';
      case 'spaceSavedMB':
        return '节省空间 (MB)';
      case 'migratedQuotes':
        return '迁移笔记数';
      case 'orphanFilesDetected':
        return '检测到孤儿文件';
      case 'checkedReferences':
        return '检查引用数';
      case 'missingFiles':
        return '缺失文件数';
      case 'isHealthy':
        return '文件完整性';
      default:
        return key;
    }
  }

  String _formatValue(dynamic value) {
    if (value is bool) {
      return value ? '正常' : '异常';
    } else if (value is double) {
      return value.toStringAsFixed(2);
    } else {
      return value.toString();
    }
  }
}
