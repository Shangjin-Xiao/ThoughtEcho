import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/streaming_text_dialog.dart';

void main() {
  group('StreamingTextDialog', () {
    testWidgets(
      'uses display transformer for preview but applies raw text',
      (tester) async {
        final controller = StreamController<String>();
        String? appliedText;

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StreamingTextDialog(
                title: 'Polish',
                textStream: controller.stream,
                applyButtonText: '应用',
                displayTextTransformer: (rawText) =>
                    rawText.replaceAll('[[TE_MEDIA_1]]', ''),
                onApply: (text) {
                  appliedText = text;
                },
                onCancel: () {},
              ),
            ),
          ),
        );

        controller.add('Hello [[TE_MEDIA_1]] world');
        await controller.close();

        await tester.pumpAndSettle();

        expect(find.textContaining('[[TE_MEDIA_1]]'), findsNothing);
        expect(find.textContaining('Hello  world'), findsOneWidget);

        await tester.tap(find.text('应用'));
        await tester.pump();

        expect(appliedText, 'Hello [[TE_MEDIA_1]] world');
      },
    );
  });
}
