import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/quill_enhanced_toolbar_unified.dart';
import 'package:thoughtecho/widgets/unified_media_import_dialog.dart';

void main() {
  testWidgets('media import dialog cannot be dismissed through the barrier', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = QuillController.basic();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UnifiedQuillToolbar(controller: controller),
        ),
      ),
    );

    final insertImageButton = find.byTooltip('Insert Image');
    await tester.ensureVisible(insertImageButton);
    await tester.tap(insertImageButton);
    await tester.pumpAndSettle();
    expect(find.byType(UnifiedMediaImportDialog), findsOneWidget);

    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(find.byType(UnifiedMediaImportDialog), findsOneWidget);
  });
}
