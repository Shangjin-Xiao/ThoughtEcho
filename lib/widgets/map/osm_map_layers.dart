import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/app_logger.dart';

/// 两个地图页共用的 OpenStreetMap 瓦片配置与版权标注。
///
/// OSM 的瓦片使用条款要求带上可识别的 User-Agent、并显著标注数据来源
/// （https://operations.osmfoundation.org/policies/tiles）。集中在一处，免得
/// 两个页面各写一份、其中一份忘了标注。
abstract final class OsmMapLayers {
  static const String _tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// 兜底瓦片源：使用 OpenStreetMap France (osmfr) 镜像源。
  /// 注意：osmfr 采用法语社区定制的 CartoCSS 渲染样式，与官方主源相比在色彩与微观注记上有轻微差异，
  /// 但具备独立的 CDN 节点；当官方主源发生超时、阻断或局部 404 时，可作为可用性兜底避免地图出现大面积白块。
  static const String _fallbackTileUrlTemplate =
      'https://tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png';

  /// 用于 User-Agent，与 Android 的 applicationId 一致。
  static const String _packageName = 'com.shangjin.thoughtecho';

  /// 官方瓦片只出到 19 级。
  ///
  /// 不设的话再往里放大会去请求根本不存在的瓦片，地图变成一片空白；设了之后
  /// 引擎会拉伸第 19 级继续放大。
  static const int _maxNativeZoom = 19;

  static final Uri _copyrightUri =
      Uri.parse('https://www.openstreetmap.org/copyright');

  /// 瓦片层。作为 [FlutterMap] 的第一个 child。
  /// 配置持久化磁盘瓦片缓存，并启用预缓冲 (panBuffer: 1) 与全球加速镜像兜底 (fallbackUrl)，
  /// 避免缩放与平移时因瓦片请求卡顿而出现灰块。
  static TileLayer tiles() => TileLayer(
        urlTemplate: _tileUrlTemplate,
        fallbackUrl: _fallbackTileUrlTemplate,
        userAgentPackageName: _packageName,
        maxNativeZoom: _maxNativeZoom,
        panBuffer: 1,
        tileProvider: NetworkTileProvider(
          cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(),
        ),
      );

  /// 版权标注层。放在 [FlutterMap] 的最后一个 child，压在瓦片之上。
  /// 明确标明数据来源自 OpenStreetMap contributors 及兜底源 OSM France。
  static Widget attribution() => SimpleAttributionWidget(
        source: const Text('OpenStreetMap contributors / OSM France'),
        onTap: _openCopyrightPage,
      );

  static Future<void> _openCopyrightPage() async {
    try {
      await launchUrl(_copyrightUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      // 打不开浏览器不影响看地图，记一笔就够了
      logDebug('打开 OpenStreetMap 版权页失败: $e', source: 'OsmMapLayers');
    }
  }
}
