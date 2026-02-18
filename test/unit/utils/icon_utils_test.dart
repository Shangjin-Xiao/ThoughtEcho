import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/icon_utils.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/gen_l10n/app_localizations_en.dart';

void main() {
  group('IconUtils', () {
    late AppLocalizations localizations;

    setUp(() {
      localizations = AppLocalizationsEn();
    });

    test('isEmoji returns correct boolean', () {
      expect(IconUtils.isEmoji('😊'), isTrue);
      expect(IconUtils.isEmoji('home'), isFalse);
      expect(IconUtils.isEmoji(null), isFalse);
      expect(IconUtils.isEmoji(''), isFalse);
      // 'lock' is in categoryIcons, so it should not be considered an emoji by isEmoji logic
      expect(IconUtils.isEmoji('lock'), isFalse);
    });

    test('getIconData returns correct IconData or default', () {
      expect(IconUtils.getIconData('home'), Icons.home);
      expect(IconUtils.getIconData('non_existent'), Icons.label);
      expect(IconUtils.getIconData(null), Icons.label);
      expect(IconUtils.getIconData(''), Icons.label);
      expect(IconUtils.getIconData('😊'), Icons.emoji_emotions);
    });

    test('getDisplayIcon returns correct icon or string', () {
      expect(IconUtils.getDisplayIcon('home'), Icons.home);
      expect(IconUtils.getDisplayIcon('😊'), '😊');
      expect(IconUtils.getDisplayIcon(null), Icons.label);
      expect(IconUtils.getDisplayIcon('non_existent'), Icons.label);
    });

    test('getIcon returns correct Widget', () {
      // Test Material Icon
      Widget iconWidget = IconUtils.getIcon('home');
      expect(iconWidget, isA<Icon>());
      expect((iconWidget as Icon).icon, Icons.home);

      // Test Emoji
      Widget emojiWidget = IconUtils.getIcon('😊');
      expect(emojiWidget, isA<Text>());
      expect((emojiWidget as Text).data, '😊');

      // Test Emoji not in list but looks like emoji (default logic check)
      // Actually getIcon checks categoryIcons then emojiCategories.values.
      // If not found in either, it returns default Icon.
      // Let's check an emoji not in the categories.
      Widget unknownEmojiWidget = IconUtils.getIcon('👽');
      expect(unknownEmojiWidget, isA<Icon>());
      expect((unknownEmojiWidget as Icon).icon, Icons.label);
    });

    test('getAllIcons returns list containing expected icons', () {
      final allIcons = IconUtils.getAllIcons();
      expect(allIcons, isNotEmpty);
      expect(allIcons.any((entry) => entry.key == 'home'), isTrue);
      expect(allIcons.any((entry) => entry.key == '😊'), isTrue);
    });

    test('getCategorizedEmojis returns map of categories', () {
      final categories = IconUtils.getCategorizedEmojis();
      expect(categories, isNotEmpty);
      expect(categories.containsKey('情感'), isTrue);
      expect(categories['情感'], contains('😊'));
    });

    test('getCategoryIcon returns correct Widget', () {
      expect(IconUtils.getCategoryIcon('home'), isA<Icon>());
      expect((IconUtils.getCategoryIcon('home') as Icon).icon, Icons.home);

      expect(IconUtils.getCategoryIcon('😊'), isA<Text>());
      expect((IconUtils.getCategoryIcon('😊') as Text).data, '😊');

      expect(IconUtils.getCategoryIcon(null), isA<Icon>());
      expect((IconUtils.getCategoryIcon(null) as Icon).icon, Icons.label);
    });

    test('getLocalizedCategoryName returns localized string', () {
      expect(IconUtils.getLocalizedCategoryName('情感', localizations), 'Emotion');
      expect(IconUtils.getLocalizedCategoryName('思考', localizations), 'Thinking');
      expect(IconUtils.getLocalizedCategoryName('Unknown', localizations), 'Unknown');
    });

    test('getLocalizedEmojiCategories returns localized map', () {
      final localizedCategories = IconUtils.getLocalizedEmojiCategories(localizations);
      expect(localizedCategories.containsKey('Emotion'), isTrue);
      expect(localizedCategories['Emotion'], contains('😊'));
      expect(localizedCategories.containsKey('Thinking'), isTrue);
    });
  });
}
