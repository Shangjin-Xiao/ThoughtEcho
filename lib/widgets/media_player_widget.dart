import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';
import '../utils/lottie_animation_manager.dart';

/// 统一的媒体播放器组件
/// 支持视频和音频播放，提供丰富的用户体验
class MediaPlayerWidget extends StatefulWidget {
  final String filePath;
  final MediaType mediaType;
  final double? width;
  final double? height;

  const MediaPlayerWidget({
    super.key,
    required this.filePath,
    required this.mediaType,
    this.width,
    this.height,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  // 新增状态：是否已初始化、是否正在初始化
  bool _isInitialized = false;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    // 修改：不再自动初始化，改为懒加载
    if (widget.mediaType == MediaType.audio) {
      // 音频文件通常较小，可以立即初始化
      _initializeAudioPlayer();
    }
  }

  // 新增：用户点击后开始初始化
  Future<void> _startVideoInitialization() async {
    if (_isInitialized || _isInitializing) return;

    setState(() {
      _isInitializing = true;
    });

    await _initializeVideoPlayer();

    if (mounted) {
      setState(() {
        _isInitializing = false;
        // 初始化成功后，_chewieController 不会为 null
        _isInitialized = _chewieController != null;
      });
    }
  }

  Future<void> _initializeVideoPlayer() async {
    try {
      // 检查文件是否存在
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('视频文件不存在: ${widget.filePath}')),
          );
        }
        return;
      }
      
      // 获取文件大小，用于日志记录
      int fileSize = 0;
      try {
        fileSize = await file.length();
      } catch (_) {}
      
      // 记录开始初始化大视频
      if (fileSize > 100 * 1024 * 1024) { // 100MB以上视为大视频
        debugPrint('开始初始化大视频文件: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');
      }

      // 创建视频控制器
      _videoController = VideoPlayerController.file(file);
      
      // 使用超时保护，防止初始化过程卡死
      bool initializeCompleted = false;
      
      // 启动一个超时计时器
      Future.delayed(const Duration(seconds: 30)).then((_) {
        if (!initializeCompleted && mounted) {
          debugPrint('视频初始化超时，尝试恢复');
          setState(() {
            _isInitializing = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('视频加载时间过长，请尝试使用较小的视频文件'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      });
      
      // 在隔离区中初始化视频
      await _videoController!.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('视频初始化超时');
          throw Exception('视频初始化超时，文件可能过大');
        },
      );
      
      initializeCompleted = true;
      
      if (!mounted) return;
      
      // 记录视频初始化成功
      if (fileSize > 100 * 1024 * 1024) {
        debugPrint('大视频初始化成功: ${(fileSize / 1024 / 1024).toStringAsFixed(1)}MB');
      }

      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        aspectRatio: _videoController!.value.aspectRatio,
        autoPlay: false,
        looping: false,
        showControls: true,
        allowFullScreen: true,
        allowMuting: true,
        allowPlaybackSpeedChanging: true,
        // 自定义控制栏样式
        materialProgressColors: ChewieProgressColors(
          playedColor: Theme.of(context).colorScheme.primary,
          handleColor: Theme.of(context).colorScheme.primary,
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          bufferedColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        // 自定义控制栏选项
        optionsTranslation: OptionsTranslation(
          playbackSpeedButtonText: '播放速度',
          subtitlesButtonText: '字幕',
          cancelButtonText: '取消',
        ),
        hideControlsTimer: const Duration(seconds: 3),
        // 添加自定义操作
        additionalOptions:
            (context) => [
              OptionItem(
                onTap: (context) => _shareVideo(),
                iconData: Icons.share,
                title: '分享视频',
              ),
              OptionItem(
                onTap: (context) => _showVideoInfo(),
                iconData: Icons.info,
                title: '视频信息',
              ),
            ],
      );

      setState(() {});
    } on OutOfMemoryError catch (e) {
      // 专门处理内存不足错误
      debugPrint('视频初始化遇到内存不足: $e');
      _cleanupVideoResources();
      await _handleOutOfMemoryError();
    } catch (e) {
      // 清理资源
      _cleanupVideoResources();
      
      debugPrint('视频初始化失败: $e');
      
      if (mounted) {
        String errorMessage = '视频加载失败';
        String suggestion = '';
        
        if (e.toString().contains('timeout') || e.toString().contains('超时')) {
          errorMessage = '视频加载超时';
          suggestion = '文件可能过大，请稍后重试或使用较小的视频文件';
        } else if (e.toString().contains('format') || e.toString().contains('格式')) {
          errorMessage = '不支持的视频格式';
          suggestion = '请使用MP4、MOV等常见格式';
        } else if (e.toString().contains('permission') || e.toString().contains('权限')) {
          errorMessage = '无法访问视频文件';
          suggestion = '请检查文件权限';
        } else {
          suggestion = '请检查文件是否完整或尝试重新导入';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(errorMessage),
                if (suggestion.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    suggestion,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ],
            ),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: '重试',
              onPressed: () => _retryVideoInitialization(),
            ),
          ),
        );
      }
    }
  }
  
  // 清理视频资源
  void _cleanupVideoResources() {
    try {
      if (_videoController != null) {
        _videoController!.dispose();
        _videoController = null;
      }
      if (_chewieController != null) {
        _chewieController!.dispose();
        _chewieController = null;
      }
    } catch (e) {
      debugPrint('清理视频资源失败: $e');
    }
  }

  /// 处理内存不足错误
  Future<void> _handleOutOfMemoryError() async {
    debugPrint('处理内存不足错误');
    
    // 强制垃圾回收
    await Future.delayed(const Duration(milliseconds: 200));
    
    if (mounted) {
      setState(() {
        _isInitializing = false;
        _isInitialized = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('内存不足，无法加载视频'),
              SizedBox(height: 4),
              Text(
                '建议：\n• 关闭其他应用释放内存\n• 重启应用后重试\n• 使用较小的视频文件',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          duration: const Duration(seconds: 10),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: '重试',
            onPressed: () => _retryVideoInitialization(),
          ),
        ),
      );
    }
  }

  /// 重试视频初始化
  Future<void> _retryVideoInitialization() async {
    if (_isInitializing) return;
    
    debugPrint('重试视频初始化');
    
    // 重置状态
    setState(() {
      _isInitialized = false;
      _isInitializing = false;
    });
    
    // 短暂延迟后重试，给系统时间回收内存
    await Future.delayed(const Duration(milliseconds: 1000));
    
    if (mounted) {
      await _startVideoInitialization();
    }
  }

  Future<void> _initializeAudioPlayer() async {
    try {
      // 检查文件是否存在
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('音频文件不存在: ${widget.filePath}')),
          );
        }
        return;
      }

      _audioPlayer = AudioPlayer();

      // 监听播放状态
      _audioPlayer!.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
          });
        }
      });

      // 监听播放进度
      _audioPlayer!.onDurationChanged.listen((duration) {
        if (mounted) {
          setState(() {
            _duration = duration;
          });
        }
      });

      _audioPlayer!.onPositionChanged.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('音频加载失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaType == MediaType.video) {
      // 根据初始化状态返回不同的小部件
      if (_isInitialized) {
        return _buildEnhancedVideoPlayer();
      } else {
        return _buildVideoPlaceholder();
      }
    } else if (widget.mediaType == MediaType.audio) {
      return _buildEnhancedAudioPlayer();
    }

    return const SizedBox.shrink();
  }

  /// 新增：视频占位符，等待用户点击
  Widget _buildVideoPlaceholder() {
    return GestureDetector(
      onTap: _startVideoInitialization,
      child: Container(
        width: widget.width ?? 300,
        height: widget.height ?? 200,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Center(
          child: _isInitializing
              ? _buildVideoLoadingState() // 复用加载动画
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.play_circle_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '点击播放视频',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildEnhancedVideoPlayer() {
    if (_chewieController == null) {
      return _buildVideoLoadingState();
    }

    return Container(
      width: widget.width ?? 300,
      height: widget.height ?? 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 视频播放器
          Chewie(controller: _chewieController!),

          // 自定义覆盖层（如果需要）
          if (_showCustomOverlay()) _buildCustomOverlay(),
        ],
      ),
    );
  }

  Widget _buildVideoLoadingState() {
    return Container(
      width: widget.width ?? 300,
      height: widget.height ?? 200,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final s = (constraints.maxHeight * 0.4).clamp(48.0, 120.0);
              return EnhancedLottieAnimation(
                type: LottieAnimationType.pulseLoading,
                width: s,
                height: s,
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            '正在加载视频...',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedAudioPlayer() {
    return Container(
      width: widget.width ?? 300,
      height: widget.height ?? 120, // 增加高度以容纳更多信息
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 音频信息行
          Row(
            children: [
              // 音频图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.audiotrack,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),

              // 文件信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getFileName(widget.filePath),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),

              // 更多选项
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                onSelected: (value) => _handleAudioMenuAction(value),
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(
                        value: 'share',
                        child: Row(
                          children: [
                            Icon(Icons.share),
                            SizedBox(width: 8),
                            Text('分享音频'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'info',
                        child: Row(
                          children: [
                            Icon(Icons.info),
                            SizedBox(width: 8),
                            Text('文件信息'),
                          ],
                        ),
                      ),
                    ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 控制栏
          Row(
            children: [
              // 播放/暂停按钮
              IconButton(
                onPressed: _toggleAudioPlayback,
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),

              // 当前时间
              Text(
                _formatDuration(_position),
                style: Theme.of(context).textTheme.bodySmall,
              ),

              const SizedBox(width: 8),

              // 进度条
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _position.inMilliseconds.toDouble(),
                    max: _duration.inMilliseconds.toDouble().clamp(
                      1.0,
                      double.infinity,
                    ),
                    onChanged: _onAudioSeek,
                    activeColor: Theme.of(context).colorScheme.primary,
                    inactiveColor: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 总时长
              Text(
                _formatDuration(_duration),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _showCustomOverlay() {
    // 可以根据需要添加自定义覆盖层的条件
    return false;
  }

  Widget _buildCustomOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.3),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.3),
          ],
        ),
      ),
    );
  }

  String _getFileName(String path) {
    return path.split('/').last.split('.').first;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  void _toggleAudioPlayback() async {
    if (_audioPlayer == null) return;

    if (_isPlaying) {
      await _audioPlayer!.pause();
    } else {
      await _audioPlayer!.play(DeviceFileSource(widget.filePath));
    }
  }

  void _onAudioSeek(double value) async {
    if (_audioPlayer == null) return;
    final position = Duration(milliseconds: value.toInt());
    await _audioPlayer!.seek(position);
  }

  void _shareVideo() {
    // 实现视频分享功能
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('分享功能开发中...')));
  }

  void _showVideoInfo() {
    if (_videoController == null) return;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('视频信息'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('文件名', _getFileName(widget.filePath)),
                _buildInfoRow(
                  '时长',
                  _formatDuration(_videoController!.value.duration),
                ),
                _buildInfoRow(
                  '分辨率',
                  '${_videoController!.value.size.width.toInt()}x${_videoController!.value.size.height.toInt()}',
                ),
                _buildInfoRow(
                  '长宽比',
                  _videoController!.value.aspectRatio.toStringAsFixed(2),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
    );
  }

  void _handleAudioMenuAction(String action) {
    switch (action) {
      case 'share':
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('分享功能开发中...')));
        break;
      case 'info':
        _showAudioInfo();
        break;
    }
  }

  void _showAudioInfo() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('音频信息'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('文件名', _getFileName(widget.filePath)),
                _buildInfoRow('时长', _formatDuration(_duration)),
                _buildInfoRow('路径', widget.filePath),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // 使用清理方法释放视频资源
    _cleanupVideoResources();
    
    // 释放音频资源
    try {
      if (_audioPlayer != null) {
        _audioPlayer!.dispose();
        _audioPlayer = null;
      }
    } catch (e) {
      debugPrint('释放音频资源失败: $e');
    }
    
    // 确保在垃圾回收前触发一次内存清理
    Future.microtask(() {
      // 触发垃圾回收
      if (!kIsWeb) {
        // 在非Web平台可以尝试一些内存管理
        Future.delayed(const Duration(milliseconds: 100));
      }
    });
    
    super.dispose();
  }
}

enum MediaType { video, audio }
