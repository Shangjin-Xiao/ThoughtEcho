import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/daily_prompt_generator.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/gen_l10n/app_localizations_zh.dart';

void main() {
  group('DailyPromptGenerator 单元测试', () {
    late AppLocalizations l10n;
    late List<String> allDefaultPrompts;

    setUp(() {
      l10n = AppLocalizationsZh();
      allDefaultPrompts = [
        l10n.promptDefault1,
        l10n.promptDefault2,
        l10n.promptDefault3,
        l10n.promptDefault4,
        l10n.promptDefault5,
        l10n.promptDefault6,
        l10n.promptDefault7,
        l10n.promptDefault8,
        l10n.promptDefault9,
        l10n.promptDefault10,
        l10n.promptDefault11,
        l10n.promptDefault12,
      ];
    });

    test('getDefaultPrompt 应该返回默认提示之一', () {
      final prompt = DailyPromptGenerator.getDefaultPrompt(l10n);
      expect(prompt, isNotEmpty);
      expect(allDefaultPrompts.contains(prompt), isTrue);
    });

    test('generatePromptBasedOnContext 在没有附加上下文时应该返回有效提示', () {
      final prompt = DailyPromptGenerator.generatePromptBasedOnContext(l10n);
      expect(prompt, isNotEmpty);
      expect(prompt, isA<String>());
    });

    test('generatePromptBasedOnContext 能够处理带天气和温度的组合', () {
      final prompt = DailyPromptGenerator.generatePromptBasedOnContext(l10n,
          weather: 'clear', temperature: '22°C');
      expect(prompt, isNotEmpty);
    });

    test('generatePromptBasedOnContext 城市上下文测试', () {
      final prompt = DailyPromptGenerator.generatePromptBasedOnContext(
        l10n,
        city: '北京',
      );
      expect(prompt, isNotEmpty);
    });

    test('generatePromptBasedOnContext 解析极端温度(热)', () {
      final prompt = DailyPromptGenerator.generatePromptBasedOnContext(
        l10n,
        temperature: '35°C', // 大于28
      );
      expect(prompt, isNotEmpty);
    });

    test('generatePromptBasedOnContext 解析极端温度(冷)', () {
      final prompt = DailyPromptGenerator.generatePromptBasedOnContext(
        l10n,
        temperature: '5°C', // 小于10
      );
      expect(prompt, isNotEmpty);
    });

    test('generatePromptBasedOnContext 处理非法温度格式不抛出异常', () {
      final prompt = DailyPromptGenerator.generatePromptBasedOnContext(
        l10n,
        temperature: '未知温度', // 内部catch忽略异常
      );
      expect(prompt, isNotEmpty);
    });

    test('generatePromptBasedOnContext 处理未知天气情况', () {
      final prompt = DailyPromptGenerator.generatePromptBasedOnContext(
        l10n,
        weather: 'alien_weather', // 未在天气key中映射
      );
      expect(prompt, isNotEmpty);
    });

    test('generatePromptBasedOnContext 当所有都为空时', () {
      final prompt = DailyPromptGenerator.generatePromptBasedOnContext(
        l10n,
        city: '',
        temperature: null,
        weather: null,
      );
      expect(prompt, isNotEmpty);
    });
  });
}
