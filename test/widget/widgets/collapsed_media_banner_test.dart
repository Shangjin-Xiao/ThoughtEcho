import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/utils/delta_media_extractor.dart';
import 'package:thoughtecho/widgets/note_list/collapsed_media_banner.dart';

DeltaMediaSummary _mediaWithImage() {
  return parseDeltaMedia(jsonEncode([
    {
      'insert': {
        'image':
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      },
    },
    {'insert': '\n'},
  ]));
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('包含 RepaintBoundary 包裹 ClipRRect 且点击事件正常响应', (tester) async {
    var tapped = false;
    final media = _mediaWithImage();

    await tester.pumpWidget(
      _wrap(
        CollapsedMediaBanner(
          media: media,
          onTap: () => tapped = true,
        ),
      ),
    );
    await tester.pump();

    final clipFinder = find.descendant(
      of: find.byType(CollapsedMediaBanner),
      matching: find.byType(ClipRRect),
    );
    expect(clipFinder, findsOneWidget);

    expect(
      find.descendant(
        of: find.byType(CollapsedMediaBanner),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(CollapsedMediaBanner));
    expect(tapped, isTrue);
  });

  testWidgets('多图折叠徽标使用 onInverseSurface / inverseSurface 语义令牌',
      (tester) async {
    final media = parseDeltaMedia(jsonEncode([
      {
        'insert': {
          'image':
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
        },
      },
      {'insert': '\n'},
      {
        'insert': {
          'image':
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
        },
      },
      {'insert': '\n'},
      {
        'insert': {
          'image':
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
        },
      },
      {'insert': '\n'},
      {
        'insert': {
          'image':
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
        },
      },
      {'insert': '\n'},
    ]));
    await tester.pumpWidget(
      _wrap(
        CollapsedMediaBanner(
          media: media,
        ),
      ),
    );
    await tester.pump();

    final textWidget = tester.widget<Text>(find.text('+3'));
    final context = tester.element(find.text('+3'));
    final theme = Theme.of(context);
    expect(textWidget.style?.color, equals(theme.colorScheme.onInverseSurface));
  });
}
