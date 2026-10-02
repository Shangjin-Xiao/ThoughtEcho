import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/widgets/note_metadata_dialogs.dart';

import '../../test_harness.dart';
import 'geocoding_test_support.dart';

Widget _buildTestApp({
  required Widget Function(BuildContext) builder,
  Locale locale = const Locale('zh'),
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    home: Scaffold(
      body: Builder(builder: builder),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await TestHarness.initialize();
  });

  tearDownAll(() {
    UnifiedLogService.instance.dispose();
  });

  group('NoteMetadataDialogs.showLocationInfoDialog', () {
    testWidgets('无位置且无坐标时提示无法添加位置并点击我知道了关闭', (tester) async {
      NoteLocationDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showLocationInfoDialog(
                context: context,
                location: null,
                latitude: null,
                longitude: null,
                poiName: null,
                isSelected: false,
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('无法添加位置'), findsOneWidget);
      expect(find.text('我知道了'), findsOneWidget);

      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();

      expect(action, isNull);
    });

    testWidgets('有位置数据且包含 POI 时展示 POI 并可点击清除地点名称', (tester) async {
      NoteLocationDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showLocationInfoDialog(
                context: context,
                location: '中国,北京市',
                latitude: 39.9,
                longitude: 116.4,
                poiName: '故宫博物院',
                isSelected: true,
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('位置信息'), findsOneWidget);
      expect(find.textContaining('地点名称: 故宫博物院'), findsOneWidget);
      expect(find.text('清除 地点名称'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);

      await tester.tap(find.text('清除 地点名称'));
      await tester.pumpAndSettle();

      expect(action, NoteLocationDialogAction.clearPoi);
    });

    testWidgets('有位置数据时点击移除返回 NoteLocationDialogAction.remove', (tester) async {
      NoteLocationDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showLocationInfoDialog(
                context: context,
                location: '中国,北京市,东城区',
                latitude: 39.9,
                longitude: 116.4,
                poiName: null,
                isSelected: true,
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('位置信息'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);

      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();

      expect(action, NoteLocationDialogAction.remove);
    });

    testWidgets('仅有坐标时展示更新位置按钮并点击返回 NoteLocationDialogAction.updateLocation', (
      tester,
    ) async {
      NoteLocationDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showLocationInfoDialog(
                context: context,
                location: null,
                latitude: 39.9,
                longitude: 116.4,
                poiName: null,
                isSelected: false,
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('更新位置'), findsOneWidget);

      await tester.tap(find.text('更新位置'));
      await tester.pumpAndSettle();

      expect(action, NoteLocationDialogAction.updateLocation);
    });

    testWidgets('点击取消按钮返回 null', (tester) async {
      NoteLocationDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showLocationInfoDialog(
                context: context,
                location: '中国,北京市',
                latitude: 39.9,
                longitude: 116.4,
                poiName: null,
                isSelected: true,
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(action, isNull);
    });
  });

  group('NoteMetadataDialogs.showWeatherInfoDialog', () {
    testWidgets('无天气数据时提示无法添加天气并点击我知道了关闭', (tester) async {
      NoteWeatherDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showWeatherInfoDialog(
                context: context,
                weather: null,
                temperature: null,
                isSelected: false,
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('无法添加天气'), findsOneWidget);
      expect(find.text('我知道了'), findsOneWidget);

      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();

      expect(action, isNull);
    });

    testWidgets('有天气数据时展示天气与温度，点击移除返回 NoteWeatherDialogAction.remove', (
      tester,
    ) async {
      NoteWeatherDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showWeatherInfoDialog(
                context: context,
                weather: 'clear',
                temperature: '25°C',
                isSelected: true,
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('天气信息'), findsOneWidget);
      expect(find.textContaining('晴 25°C'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);

      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();

      expect(action, NoteWeatherDialogAction.remove);
    });

    testWidgets('有天气数据但未被选中时不展示移除按钮，点击取消返回 null', (tester) async {
      NoteWeatherDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showWeatherInfoDialog(
                context: context,
                weather: 'clear',
                temperature: '25°C',
                isSelected: false,
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('天气信息'), findsOneWidget);
      expect(find.text('移除'), findsNothing);
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(action, isNull);
    });
  });

  group('NoteMetadataDialogs.updateAddressFromCoordinates', () {
    testWidgets('反查地址成功时展示位置已更新提示并返回格式化地址', (tester) async {
      final mockPlatform = AdminMockGeocodingPlatform();
      final prevPlatform = installAdminMockPlatform(mockPlatform);
      addTearDown(() => restoreAdminMockPlatform(prevPlatform));

      String? updatedAddress;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              updatedAddress =
                  await NoteMetadataDialogs.updateAddressFromCoordinates(
                context: context,
                latitude: 39.9042,
                longitude: 116.4074,
              );
            },
            child: const Text('update'),
          ),
        ),
      );

      await tester.tap(find.text('update'));
      await tester.pumpAndSettle();

      expect(updatedAddress, '中国,北京市,北京市,西城区');
      expect(find.textContaining('位置已更新为'), findsOneWidget);
      expect(mockPlatform.placemarkCalls, 1);
    });
  });
}
