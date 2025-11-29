import 'dart:io';
import '../constants/app_constants.dart';
import '../gen_l10n/app_localizations.dart';

import 'package:file_selector/file_selector.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/backup_service.dart';
import '../services/large_file_manager.dart';
import '../utils/time_utils.dart';
import '../utils/stream_file_selector.dart';

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
  double _progress = 0.0;
  String _progressText = '';
  CancelToken? _cancelToken;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupAndRestore), elevation: 0),
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
    final l10n = AppLocalizations.of(context);
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
                  l10n.dataBackup,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 媒体文件选项
            CheckboxListTile(
              title: Text(l10n.includeMediaFiles),
              subtitle: const Text('勾选后将备份图片、音频等媒体文件（文件更大但更完整）'),
              value: _includeMediaFiles,
              onChanged: _isLoading
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
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt),
                label: Text(_isLoading ? l10n.creatingBackup : l10n.createBackup),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // 进度显示
            if (_isLoading) ...[
              const SizedBox(height: 16),
              Column(
                children: [
                  LinearProgressIndicator(value: _progress / 100),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _progressText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${_progress.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      _cancelToken?.cancel();
                      setState(() {
                        _isLoading = false;
                        _progress = 0.0;
                        _progressText = '';
                      });
                    },
                    child: const Text('取消'),
                  ),
                ],
              ),
            ],

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
    final l10n = AppLocalizations.of(context);
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
                  l10n.dataRestore,
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
                label: Text(l10n.selectBackupFileToRestore),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                ),
              ),
            ),

            // 还原进度显示
            if (_isLoading) ...[
              const SizedBox(height: 16),
              Column(
                children: [
                  LinearProgressIndicator(value: _progress / 100),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _progressText,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_progress.toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      _cancelToken?.cancel();
                      setState(() {
                        _isLoading = false;
                        _progress = 0.0;
                        _progressText = '';
                      });
                    },
                    child: const Text('取消'),
                  ),
                ],
              ),
            ],

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
    final l10n = AppLocalizations.of(context);
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
                  l10n.importantNotes,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoItem(l10n.dataSecurity, l10n.dataSafetyDesc),
            _buildInfoItem(l10n.backupAdvice, l10n.backupAdviceDesc),
            _buildInfoItem(l10n.formatInfo, l10n.formatInfoDesc),
            _buildInfoItem(l10n.compatibility, l10n.compatibilityDesc),
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
      _progress = 0.0;
      _progressText = '准备开始备份...';
    });

    // 创建取消令牌
    _cancelToken = CancelToken();

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
          onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _progress = (current / total * 100).toDouble();

                // 根据进度阶段显示不同的状态文本
                if (current < 15) {
                  _progressText = '正在收集数据...';
                } else if (current < 30) {
                  _progressText = '正在处理笔记数据...';
                } else if (current < 60) {
                  _progressText = '正在处理媒体文件...';
                } else if (current < 95) {
                  _progressText = '正在创建备份文件...';
                } else {
                  _progressText = '正在验证备份文件...';
                }
              });
            }
          },
          cancelToken: _cancelToken,
        );

        if (mounted) {
          await SharePlus.instance.share(
            ShareParams(
              text: '心迹备份文件',
              subject: fileName,
              files: [XFile(backupPath)],
            ),
          );

          _showSuccessSnackBar('备份文件已准备就绪，请通过分享保存');
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        // 移动平台：创建备份并分享
        backupPath = await backupService.exportAllData(
          includeMediaFiles: _includeMediaFiles,
          onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _progress = (current / total * 100).toDouble();

                // 根据进度阶段显示不同的状态文本
                if (current < 15) {
                  _progressText = '正在收集数据...';
                } else if (current < 30) {
                  _progressText = '正在处理笔记数据...';
                } else if (current < 60) {
                  _progressText = '正在处理媒体文件...';
                } else if (current < 95) {
                  _progressText = '正在创建备份文件...';
                } else {
                  _progressText = '正在验证备份文件...';
                }
              });
            }
          },
          cancelToken: _cancelToken,
        );

        if (mounted) {
          await SharePlus.instance.share(
            ShareParams(
              text: '心迹备份文件',
              subject: fileName,
              files: [XFile(backupPath)],
            ),
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
            onProgress: (current, total) {
              if (mounted) {
                setState(() {
                  _progress = (current / total * 100).toDouble();

                  // 根据进度阶段显示不同的状态文本
                  if (current < 15) {
                    _progressText = '正在收集数据...';
                  } else if (current < 30) {
                    _progressText = '正在处理笔记数据...';
                  } else if (current < 60) {
                    _progressText = '正在处理媒体文件...';
                  } else if (current < 95) {
                    _progressText = '正在创建备份文件...';
                  } else {
                    _progressText = '正在验证备份文件...';
                  }
                });
              }
            },
            cancelToken: _cancelToken,
          );

          _showSuccessSnackBar('备份已保存到: ${saveLocation.path}');
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = '无法完成备份：$e';

        // 针对不同类型的错误提供更友好的提示
        if (e.toString().contains('OutOfMemoryError') ||
            e.toString().contains('内存不足')) {
          errorMessage =
              '备份失败：内存不足\n\n建议：\n• 关闭其他应用释放内存\n• 尝试不包含媒体文件的备份\n• 重启应用后再试';
        } else if (e.toString().contains('存储空间') ||
            e.toString().contains('No space left')) {
          errorMessage = '备份失败：存储空间不足\n\n请清理设备存储空间后重试。';
        } else if (e.toString().contains('权限') ||
            e.toString().contains('Permission')) {
          errorMessage = '备份失败：权限不足\n\n请检查应用的存储权限设置。';
        } else if (e.toString().contains('cancelled') ||
            e.toString().contains('取消')) {
          errorMessage = '备份已取消';
        }

        _showErrorDialog('备份失败', errorMessage);
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
      final FilePickerResult? result = await StreamFileSelector.selectFile(
        extensions: ['zip', 'json'],
        description: 'Backup Files',
      );
      if (result == null || result.files.isEmpty || !mounted) return;

      final file = result.files.first;
      if (file.path == null) {
        _showErrorDialog('选择文件失败', '无法获取文件路径，请重新选择');
        return;
      }

      setState(() {
        _isLoading = true;
      });

      final backupService = Provider.of<BackupService>(context, listen: false);

      // 验证备份文件
      final isValid = await backupService.validateBackupFile(file.path!);
      if (!isValid) {
        if (mounted) {
          _showErrorDialog('无效的备份文件', '所选文件不是有效的心迹备份文件。\n\n请选择正确的备份文件。');
        }
        return;
      }

      // 选择导入模式：覆盖 或 合并(LWW)
      bool useMerge = false;
      if (mounted) {
        final mode = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (c) {
            String selected = 'overwrite';
            return StatefulBuilder(builder: (ctx, setLocal) {
              return AlertDialog(
                title: const Text('选择导入模式'),
                content: RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (v) => setLocal(() => selected = v!),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RadioListTile<String>(
                        title: Text('覆盖导入 (清空现有数据)'),
                        subtitle: Text('删除当前所有数据，以备份内容替换'),
                        value: 'overwrite',
                        dense: true,
                      ),
                      RadioListTile<String>(
                        title: Text('合并导入 (LWW策略)'),
                        subtitle: Text('保留现有数据，与备份数据按更新时间合并'),
                        value: 'merge',
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(null),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(selected),
                    child: const Text('继续'),
                  ),
                ],
              );
            });
          },
        );
        if (mode == null) return; // 用户取消
        useMerge = mode == 'merge';
      }

      // 确认还原/合并操作
      if (mounted) {
        final confirmed = useMerge
            ? await _showMergeConfirmDialog()
            : await _showRestoreConfirmDialog();
        if (!confirmed) return;
      }

      // 执行导入
      if (useMerge) {
        final report = await backupService.importData(
          file.path!,
          clearExisting: false,
          merge: true,
          onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _progress = (current / total * 100).toDouble();
                _progressText = '正在合并数据... $current/$total';
              });
            }
          },
          cancelToken: _cancelToken,
        );
        debugPrint('合并导入完成: ${report?.summary}');
      } else {
        await backupService.importData(
          file.path!,
          clearExisting: true,
          onProgress: (current, total) {
            if (mounted) {
              setState(() {
                _progress = (current / total * 100).toDouble();
                _progressText = '正在还原数据... $current/$total';
              });
            }
          },
          cancelToken: _cancelToken,
        );
      }

      if (mounted) {
        // 还原成功，回到主页并显示成功消息
        Navigator.of(context).popUntil((route) => route.isFirst);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('数据还原成功！所有数据已更新。'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: AppConstants.snackBarDurationImportant,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = '无法完成数据还原：$e';

        // 修复：针对不同类型的错误提供更友好的提示
        if (e.toString().contains('OutOfMemoryError') ||
            e.toString().contains('内存不足')) {
          errorMessage =
              '还原失败：内存不足\n\n建议：\n• 关闭其他应用释放内存\n• 重启应用后再试\n• 检查备份文件大小是否过大';
        } else if (e.toString().contains('存储空间') ||
            e.toString().contains('No space left')) {
          errorMessage = '还原失败：存储空间不足\n\n请清理设备存储空间后重试。';
        } else if (e.toString().contains('权限') ||
            e.toString().contains('Permission')) {
          errorMessage = '还原失败：权限不足\n\n请检查应用的存储权限设置。';
        } else if (e.toString().contains('cancelled') ||
            e.toString().contains('取消')) {
          errorMessage = '还原已取消';
        } else if (e.toString().contains('无效') ||
            e.toString().contains('corrupt')) {
          errorMessage = '还原失败：备份文件损坏或格式不正确\n\n请检查备份文件是否完整。';
        } else if (e.toString().contains('has no column named')) {
          // 修复：专门处理字段名不匹配的错误
          final columnMatch = RegExp(
            r'has no column named (\w+)',
          ).firstMatch(e.toString());
          final columnName = columnMatch?.group(1) ?? '未知字段';

          errorMessage = '''还原失败：备份文件格式不兼容

问题：数据库中缺少字段 "$columnName"

可能的原因：
• 备份文件来自较旧版本的应用
• 字段名格式发生了变化（如：sourceAuthor → source_author）
• 备份文件中包含了当前版本不支持的字段

解决方案：
1. 确保使用最新版本的应用
2. 如果备份来自旧版本，请尝试先升级应用再导入
3. 如果问题持续，请联系开发者获取帮助

技术详情：$e''';
        } else if (e.toString().contains('SQLITE_ERROR')) {
          errorMessage = '''还原失败：数据库操作错误

这可能是由于：
• 备份文件格式不正确
• 数据库约束冲突
• 字段类型不匹配

建议：
1. 检查备份文件是否完整
2. 尝试重新导出备份文件
3. 确保备份文件来自相同或兼容的应用版本

技术详情：$e''';
        }

        _showErrorDialog('还原失败', errorMessage);
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
          builder: (context) => AlertDialog(
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

  /// 显示合并导入确认对话框
  Future<bool> _showMergeConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.merge_type, color: Colors.indigo),
                SizedBox(width: 8),
                Text('确认合并导入'),
              ],
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('此操作将保留当前数据，并与备份数据进行合并：'),
                SizedBox(height: 8),
                Text('• 相同ID的笔记按“最后写入 wins”保留较新版本'),
                Text('• 不同ID的笔记全部保留'),
                Text('• 设置与AI分析数据合并追加'),
                SizedBox(height: 12),
                Text('此操作可逆：可再次导入覆盖备份或继续合并。'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('开始合并'),
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
        duration: AppConstants.snackBarDurationImportant,
      ),
    );
  }

  /// 显示错误对话框
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
