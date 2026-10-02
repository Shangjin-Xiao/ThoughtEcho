import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/location_service.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/widgets/note_metadata_dialogs.dart';

import '../../test_harness.dart';

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

    testWidgets('有位置数据且包含 POI 时展示 POI 并可点击清除地点名称（文案中不重复 POI）', (
      tester,
    ) async {
      NoteLocationDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showLocationInfoDialog(
                context: context,
                location: '中国,北京市,北京市,东城区',
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
      // 当前位置只展示行政区，不重复出现"故宫博物院"
      expect(find.textContaining('当前位置：北京市·东城区'), findsOneWidget);
      expect(find.text('清除 地点名称'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);

      // 全文匹配"故宫博物院"只应出现一次（在地点名称标签中）
      final dialogTextWidgets = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join('\n');
      final occurrences = '故宫博物院'.allMatches(dialogTextWidgets).length;
      expect(occurrences, 1);

      await tester.tap(find.text('清除 地点名称'));
      await tester.pumpAndSettle();

      expect(action, NoteLocationDialogAction.clearPoi);
    });

    testWidgets('当 location 仅为非展示标记（如 pending 标记）但有坐标时识别为仅坐标并提供更新位置选项', (
      tester,
    ) async {
      NoteLocationDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showLocationInfoDialog(
                context: context,
                location: LocationService.kAddressPending,
                latitude: 39.9042,
                longitude: 116.4074,
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

      expect(find.text('更新位置'), findsOneWidget);

      await tester.tap(find.text('更新位置'));
      await tester.pumpAndSettle();

      expect(action, NoteLocationDialogAction.updateLocation);
    });

    testWidgets('有位置数据时点击移除返回 NoteLocationDialogAction.remove', (tester) async {
      NoteLocationDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showLocationInfoDialog(
                context: context,
                location: '中国,北京市,北京市,东城区',
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

    testWidgets('空字符串天气且被勾选时仍提供移除按钮', (tester) async {
      NoteWeatherDialogAction? action;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              action = await NoteMetadataDialogs.showWeatherInfoDialog(
                context: context,
                weather: '',
                temperature: null,
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
      expect(find.text('移除'), findsOneWidget);

      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();

      expect(action, NoteWeatherDialogAction.remove);
    });
  });

  group('NoteMetadataDialogs.updateAddressFromCoordinates', () {
    testWidgets('反查地址成功时展示成功 SnackBar 并返回格式化地址', (tester) async {
      String? updatedAddress;
      int fetcherCalls = 0;
      double? capturedLat;
      double? capturedLon;
      String? capturedLocale;

      await tester.pumpWidget(
        _buildTestApp(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              updatedAddress =
                  await NoteMetadataDialogs.updateAddressFromCoordinates(
                context: context,
                latitude: 39.9042,
                longitude: 116.4074,
                addressFetcher: (lat, lon, locale) async {
                  fetcherCalls++;
                  capturedLat = lat;
                  capturedLon = lon;
                  capturedLocale = locale;
                  return {
                    'country': '中国',
                    'province': '北京市',
                    'city': '北京市',
                    'district': '西城区',
                    'formatted_address': '北京市西城区',
                  };
                },
              );
            },
            child: const Text('update'),
          ),
        ),
      );

      await tester.tap(find.text('update'));
      await tester.pumpAndSettle();

      expect(fetcherCalls, equals(1));
      expect(capturedLat, equals(39.9042));
      expect(capturedLon, equals(116.4074));
      expect(capturedLocale, isNotNull);
      expect(updatedAddress, '中国,北京市,北京市,西城区');
      expect(find.textContaining('位置已更新为'), findsOneWidget);
    });

    testWidgets('反查地址返回 null 且 useDialogOnFailure 为 false 时通过 SnackBar 提示', (
      tester,
    ) async {
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
                useDialogOnFailure: false,
                addressFetcher: (lat, lon, locale) async => null,
              );
            },
            child: const Text('update'),
          ),
        ),
      );

      await tester.tap(find.text('update'));
      await tester.pumpAndSettle();

      expect(updatedAddress, isNull);
      expect(find.text('无法获取地址，请检查网络'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('反查地址返回 null 且 useDialogOnFailure 为 true 时弹出 AlertDialog 错误弹窗',
        (
      tester,
    ) async {
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
                useDialogOnFailure: true,
                addressFetcher: (lat, lon, locale) async => null,
              );
            },
            child: const Text('update'),
          ),
        ),
      );

      await tester.tap(find.text('update'));
      await tester.pumpAndSettle();

      expect(updatedAddress, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('无法获取位置'), findsOneWidget);
      expect(find.text('无法获取地址，请检查网络'), findsOneWidget);

      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('反查地址返回缺失省市数据（buildStorageLocation 为 null）时给出错误提示', (
      tester,
    ) async {
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
                useDialogOnFailure: false,
                addressFetcher: (lat, lon, locale) async => {
                  'country': '中国',
                  'province': null,
                  'city': null,
                  'district': null,
                },
              );
            },
            child: const Text('update'),
          ),
        ),
      );

      await tester.tap(find.text('update'));
      await tester.pumpAndSettle();

      expect(updatedAddress, isNull);
      expect(find.text('无法获取地址，请检查网络'), findsOneWidget);
    });

    testWidgets('反查地址抛出异常时展示更新失败提示并返回 null', (tester) async {
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
                useDialogOnFailure: false,
                addressFetcher: (lat, lon, locale) async {
                  throw Exception('Network disconnected');
                },
              );
            },
            child: const Text('update'),
          ),
        ),
      );

      await tester.tap(find.text('update'));
      await tester.pumpAndSettle();

      expect(updatedAddress, isNull);
      expect(find.textContaining('更新失败'), findsOneWidget);
    });
  });
}
