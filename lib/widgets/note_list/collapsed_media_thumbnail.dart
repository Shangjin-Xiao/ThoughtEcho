import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../theme/theme_style.dart';
import '../../utils/delta_media_extractor.dart';
import '../../utils/optimized_image_loader.dart';
import 'collapsed_media_image.dart';

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
    this.onTap,
    this.size = defaultSize,
  });

  /// 缩略图边长。折叠正文区高 160px，72 既能看清内容又不挤占文字宽度。
  static const double defaultSize = 72.0;

  /// 缩略图与正文之间的间距。
  static const double gap = 12.0;

  /// 折叠卡片为缩略图预留的总宽度（含间距）。布局侧据此收窄文字宽度。
  static double reservedWidth({double size = defaultSize}) => size + gap;

  final DeltaMediaSummary media;

  /// 点击缩略图的回调，一般是打开大图预览。为 null 时不可点。
  final VoidCallback? onTap;

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

    final Widget thumbnail = SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 语义标签放在图片分支内部：加载失败时读屏应当播报「图片加载失败」，
            // 而不是继续说「查看图片」——失败态只有 _ThumbnailImage 自己知道。
            if (imageSource != null)
              _ThumbnailImage(size: size, source: imageSource)
            else
              Semantics(
                label: media.videoCount > 0 ? l10n.video : l10n.audio,
                child: CollapsedMediaPlaceholder(
                  icon: media.videoCount > 0
                      ? Icons.videocam_outlined
                      : Icons.audiotrack_outlined,
                ),
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
    );

    if (onTap == null) return thumbnail;

    // 卡片本身的双击是「展开」，这里的单击是「看这张图」，两个手势各管各的。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: thumbnail,
    );
  }
}

/// 方形缩略图本体：按自身边长解码，`cover` 居中裁切。
///
/// 方形不是随手挑的——`BoxFit.cover` 要求解码尺寸在两个维度上都不小于显示尺寸，
/// 只有近方形时这个要求才有界。宽扁的条带要同时满足宽和高，反而会解到比原来
/// 整宽渲染还大。通栏版式因此走另一套解码策略，见 [CollapsedMediaBanner]。
class _ThumbnailImage extends StatelessWidget {
  const _ThumbnailImage({required this.size, required this.source});

  final double size;
  final String source;

  /// 卡片内预览图的解码倍率上限，沿用富文本嵌入那条路的取值。
  static const double _maxPixelRatio = 2.0;

  @override
  Widget build(BuildContext context) {
    // 72pt × dpr2 = 144px，单张约 83KB；相比按卡片全宽解码的 ~1.2MB 小一个量级。
    final decodeSize = decodeSizeFor(
      size,
      MediaQuery.devicePixelRatioOf(context).clamp(1.0, _maxPixelRatio),
    );
    return CollapsedMediaImage(
      source: source,
      cacheWidth: decodeSize,
      cacheHeight: decodeSize,
    );
  }
}
