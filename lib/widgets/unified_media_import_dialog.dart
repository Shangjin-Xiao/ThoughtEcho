import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import '../services/media_file_service.dart';
import '../utils/stream_file_selector.dart';
import '../services/large_file_manager.dart' as lfm;
import '../utils/app_logger.dart';

/// 统一的媒体导入对话框
/// 
/// 整合所有媒体类型的导入逻辑：
/// - 支持图片、视频、音频导入
/// - 优化大文件处理，防止OOM
/// - 提供多种导入方式：文件选择、拍照/录制、网址
/// - 实时进度显示和取消支持
/// - 内存保护机制
class UnifiedMediaImportDialog extends StatefulWidget {
  final String mediaType; // 'image', 'video', 'audio'
  final Function(String filePath) onMediaImported;

  const UnifiedMediaImportDialog({
    super.key,
    required this.mediaType,
    required this.onMediaImported,
  });

  @override
  State<UnifiedMediaImportDialog> createState() => _UnifiedMediaImportDialogState();
}

class _UnifiedMediaImportDialogState extends State<UnifiedMediaImportDialog> {
  bool _isImporting = false;
  double _progress = 0.0;
  String _statusMessage = '';
  lfm.CancelToken? _cancelToken;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('导入${_getMediaTypeName(widget.mediaType)}'),
      content: SizedBox(
        width: 400,
        child: _isImporting ? _buildImportProgress() : _buildImportOptions(),
      ),
      actions: _isImporting ? _buildImportingActions() : _buildNormalActions(),
    );
  }

  Widget _buildImportOptions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 文件选择选项
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: Text('从文件选择${_getMediaTypeName(widget.mediaType)}'),
          subtitle: const Text('支持大文件，内存安全处理'),
          onTap: () => _importFromFile(),
        ),
        
        // 拍照/录制选项（仅移动端）
        if (_shouldShowCameraOption()) ...[
          ListTile(
            leading: Icon(_getCameraIcon()),
            title: Text(_getCameraTitle()),
            subtitle: Text('直接${_getCameraAction()}'),
            onTap: () => _importFromCamera(),
          ),
        ],
        
        // 网址导入选项
        ListTile(
          leading: const Icon(Icons.link),
          title: Text('从网址导入${_getMediaTypeName(widget.mediaType)}'),
          subtitle: const Text('输入媒体文件的网址'),
          onTap: () => _importFromUrl(),
        ),
        
        const SizedBox(height: 16),
        
        // 提示信息
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '导入说明',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _getImportTips(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImportProgress() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 进度指示器
        LinearProgressIndicator(
          value: _progress,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        
        // 进度文本
        Text(
          '${(_progress * 100).toStringAsFixed(1)}%',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        
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
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildNormalActions() {
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    ];
  }

  List<Widget> _buildImportingActions() {
    return [
      TextButton(
        onPressed: _cancelImport,
        child: const Text('取消导入'),
      ),
    ];
  }

  /// 从文件导入
  Future<void> _importFromFile() async {
    try {
      setState(() {
        _isImporting = true;
        _progress = 0.0;
        _statusMessage = '正在选择文件...';
        _cancelToken = lfm.LargeFileManager.createCancelToken();
      });

      // 使用内存保护的文件选择
      final XFile? file = await lfm.LargeFileManager.executeWithMemoryProtection<XFile?>(
        () async {
          switch (widget.mediaType) {
            case 'image':
              return await StreamFileSelector.selectImageFile();
            case 'video':
              return await StreamFileSelector.selectVideoFile();
            case 'audio':
              return await StreamFileSelector.selectFile(
                extensions: ['mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac'],
                description: 'Audio Files',
              );
            default:
              throw Exception('不支持的媒体类型: ${widget.mediaType}');
          }
        },
        operationName: '选择${_getMediaTypeName(widget.mediaType)}文件',
      );

      if (file == null) {
        _resetState();
        return;
      }

      setState(() {
        _statusMessage = '正在处理文件...';
        _progress = 0.1;
      });

      // 检查文件是否可以处理
      final canProcess = await lfm.LargeFileManager.canProcessFile(file.path);
      if (!canProcess) {
        throw Exception('文件无法读取或已损坏');
      }

      setState(() {
        _statusMessage = '正在导入文件...';
        _progress = 0.3;
      });

      // 使用内存保护的文件保存
      final String? savedPath = await lfm.LargeFileManager.executeWithMemoryProtection<String?>(
        () async {
          switch (widget.mediaType) {
            case 'image':
              return await MediaFileService.saveImage(
                file.path,
                onProgress: _updateProgress,
                cancelToken: _cancelToken,
              );
            case 'video':
              return await MediaFileService.saveVideo(
                file.path,
                onProgress: _updateProgress,
                onStatusUpdate: _updateStatus,
                cancelToken: _cancelToken,
              );
            case 'audio':
              return await MediaFileService.saveAudio(
                file.path,
                onProgress: _updateProgress,
                cancelToken: _cancelToken,
              );
            default:
              throw Exception('不支持的媒体类型: ${widget.mediaType}');
          }
        },
        operationName: '保存${_getMediaTypeName(widget.mediaType)}文件',
      );

      if (savedPath != null && mounted) {
        setState(() {
          _progress = 1.0;
          _statusMessage = '导入完成！';
        });

        // 延迟一下让用户看到完成状态
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          Navigator.of(context).pop();
          widget.onMediaImported(savedPath);
        }
      } else {
        throw Exception('文件保存失败');
      }
    } catch (e) {
      logDebug('文件导入失败: $e');
      if (mounted) {
        _showError('导入失败: $e');
      }
    }
  }

  /// 从相机导入
  Future<void> _importFromCamera() async {
    try {
      setState(() {
        _isImporting = true;
        _progress = 0.0;
        _statusMessage = '正在${_getCameraAction()}...';
      });

      final ImagePicker picker = ImagePicker();
      XFile? file;

      switch (widget.mediaType) {
        case 'image':
          file = await picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 85,
            maxWidth: 1920,
            maxHeight: 1920,
          );
          break;
        case 'video':
          file = await picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(minutes: 5),
          );
          break;
        default:
          throw Exception('${widget.mediaType}不支持相机导入');
      }

      if (file == null) {
        _resetState();
        return;
      }

      setState(() {
        _statusMessage = '正在处理${_getMediaTypeName(widget.mediaType)}...';
        _progress = 0.5;
      });

      // 保存文件
      final String? savedPath = await lfm.LargeFileManager.executeWithMemoryProtection<String?>(
        () async {
          switch (widget.mediaType) {
            case 'image':
              return await MediaFileService.saveImage(file!.path);
            case 'video':
              return await MediaFileService.saveVideo(file!.path);
            default:
              throw Exception('不支持的媒体类型');
          }
        },
        operationName: '保存${_getMediaTypeName(widget.mediaType)}',
      );

      if (savedPath != null && mounted) {
        setState(() {
          _progress = 1.0;
          _statusMessage = '导入完成！';
        });

        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          Navigator.of(context).pop();
          widget.onMediaImported(savedPath);
        }
      }
    } catch (e) {
      logDebug('相机导入失败: $e');
      if (mounted) {
        _showError('${_getCameraAction()}失败: $e');
      }
    }
  }

  /// 从网址导入
  Future<void> _importFromUrl() async {
    final TextEditingController urlController = TextEditingController();

    final String? url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('输入${_getMediaTypeName(widget.mediaType)}网址'),
        content: TextField(
          controller: urlController,
          decoration: InputDecoration(
            hintText: '请输入${_getMediaTypeName(widget.mediaType)}文件的网址',
            border: const OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(urlController.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (url == null || url.isEmpty) return;

    try {
      setState(() {
        _isImporting = true;
        _progress = 0.0;
        _statusMessage = '正在下载文件...';
        _cancelToken = lfm.LargeFileManager.createCancelToken();
      });

      // 使用内存保护下载文件
      final String? savedPath = await lfm.LargeFileManager.executeWithMemoryProtection<String?>(
        () async {
          return await _downloadMediaFromUrl(url);
        },
        operationName: '下载${_getMediaTypeName(widget.mediaType)}',
      );

      if (savedPath != null && mounted) {
        setState(() {
          _progress = 1.0;
          _statusMessage = '下载完成！';
        });

        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          Navigator.of(context).pop();
          widget.onMediaImported(savedPath);
        }
      }
    } catch (e) {
      logDebug('网址导入失败: $e');
      if (mounted) {
        _showError('下载失败: $e');
      }
    }
  }

  /// 取消导入
  void _cancelImport() {
    _cancelToken?.cancel();
    _resetState();
  }

  /// 重置状态
  void _resetState() {
    if (mounted) {
      setState(() {
        _isImporting = false;
        _progress = 0.0;
        _statusMessage = '';
        _cancelToken = null;
      });
    }
  }

  /// 显示错误
  void _showError(String message) {
    _resetState();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// 更新进度
  void _updateProgress(double progress) {
    if (mounted) {
      setState(() {
        _progress = progress;
      });
    }
  }

  /// 更新状态消息
  void _updateStatus(String status) {
    if (mounted) {
      setState(() {
        _statusMessage = status;
      });
    }
  }

  /// 获取媒体类型名称
  String _getMediaTypeName(String type) {
    switch (type) {
      case 'image':
        return '图片';
      case 'video':
        return '视频';
      case 'audio':
        return '音频';
      default:
        return '媒体';
    }
  }

  /// 是否显示相机选项
  bool _shouldShowCameraOption() {
    if (kIsWeb) return false;
    return widget.mediaType == 'image' || widget.mediaType == 'video';
  }

  /// 获取相机图标
  IconData _getCameraIcon() {
    switch (widget.mediaType) {
      case 'image':
        return Icons.camera_alt;
      case 'video':
        return Icons.videocam;
      default:
        return Icons.camera;
    }
  }

  /// 获取相机标题
  String _getCameraTitle() {
    switch (widget.mediaType) {
      case 'image':
        return '拍照';
      case 'video':
        return '录制视频';
      default:
        return '拍摄';
    }
  }

  /// 获取相机动作
  String _getCameraAction() {
    switch (widget.mediaType) {
      case 'image':
        return '拍照';
      case 'video':
        return '录制';
      default:
        return '拍摄';
    }
  }

  /// 获取导入提示
  String _getImportTips() {
    switch (widget.mediaType) {
      case 'image':
        return '• 支持 JPG、PNG、GIF、WebP 等格式\n'
               '• 自动优化大图片以节省存储空间\n'
               '• 使用内存保护技术，支持超大图片';
      case 'video':
        return '• 支持 MP4、MOV、AVI、MKV 等格式\n'
               '• 智能处理大视频文件\n'
               '• 流式处理技术，防止内存溢出';
      case 'audio':
        return '• 支持 MP3、WAV、AAC、M4A 等格式\n'
               '• 高质量音频保存\n'
               '• 优化存储，快速加载';
      default:
        return '• 支持多种媒体格式\n'
               '• 智能文件处理\n'
               '• 内存安全保护';
    }
  }

  /// 从URL下载媒体文件
  Future<String?> _downloadMediaFromUrl(String url) async {
    try {
      _updateStatus('正在连接服务器...');

      // 生成临时文件路径
      final tempDir = Directory.systemTemp;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(url)}';
      final tempFile = File(path.join(tempDir.path, fileName));

      // 创建Dio实例
      final dio = Dio();

      // 创建Dio的CancelToken
      final dioCancelToken = CancelToken();

      try {
        // 使用Dio下载文件
        await dio.download(
          url,
          tempFile.path,
          cancelToken: dioCancelToken,
          onReceiveProgress: (received, total) {
            // 检查是否被取消
            _cancelToken?.throwIfCancelled();

            if (total > 0) {
              _updateProgress(received / total * 0.8); // 80%用于下载
            }
            _updateStatus('正在下载文件... ${(received / 1024 / 1024).toStringAsFixed(1)}MB');
          },
        );

        _updateStatus('正在保存文件...');
        _updateProgress(0.9);

        // 保存到应用目录
        String? savedPath;
        switch (widget.mediaType) {
          case 'image':
            savedPath = await MediaFileService.saveImage(
              tempFile.path,
              onProgress: (progress) => _updateProgress(0.9 + progress * 0.1),
              cancelToken: _cancelToken,
            );
            break;
          case 'video':
            savedPath = await MediaFileService.saveVideo(
              tempFile.path,
              onProgress: (progress) => _updateProgress(0.9 + progress * 0.1),
              onStatusUpdate: _updateStatus,
              cancelToken: _cancelToken,
            );
            break;
          case 'audio':
            savedPath = await MediaFileService.saveAudio(
              tempFile.path,
              onProgress: (progress) => _updateProgress(0.9 + progress * 0.1),
              cancelToken: _cancelToken,
            );
            break;
        }

        // 清理临时文件
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e) {
          logDebug('清理临时文件失败: $e');
        }

        return savedPath;
      } catch (e) {
        // 清理临时文件
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (cleanupError) {
          logDebug('清理临时文件失败: $cleanupError');
        }
        rethrow;
      }
    } catch (e) {
      logDebug('URL下载失败: $e');
      rethrow;
    }
  }
}
