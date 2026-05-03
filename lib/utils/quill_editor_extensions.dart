import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../gen_l10n/app_localizations.dart';
import '../utils/app_logger.dart';
import '../utils/optimized_image_loader.dart';
import '../widgets/media_player_widget.dart';
import '../widgets/motion_photo_preview_page.dart';

/// 全局滚动状态信号，由 NoteListView 的 NotificationListener 写入。
/// _LazyQuillImage 通过读取此信号判断列表是否仍在 ballistic（惯性）滚动阶段，
/// 从而避免松手后图片立即解码与惯性帧竞争 raster 线程导致的卡顿。
final ValueNotifier<bool> isListScrolling = ValueNotifier<bool>(false);

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
  static final LinkedHashSet<String> _loadedSources = LinkedHashSet<String>();
  static final LinkedHashMap<String, double> _aspectRatioCache =
      LinkedHashMap<String, double>();
  static const int _maxCachedSources = 200;
  static const int _maxCachedAspectRatios = 200;
  static const double _fallbackAspectRatio = 4 / 3;

  bool _shouldLoad = false;
  bool _hasError = false;
  bool _isLoaded = false;
  bool _isResolvingImage = false;
  double? _aspectRatio;
  double? _lastDisplayWidth;
  int? _lastCacheWidth;
  ImageProvider? _resolvedProvider;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  Timer? _deferredLoadTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _aspectRatio = _aspectRatioCache[widget.source];
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
      _isResolvingImage = false;
      _aspectRatio = _aspectRatioCache[widget.source];
      _resolvedProvider = null;
      _detachImageStreamListener();
      final bool previouslyLoaded = _loadedSources.contains(widget.source);
      _shouldLoad = previouslyLoaded;
      _isLoaded = previouslyLoaded;
      _deferredLoadTimer?.cancel();
    }
  }

  void _handleVisibility(VisibilityInfo info) {
    if (_shouldLoad) {
      return;
    }

    if (info.visibleFraction <= 0.01) {
      _deferredLoadTimer?.cancel();
      return;
    }

    if (info.visibleFraction > 0.05) {
      _tryStartLoading();
    }
  }

  void _tryStartLoading() {
    if (!mounted || _shouldLoad) {
      return;
    }

    // 检查 Flutter 滚动系统是否建议推迟加载（drag 阶段）
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      _deferredLoadTimer?.cancel();
      _deferredLoadTimer = Timer(const Duration(milliseconds: 120), () {
        if (!mounted || _shouldLoad) {
          return;
        }
        _tryStartLoading();
      });
      return;
    }

    // 额外检查：recommendDeferredLoadingForContext 在 ballistic（惯性）阶段
    // 也会返回 false，但此时列表仍在高速惯性滑动。通过外层 NoteListView 写入的
    // 全局信号判断是否处于 ballistic 阶段，继续延迟解码避免和惯性帧竞争 raster。
    if (isListScrolling.value) {
      _deferredLoadTimer?.cancel();
      _deferredLoadTimer = Timer(const Duration(milliseconds: 80), () {
        if (!mounted || _shouldLoad) return;
        _tryStartLoading();
      });
      return;
    }

    _resolveImageBeforeDisplay();
  }

  void _resolveImageBeforeDisplay() {
    if (!mounted || _shouldLoad || _isResolvingImage) {
      return;
    }

    final provider = createOptimizedImageProvider(
      widget.source,
      cacheWidth: _lastCacheWidth,
    );

    if (provider == null) {
      logDebug(
        '图片Provider创建失败: ${widget.source}',
        source: 'OptimizedImageEmbed',
      );
      setState(() {
        _hasError = true;
      });
      return;
    }

    _resolvedProvider = provider;
    _isResolvingImage = true;
    _detachImageStreamListener();

    final stream = provider.resolve(
      createLocalImageConfiguration(
        context,
        size:
            _lastDisplayWidth != null ? Size.square(_lastDisplayWidth!) : null,
      ),
    );
    _imageStream = stream;
    _imageStreamListener = ImageStreamListener(
      (imageInfo, _) {
        final image = imageInfo.image;
        final ratio = image.height == 0
            ? null
            : image.width.toDouble() / image.height.toDouble();

        if (ratio != null && ratio.isFinite && ratio > 0) {
          _rememberAspectRatio(widget.source, ratio);
          _aspectRatio = ratio;
        }

        if (!mounted) {
          return;
        }

        setState(() {
          _isResolvingImage = false;
          _shouldLoad = true;
        });
        _detachImageStreamListener();
      },
      onError: (error, stackTrace) {
        logError(
          '图片尺寸解析失败: ${widget.source}',
          error: error,
          stackTrace: stackTrace,
          source: 'OptimizedImageEmbed',
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _isResolvingImage = false;
          _hasError = true;
        });
        _detachImageStreamListener();
      },
    );
    stream.addListener(_imageStreamListener!);
  }

  @override
  void dispose() {
    _deferredLoadTimer?.cancel();
    _detachImageStreamListener();
    super.dispose();
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
        _lastDisplayWidth = displayWidth;
        _lastCacheWidth = targetCacheWidth;

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
    if (!_shouldLoad) {
      return _buildImagePlaceholder(context, width);
    }

    if (_hasError) {
      return _buildErrorPlaceholder(context, width);
    }

    final provider = _resolvedProvider ??
        createOptimizedImageProvider(
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

    final image = Semantics(
      button: true,
      label: AppLocalizations.of(context).viewImage,
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

    final reservedHeight = _reservedHeightForWidth(width);
    if (reservedHeight == null) {
      return image;
    }

    return SizedBox(
      width: width,
      height: reservedHeight,
      child: image,
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

  void _rememberAspectRatio(String source, double aspectRatio) {
    if (_aspectRatioCache.containsKey(source)) {
      _aspectRatioCache.remove(source);
    }
    _aspectRatioCache[source] = aspectRatio;
    if (_aspectRatioCache.length > _maxCachedAspectRatios) {
      final oldest = _aspectRatioCache.keys.first;
      _aspectRatioCache.remove(oldest);
    }
  }

  void _detachImageStreamListener() {
    final listener = _imageStreamListener;
    final stream = _imageStream;
    if (listener != null && stream != null) {
      stream.removeListener(listener);
    }
    _imageStreamListener = null;
    _imageStream = null;
  }

  Future<void> _openImagePreview(BuildContext context) async {
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MotionPhotoPreviewPage(imageUrl: widget.source),
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
    return SizedBox(
      width: width,
      height: _reservedHeightForWidth(width) ?? 160,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            size: 32,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder(BuildContext context, double width) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      height: _reservedHeightForWidth(width) ?? 160,
      child: ColoredBox(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        child: Center(
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
        ),
      ),
    );
  }

  double? _reservedHeightForWidth(double width) {
    if (!width.isFinite || width <= 0) {
      return null;
    }

    final specifiedHeight = widget.specifiedHeight;
    if (specifiedHeight != null && specifiedHeight > 0) {
      return specifiedHeight.clamp(80.0, 4096.0).toDouble();
    }

    final ratio = _aspectRatio ?? _aspectRatioCache[widget.source];
    final effectiveRatio = ratio != null && ratio.isFinite && ratio > 0
        ? ratio
        : _fallbackAspectRatio;
    return (width / effectiveRatio).clamp(120.0, 4096.0).toDouble();
  }
}
