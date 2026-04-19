import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/extensions/note_category_localization_extension.dart';
import 'package:thoughtecho/gen_l10n/app_localizations_en.dart';
import 'package:thoughtecho/models/note_category.dart';
import 'package:thoughtecho/services/database_service.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('NoteCategoryLocalizationExtension', () {
    test('localizes built-in non-deletable categories by fixed id', () {
      final quoteCategory = NoteCategory(
        id: DatabaseService.defaultCategoryIdHitokoto,
        name: '每日一言',
      );
      final animeCategory = NoteCategory(
        id: DatabaseService.defaultCategoryIdAnime,
        name: '动画',
      );
      final jokeCategory = NoteCategory(
        id: DatabaseService.defaultCategoryIdJoke,
        name: '抖机灵',
      );

      expect(quoteCategory.localizedName(l10n), 'Daily Quote');
      expect(animeCategory.localizedName(l10n), 'Anime');
      expect(jokeCategory.localizedName(l10n), 'Humor');
    });

    test('localizes hidden system tag', () {
      final hiddenTag = NoteCategory(
        id: DatabaseService.hiddenTagId,
        name: '隐藏',
      );

      expect(hiddenTag.localizedName(l10n), 'Hidden');
    });

    test('keeps custom tag name untouched', () {
      final customTag = NoteCategory(id: 'custom_tag', name: 'My Custom Tag');

      expect(customTag.localizedName(l10n), 'My Custom Tag');
    });
  });
}
