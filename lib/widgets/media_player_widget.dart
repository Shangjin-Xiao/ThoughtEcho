import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 统一的媒体播放器组件
/// 支持视频和音频播放
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
      _videoController = VideoPlayerController.file(File(widget.filePath));
      await _videoController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        aspectRatio: _videoController!.value.aspectRatio,
        autoPlay: false,
        looping: false,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Theme.of(context).colorScheme.primary,
          handleColor: Theme.of(context).colorScheme.primary,
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          bufferedColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      );

      if (mounted) setState(() {});
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
      return _buildVideoPlayer();
    } else if (widget.mediaType == MediaType.audio) {
      return _buildAudioPlayer();
    }

    return const SizedBox.shrink();
  }

  Widget _buildVideoPlayer() {
    if (_chewieController == null) {
      return Container(
        width: widget.width ?? 300,
        height: widget.height ?? 200,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      width: widget.width ?? 300,
      height: widget.height ?? 200,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: Chewie(controller: _chewieController!),
    );
  }

  Widget _buildAudioPlayer() {
    return Container(
      width: widget.width ?? 300,
      height: widget.height ?? 80,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // 播放/暂停按钮
          IconButton(
            onPressed: _toggleAudioPlayback,
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),

          // 进度条
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value:
                      _duration.inMilliseconds > 0
                          ? _position.inMilliseconds / _duration.inMilliseconds
                          : 0.0,
                  onChanged: (value) {
                    final position = Duration(
                      milliseconds: (value * _duration.inMilliseconds).round(),
                    );
                    _audioPlayer?.seek(position);
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 音频图标
          Icon(Icons.audiotrack, color: Theme.of(context).colorScheme.primary),
        ],
      ),
    );
  }

  Future<void> _toggleAudioPlayback() async {
    if (_audioPlayer == null) return;

    try {
      if (_isPlaying) {
        await _audioPlayer!.pause();
      } else {
        await _audioPlayer!.play(DeviceFileSource(widget.filePath));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('播放失败: $e')));
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }
}

/// 媒体类型枚举
enum MediaType { image, video, audio }
