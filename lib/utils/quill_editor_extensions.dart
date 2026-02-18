// ignore_for_file: implementation_imports

import 'dart:collection';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:flutter_quill_extensions/src/editor/image/widgets/image.dart'
    show ImageTapWrapper;
import 'package:visibility_detector/visibility_detector.dart';

import '../utils/app_logger.dart';
import '../utils/optimized_image_loader.dart';
import '../widgets/media_player_widget.dart';

/// Quill编辑器扩展配置
/// 图片使用flutter_quill_extensions官方实现，视频和音频使用自定义MediaPlayerWidget
class QuillEditorExtensions {
  /// 获取编辑器的嵌入构建器
  static List<quill.EmbedBuilder> getEmbedBuilders({
    bool optimizedImages = true,
  }) {
    // 获取官方的builders作为基础
    final builders = kIsWeb
        ? FlutterQuillEmbeds.editorWebBuilders()
        : FlutterQuillEmbeds.editorBuilders();

    if (!kIsWeb) {
      // 非Web平台使用自定义的视频和音频构建器
      builders.removeWhere(
        (builder) => builder.key == 'video' || builder.key == 'audio',
      );
      builders.add(_CustomVideoEmbedBuilder());
      builders.add(_CustomAudioEmbedBuilder());
    }

    if (optimizedImages) {
      builders.removeWhere((builder) => builder.key == 'image');
      builders.add(_OptimizedImageEmbedBuilder());
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
  static const QuillEditorImageEmbedConfig _imageConfig =
      QuillEditorImageEmbedConfig(
        imageProviderBuilder: _optimizedImageProviderBuilder,
      );

  static ImageProvider? _optimizedImageProviderBuilder(
    BuildContext context,
    String imageUrl,
  ) {
    return createOptimizedImageProvider(imageUrl);
  }

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
    final double? specifiedWidth = _readDimension(
      styleAttributes[quill.Attribute.width.key]?.value,
    );
    final double? specifiedHeight = _readDimension(
      styleAttributes[quill.Attribute.height.key]?.value,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: _LazyQuillImage(
        source: source,
        specifiedWidth: specifiedWidth,
        specifiedHeight: specifiedHeight,
        uniqueId: embedContext.node.hashCode,
        config: _imageConfig,
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
    required this.config,
  });

  final String source;
  final int uniqueId;
  final double? specifiedWidth;
  final double? specifiedHeight;
  final QuillEditorImageEmbedConfig config;

  @override
  State<_LazyQuillImage> createState() => _LazyQuillImageState();
}

class _LazyQuillImageState extends State<_LazyQuillImage>
    with AutomaticKeepAliveClientMixin {
  static final LinkedHashSet<String> _loadedSources = LinkedHashSet<String>();
  static const int _maxCachedSources = 200;

  bool _shouldLoad = false;
  bool _hasError = false;
  bool _isLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (_loadedSources.contains(widget.source)) {
      _shouldLoad = true;
      _isLoaded = true;
    }
  }

  @override
  void didUpdateWidget(covariant _LazyQuillImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _hasError = false;
      final bool previouslyLoaded = _loadedSources.contains(widget.source);
      _shouldLoad = previouslyLoaded;
      _isLoaded = previouslyLoaded;
    }
  }

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

        final double devicePixelRatio = mediaQuery.devicePixelRatio.clamp(
          1.0,
          3.0,
        );
        final int? targetCacheWidth = _computeCacheSize(
          displayWidth,
          devicePixelRatio,
        );

        return RepaintBoundary(
          child: VisibilityDetector(
            key: ValueKey(
              'quill_image_${widget.uniqueId}_${widget.source.hashCode}',
            ),
            onVisibilityChanged: _handleVisibility,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: displayWidth),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildImageContent(
                  context,
                  displayWidth,
                  targetCacheWidth,
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

  Widget _buildImageContent(
    BuildContext context,
    double width,
    int? cacheWidth,
  ) {
    if (_hasError) {
      return _buildErrorPlaceholder(context, width);
    }

    final provider = createOptimizedImageProvider(
      widget.source,
      cacheWidth: _shouldLoad ? cacheWidth : null,
    );

    if (provider == null) {
      logDebug(
        '图片Provider创建失败: ${widget.source}',
        source: 'OptimizedImageEmbed',
      );
      return _buildErrorPlaceholder(context, width);
    }

    return Semantics(
      button: true,
      label: '查看图片',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openImagePreview(context),
        child: Image(
          image: provider,
          width: width,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          isAntiAlias: true,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) {
              _rememberSource(widget.source);
              _isLoaded = true;
              return child;
            }

            if (frame != null && !_isLoaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _isLoaded) {
                  return;
                }
                setState(() {
                  _isLoaded = true;
                  _rememberSource(widget.source);
                });
              });
            }

            if (_isLoaded) {
              return child;
            }

            if (frame == null) {
              // 图片未加载时显示占位符
              return _buildImagePlaceholder(context, width);
            }

            return AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: child,
            );
          },
          loadingBuilder: (context, child, progress) {
            // 如果不应该加载或已加载完成，直接显示图片
            if (!_shouldLoad || progress == null || _isLoaded) {
              return child;
            }

            // 加载中：在图片上叠加半透明背景和进度指示器
            return Stack(
              alignment: Alignment.center,
              children: [
                child, // 图片本身占据空间
                Container(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                          : null,
                      strokeWidth: 2,
                    ),
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

            return _buildErrorPlaceholder(context, width);
          },
        ),
      ),
    );
  }

  void _rememberSource(String source) {
    if (_loadedSources.contains(source)) {
      _loadedSources.remove(source);
    }
    _loadedSources.add(source);
    if (_loadedSources.length > _maxCachedSources) {
      final oldest = _loadedSources.first;
      _loadedSources.remove(oldest);
    }
  }

  Future<void> _openImagePreview(BuildContext context) async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ImageTapWrapper(imageUrl: widget.source, config: widget.config),
      ),
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

  Widget _buildImagePlaceholder(BuildContext context, double width) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 80),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
        size: 32,
      ),
    );
  }

  Widget _buildErrorPlaceholder(BuildContext context, double width) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 120),
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
