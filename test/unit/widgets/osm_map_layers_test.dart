import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/map/osm_map_layers.dart';

import '../../test_harness.dart';

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  tearDownAll(() async {
    await TestHarness.tearDown();
  });

  group('OsmMapLayers 瓦片层与版权测试', () {
    test('tiles() 正确配置主瓦片源、镜像兜底源、预缓冲与最大原生缩放级别', () {
      final tileLayer = OsmMapLayers.tiles();

      expect(tileLayer.urlTemplate,
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      expect(tileLayer.fallbackUrl,
          'https://tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png');
      expect(tileLayer.panBuffer, equals(1));
      expect(tileLayer.maxNativeZoom, equals(19));
      expect(tileLayer.tileProvider, isA<NetworkTileProvider>());
      expect(tileLayer.tileProvider.headers['User-Agent'],
          contains('com.shangjin.thoughtecho'));
    });

    testWidgets('attribution() 包含 OpenStreetMap contributors 版权标注',
        (WidgetTester tester) async {
      final widget = OsmMapLayers.attribution();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: widget,
          ),
        ),
      );

      expect(find.text('OpenStreetMap contributors'), findsOneWidget);
    });
  });
}
