import 'package:flutter/material.dart';

import '../../gen_l10n/app_localizations.dart';
import '../../theme/theme_style.dart';
import '../../utils/delta_media_extractor.dart';
import '../../utils/optimized_image_loader.dart';
import 'collapsed_media_image.dart';

/// 折叠卡片顶部的通栏媒体条。
///
/// 和 [CollapsedMediaThumbnail] 是同一件事的另一种版式，区别只在「画在哪、画多大」：
///
/// - 缩略图：右侧 72×72 方块，文字是主角，解码约 80KB
/// - 通栏条：卡片顶部整宽固定高，照片是主角，解码约 0.8~1.4MB
///
/// 通栏的解码开销高一个量级，这不是浪费——在 340pt 宽的位置显示清晰，就必须解到
/// ≥680px 宽，高度按原图比例跟着来，没法只解一条带。选它就是选这个代价。
///
/// 位置上是**归一化**的：不管图片在 delta 里排第几，都画在卡片顶部。因此它和
/// 缩略图一样，只要笔记里有媒体就一定看得见——而 inline 版式下排在正文后面的图
/// 会被折叠高度直接截掉。
class CollapsedMediaBanner extends StatelessWidget {
  const CollapsedMediaBanner({
    super.key,
    required this.media,
    this.onTap,
    this.height = defaultHeight,
  });

  /// 通栏条高度。取值接近 16:9 在常规卡片宽度下的高度，照片不至于被压成窄带。
  static const double defaultHeight = 150.0;

  /// 通栏条与下方正文的间距。
  static const double gap = 10.0;

  final DeltaMediaSummary media;

  /// 点击回调，一般是打开大图预览。为 null 时不可点。
  final VoidCallback? onTap;

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(
      AppShapeTokens.of(context).cardRadius * 0.75,
    );

    final String? imageSource = media.firstImageSource;
    final int extraCount = media.totalCount - 1;

    final Widget banner = SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageSource != null)
              _BannerImage(source: imageSource)
            else
              Semantics(
                label: media.videoCount > 0 ? l10n.video : l10n.audio,
                child: CollapsedMediaPlaceholder(
                  icon: media.videoCount > 0
                      ? Icons.videocam_outlined
                      : Icons.audiotrack_outlined,
                  iconSize: 32,
                ),
              ),
            if (extraCount > 0)
              Positioned(
                right: 8,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.scrim.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Text(
                      '+$extraCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        // 底板是 scrim（任何主题下都是半透明黑），刻意用固定白色：
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

    if (onTap == null) return banner;

    // 卡片本身的双击是「展开」，这里的单击是「看这张图」，两个手势各管各的。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: banner,
    );
  }
}

/// 通栏图本体：按卡片实际宽度解码，`cover` 填满固定高度的条。
class _BannerImage extends StatelessWidget {
  const _BannerImage({required this.source});

  final String source;

  /// 通栏解码的像素比上限。
  ///
  /// 比缩略图那条路（2.0）更保守：通栏的绝对尺寸大一个量级，同样的倍率下单张要
  /// 多花好几倍内存，而通栏本身是装饰性的，轻微软化远不如内存重要。
  static const double _maxPixelRatio = 1.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
        final double pixelRatio =
            MediaQuery.devicePixelRatioOf(context).clamp(1.0, _maxPixelRatio);

        // 只按宽度封顶，高度交给 decodeHeightBudget 兜住超长拼接图：
        // 同时给宽高会走 ResizeImagePolicy.fit（等比缩进框内），横图会被压到
        // 高度不足以 cover，反而糊。
        final int? decodeWidth = decodeSizeFor(width, pixelRatio);

        return CollapsedMediaImage(
          source: source,
          cacheWidth: decodeWidth,
          cacheHeight: decodeHeightBudget(decodeWidth),
          placeholderIconSize: 32,
        );
      },
    );
  }
}
