import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets(
    'UnifiedQuillToolbar is wrapped with an independent RepaintBoundary',
    (tester) async {
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

      final toolbarBoundaryFinder = find.descendant(
        of: find.byType(UnifiedQuillToolbar),
        matching: find.byType(RepaintBoundary),
      );
      expect(toolbarBoundaryFinder, findsOneWidget);

      final renderBoundary =
          tester.renderObject<RenderRepaintBoundary>(toolbarBoundaryFinder);
      expect(renderBoundary.isRepaintBoundary, isTrue);
    },
  );

  testWidgets(
    'editing text and cursor blink do not mark toolbar RenderRepaintBoundary dirty',
    (tester) async {
      final controller = QuillController.basic();
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                UnifiedQuillToolbar(controller: controller),
                Expanded(
                  child: RepaintBoundary(
                    child: QuillEditor(
                      controller: controller,
                      scrollController: scrollController,
                      focusNode: focusNode,
                      config: const QuillEditorConfig(
                        autoFocus: true,
                        showCursor: true,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final toolbarBoundaryFinder = find.descendant(
        of: find.byType(UnifiedQuillToolbar),
        matching: find.byType(RepaintBoundary),
      );
      final toolbarRenderObject =
          tester.renderObject<RenderRepaintBoundary>(toolbarBoundaryFinder);

      expect(toolbarRenderObject.isRepaintBoundary, isTrue);
      expect(toolbarRenderObject.debugNeedsPaint, isFalse);

      // Trigger text modification in the editor
      controller.document.insert(0, 'Hello ThoughtEcho');
      expect(toolbarRenderObject.debugNeedsPaint, isFalse);

      await tester.pump();
      expect(toolbarRenderObject.debugNeedsPaint, isFalse);

      // Trigger selection / cursor movement
      controller.updateSelection(
        const TextSelection.collapsed(offset: 5),
        ChangeSource.local,
      );
      expect(toolbarRenderObject.debugNeedsPaint, isFalse);

      await tester.pump();
      expect(toolbarRenderObject.debugNeedsPaint, isFalse);

      // Trigger cursor blinking animation cycles
      await tester.pump(const Duration(milliseconds: 500));
      expect(toolbarRenderObject.debugNeedsPaint, isFalse);

      await tester.pump(const Duration(milliseconds: 500));
      expect(toolbarRenderObject.debugNeedsPaint, isFalse);
    },
  );
}
