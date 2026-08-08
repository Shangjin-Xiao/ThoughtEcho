import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';

import '../gen_l10n/app_localizations.dart';
import '../theme/theme_style.dart';
import '../utils/app_logger.dart';
import '../utils/optimized_image_loader.dart';
import '../widgets/media_player_widget.dart';
import '../widgets/motion_photo_preview_page.dart';

/// 全局滚动状态信号，由 NoteListView 的 NotificationListener 写入。
/// _LazyQuillImage 通过读取此信号判断列表是否仍在 ballistic（惯性）滚动阶段，
/// 从而避免松手后图片立即解码与惯性帧竞争 raster 线程导致的卡顿。
final ValueNotifier<bool> isListScrolling = ValueNotifier<bool>(false);

/// 全局拖拽手势信号：ScrollStart(带 dragDetails)→true，ScrollEnd→false。
/// [isListScrolling] 依赖"32ms 内是否有滚动更新"，手指按住但暂停移动时会误判
/// 为已停止；冷 Quill 恢复队列若在此刻物化（单帧可达 20~100ms），用户继续拖动
/// 就会撞上。恢复队列必须同时等待两个信号都为 false。
final ValueNotifier<bool> isListDragActive = ValueNotifier<bool>(false);

/// Lightweight counters for correlating rich-text image loading with list
/// scroll jank. These counters are only read by developer performance logs.
///
/// `sync` 是这里最重要的一个指标：它统计有多少张图在**首帧就同步画出来**
/// （`wasSynchronouslyLoaded`），也就是命中了 `PaintingBinding.imageCache`。
/// `sync / complete` 偏低说明图片真的在被反复重解码；偏高则说明滑回来时看到的
/// 灰框来自别处，不是解码。
class QuillImageEmbedPerfStats {
  static int _startLoadCount = 0;
  static int _syncHitCount = 0;
  static int _frameCompleteCount = 0;
  static int _errorCount = 0;

  static void recordStartLoad() => _startLoadCount++;

  static void recordSyncHit() => _syncHitCount++;

  static void recordFrameComplete() => _frameCompleteCount++;

  static void recordError() => _errorCount++;

  static Map<String, int> snapshot() => {
        'start': _startLoadCount,
        'sync': _syncHitCount,
        'complete': _frameCompleteCount,
        'error': _errorCount,
      };

  static String compact({Map<String, int>? baseline}) {
    final stats = snapshot();
    final start = stats['start']!;
    final sync = stats['sync']!;
    final complete = stats['complete']!;
    final error = stats['error']!;

    return 'start=$start,sync=$sync,complete=$complete,error=$error'
        '${baseline == null ? '' : ',Δstart+${start - (baseline['start'] ?? 0)}'}'
        '${baseline == null ? '' : ',Δsync+${sync - (baseline['sync'] ?? 0)}'}'
        '${baseline == null ? '' : ',Δcomplete+${complete - (baseline['complete'] ?? 0)}'}'
        '${baseline == null ? '' : ',Δerror+${error - (baseline['error'] ?? 0)}'}';
  }
}

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

/// quill 段落基准样式的**唯一**纠正入口。
///
/// `DefaultStyles.getInstance` 的 baseStyle 是从 `DefaultTextStyle` 拷的
/// （颜色、字体族确实跟着主题走），但 `fontSize` 和 `height` 被硬写成 16 / 1.15。
/// 1.15 对中文正文太挤，换成衬线体之后尤其闷；16 则在衬线风格把正文放大到 17
/// （[ThemeStyleForm.bodyFontScale]）之后跟纯文本笔记对不上。
///
/// 两个用到 `QuillEditor` 的地方——笔记卡片正文和全屏编辑器——必须按同一套令牌
/// 纠正，否则「写的时候」和「读的时候」行距不一样。规则因此放在这里一处。
class QuillThemeTypography {
  /// [base] 是调用方已有的正文样式（卡片会传 `bodyLarge` + 笔记颜色）。
  ///
  /// 字号和行高**不从 [DefaultTextStyle] 取**：调用方可能没传 [base]，而那里
  /// 往往是 `bodyMedium`(14)，直接用会把正文缩一号。规则统一成「富文本正文 =
  /// `bodyLarge`」，兜底才轮到 quill 的硬编码值。
  ///
  /// `decoration` 必须显式清掉，否则 [DefaultTextStyle] 里的下划线会漏进正文。
  static TextStyle paragraphStyle(BuildContext context, {TextStyle? base}) {
    final bodyLarge = Theme.of(context).textTheme.bodyLarge;
    final inherited = DefaultTextStyle.of(context).style.merge(base);
    return inherited.copyWith(
      fontSize: base?.fontSize ?? bodyLarge?.fontSize ?? 16,
      height: base?.height ?? bodyLarge?.height ?? 1.15,
      decoration: TextDecoration.none,
    );
  }

  /// 只替换段落样式、其余沿用 quill 默认的 [quill.DefaultStyles]。
  ///
  /// 卡片正文那条路还要额外处理 Android 的加粗降档，所以自己拼 `DefaultStyles`；
  /// 编辑器只需要这一项。
  static quill.DefaultStyles paragraphOnly(TextStyle paragraphStyle) {
    return quill.DefaultStyles(
      paragraph: quill.DefaultTextBlockStyle(
        paragraphStyle,
        const quill.HorizontalSpacing(0, 0),
        quill.VerticalSpacing.zero,
        quill.VerticalSpacing.zero,
        null,
      ),
    );
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
  /// 卡片内预览图的解码倍率上限。
  ///
  /// 这条路径只服务笔记卡片（全屏编辑器用 `optimizedImages: false` 的原生
  /// builder，点开的大图预览页不传解码上限，都拿全分辨率），所以这里只需要
  /// 满足"滑过去看一眼"的清晰度。
  ///
  /// 按屏幕最高精度（dpr 3）解码，单张常规照片就要 2.8MB，二十几张即可占满
  /// Flutter 默认 100MB 的图片缓存；之后每次上下滑都在淘汰和重新解码，
  /// 正是滑过图片时卡顿的来源。降到 2 倍后单张约 1.2MB，占用降到三分之一，
  /// 常规滚动不再触发淘汰。
  ///
  /// 注意这个上限只是封顶：真实倍率仍取设备的 devicePixelRatio，
  /// 低分屏机型本来就低于 2，画质按屏幕自适应这件事没有变。
  static const double _previewMaxPixelRatio = 2.0;

  bool _hasError = false;

  /// 首帧是否已记过一次统计。只用于开发者性能日志，不参与渲染，
  /// 所以不走 `setState`——每张图片一次 `setState` 就是一次滚动帧内的额外重建。
  bool _frameRecorded = false;

  /// `ImageProvider` 按 `(source, cacheWidth, cacheHeight)` 记忆化。
  ///
  /// [build] 跑在 `LayoutBuilder` 里，每帧都会执行；provider 本身的 `==` 虽然稳定
  /// （`ResizeImage` / `FileImage` 都按值比较），但没必要每帧重新分配对象再算一次
  /// 缓存键。
  ImageProvider? _provider;
  String? _providerSource;
  int? _providerCacheWidth;
  int? _providerCacheHeight;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant _LazyQuillImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _hasError = false;
      _frameRecorded = false;
      _provider = null;
      _providerSource = null;
      _providerCacheWidth = null;
      _providerCacheHeight = null;
    }
  }

  /// **不要**在这里重新引入"滚动时先别加载"的门控。
  ///
  /// `Image` 内部已经把 provider 包了一层 `ScrollAwareImageProvider`，它的
  /// `resolveStreamForKey` 是：
  ///
  /// ```
  /// if (stream.completer != null || imageCache.containsKey(key)) → 立即解析
  /// else if (Scrollable.recommendDeferredLoadingForContext(ctx)) → 延到下一帧
  /// else → 立即解析
  /// ```
  ///
  /// 即「快速滚动时延迟解码，但缓存命中永不延迟」这件事 Flutter 本来就做对了，
  /// 命中时在同一帧同步完成、`wasSynchronouslyLoaded == true`、零闪烁。
  ///
  /// 历史实现在 `Image` **被创建之前**加了一道 `_shouldLoad` 门控（postFrame +
  /// 80~120ms Timer），对命中和未命中一视同仁地砍掉一帧加百来毫秒——"滑回来又变灰"
  /// 大多不是真的重解码，而是这道门控自己造出来的。它还配了一个 `_loadedSources`
  /// 影子集合去猜缓存状态，和真实的 `imageCache` 会各自失效、互相说谎。
  ImageProvider? _resolveProvider(int? cacheWidth, int? cacheHeight) {
    // 命中条件**不能**带上 `_provider != null`：source 非法时
    // createOptimizedImageProvider 返回 null，带上这个条件就永远命不中，
    // 每一帧都要重新解析一次来源。已存的三个字段本身就足以标识缓存键。
    if (_providerSource == widget.source &&
        _providerCacheWidth == cacheWidth &&
        _providerCacheHeight == cacheHeight) {
      return _provider;
    }

    final provider = createOptimizedImageProvider(
      widget.source,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
    _provider = provider;
    _providerSource = widget.source;
    _providerCacheWidth = cacheWidth;
    _providerCacheHeight = cacheHeight;
    // 换了缓存键就是一次新的加载，首帧统计要重新记一次，
    // 否则布局宽度变化后的那次解析在 sync/complete 里查无此人。
    _frameRecorded = false;
    if (provider != null) {
      QuillImageEmbedPerfStats.recordStartLoad();
    }
    return provider;
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
          _previewMaxPixelRatio,
        );
        // 只按显示宽度封顶，**不要**再给高度单独封顶。
        // 等比缩放不是裁剪：给长图加高度上限会把解码宽度一起压下去，而卡片
        // 仍按完整宽度显示，结果是整张图（包括当前可见的那一截）被放大变糊。
        // 长图的内存占用只能靠宽度这一个维度控制。
        final int? targetCacheWidth = decodeSizeFor(
          displayWidth,
          devicePixelRatio,
        );
        // 唯一的高度约束是总像素预算这条防炸保险：只给宽度封顶时高度按原图
        // 比例展开，1080×100000 这种超长拼接图会解成上千万像素直接压垮进程。
        // 常规照片和长截图都在预算之内，不会被它改变尺寸（fit 策略只在超框时
        // 才缩放），因此不会重新引入长图变糊的问题。
        final int? decodePixelBudgetHeight = decodeHeightBudget(
          targetCacheWidth,
        );

        return RepaintBoundary(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: displayWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                AppShapeTokens.of(context).cardRadius,
              ),
              child: _buildImageContent(
                context,
                displayWidth,
                targetCacheWidth,
                decodePixelBudgetHeight,
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
    int? cacheHeight,
  ) {
    if (_hasError) {
      return _buildErrorPlaceholder(context, width);
    }

    final provider = _resolveProvider(cacheWidth, cacheHeight);

    if (provider == null) {
      logDebug(
        '图片Provider创建失败: ${widget.source}',
        source: 'OptimizedImageEmbed',
      );
      return _buildErrorPlaceholder(context, width);
    }

    return Semantics(
      button: true,
      label: AppLocalizations.of(context).viewImage,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openImagePreview(context),
        child: Image(
          image: provider,
          width: width,
          fit: BoxFit.contain,
          // 解码尺寸已按 displayWidth × devicePixelRatio 匹配显示尺寸
          // （见 decodeDimensionFor），绘制时基本是 1:1 采样，medium 的
          // mipmap 生成属于纯浪费：多一份 GPU 内存和一趟缩略链构建，
          // 画面却和 low 没有区别。
          filterQuality: FilterQuality.low,
          isAntiAlias: true,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            // 缓存命中：provider 在同一帧就解析完了，直接交出 child。
            // 这里**不能**插入任何过渡包装——插一层就等于把"零闪烁"重新变成
            // "闪一下"。
            if (wasSynchronouslyLoaded) {
              if (!_frameRecorded) {
                _frameRecorded = true;
                QuillImageEmbedPerfStats.recordSyncHit();
                QuillImageEmbedPerfStats.recordFrameComplete();
              }
              return child;
            }

            if (frame == null) {
              return _buildImagePlaceholder(context, width);
            }

            if (!_frameRecorded) {
              _frameRecorded = true;
              QuillImageEmbedPerfStats.recordFrameComplete();
            }

            // 冷加载才淡入，而且只淡这一次：`TweenAnimationBuilder` 在挂载时跑完
            // 0→1 就停在 1，之后 `Opacity` 的 alpha 为 255，`RenderOpacity.paint`
            // 直接透传子节点，不留常驻图层。
            return _FadeInOnce(child: child);
          },
          errorBuilder: (context, error, stackTrace) {
            logError(
              '图片加载失败: ${widget.source}',
              error: error,
              stackTrace: stackTrace,
              source: 'OptimizedImageEmbed',
            );

            if (!_hasError && mounted) {
              QuillImageEmbedPerfStats.recordError();
              // 回调是异步的，期间 source 可能已经换掉。不校验的话，旧图的失败
              // 会把新图永久钉在错误占位上。
              final failedSource = widget.source;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && widget.source == failedSource) {
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
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MotionPhotoPreviewPage(imageUrl: widget.source),
      ),
    );
  }

  Widget _buildImagePlaceholder(BuildContext context, double width) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 80),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.3),
        borderRadius:
            BorderRadius.circular(AppShapeTokens.of(context).cardRadius),
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
            AppLocalizations.of(context).imageLoadFailed,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

/// 挂载时播一次 0→1 淡入，之后永久停在 1。
///
/// 停在 1 之后 `Opacity` 的 alpha 是 255，`RenderOpacity.paint` 会直接
/// `context.paintChild(...)` 透传，`alwaysNeedsCompositing` 也为 false，
/// 所以不会给每张图留一个常驻的 `OpacityLayer`。
class _FadeInOnce extends StatelessWidget {
  const _FadeInOnce({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}
