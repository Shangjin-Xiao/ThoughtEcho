import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../services/media_file_service.dart';
import '../services/large_file_manager.dart';
import '../services/large_video_handler.dart';
import '../utils/stream_file_selector.dart';

/// 增强的媒体导入对话框
/// 
/// 专门处理大文件导入，提供：
/// - 文件预检查和验证
/// - 进度显示和状态更新
/// - 取消操作支持
/// - 错误处理和重试机制
class EnhancedMediaImportDialog extends StatefulWidget {
  final Function(String filePath) onFileImported;
  
  const EnhancedMediaImportDialog({
    super.key,
    required this.onFileImported,
  });

  @override
  State<EnhancedMediaImportDialog> createState() => _EnhancedMediaImportDialogState();
}

class _EnhancedMediaImportDialogState extends State<EnhancedMediaImportDialog> {
  bool _isImporting = false;
  double _progress = 0.0;
  String _statusMessage = '';
  CancelToken? _cancelToken;
  String? _selectedFilePath;
  VideoFileInfo? _videoInfo;
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入媒体文件'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isImporting) ...[
              // 文件选择区域
              _buildFileSelectionArea(),
              const SizedBox(height: 16),
              
              // 文件信息显示
              if (_videoInfo != null) _buildFileInfoDisplay(),
              
              // 导入按钮
              if (_selectedFilePath != null) _buildImportButton(),
            ] else ...[
              // 导入进度区域
              _buildImportProgressArea(),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isImporting)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          )
        else
          TextButton(
            onPressed: _cancelImport,
            child: const Text('取消导入'),
          ),
      ],
    );
  }
  
  Widget _buildFileSelectionArea() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            _selectedFilePath == null ? '选择视频文件' : '已选择文件',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_selectedFilePath != null)
            Text(
              _selectedFilePath!.split('/').last,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _selectFile,
            icon: const Icon(Icons.folder_open),
            label: Text(_selectedFilePath == null ? '选择文件' : '重新选择'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFileInfoDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '文件信息',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _buildInfoRow('文件名', _videoInfo!.fileName),
          _buildInfoRow('大小', '${_videoInfo!.fileSizeMB.toStringAsFixed(1)} MB'),
          _buildInfoRow('格式', _videoInfo!.extension.toUpperCase()),
          
          // 大文件警告
          if (_videoInfo!.fileSizeMB > 100) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    size: 16,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '大文件警告：此文件较大，导入可能需要较长时间',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildImportButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _startImport,
        icon: const Icon(Icons.download),
        label: const Text('开始导入'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
  
  Widget _buildImportProgressArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '正在导入文件...',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        
        // 进度条
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        
        // 进度百分比
        Text(
          '${(_progress * 100).toInt()}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        
        // 状态消息
        if (_statusMessage.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _statusMessage,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
  
  Future<void> _selectFile() async {
    try {
      // 使用内存保护机制包装文件选择操作
      final XFile? file = await LargeFileManager.executeWithMemoryProtection<XFile?>(
        () async {
          return await StreamFileSelector.selectVideoFile();
        },
        operationName: '选择视频文件',
      );
      
      if (file != null) {
        setState(() {
          _selectedFilePath = file.path;
          _videoInfo = null;
        });
        
        // 获取文件信息 - 也使用内存保护
        final videoInfo = await LargeFileManager.executeWithMemoryProtection<VideoFileInfo?>(
          () async {
            return await LargeVideoHandler.getVideoFileInfo(file.path);
          },
          operationName: '获取视频信息',
        );
        
        if (videoInfo != null) {
          setState(() {
            _videoInfo = videoInfo;
          });
        } else {
          // 如果无法获取视频信息，显示警告但仍允许导入
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('无法获取视频文件详细信息，但仍可尝试导入'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage;
        if (e.toString().contains('内存不足')) {
          errorMessage = '内存不足，无法处理该文件。请尝试选择较小的文件或重启应用';
        } else if (e.toString().contains('权限') || e.toString().contains('access')) {
          errorMessage = '无法访问所选文件，请检查文件权限';
        } else {
          errorMessage = '选择文件失败: ${e.toString()}';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
  
  Future<void> _startImport() async {
    if (_selectedFilePath == null) return;
    
    setState(() {
      _isImporting = true;
      _progress = 0.0;
      _statusMessage = '准备导入...';
    });
    
    _cancelToken = LargeFileManager.createCancelToken();
    
    try {
      // 使用内存保护机制包装视频导入操作
      final result = await LargeFileManager.executeWithMemoryProtection<String?>(
        () async {
          return await MediaFileService.saveVideo(
            _selectedFilePath!,
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _progress = progress;
                });
              }
            },
            onStatusUpdate: (status) {
              if (mounted) {
                setState(() {
                  _statusMessage = status;
                });
              }
            },
            cancelToken: _cancelToken,
          );
        },
        operationName: '视频导入',
      );
      
      if (result != null && mounted) {
        widget.onFileImported(result);
        Navigator.of(context).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('文件导入成功'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted && !(_cancelToken?.isCancelled ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('文件导入失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted && !(_cancelToken?.isCancelled ?? false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入过程中出错: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _progress = 0.0;
          _statusMessage = '';
        });
      }
    }
  }
  
  void _cancelImport() {
    _cancelToken?.cancel();
    Navigator.of(context).pop();
  }
  
  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }
}