import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// 按解码上限包装 provider。
///
/// 同时给了宽高时必须用 [ResizeImagePolicy.fit]（等比缩放到框内），
/// `ResizeImage` 默认的 `exact` 会把图拉成给定的宽高、直接变形。
/// 只给一个维度时另一维本就按比例推算，沿用默认策略即可。
ImageProvider wrapWithDecodeLimit(
  ImageProvider provider,
  int? cacheWidth,
  int? cacheHeight,
) {
  if (cacheWidth == null && cacheHeight == null) {
    return provider;
  }

  return ResizeImage(
    provider,
    width: cacheWidth,
    height: cacheHeight,
    policy: (cacheWidth != null && cacheHeight != null)
        ? ResizeImagePolicy.fit
        : ResizeImagePolicy.exact,
  );
}

/// 解码尺寸的下限与上限（设备像素）。
///
/// 下限避免极窄容器把图解成马赛克；上限避免超大图把单张解码撑爆。
const int minDecodeDimension = 160;
const int maxDecodeDimension = 2048;

/// 把「逻辑显示尺寸 × 像素比」换算成解码用的设备像素尺寸。
///
/// 尺寸非法（0、负数、NaN、无穷）时返回 null，表示不设解码上限、按原图解。
int? decodeDimensionFor(double logicalSize, double pixelRatio) {
  if (!logicalSize.isFinite || logicalSize <= 0) {
    return null;
  }

  final double devicePixels = logicalSize * pixelRatio;
  if (!devicePixels.isFinite || devicePixels <= 0) {
    return null;
  }

  if (devicePixels < minDecodeDimension) return minDecodeDimension;
  if (devicePixels > maxDecodeDimension) return maxDecodeDimension;
  return devicePixels.round();
}

/// 全屏预览相对屏幕尺寸的解码放大倍率。
///
/// 预览要能捏合放大看细节，所以不能只按屏幕像素解；但**更不能不设上限按原图解**。
const double previewZoomHeadroom = 2.0;

/// 全屏预览一个维度的解码上限（设备像素）。
///
/// 两个维度都传给 `ResizeImage`（走 [ResizeImagePolicy.fit] 等比缩进框内），
/// 再由 [decodeDimensionFor] 的 [maxDecodeDimension] 封顶，单张最坏
/// 2048×2048 ≈ 16MB。
///
/// 不封顶的代价是实测过的：一张 12MP 照片按原图解就是约 48MB，一次预览就能把
/// 64MB 的 `imageCache` 整个挤空（性能日志里的 `img=1/1000, bytes=47.6MB`），
/// 回到列表后每张缩略图都要重新解码，表现就是「滑过图片格外卡」。
int? previewDecodeDimensionFor(double logicalSize, double pixelRatio) =>
    decodeDimensionFor(logicalSize * previewZoomHeadroom, pixelRatio);

/// 单张图片的解码总像素预算（宽 × 高）。
///
/// 这是**防炸保险，不是画质旋钮**。只给解码宽度封顶时，高度会按原图比例推算：
/// 一张 1080×100000 的超长拼接图在 688 的解码宽度下会展开成 688×63703
/// ≈ 4400 万像素、单张约 175MB，足以直接压垮图片缓存乃至进程。
///
/// 取值刻意留得很宽（12M 像素，约 48MB）：常规照片、甚至十来屏拼接的长截图
/// 都远在预算之内，不会被这条保险碰到。**不要**拿它当"长图省内存"的手段——
/// 等比缩放不是裁剪，压低总像素会连带压低解码宽度，而卡片仍按完整宽度显示，
/// 结果是整张图（含当前可见的那一截）被放大变糊。
const int maxDecodePixels = 12 * 1000 * 1000;

/// 由解码宽度推出满足 [maxDecodePixels] 的高度上限，配合
/// [ResizeImagePolicy.fit] 使用：没超预算的图片不会被这个框改变尺寸。
///
/// [decodeWidth] 为 null（不限制宽度）时返回 null，此时也不设高度上限。
int? decodeHeightBudgetFor(int? decodeWidth) {
  if (decodeWidth == null || decodeWidth <= 0) {
    return null;
  }
  final budget = maxDecodePixels ~/ decodeWidth;
  return budget > 0 ? budget : null;
}

bool isDataUrl(String source) => source.startsWith('data:');

Uint8List? tryDecodeDataUrl(String source) {
  if (!isDataUrl(source)) {
    return null;
  }

  try {
    final uri = Uri.parse(source);
    if (!uri.isScheme('data')) {
      return null;
    }

    final data = uri.data;
    if (data == null) {
      return null;
    }

    return data.contentAsBytes();
  } catch (_) {
    return null;
  }
}
