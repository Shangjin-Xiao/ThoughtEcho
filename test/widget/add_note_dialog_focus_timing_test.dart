import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';

void main() {
  testWidgets('delays content focus until bottom sheet entrance settles',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<FeatureGuideService>(
        create: (_) => _MockFeatureGuideService(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => AddNoteDialog(
                      tags: const [],
                      onSave: (_) {},
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    final contentField = tester.widget<TextField>(find.byType(TextField).first);
    expect(contentField.focusNode?.hasFocus, isFalse);

    await tester.pumpAndSettle();

    expect(contentField.focusNode?.hasFocus, isTrue);

    await tester.pump(const Duration(seconds: 1));
  });
}

class _MockFeatureGuideService extends FeatureGuideService {
  _MockFeatureGuideService() : super(SafeMMKV());

  @override
  bool hasShown(String guideId) => true;

  @override
  Future<void> markAsShown(String guideId) async {}

  @override
  Future<void> resetGuide(String guideId) async {}

  @override
  Future<void> resetAllGuides() async {}
}
