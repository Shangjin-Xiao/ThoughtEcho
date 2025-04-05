import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import '../services/database_service.dart';
import 'home_page.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  Future<void> _handleExport(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // 显示备份选项对话框
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
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

      if (choice == null || !mounted) return;

      final dbService = Provider.of<DatabaseService>(context, listen: false);
      String path;

      if (choice == 'save') {
        // 使用文件选择器保存文件
        final fileName = '心迹_${DateTime.now().millisecondsSinceEpoch}.json';
        final saveLocation = await getSaveLocation(
          suggestedName: fileName,
          acceptedTypeGroups: [
            const XTypeGroup(label: 'JSON', extensions: ['json']),
          ],
        );

        if (saveLocation == null || !mounted) return;

        path = await dbService.exportAllData(customPath: saveLocation.path);

        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('备份已保存到: $path')),
        );
      } else {
        // 使用默认路径并分享
        path = await dbService.exportAllData();

        if (!mounted) return;
        await Share.shareXFiles([XFile(path)], text: '心迹应用数据备份');
      }
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('备份失败: $e')));
    }
  }

  Future<void> _handleImport(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      // 使用file_selector替代file_picker
      const jsonTypeGroup = XTypeGroup(label: 'JSON', extensions: ['json']);

      final XFile? file = await openFile(acceptedTypeGroups: [jsonTypeGroup]);

      if (file == null || !mounted) return;

      // 添加选项让用户选择是清空原有数据还是合并数据
      final importOption = await showDialog<String>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
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

      if (importOption == 'cancel' || importOption == null || !mounted) return;

      // 如果选择清空并导入，再次确认
      bool? confirmed = true;
      if (importOption == 'clear') {
        confirmed = await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                title: const Text('确认清空数据'),
                content: const Text('这将清空当前所有数据，确定要继续吗？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('确定'),
                  ),
                ],
              ),
        );
      }

      if (confirmed != true || !mounted) return;

      final dbService = Provider.of<DatabaseService>(context, listen: false);
      final bool clearExisting = importOption == 'clear';
      await dbService.importData(file.path, clearExisting: clearExisting);

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('数据已恢复，重启应用以完成导入'),
          duration: Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('恢复失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据备份与恢复')),
      body: ListView(
        children: [
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
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              '安全提示：请在操作前确保备份文件来源可靠，避免数据丢失',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
