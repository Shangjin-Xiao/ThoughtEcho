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
    final double? specifiedWidth =
        _readDimension(styleAttributes[quill.Attribute.width.key]?.value);
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
  static final Set<String> _loadedSources = <String>{};

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

        final double devicePixelRatio =
            mediaQuery.devicePixelRatio.clamp(1.0, 3.0);
        final int? targetCacheWidth =
            _computeCacheSize(displayWidth, devicePixelRatio);

        return RepaintBoundary(
          child: VisibilityDetector(
            key: ValueKey(
              'quill_image_${widget.uniqueId}_${widget.source.hashCode}',
            ),
            onVisibilityChanged: _handleVisibility,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: displayWidth,
              ),
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
      logDebug('图片Provider创建失败: ${widget.source}',
          source: 'OptimizedImageEmbed');
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
              _loadedSources.add(widget.source);
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
                  _loadedSources.add(widget.source);
                });
              });
            }

            if (_isLoaded) {
              return child;
            }

            return AnimatedOpacity(
              opacity: frame == null ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 220),
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
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHigh
                      .withValues(alpha: 0.7),
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

  Future<void> _openImagePreview(BuildContext context) async {
    final ImageProvider? previewProvider = createOptimizedImageProvider(
            widget.source,
            cacheWidth: null,
            cacheHeight: null) ??
        createOptimizedImageProvider(widget.source);

    if (previewProvider == null) {
      logWarning('无法打开图片预览: Provider 创建失败 (${widget.source})',
          source: 'OptimizedImageEmbed');
      return;
    }

    if (!mounted) {
      return;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final theme = Theme.of(dialogContext);
        return Material(
          color: Colors.black.withValues(alpha: 0.92),
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 0.6,
                    maxScale: 4.0,
                    child: Image(
                      image: previewProvider,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) {
                          return child;
                        }
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              constraints: const BoxConstraints(
                                  maxWidth: 420, maxHeight: 420),
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 36,
                                height: 36,
                                child:
                                    CircularProgressIndicator(strokeWidth: 3),
                              ),
                            ),
                          ],
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return SizedBox(
                          width: 260,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.broken_image_outlined,
                                  color: Colors.white70, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                '图片加载失败',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(color: Colors.white70),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: '关闭图片预览',
                    onPressed: () => Navigator.of(dialogContext).maybePop(),
                  ),
                ),
              ],
            ),
          ),
        );
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

  Widget _buildErrorPlaceholder(
    BuildContext context,
    double width,
  ) {
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
