import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../utils/app_logger.dart';
import '../utils/optimized_image_loader.dart';
import '../widgets/media_player_widget.dart';

/// Quill编辑器扩展配置
/// 图片使用flutter_quill_extensions官方实现，视频和音频使用自定义MediaPlayerWidget
class QuillEditorExtensions {
  /// 获取编辑器的嵌入构建器
  static List<quill.EmbedBuilder> getEmbedBuilders() {
    // 获取官方的builders作为基础
    final builders = kIsWeb
        ? FlutterQuillEmbeds.editorWebBuilders()
        : FlutterQuillEmbeds.editorBuilders();

    // 移除官方的图片构建器，替换为优化版
    builders.removeWhere((builder) => builder.key == 'image');

    // 添加优化的图片构建器
    builders.add(_OptimizedImageEmbedBuilder());

    if (!kIsWeb) {
      // 非Web平台使用自定义的视频和音频构建器
      builders.removeWhere(
        (builder) => builder.key == 'video' || builder.key == 'audio',
      );
      builders.add(_CustomVideoEmbedBuilder());
      builders.add(_CustomAudioEmbedBuilder());
    }

    return builders;
  }

  /// 获取工具栏的嵌入按钮构建器
  static List<quill.EmbedButtonBuilder> getToolbarBuilders() {
    return FlutterQuillEmbeds.toolbarButtons();
  }
}

/// 自定义视频嵌入构建器
class _CustomVideoEmbedBuilder extends quill.EmbedBuilder {
  @override
  String get key => 'video';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final videoUrl = embedContext.node.value.data as String;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: MediaPlayerWidget(
        filePath: videoUrl,
        mediaType: MediaType.video,
        width: MediaQuery.of(context).size.width * 0.9,
        height: 200,
      ),
    );
  }
}

/// 自定义音频嵌入构建器
class _CustomAudioEmbedBuilder extends quill.EmbedBuilder {
  @override
  String get key => 'audio';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final audioUrl = embedContext.node.value.data as String;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: MediaPlayerWidget(
        filePath: audioUrl,
        mediaType: MediaType.audio,
        width: MediaQuery.of(context).size.width * 0.9,
        height: 120,
      ),
    );
  }
}

class _OptimizedImageEmbedBuilder extends quill.EmbedBuilder {
  @override
  String get key => 'image';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final dynamic data = embedContext.node.value.data;
    final String source = _extractSource(data);

    if (source.isEmpty) {
      logDebug('富文本图片数据为空，跳过渲染', source: 'OptimizedImageEmbed');
      return const SizedBox.shrink();
    }

    final styleAttributes = embedContext.node.style.attributes;
    final double? specifiedWidth = _readDimension(styleAttributes[quill.Attribute.width.key]?.value);
    final double? specifiedHeight =
        _readDimension(styleAttributes[quill.Attribute.height.key]?.value);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _LazyQuillImage(
        source: source,
        specifiedWidth: specifiedWidth,
        specifiedHeight: specifiedHeight,
        uniqueId: embedContext.node.hashCode,
      ),
    );
  }

  String _extractSource(dynamic data) {
    if (data is String) {
      return data;
    }
    if (data is Map<String, dynamic>) {
      return data['source']?.toString() ?? data['image']?.toString() ?? '';
    }
    return data?.toString() ?? '';
  }

  double? _readDimension(dynamic rawValue) {
    if (rawValue == null) {
      return null;
    }

    if (rawValue is num) {
      return rawValue.toDouble();
    }

    if (rawValue is String) {
      final sanitized = rawValue.replaceAll('px', '').trim();
      return double.tryParse(sanitized);
    }

    return null;
  }
}

class _LazyQuillImage extends StatefulWidget {
  const _LazyQuillImage({
    required this.source,
    required this.uniqueId,
    this.specifiedWidth,
    this.specifiedHeight,
  });

  final String source;
  final int uniqueId;
  final double? specifiedWidth;
  final double? specifiedHeight;

  @override
  State<_LazyQuillImage> createState() => _LazyQuillImageState();
}

class _LazyQuillImageState extends State<_LazyQuillImage>
    with AutomaticKeepAliveClientMixin {
  bool _shouldLoad = false;
  bool _hasError = false;
  bool _isLoaded = false;

  @override
  bool get wantKeepAlive => true;

  void _handleVisibility(VisibilityInfo info) {
    if (_shouldLoad) {
      return;
    }

    if (info.visibleFraction > 0.05) {
      setState(() {
        _shouldLoad = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final double screenWidth = mediaQuery.size.width;

        double fallbackWidth;
        if (constraints.hasBoundedWidth &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0) {
          fallbackWidth = constraints.maxWidth;
        } else if (screenWidth.isFinite && screenWidth > 0) {
          fallbackWidth = screenWidth - 32;
        } else {
          fallbackWidth = 360;
        }

        if (!fallbackWidth.isFinite || fallbackWidth <= 0) {
          fallbackWidth = 360;
        }

        if (fallbackWidth < 120) {
          fallbackWidth = screenWidth * 0.9;
        }

        final double displayWidth = _resolveWidth(fallbackWidth);
        final double displayHeight = _resolveHeight(displayWidth);

        final double devicePixelRatio =
            mediaQuery.devicePixelRatio.clamp(1.0, 3.0);
        final int? targetCacheWidth =
            _computeCacheSize(displayWidth, devicePixelRatio);
        final int? targetCacheHeight =
            _computeCacheSize(displayHeight, devicePixelRatio);

        return RepaintBoundary(
          child: VisibilityDetector(
            key: ValueKey(
              'quill_image_${widget.uniqueId}_${widget.source.hashCode}',
            ),
            onVisibilityChanged: _handleVisibility,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: displayWidth,
                  maxWidth: displayWidth,
                  minHeight: displayHeight,
                  maxHeight: displayHeight,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildImageContent(
                    context,
                    displayWidth,
                    displayHeight,
                    targetCacheWidth,
                    targetCacheHeight,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _resolveWidth(double fallbackWidth) {
    final double? specified = widget.specifiedWidth;
    if (specified != null && specified > 0) {
      return specified.clamp(80.0, fallbackWidth);
    }
    return fallbackWidth;
  }

  double _resolveHeight(double displayWidth) {
    final double? specifiedWidth = widget.specifiedWidth;
    final double? specifiedHeight = widget.specifiedHeight;

    if (specifiedWidth != null &&
        specifiedWidth > 0 &&
        specifiedHeight != null &&
        specifiedHeight > 0) {
      final aspectRatio = specifiedWidth / specifiedHeight;
      if (aspectRatio > 0) {
        final height = displayWidth / aspectRatio;
        return height.clamp(80.0, displayWidth * 1.8);
      }
    }

    if (specifiedHeight != null && specifiedHeight > 0) {
      return specifiedHeight.clamp(80.0, displayWidth * 1.8);
    }

    return displayWidth * 0.6;
  }

  Widget _buildImageContent(
    BuildContext context,
    double width,
    double height,
    int? cacheWidth,
    int? cacheHeight,
  ) {
    if (_hasError) {
      return _buildErrorPlaceholder(context, width, height);
    }

    if (!_shouldLoad) {
      return _buildPlaceholder(context, width, height);
    }

    final provider = createOptimizedImageProvider(
      widget.source,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );

    if (provider == null) {
      logDebug('图片Provider创建失败: ${widget.source}', source: 'OptimizedImageEmbed');
      return _buildErrorPlaceholder(context, width, height);
    }

    return Image(
      image: provider,
      width: width,
      height: height,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      isAntiAlias: true,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null && !_isLoaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isLoaded = true;
              });
            }
          });
        }

        return AnimatedOpacity(
          opacity: frame == null ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            _buildPlaceholder(context, width, height),
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        );
      },
      errorBuilder: (context, error, stackTrace) {
        logError(
          '图片加载失败: ${widget.source}',
          error: error,
          stackTrace: stackTrace,
          source: 'OptimizedImageEmbed',
        );

        if (!_hasError && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _hasError = true;
              });
            }
          });
        }

        return _buildErrorPlaceholder(context, width, height);
      },
    );
  }

  int? _computeCacheSize(double dimension, double devicePixelRatio) {
    if (!dimension.isFinite || dimension <= 0) {
      return null;
    }

    final double logicalPixels = dimension * devicePixelRatio;
    if (!logicalPixels.isFinite || logicalPixels <= 0) {
      return null;
    }

    final double bounded = logicalPixels.clamp(160.0, 2048.0);
    return bounded.round();
  }

  Widget _buildPlaceholder(BuildContext context, double width, double height) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: theme.colorScheme.outline,
        size: 28,
      ),
    );
  }

  Widget _buildErrorPlaceholder(
    BuildContext context,
    double width,
    double height,
  ) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: theme.colorScheme.error,
            size: 28,
          ),
          const SizedBox(height: 4),
          Text(
            '图片加载失败',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}
