import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import '../services/database_service.dart';
import 'home_page.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  Future<void> _handleExport(BuildContext context) async {
    try {
      final dbService = Provider.of<DatabaseService>(context, listen: false);
      final path = await dbService.exportAllData();
      
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('备份成功'),
          content: SelectableText('文件路径:\n$path'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份失败: $e')),
      );
    }
  }

  Future<void> _handleImport(BuildContext context) async {
    try {
      // 使用file_selector替代file_picker
      final XTypeGroup jsonTypeGroup = XTypeGroup(
        label: 'JSON',
        extensions: ['json'],
      );
      final XFile? file = await openFile(
        acceptedTypeGroups: [jsonTypeGroup],
      );
      
      // 转换为与原代码兼容的格式
      final result = file != null ? {'files': [file]} : null;
      
      if (result == null) return;
      
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认导入'),
          content: const Text('导入数据将清空当前所有数据，确定要继续吗？'),
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
      
      if (confirmed != true || !mounted) return;
      
      final dbService = Provider.of<DatabaseService>(context, listen: false);
      final selectedFile = result['files']![0] as XFile;
      await dbService.importData(selectedFile.path);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败: $e')),
      );
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
            subtitle: const Text('导出所有数据到本地文件'),
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
            child: Text('安全提示：请在操作前确保备份文件来源可靠，避免数据丢失',
              style: TextStyle(color: Colors.red, fontSize: 12)),
          )
        ],
      ),
    );
  }
}