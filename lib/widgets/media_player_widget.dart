import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    if (widget.mediaType == MediaType.video) {
      await _initializeVideoPlayer();
    } else if (widget.mediaType == MediaType.audio) {
      await _initializeAudioPlayer();
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

      _videoController = VideoPlayerController.file(file);
      await _videoController!.initialize();

      if (!mounted) return;

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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('视频加载失败: $e')));
      }
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
      return _buildEnhancedVideoPlayer();
    } else if (widget.mediaType == MediaType.audio) {
      return _buildEnhancedAudioPlayer();
    }

    return const SizedBox.shrink();
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
            color: Colors.black.withOpacity(0.1),
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
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '正在加载视频...',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
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
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                        ).colorScheme.onSurface.withOpacity(0.6),
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
                  ).colorScheme.onSurface.withOpacity(0.6),
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
                    ).colorScheme.outline.withOpacity(0.3),
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
            Colors.black.withOpacity(0.3),
            Colors.transparent,
            Colors.black.withOpacity(0.3),
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
    _chewieController?.dispose();
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }
}

enum MediaType { video, audio }
