import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/widgets/map/osm_map_layers.dart';

import '../../../test_harness.dart';

void main() {
  setUpAll(() async {
    await TestHarness.initialize();
  });

  tearDownAll(() async {
    await TestHarness.tearDown();
  });

  group('OsmMapLayers 瓦片层与版权测试', () {
    testWidgets(
        'tiles(context) 浅色模式下不配置 tileBuilder，暗色模式下挂载 darkModeTileBuilder 色阵滤镜',
        (WidgetTester tester) async {
      late TileLayer lightTileLayer;
      late TileLayer darkTileLayer;

      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: ThemeData(brightness: Brightness.light),
            child: Builder(
              builder: (context) {
                lightTileLayer = OsmMapLayers.tiles(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(lightTileLayer.urlTemplate,
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
      expect(lightTileLayer.fallbackUrl,
          'https://tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png');
      expect(lightTileLayer.panBuffer, equals(2));
      expect(lightTileLayer.maxNativeZoom, equals(19));
      expect(lightTileLayer.tileProvider, isA<NetworkTileProvider>());
      expect(lightTileLayer.tileProvider.headers['User-Agent'],
          contains('com.shangjin.thoughtecho'));
      expect(lightTileLayer.tileBuilder, isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: ThemeData(brightness: Brightness.dark),
            child: Builder(
              builder: (context) {
                darkTileLayer = OsmMapLayers.tiles(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(darkTileLayer.tileBuilder, equals(darkModeTileBuilder));
    });

    testWidgets(
        'attribution(context) 包含 OpenStreetMap contributors 与 OSM France 版权标注，并应用主题对应的背景颜色与文字样式',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final lightTheme = ThemeData.light();
      final darkTheme = ThemeData.dark();

      // 1. 验证浅色主题下的背景色与文字颜色
      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: lightTheme,
            child: Scaffold(
              body: Builder(
                builder: (context) => OsmMapLayers.attribution(context),
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
      expect(find.textContaining('OSM France'), findsOneWidget);

      final lightAttributionWidget = tester.widget<SimpleAttributionWidget>(
          find.byType(SimpleAttributionWidget));
      expect(
        lightAttributionWidget.backgroundColor,
        equals(lightTheme.colorScheme.surface.withValues(alpha: 0.8)),
      );

      final lightText = tester
          .widget<Text>(find.textContaining('OpenStreetMap contributors'));
      expect(
        lightText.style?.color,
        equals(lightTheme.colorScheme.onSurface),
      );

      // 2. 验证暗色主题下的背景色与文字颜色
      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: darkTheme,
            child: Scaffold(
              body: Builder(
                builder: (context) => OsmMapLayers.attribution(context),
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
      expect(find.textContaining('OSM France'), findsOneWidget);

      final darkAttributionWidget = tester.widget<SimpleAttributionWidget>(
          find.byType(SimpleAttributionWidget));
      expect(
        darkAttributionWidget.backgroundColor,
        equals(darkTheme.colorScheme.surface.withValues(alpha: 0.8)),
      );

      final darkText = tester
          .widget<Text>(find.textContaining('OpenStreetMap contributors'));
      expect(
        darkText.style?.color,
        equals(darkTheme.colorScheme.onSurface),
      );
    });
  });
}
