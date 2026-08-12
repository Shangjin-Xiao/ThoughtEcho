import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/widgets/chat_input_suggestions.dart';

void main() {
  final l10nEn = lookupAppLocalizations(const Locale('en'));
  final l10nZh = lookupAppLocalizations(const Locale('zh'));

  group('ChatInputSuggestions.generateSuggestions', () {
    test('中文关键词触发对应建议', () {
      final suggestions =
          ChatInputSuggestions.generateSuggestions(l10nZh, '遇到了一个问题');

      expect(suggestions, contains(l10nZh.aiSuggestionSolution));
    });

    test('英文关键词触发对应建议（英文界面）', () {
      final suggestions =
          ChatInputSuggestions.generateSuggestions(l10nEn, 'I have a problem');

      expect(suggestions, contains(l10nEn.aiSuggestionSolution));
    });

    test('英文关键词在中文界面同样触发建议', () {
      final suggestions =
          ChatInputSuggestions.generateSuggestions(l10nZh, 'I have a problem');

      expect(suggestions, contains(l10nZh.aiSuggestionSolution));
    });

    test('关键词匹配不区分大小写', () {
      final suggestions = ChatInputSuggestions.generateSuggestions(
          l10nEn, 'How to LEARN faster');

      expect(suggestions, contains(l10nEn.aiSuggestionUnderstandConcept));
    });

    test('plan 与 emotion 关键词触发行动计划与心理分析建议', () {
      final suggestions = ChatInputSuggestions.generateSuggestions(
        l10nEn,
        'my plan and emotion journal',
      );

      expect(suggestions, contains(l10nEn.aiSuggestionActionPlan));
      expect(suggestions, contains(l10nEn.aiSuggestionPsychology));
    });

    test('无关键词时只返回基础与通用建议', () {
      final suggestions =
          ChatInputSuggestions.generateSuggestions(l10nEn, 'hi');

      expect(suggestions, contains(l10nEn.aiSuggestionCoreIdea));
      expect(suggestions, contains(l10nEn.aiSuggestionInspiration));
      expect(suggestions, contains(l10nEn.aiSuggestionRealLife));
      expect(suggestions, contains(l10nEn.aiSuggestionThinkingPattern));
      expect(suggestions, isNot(contains(l10nEn.aiSuggestionSolution)));
      expect(suggestions, isNot(contains(l10nEn.aiSuggestionPsychology)));
    });
  });
}
