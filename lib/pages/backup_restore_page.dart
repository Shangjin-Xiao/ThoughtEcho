import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart'; 
import '../services/database_service.dart';
import 'home_page.dart';
import '../utils/color_utils.dart'; // Import color_utils.dart

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  Future<void> _handleExport(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final dbService = Provider.of<DatabaseService>(context, listen: false);

    try {
      final loadingOverlay = _showLoadingOverlay(context, '准备导出数据...');
      bool canExport = false;
      try {
        canExport = await dbService.checkCanExport();
      } catch (e) {
        debugPrint('数据库访问验证失败: $e');
      }
      loadingOverlay.remove();
      if (!mounted) return;
      if (!canExport) {
        _showErrorDialog(context, '数据访问错误', '无法访问数据库，请确保应用有足够的存储权限，然后重试。');
        return;
      }
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('选择备份方式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.save),
                title: const Text('保存到本地'),
                subtitle: const Text('选择保存位置'),
                onTap: () => Navigator.pop(dialogContext, 'save'),
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享备份文件'),
                subtitle: const Text('通过其他应用分享'),
                onTap: () => Navigator.pop(dialogContext, 'share'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (choice == null) return;
      String path = '';
      if (!mounted) return;
      final progressOverlay = _showLoadingOverlay(context, '正在导出数据...');
      try {
        if (choice == 'save') {
          final now = DateTime.now();
          final formattedDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
          final fileName = '心迹_备份_$formattedDate.json';
          if (Platform.isWindows) {
            final tempDir = await getTemporaryDirectory();
            final tempFilePath = '${tempDir.path}/$fileName';
            final tempFile = await dbService.exportAllData(customPath: tempFilePath);
            progressOverlay.remove();
            if (!mounted) return;
            final saveLocation = await getSaveLocation(
              suggestedName: fileName,
              acceptedTypeGroups: [
                const XTypeGroup(label: 'JSON', extensions: ['json']),
              ],
            );
            if (saveLocation == null) {
              try { File(tempFile).deleteSync(); } catch (_) {}
              return;
            }
            if (!mounted) return;
            final saveOverlay = _showLoadingOverlay(context, '正在保存文件...');
            try {
              await File(tempFile).copy(saveLocation.path);
              await File(tempFile).delete();
              path = saveLocation.path;
              saveOverlay.remove();
              if (!mounted) return;
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('备份已保存到: $path'),
                  duration: const Duration(seconds: 5),
                ),
              );
            } catch (e) {
              saveOverlay.remove();
              rethrow;
            }
          } else if (Platform.isAndroid) {
            final docsDir = await getApplicationDocumentsDirectory();
            final localPath = '${docsDir.path}/$fileName';
            path = await dbService.exportAllData(customPath: localPath);
            progressOverlay.remove();
            if (!mounted) return;
            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text('备份文件已生成，即将打开分享选项...'),
                duration: Duration(seconds: 2),
              ),
            );
            await Future.delayed(const Duration(seconds: 1));
            if (!mounted) return;
            await Share.shareXFiles(
              [XFile(path)],
              text: '心迹备份文件',
              subject: '保存心迹备份文件',
            );
            if (!mounted) return;
            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text('提示: 选择"保存到设备"可将备份文件保存到本地存储'),
                duration: Duration(seconds: 5),
              ),
            );
          } else {
            try {
              if (!mounted) return;
              final saveLocation = await getSaveLocation(
                suggestedName: fileName,
                acceptedTypeGroups: [
                  const XTypeGroup(label: 'JSON', extensions: ['json']),
                ],
              );
              progressOverlay.remove();
              if (saveLocation == null) return;
              if (!mounted) return;
              final exportOverlay = _showLoadingOverlay(context, '正在保存数据...');
              try {
                path = await dbService.exportAllData(customPath: saveLocation.path);
                exportOverlay.remove();
                if (!mounted) return;
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('备份已保存到: $path'),
                    duration: const Duration(seconds: 5),
                  ),
                );
              } catch (e) {
                exportOverlay.remove();
                rethrow;
              }
            } catch (e) {
              progressOverlay.remove();
              rethrow;
            }
          }
        } else {
          path = await dbService.exportAllData();
          progressOverlay.remove();
          if (!mounted) return;
          await Share.shareXFiles(
            [XFile(path)],
            text: '心迹应用数据备份',
          );
        }
      } catch (e) {
        progressOverlay.remove();
        if (!mounted) return;
        _showErrorDialog(context, '备份失败', '无法完成备份: $e\n\n请检查应用权限和剩余存储空间。');
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog(context, '备份失败', '发生未知错误: $e\n\n请重试并检查应用权限。');
    }
  }

  Future<void> _handleImport(BuildContext context) async {
    final navigator = Navigator.of(context);
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    try {
      const XTypeGroup jsonTypeGroup = XTypeGroup(label: 'JSON', extensions: ['json']);
      final XFile? file = await openFile(acceptedTypeGroups: [jsonTypeGroup]);
      final result = file != null ? {'files': [file]} : null;
      if (result == null) return;
      if (!mounted) return;
      final selectedFile = result['files']![0];
      final validateOverlay = _showLoadingOverlay(context, '正在验证备份文件...');
      bool isValidBackup = false;
      String errorMessage = '';
      try {
        isValidBackup = await dbService.validateBackupFile(selectedFile.path);
      } catch (e) {
        errorMessage = e.toString();
      } finally {
        validateOverlay.remove();
      }
      if (!mounted) return;
      if (!isValidBackup) {
        _showErrorDialog(
          context,
          '无效的备份文件',
          '所选文件不是有效的心迹备份文件${errorMessage.isNotEmpty ? ':\n\n$errorMessage' : '。'}\n\n请选择有效的备份文件。'
        );
        return;
      }
      if (!mounted) return;
      final importOption = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('导入选项'),
          content: const Text('请选择导入方式：'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'clear'),
              child: const Text('清空并导入'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'merge'),
              child: const Text('合并数据'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (importOption == 'cancel' || importOption == null) return;
      if (importOption == 'clear') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('确认清空数据'),
            content: const Text('这将清空当前所有数据，确定要继续吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('确定清空并导入'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        if (!mounted) return;
      }
      final importOverlay = _showLoadingOverlay(context, '正在导入数据...');
      try {
        final bool clearExisting = importOption == 'clear';
        await dbService.importData(selectedFile.path, clearExisting: clearExisting);
        importOverlay.remove();
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('导入成功'),
            content: const Text('数据已成功导入。\n\n需要重启应用以完成导入过程。'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  if (!mounted) return;
                  navigator.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomePage()),
                    (route) => false,
                  );
                },
                child: const Text('重启应用'),
              ),
            ],
          ),
        );
      } catch (e) {
        importOverlay.remove();
        if (!mounted) return;
        _showErrorDialog(context, '导入失败', '导入数据时发生错误: $e');
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog(context, '恢复失败', '无法访问或读取备份文件: $e');
    }
  }
  
  OverlayEntry _showLoadingOverlay(BuildContext context, String message) {
    if (!mounted) return OverlayEntry(builder: (_) => const SizedBox.shrink());
    final overlay = OverlayEntry(
      builder: (overlayContext) => Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(overlay);
    return overlay;
  }
  
  void _showErrorDialog(BuildContext context, String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据备份与恢复')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '定期备份数据可以帮助您防止意外数据丢失。建议每次进行重要更改后都创建一个备份。',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.applyOpacity(0.7), // Use applyOpacity
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('备份数据'),
            subtitle: const Text('导出所有数据并选择保存方式'),
            onTap: () => _handleExport(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('恢复数据'),
            subtitle: const Text('从备份文件导入数据'),
            onTap: () => _handleImport(context),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              color: Colors.amber, // This is a const color, so it should be fine.
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, size: 20, color: Theme.of(context).colorScheme.onError.applyOpacity(0.8)),
                        const SizedBox(width: 8),
                        const Text(
                          '数据安全提示',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. 请在多个位置保存备份文件，如云存储和本地存储\n'
                      '2. 导入前建议先备份当前数据，以防导入失败\n'
                      '3. 确保备份文件来源可靠，避免导入损坏的文件\n'
                      '4. 推荐在重要操作或APP更新前进行备份',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '重要提示：',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onError.applyOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 恢复数据时，如果选择“清空并导入”，当前设备上的所有笔记和标签都将被删除，并替换为备份文件中的数据。此操作无法撤销。',
                      style: TextStyle(color: Theme.of(context).colorScheme.onError.applyOpacity(0.85)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• 如果选择“合并数据”，备份文件中的数据将尝试与现有数据合并。如果存在ID冲突的笔记或标签，备份文件中的版本将覆盖现有版本。',
                      style: TextStyle(color: Theme.of(context).colorScheme.onError.applyOpacity(0.85)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• 请确保您从可信任的来源导入备份文件，以避免潜在的数据损坏或安全风险。',
                      style: TextStyle(color: Theme.of(context).colorScheme.onError.applyOpacity(0.85)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}