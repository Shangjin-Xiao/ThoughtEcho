import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../utils/time_utils.dart';

/// 备份与还原页面
///
/// 支持新版ZIP格式备份（包含媒体文件）和旧版JSON格式兼容
class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  bool _isLoading = false;
  bool _includeMediaFiles = true; // 默认包含媒体文件

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据备份与还原'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBackupSection(),
            const SizedBox(height: 24),
            _buildRestoreSection(),
            const SizedBox(height: 24),
            _buildInfoSection(),
          ],
        ),
      ),
    );
  }

  /// 构建备份区域
  Widget _buildBackupSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.backup,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '数据备份',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 媒体文件选项
            CheckboxListTile(
              title: const Text('包含媒体文件'),
              subtitle: const Text('勾选后将备份图片、音频等媒体文件（文件更大但更完整）'),
              value: _includeMediaFiles,
              onChanged:
                  _isLoading
                      ? null
                      : (value) {
                        setState(() {
                          _includeMediaFiles = value ?? true;
                        });
                      },
            ),

            const SizedBox(height: 16),

            // 备份按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleBackup,
                icon:
                    _isLoading
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.save_alt),
                label: Text(_isLoading ? '正在备份...' : '创建备份'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 8),
            Text(
              '将创建${_includeMediaFiles ? 'ZIP' : 'JSON'}格式的备份文件，包含所有笔记、设置${_includeMediaFiles ? '和媒体文件' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建还原区域
  Widget _buildRestoreSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.restore,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  '数据还原',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleRestore,
                icon: const Icon(Icons.folder_open),
                label: const Text('选择备份文件还原'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
            ),

            const SizedBox(height: 8),
            Text(
              '支持新版ZIP格式和旧版JSON格式的备份文件',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建信息区域
  Widget _buildInfoSection() {
    return Card(
      color: Theme.of(
        context,
      ).colorScheme.errorContainer.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '重要提示',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildInfoItem('数据安全', '还原数据将覆盖当前所有数据，请在还原前确保当前数据已备份'),
            _buildInfoItem('备份建议', '建议定期备份数据到多个位置（本地、云存储等）'),
            _buildInfoItem('格式说明', '新版ZIP格式包含完整数据和媒体文件，旧版JSON格式仅包含文本数据'),
            _buildInfoItem('兼容性', '支持导入新版ZIP格式和旧版JSON格式的备份文件'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 8, right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodySmall,
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: content),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 处理备份操作
  Future<void> _handleBackup() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final backupService = Provider.of<BackupService>(context, listen: false);
      final now = DateTime.now();
      final formattedDate = TimeUtils.formatFileTimestamp(now);
      final extension = _includeMediaFiles ? 'zip' : 'json';
      final fileName = '心迹_备份_$formattedDate.$extension';

      String? backupPath;

      if (kIsWeb) {
        // Web 平台：直接创建备份并分享
        backupPath = await backupService.exportAllData(
          includeMediaFiles: _includeMediaFiles,
        );

        if (mounted) {
          await Share.shareXFiles(
            [XFile(backupPath)],
            text: '心迹备份文件',
            subject: fileName,
          );

          _showSuccessSnackBar('备份文件已准备就绪，请通过分享保存');
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        // 移动平台：创建备份并分享
        backupPath = await backupService.exportAllData(
          includeMediaFiles: _includeMediaFiles,
        );

        if (mounted) {
          await Share.shareXFiles(
            [XFile(backupPath)],
            text: '心迹备份文件',
            subject: fileName,
          );

          _showSuccessSnackBar('备份完成，请选择保存位置');
        }
      } else {
        // 桌面平台：选择保存位置
        final saveLocation = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: [
            XTypeGroup(
              label: _includeMediaFiles ? 'ZIP 文件' : 'JSON 文件',
              extensions: [extension],
            ),
          ],
        );

        if (saveLocation != null && mounted) {
          backupPath = await backupService.exportAllData(
            includeMediaFiles: _includeMediaFiles,
            customPath: saveLocation.path,
          );

          _showSuccessSnackBar('备份已保存到: ${saveLocation.path}');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('备份失败', '无法完成备份：$e\n\n请检查存储空间和权限设置。');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 处理还原操作
  Future<void> _handleRestore() async {
    if (!mounted) return;

    try {
      // 选择备份文件
      const typeGroups = [
        XTypeGroup(label: 'ZIP 备份文件', extensions: ['zip']),
        XTypeGroup(label: 'JSON 备份文件', extensions: ['json']),
        XTypeGroup(label: '所有支持的格式', extensions: ['zip', 'json']),
      ];

      final file = await openFile(acceptedTypeGroups: typeGroups);
      if (file == null || !mounted) return;

      setState(() {
        _isLoading = true;
      });

      final backupService = Provider.of<BackupService>(context, listen: false);

      // 验证备份文件
      final isValid = await backupService.validateBackupFile(file.path);
      if (!isValid) {
        if (mounted) {
          _showErrorDialog('无效的备份文件', '所选文件不是有效的心迹备份文件。\n\n请选择正确的备份文件。');
        }
        return;
      }

      // 确认还原操作
      if (mounted) {
        final confirmed = await _showRestoreConfirmDialog();
        if (!confirmed) return;
      }

      // 执行还原
      await backupService.importData(file.path, clearExisting: true);

      if (mounted) {
        // 还原成功，回到主页并显示成功消息
        Navigator.of(context).popUntil((route) => route.isFirst);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('数据还原成功！所有数据已更新。'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('还原失败', '无法完成数据还原：$e\n\n请检查备份文件是否完整。');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 显示还原确认对话框
  Future<bool> _showRestoreConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('确认还原数据'),
                  ],
                ),
                content: const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '此操作将：',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 8),
                    Text('• 删除当前设备上的所有笔记和设置'),
                    Text('• 用备份文件中的数据替换'),
                    Text('• 此操作无法撤销'),
                    SizedBox(height: 16),
                    Text(
                      '请确保您已经备份了当前的重要数据。',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('确认还原'),
                  ),
                ],
              ),
        ) ??
        false;
  }

  /// 显示成功提示
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// 显示错误对话框
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
    );
  }
}
