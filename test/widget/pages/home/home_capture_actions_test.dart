import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/local_ai_settings.dart';
import 'package:thoughtecho/pages/home/home_capture_actions.dart';
import 'package:thoughtecho/services/settings_service.dart';
import 'package:thoughtecho/widgets/local_ai/voice_input_overlay.dart';

class _SettingsService extends ChangeNotifier implements SettingsService {
  _SettingsService(this.localAISettings);

  @override
  final LocalAISettings localAISettings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('startVoiceCapture opens the capture overlay when enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: _SettingsService(
          const LocalAISettings(enabled: true, speechToTextEnabled: true),
        ),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final actions = HomeCaptureActions(
                  context: context,
                  isMounted: () => true,
                  onInsertText: (_) {},
                );
                return ElevatedButton(
                  onPressed: actions.startVoiceCapture,
                  child: const Text('capture'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('capture'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(VoiceInputOverlay), findsOneWidget);
  });
}
