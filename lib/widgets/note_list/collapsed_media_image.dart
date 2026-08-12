import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../utils/optimized_image_loader.dart';

/// 折叠卡片里媒体图片的统一渲染实现，[CollapsedMediaThumbnail] 与
/// [CollapsedMediaBanner] 共用。两种版式的差别只在尺寸和解码上限，加载时序、
/// 失败处理、语义标签这些必须一致，所以抽在这里一份。
///
/// 关键约束：**不要在这里加任何自建的「滚动时先别加载」门控。**
/// `Image` 内部已经把 provider 包了一层 `ScrollAwareImageProvider`：
///
/// ```
/// if (stream.completer != null || imageCache.containsKey(key)) → 立即解析
/// else if (Scrollable.recommendDeferredLoadingForContext(ctx)) → 延到下一帧
/// else → 立即解析
/// ```
///
/// 即「快滚时延迟解码、但缓存命中永不延迟」这件事 Flutter 本来就做对了。自己再加
/// 一层会跑在 `Image` 被创建之前，对命中和未命中一视同仁地砍掉一帧加上百毫秒——
/// 「滑回来又变灰」大多是这么造出来的。
class CollapsedMediaImage extends StatefulWidget {
  const CollapsedMediaImage({
    super.key,
    required this.source,
    this.cacheWidth,
    this.cacheHeight,
    this.placeholderIconSize = 24,
  });

  final String source;
  final int? cacheWidth;
  final int? cacheHeight;
  final double placeholderIconSize;

  @override
  State<CollapsedMediaImage> createState() => _CollapsedMediaImageState();
}

class _CollapsedMediaImageState extends State<CollapsedMediaImage> {
  bool _hasError = false;

  ImageProvider? _provider;
  String? _providerSource;
  int? _providerCacheWidth;
  int? _providerCacheHeight;

  @override
  void didUpdateWidget(covariant CollapsedMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 解码尺寸变化（旋屏、dpr 变化、通栏宽度变化）也要重置。
    // 只比 source 的话 _hasError 会一直挂着，而 build 第一行就因它提前返回失败
    // 占位——新建出来的 provider 永远没机会被试，这张图就永久停在 broken-image。
    if (oldWidget.source != widget.source ||
        oldWidget.cacheWidth != widget.cacheWidth ||
        oldWidget.cacheHeight != widget.cacheHeight) {
      _hasError = false;
      _provider = null;
      _providerSource = null;
      _providerCacheWidth = null;
      _providerCacheHeight = null;
    }
  }

  ImageProvider? _resolveProvider() {
    // 命中条件**不能**带上 `_provider != null`：source 非法时
    // createOptimizedImageProvider 返回 null，带上这个条件就永远命不中，
    // 每一帧都要重新解析一次来源。已存的三个字段本身就是缓存键。
    if (_providerSource == widget.source &&
        _providerCacheWidth == widget.cacheWidth &&
        _providerCacheHeight == widget.cacheHeight) {
      return _provider;
    }
    final provider = createOptimizedImageProvider(
      widget.source,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
    );
    _provider = provider;
    _providerSource = widget.source;
    _providerCacheWidth = widget.cacheWidth;
    _providerCacheHeight = widget.cacheHeight;
    return provider;
  }

  Widget _failed(BuildContext context) => Semantics(
        label: AppLocalizations.of(context).imageLoadFailed,
        child: CollapsedMediaPlaceholder(
          icon: Icons.broken_image_outlined,
          iconSize: widget.placeholderIconSize,
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_hasError) return _failed(context);

    final provider = _resolveProvider();
    if (provider == null) return _failed(context);

    // 失败回调是异步的（postFrame），期间这张图可能已经被换掉。回调里必须确认
    // 失败的还是当前这张，否则旧请求的失败会把新图永久钉在 broken-image 上。
    //
    // 只比 source 不够：尺寸或 devicePixelRatio 变化时 source 不变、provider 却
    // 换了新的，旧 provider 的失败照样会污染新解码。所以连 provider 身份一起比。
    final failedSource = widget.source;
    final failedProvider = provider;

    return Semantics(
      image: true,
      label: AppLocalizations.of(context).viewImage,
      child: Image(
        image: provider,
        fit: BoxFit.cover,
        // 非方形图裁掉的是下半截，不是上下各一半。长截图、竖版照片的信息几乎都
        // 在顶部，居中裁会把标题和人脸切掉。
        //
        // ⚠️ 不要改成「按原图比例的非方形缩略图」来避免裁切：方形是唯一能让
        // `cover` 的解码尺寸有上界的形状（见 CollapsedMediaThumbnail 的说明），
        // 改了会把已经解决的内存问题重新引进来。
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.low,
        isAntiAlias: true,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return CollapsedMediaPlaceholder(
            icon: Icons.image_outlined,
            iconSize: widget.placeholderIconSize,
          );
        },
        errorBuilder: (context, error, stackTrace) {
          if (!_hasError) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  widget.source == failedSource &&
                  identical(_provider, failedProvider)) {
                setState(() => _hasError = true);
              }
            });
          }
          return CollapsedMediaPlaceholder(
            icon: Icons.broken_image_outlined,
            iconSize: widget.placeholderIconSize,
          );
        },
      ),
    );
  }
}

/// 占位与非图片媒体共用的同尺寸底板：和成图完全同尺寸，切换时不改变布局。
class CollapsedMediaPlaceholder extends StatelessWidget {
  const CollapsedMediaPlaceholder({
    super.key,
    required this.icon,
    this.iconSize = 24,
  });

  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
      child: Center(
        child: Icon(
          icon,
          size: iconSize,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
