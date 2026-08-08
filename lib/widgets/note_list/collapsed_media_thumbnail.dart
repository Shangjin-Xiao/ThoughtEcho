import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../theme/theme_style.dart';
import '../../utils/delta_media_extractor.dart';
import '../../utils/optimized_image_loader.dart';

/// 折叠卡片右侧的媒体缩略图。
///
/// 这个组件存在的理由是**时序**，不是样式：
///
/// 1. 折叠卡片的正文区只有 `QuoteContent.collapsedContentMaxHeight`（160px）高，
///    原来在这个窗口里用 Quill 的 embedBuilder 渲染一张按卡片全宽解码的图（约
///    720px 宽 / 1.2MB），再被 `ClipRect` 裁掉大半——花整张图的内存只换来一条窄带。
/// 2. 更要命的是，Quill 在滚动期间根本不物化（见 `_DeferredRichTextContent`），
///    所以图片组件压根不进 widget 树，用户看到的是「空白 → 灰框 → 图片」三段式。
///
/// 把缩略图提到 Quill 外面之后，它随卡片一起挂载、随卡片一起加载，不再排在富文本
/// 物化队列后面；固定尺寸也让占位和成图完全同尺寸，列表 extent 不会因为图片解码
/// 完成而变化。
///
/// 完整的图文混排仍然在展开态和全屏编辑器里，由真正的 Quill 渲染。
class CollapsedMediaThumbnail extends StatelessWidget {
  const CollapsedMediaThumbnail({
    super.key,
    required this.media,
    this.size = defaultSize,
  });

  /// 缩略图边长。折叠正文区高 160px，72 既能看清内容又不挤占文字宽度。
  static const double defaultSize = 72.0;

  /// 缩略图与正文之间的间距。
  static const double gap = 12.0;

  /// 折叠卡片为缩略图预留的总宽度（含间距）。布局侧据此收窄文字宽度。
  static double reservedWidth({double size = defaultSize}) => size + gap;

  final DeltaMediaSummary media;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(
      AppShapeTokens.of(context).cardRadius * 0.75,
    );

    final String? imageSource = media.firstImageSource;
    final int extraCount = media.totalCount - 1;

    return Semantics(
      image: imageSource != null,
      label: imageSource != null
          ? l10n.viewImage
          : (media.videoCount > 0 ? l10n.video : l10n.audio),
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageSource != null)
                _ThumbnailImage(source: imageSource, size: size)
              else
                _MediaKindPlaceholder(
                  icon: media.videoCount > 0
                      ? Icons.videocam_outlined
                      : Icons.audiotrack_outlined,
                ),
              if (extraCount > 0)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.scrim.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.only(
                        topLeft: radius.topLeft,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      child: Text(
                        '+$extraCount',
                        style: theme.textTheme.labelSmall?.copyWith(
                          // 底板是 scrim（任何主题下都是半透明黑），所以这里刻意
                          // 用固定白色而不是跟随主题的 onSurface 一类令牌——
                          // 跟随主题会在浅色模式下变成黑字压在黑底上。
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 缩略图本体。
///
/// 直接构建 `Image`，**不加任何自建的"滚动时先别加载"门控**——`Image` 内部的
/// `ScrollAwareImageProvider` 已经实现了「快滚时延迟解码、但缓存命中永不延迟」，
/// 自己再加一层只会把命中路径也拖慢一帧加上百毫秒。
class _ThumbnailImage extends StatefulWidget {
  const _ThumbnailImage({required this.source, required this.size});

  final String source;
  final double size;

  @override
  State<_ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<_ThumbnailImage> {
  bool _hasError = false;

  ImageProvider? _provider;
  String? _providerSource;
  int? _providerDecodeSize;

  @override
  void didUpdateWidget(covariant _ThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _hasError = false;
      _provider = null;
      _providerSource = null;
      _providerDecodeSize = null;
    }
  }

  ImageProvider? _resolveProvider(int? decodeSize) {
    // 命中条件**不能**带上 `_provider != null`：source 非法时
    // createOptimizedImageProvider 返回 null，带上这个条件就永远命不中，
    // 每一帧都要重新解析一次来源。
    if (_providerSource == widget.source && _providerDecodeSize == decodeSize) {
      return _provider;
    }
    final provider = createOptimizedImageProvider(
      widget.source,
      cacheWidth: decodeSize,
      cacheHeight: decodeSize,
    );
    _provider = provider;
    _providerSource = widget.source;
    _providerDecodeSize = decodeSize;
    return provider;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const _MediaKindPlaceholder(icon: Icons.broken_image_outlined);
    }

    // 缩略图按自己的边长解码，不再按卡片全宽：72pt × dpr3 ≈ 216px，
    // 单张约 190KB，相比原来整宽解码的 ~1.2MB 少一个数量级，
    // 滚动时也就不再逼近图片缓存上限、不再触发淘汰重解。
    final decodeSize = decodeSizeFor(
      widget.size,
      MediaQuery.devicePixelRatioOf(context),
    );
    final provider = _resolveProvider(decodeSize);
    if (provider == null) {
      return const _MediaKindPlaceholder(icon: Icons.broken_image_outlined);
    }

    return Image(
      image: provider,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      isAntiAlias: true,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return const _MediaKindPlaceholder(icon: Icons.image_outlined);
      },
      errorBuilder: (context, error, stackTrace) {
        if (!_hasError) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _hasError = true);
            }
          });
        }
        return const _MediaKindPlaceholder(icon: Icons.broken_image_outlined);
      },
    );
  }
}

/// 占位与非图片媒体共用的同尺寸底板：和成图完全同尺寸，切换时不改变布局。
class _MediaKindPlaceholder extends StatelessWidget {
  const _MediaKindPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
      child: Center(
        child: Icon(
          icon,
          size: 24,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
