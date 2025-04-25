import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart'; 
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
      // 显示备份选项对话框
      if (!mounted) return;
      
      // 显示加载指示器
      final loadingOverlay = _showLoadingOverlay(context, '准备导出数据...');
      
      // 确保数据库服务已初始化
      final dbService = Provider.of<DatabaseService>(context, listen: false);
      
      // 尝试预先验证能否导出
      bool canExport = await dbService.checkCanExport();
      
      // 关闭加载指示器
      loadingOverlay.remove();
      
      if (!canExport) {
        if (!mounted) return;
        _showErrorDialog(
          context, 
          '数据访问错误', 
          '无法访问数据库，请确保应用有足够的存储权限，然后重试。'
        );
        return;
      }
      
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('选择备份方式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.save),
                title: const Text('保存到本地'),
                subtitle: const Text('选择保存位置'),
                onTap: () => Navigator.pop(context, 'save'),
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('分享备份文件'),
                subtitle: const Text('通过其他应用分享'),
                onTap: () => Navigator.pop(context, 'share'),
              ),
            ],
          ),
        ),
      );
      
      if (choice == null) return;
      
      String path = '';
      
      // 显示导出进度
      final progressOverlay = _showLoadingOverlay(context, '正在导出数据...');
      
      try {
        if (choice == 'save') {
          // 创建临时文件
          final now = DateTime.now();
          final formattedDate = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
          final fileName = '心记_备份_$formattedDate.json';
          
          if (Platform.isWindows) {
            // Windows 平台特殊处理
            // 先创建备份文件到临时目录
            final tempDir = await getTemporaryDirectory();
            final tempFilePath = '${tempDir.path}/$fileName';
            
            // 导出到临时文件
            final tempFile = await dbService.exportAllData(customPath: tempFilePath);
            
            // 关闭进度指示器
            progressOverlay.remove();
            
            // 然后使用系统对话框保存
            final saveLocation = await getSaveLocation(
              suggestedName: fileName,
              acceptedTypeGroups: [
                const XTypeGroup(
                  label: 'JSON',
                  extensions: ['json'],
                ),
              ],
            );
            
            if (saveLocation == null) {
              // 用户取消了保存，删除临时文件
              try {
                File(tempFile).deleteSync();
              } catch (_) {}
              return;
            }
            
            // 创建新的进度指示器
            final saveOverlay = _showLoadingOverlay(context, '正在保存文件...');
            
            try {
              // 复制临时文件到用户选择的位置
              await File(tempFile).copy(saveLocation.path);
              
              // 删除临时文件
              await File(tempFile).delete();
              
              path = saveLocation.path;
              saveOverlay.remove();
              
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
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
            // 安卓平台特殊处理
            // 先导出到应用专用目录
            final docsDir = await getApplicationDocumentsDirectory();
            final localPath = '${docsDir.path}/$fileName';
            
            // 导出数据
            path = await dbService.exportAllData(customPath: localPath);
            
            // 关闭进度指示器
            progressOverlay.remove();
            
            // 使用分享功能让用户选择保存位置
            if (!mounted) return;
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('备份文件已生成，即将打开分享选项...'),
                duration: Duration(seconds: 2),
              ),
            );
            
            // 延迟一下再打开分享，让用户看到提示
            await Future.delayed(const Duration(seconds: 1));
            
            if (!mounted) return;
            await Share.shareXFiles(
              [XFile(path)],
              text: '心记备份文件',
              subject: '保存心记备份文件',
            );
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('提示: 选择"保存到设备"可将备份文件保存到本地存储'),
                duration: Duration(seconds: 5),
              ),
            );
          } else {
            // 其他平台使用常规方式
            try {
              final saveLocation = await getSaveLocation(
                suggestedName: fileName,
                acceptedTypeGroups: [
                  const XTypeGroup(
                    label: 'JSON',
                    extensions: ['json'],
                  ),
                ],
              );
              
              // 关闭进度指示器
              progressOverlay.remove();
              
              if (saveLocation == null) return;
              
              // 重新显示进度，因为用户选择了保存位置
              final exportOverlay = _showLoadingOverlay(context, '正在保存数据...');
              
              try {
                path = await dbService.exportAllData(customPath: saveLocation.path);
                
                exportOverlay.remove();
                
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
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
              // 确保关闭进度指示器
              progressOverlay.remove();
              rethrow;
            }
          }
        } else {
          // 使用默认路径并分享
          path = await dbService.exportAllData();
          
          progressOverlay.remove();
          
          if (!mounted) return;
          await Share.shareXFiles(
            [XFile(path)],
            text: '心记应用数据备份',
          );
        }
      } catch (e) {
        // 确保关闭进度指示器
        progressOverlay.remove();
        
        if (!mounted) return;
        _showErrorDialog(
          context, 
          '备份失败', 
          '无法完成备份: $e\n\n请检查应用权限和剩余存储空间。'
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog(context, '备份失败', '发生未知错误: $e\n\n请重试并检查应用权限。');
    }
  }

  Future<void> _handleImport(BuildContext context) async {
    try {
      // 使用file_selector替代file_picker
      const XTypeGroup jsonTypeGroup = XTypeGroup(
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
      
      // 先尝试验证备份文件格式
      final dbService = Provider.of<DatabaseService>(context, listen: false);
      final selectedFile = result['files']![0];
      
      // 显示加载指示器
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
      
      if (!isValidBackup) {
        if (!mounted) return;
        _showErrorDialog(
          context, 
          '无效的备份文件', 
          '所选文件不是有效的心记备份文件${errorMessage.isNotEmpty ? ':\n\n$errorMessage' : '。'}\n\n请选择有效的备份文件。'
        );
        return;
      }
      
      // 添加选项让用户选择是清空原有数据还是合并数据
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
      
      if (importOption == 'cancel' || importOption == null || !mounted) return;
      
      // 如果选择清空并导入，再次确认
      if (importOption == 'clear') {
        // 直接确认清空操作，删除了自动备份提示
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
        
        if (confirmed != true || !mounted) return;
      }
      
      // 显示导入进度
      final importOverlay = _showLoadingOverlay(context, '正在导入数据...');
      
      try {
        final bool clearExisting = importOption == 'clear';
        await dbService.importData(selectedFile.path, clearExisting: clearExisting);
        
        importOverlay.remove();
        
        if (!mounted) return;
        
        // 显示成功对话框而不是SnackBar，确保用户看到
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
                  // 重启应用
                  Navigator.pushAndRemoveUntil(
                    context,
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
  
  /// 显示加载覆盖层
  OverlayEntry _showLoadingOverlay(BuildContext context, String message) {
    final overlay = OverlayEntry(
      builder: (context) => Container(
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
  
  /// 显示错误对话框
  void _showErrorDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
  
  /// 获取文档目录路径
  Future<String> _getDocumentsPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
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
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Card(
              color: Colors.amber,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '数据安全提示',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. 请在多个位置保存备份文件，如云存储和本地存储\n'
                      '2. 导入前建议先备份当前数据，以防导入失败\n'
                      '3. 确保备份文件来源可靠，避免导入损坏的文件\n'
                      '4. 推荐在重要操作或APP更新前进行备份',
                      style: TextStyle(fontSize: 12),
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