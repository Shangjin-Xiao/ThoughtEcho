import 'package:flutter/material.dart';
import '../services/media_cleanup_service.dart';
import '../services/media_reference_service.dart';
import '../services/temporary_media_service.dart';
import '../utils/app_logger.dart';
import '../gen_l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);
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
            content: Text(l10n.loadStatsError(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
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
    final l10n = AppLocalizations.of(context);
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
            content: Text(l10n.operationCompleted(operation)),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
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
            content: Text(l10n.operationFailed(operation, e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mediaManagementTitle),
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
    final l10n = AppLocalizations.of(context);
    if (_mediaStats == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.loadStatsFailed),
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
            Text(
              l10n.mediaFileStats,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStatRow(l10n.totalFiles, '${stats['totalFiles'] ?? 0}'),
            _buildStatRow(
                l10n.referencedFiles, '${stats['referencedFiles'] ?? 0}'),
            _buildStatRow(l10n.orphanFiles, '${stats['orphanFiles'] ?? 0}'),
            _buildStatRow(
                l10n.totalReferences, '${stats['totalReferences'] ?? 0}'),
            const Divider(),
            _buildStatRow(l10n.totalSize,
                '${(stats['totalSizeMB'] ?? 0.0).toStringAsFixed(2)} MB'),
            _buildStatRow(l10n.imagesSize,
                '${(stats['imagesSizeMB'] ?? 0.0).toStringAsFixed(2)} MB'),
            _buildStatRow(l10n.videosSize,
                '${(stats['videosSizeMB'] ?? 0.0).toStringAsFixed(2)} MB'),
            _buildStatRow(l10n.audiosSize,
                '${(stats['audiosSizeMB'] ?? 0.0).toStringAsFixed(2)} MB'),
            const Divider(),
            Text(
              l10n.tempFiles,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _buildStatRow(
                l10n.tempFilesCount, '${tempStats['totalFiles'] ?? 0}'),
            _buildStatRow(
                l10n.expiredFilesCount, '${tempStats['expiredFiles'] ?? 0}'),
            _buildStatRow(l10n.tempFilesSize,
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
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.cleanupOperations,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              l10n.cleanupExpiredTempFiles,
              l10n.cleanupExpiredTempFilesDesc,
              Icons.cleaning_services,
              () => _performOperation(
                l10n.cleanupExpiredTempFiles,
                () async {
                  final count = await TemporaryMediaService
                      .cleanupExpiredTemporaryFiles();
                  return {'cleanedFiles': count};
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              l10n.cleanupOrphanFiles,
              l10n.cleanupOrphanFilesDesc,
              Icons.delete_sweep,
              () => _performOperation(
                l10n.cleanupOrphanFiles,
                () async {
                  final count =
                      await MediaReferenceService.cleanupOrphanFiles();
                  return {'cleanedFiles': count};
                },
              ),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              l10n.fullCleanup,
              l10n.fullCleanupDesc,
              Icons.cleaning_services_outlined,
              () => _performOperation(
                l10n.fullCleanup,
                () => MediaCleanupService.performFullCleanup(),
              ),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              l10n.migrateExistingNotes,
              l10n.migrateExistingNotesDesc,
              Icons.sync,
              () => _performOperation(
                l10n.migrateExistingNotes,
                () => MediaCleanupService.migrateExistingNotes(),
              ),
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              l10n.verifyFileIntegrity,
              l10n.verifyFileIntegrityDesc,
              Icons.verified,
              () => _performOperation(
                l10n.verifyFileIntegrity,
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
    final l10n = AppLocalizations.of(context);
    final result = _lastOperationResult!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.operationResult(_lastOperation!),
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
    final l10n = AppLocalizations.of(context);
    switch (key) {
      case 'cleanedFiles':
        return l10n.cleanedFilesCount;
      case 'spaceSavedMB':
        return l10n.spaceSavedMb;
      case 'migratedQuotes':
        return l10n.migratedQuotesCount;
      case 'orphanFilesDetected':
        return l10n.orphanFilesDetected;
      case 'checkedReferences':
        return l10n.checkedReferencesCount;
      case 'missingFiles':
        return l10n.missingFilesCount;
      case 'isHealthy':
        return l10n.fileIntegrity;
      default:
        return key;
    }
  }

  String _formatValue(dynamic value) {
    final l10n = AppLocalizations.of(context);
    if (value is bool) {
      return value ? l10n.normal : l10n.abnormal;
    } else if (value is double) {
      return value.toStringAsFixed(2);
    } else {
      return value.toString();
    }
  }
}
