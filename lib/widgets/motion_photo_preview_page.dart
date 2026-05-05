import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

import '../gen_l10n/app_localizations.dart';
import '../utils/app_logger.dart';
import '../utils/local_video_controller.dart';
import '../utils/motion_photo_utils.dart';
import '../utils/optimized_image_loader.dart';

bool shouldAutoReturnToStillImage(VideoPlayerValue value) {
  if (!value.isInitialized || value.isPlaying) {
    return false;
  }

  final duration = value.duration;
  if (duration <= Duration.zero) {
    return false;
  }

  return value.position >= duration;
}

class MotionPhotoPreviewPage extends StatefulWidget {
  MotionPhotoPreviewPage({
    super.key,
    required this.imageUrl,
    MotionPhotoUtils? motionPhotoUtils,
  }) : motionPhotoUtils = motionPhotoUtils ?? createMotionPhotoUtils();

  final String imageUrl;
  final MotionPhotoUtils motionPhotoUtils;

  @override
  State<MotionPhotoPreviewPage> createState() => _MotionPhotoPreviewPageState();
}

class _MotionPhotoPreviewPageState extends State<MotionPhotoPreviewPage> {
  MotionPhotoInfo? _motionInfo;
  String? _localFilePath;
  String? _extractedVideoPath;
  ChewieController? _chewieController;
  VideoPlayerController? _videoController;
  VoidCallback? _videoPlaybackListener;
  bool _checkingMotionPhoto = false;
  bool _preparingVideo = false;
  bool _showVideo = false;

  @override
  void initState() {
    super.initState();
    _localFilePath = _resolveLocalFilePath(widget.imageUrl);
    unawaited(_checkMotionPhotoAvailability());
  }

  @override
  void dispose() {
    unawaited(_disposeResources());
    super.dispose();
  }

  bool get _canCheckMotionPhoto =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _localFilePath != null;

  Future<void> _checkMotionPhotoAvailability() async {
    if (!_canCheckMotionPhoto) {
      return;
    }

    setState(() {
      _checkingMotionPhoto = true;
    });

    try {
      final info = await widget.motionPhotoUtils.detect(_localFilePath!);
      if (!mounted) {
        return;
      }
      setState(() {
        _motionInfo = info;
      });
    } catch (error, stackTrace) {
      logError(
        '检测动态照片失败: ${widget.imageUrl}',
        error: error,
        stackTrace: stackTrace,
        source: 'MotionPhotoPreviewPage',
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingMotionPhoto = false;
        });
      }
    }
  }

  Future<void> _playMotionPhoto() async {
    if (_localFilePath == null || _motionInfo == null || _preparingVideo) {
      return;
    }

    final l10n = AppLocalizations.of(context);
    final primaryColor = Theme.of(context).colorScheme.primary;
    setState(() {
      _preparingVideo = true;
    });

    try {
      _extractedVideoPath ??=
          await widget.motionPhotoUtils.extractVideoToTemporaryFile(
        _localFilePath!,
        info: _motionInfo,
      );

      await _disposeVideoControllers();

      final videoController = createLocalVideoPlayerController(
        _extractedVideoPath!,
      );
      await videoController.initialize();
      await videoController.setLooping(false);

      void playbackListener() {
        if (!mounted || !_showVideo) {
          return;
        }
        if (shouldAutoReturnToStillImage(videoController.value)) {
          unawaited(_showImage(resetToStart: true));
        }
      }

      _videoPlaybackListener = playbackListener;
      videoController.addListener(playbackListener);

      final chewieController = ChewieController(
        videoPlayerController: videoController,
        autoPlay: true,
        autoInitialize: true,
        looping: false,
        showControls: false,
        allowFullScreen: false,
        allowPlaybackSpeedChanging: false,
        allowMuting: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: primaryColor,
          handleColor: primaryColor,
          bufferedColor: Colors.white38,
          backgroundColor: Colors.white24,
        ),
      );

      if (!mounted) {
        chewieController.dispose();
        await videoController.dispose();
        return;
      }

      setState(() {
        _videoController = videoController;
        _chewieController = chewieController;
        _showVideo = true;
      });
    } catch (error, stackTrace) {
      logError(
        '播放动态照片失败: ${widget.imageUrl}',
        error: error,
        stackTrace: stackTrace,
        source: 'MotionPhotoPreviewPage',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.motionPhotoPlayFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _preparingVideo = false;
        });
      }
    }
  }

  Future<void> _showImage({bool resetToStart = false}) async {
    final videoController = _videoController;
    if (videoController != null) {
      await videoController.pause();
      if (resetToStart && videoController.value.isInitialized) {
        await videoController.seekTo(Duration.zero);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _showVideo = false;
    });
  }

  Future<void> _disposeResources() async {
    await _disposeVideoControllers();
    final extractedVideoPath = _extractedVideoPath;
    _extractedVideoPath = null;
    if (extractedVideoPath != null) {
      await widget.motionPhotoUtils.deleteTemporaryVideo(extractedVideoPath);
    }
  }

  Future<void> _disposeVideoControllers() async {
    final chewieController = _chewieController;
    final videoController = _videoController;
    final playbackListener = _videoPlaybackListener;
    _chewieController = null;
    _videoController = null;
    _videoPlaybackListener = null;
    if (chewieController != null) {
      chewieController.dispose();
    }
    if (videoController != null) {
      if (playbackListener != null) {
        videoController.removeListener(playbackListener);
      }
      await videoController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _showVideo ? _buildVideoContent() : _buildImageContent(),
          ),
          Positioned(
            top: mediaQuery.padding.top + 10,
            right: 10,
            child: _CircleIconButton(
              icon: Icons.close,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          if (_motionInfo != null)
            Positioned(
              right: 16,
              bottom: mediaQuery.padding.bottom + 16,
              child: FilledButton.tonalIcon(
                onPressed: _preparingVideo
                    ? null
                    : (_showVideo ? _showImage : _playMotionPhoto),
                icon: _preparingVideo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_showVideo ? Icons.photo : Icons.motion_photos_on),
                label: Text(
                  _showVideo
                      ? AppLocalizations.of(context).viewPhoto
                      : AppLocalizations.of(context).motionPhoto,
                ),
              ),
            ),
          if (_checkingMotionPhoto)
            Positioned(
              left: 16,
              bottom: mediaQuery.padding.bottom + 20,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageContent() {
    final provider = createOptimizedImageProvider(widget.imageUrl);
    if (provider == null) {
      return const Center(
        child:
            Icon(Icons.broken_image_outlined, color: Colors.white70, size: 40),
      );
    }

    return PhotoView(
      imageProvider: provider,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (context, event) => const Center(
        child: CircularProgressIndicator(),
      ),
      errorBuilder: (context, error, stackTrace) => const Center(
        child:
            Icon(Icons.broken_image_outlined, color: Colors.white70, size: 40),
      ),
    );
  }

  Widget _buildVideoContent() {
    if (_preparingVideo || _chewieController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _videoController?.value.aspectRatio == 0
            ? 16 / 9
            : (_videoController?.value.aspectRatio ?? 16 / 9),
        child: Chewie(controller: _chewieController!),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        tooltip: tooltip,
      ),
    );
  }
}

String? _resolveLocalFilePath(String source) {
  if (source.isEmpty) {
    return null;
  }
  if (source.startsWith('data:')) {
    return null;
  }

  final uri = Uri.tryParse(source);
  if (uri != null && uri.hasScheme) {
    if (uri.scheme == 'file') {
      return uri.toFilePath();
    }
    return null;
  }

  return source;
}
