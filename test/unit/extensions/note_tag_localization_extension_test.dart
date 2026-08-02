import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/extensions/note_tag_localization_extension.dart';
import 'package:thoughtecho/gen_l10n/app_localizations_en.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/services/database_service.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('NoteTagLocalizationExtension', () {
    test('localizes built-in non-deletable categories by fixed id', () {
      final quoteCategory = NoteTag(
        id: DatabaseService.defaultTagIdHitokoto,
        name: '每日一言',
      );
      final animeCategory = NoteTag(
        id: DatabaseService.defaultTagIdAnime,
        name: '动画',
      );
      final jokeCategory = NoteTag(
        id: DatabaseService.defaultTagIdJoke,
        name: '抖机灵',
      );

      expect(quoteCategory.localizedName(l10n), 'Daily Quote');
      expect(animeCategory.localizedName(l10n), 'Anime');
      expect(jokeCategory.localizedName(l10n), 'Humor');
    });

    test('localizes hidden system tag', () {
      final hiddenTag = NoteTag(
        id: DatabaseService.hiddenTagId,
        name: '隐藏',
      );

      expect(hiddenTag.localizedName(l10n), 'Hidden');
    });

    test('keeps custom tag name untouched', () {
      final customTag = NoteTag(id: 'custom_tag', name: 'My Custom Tag');

      expect(customTag.localizedName(l10n), 'My Custom Tag');
    });
  });
}
