import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/theme_style_labels.dart';
import 'package:thoughtecho/theme/theme_style.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

class MockAppLocalizations implements AppLocalizations {
  @override
  String get themeStyleMaterial => 'Material';
  @override
  String get themeStyleMaterialDesc => 'Material Desc';
  @override
  String get themeStylePaper => 'Paper';
  @override
  String get themeStylePaperDesc => 'Paper Desc';
  @override
  String get themeStylePlain => 'Plain';
  @override
  String get themeStylePlainDesc => 'Plain Desc';

  // ignore: noSuchMethod
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('themeStyleLabel', () {
    test('returns correct label and description for ThemeStyle.material', () {
      final l10n = MockAppLocalizations();
      final result = themeStyleLabel(l10n, ThemeStyle.material);
      expect(result.$1, 'Material');
      expect(result.$2, 'Material Desc');
    });

    test('returns correct label and description for ThemeStyle.paper', () {
      final l10n = MockAppLocalizations();
      final result = themeStyleLabel(l10n, ThemeStyle.paper);
      expect(result.$1, 'Paper');
      expect(result.$2, 'Paper Desc');
    });

    test('returns correct label and description for ThemeStyle.plain', () {
      final l10n = MockAppLocalizations();
      final result = themeStyleLabel(l10n, ThemeStyle.plain);
      expect(result.$1, 'Plain');
      expect(result.$2, 'Plain Desc');
    });
  });
}
