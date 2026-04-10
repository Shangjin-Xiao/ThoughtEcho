import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/services/api_service.dart';
import 'package:thoughtecho/utils/http_response.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiService provider defaults', () {
    test('prefers locale-native providers before falling back to zenquotes',
        () {
      expect(
        ApiService.recommendedDailyQuoteProviderForLanguage('zh'),
        ApiService.hitokotoProvider,
      );
      expect(
        ApiService.recommendedDailyQuoteProviderForLanguage('ja'),
        ApiService.meigenProvider,
      );
      expect(
        ApiService.recommendedDailyQuoteProviderForLanguage('ko'),
        ApiService.koreanAdviceProvider,
      );
      expect(
        ApiService.recommendedDailyQuoteProviderForLanguage('en'),
        ApiService.zenQuotesProvider,
      );
      expect(
        ApiService.recommendedDailyQuoteProviderForLanguage('fr'),
        ApiService.zenQuotesProvider,
      );
    });
  });

  group('ApiService local-only fallback logic', () {
    test('useLocalOnly + tagOnly 在没有本地内容时返回历史每日一言空状态', () async {
      final l10n = lookupAppLocalizations(const Locale('zh'));

      final result = await ApiService.getDailyQuote(
        l10n,
        'a',
        useLocalOnly: true,
        offlineQuoteSource: 'tagOnly',
        databaseService: null,
      );

      expect(result['content'], l10n.noLocalSavedQuotes);
      expect(result['type'], 'local-empty');
    });

    test('useLocalOnly + allNotes 在没有本地内容时仍可使用默认一言', () async {
      final l10n = lookupAppLocalizations(const Locale('zh'));

      final result = await ApiService.getDailyQuote(
        l10n,
        'a',
        useLocalOnly: true,
        offlineQuoteSource: 'allNotes',
        databaseService: null,
      );

      final defaultQuotes = [
        l10n.defaultQuote1,
        l10n.defaultQuote2,
        l10n.defaultQuote3,
      ];

      expect(defaultQuotes.contains(result['content']), isTrue);
    });

    test('hitokoto provider keeps current normalization contract', () async {
      final l10n = lookupAppLocalizations(const Locale('zh'));

      final result = await ApiService.getDailyQuote(
        l10n,
        'a,b',
        provider: 'hitokoto',
        httpGet: (
          url, {
          Map<String, String>? headers,
          int? timeoutSeconds,
        }) async {
          expect(url, 'https://v1.hitokoto.cn/?c=a&c=b');
          return HttpResponse(
            '{"hitokoto":"测试句子","from":"测试出处","from_who":"测试作者","type":"b"}',
            200,
          );
        },
      );

      expect(result['content'], '测试句子');
      expect(result['from'], '测试出处');
      expect(result['from_who'], '测试作者');
      expect(result['type'], 'b');
      expect(result['provider'], 'hitokoto');
    });

    test('zenquotes provider returns normalized quote fields', () async {
      final l10n = lookupAppLocalizations(const Locale('zh'));

      final result = await ApiService.getDailyQuote(
        l10n,
        'k',
        provider: 'zenquotes',
        httpGet: (
          url, {
          Map<String, String>? headers,
          int? timeoutSeconds,
        }) async {
          expect(url, 'https://zenquotes.io/api/random');
          return HttpResponse(
            '[{"q":"Stay hungry","a":"Steve Jobs"}]',
            200,
          );
        },
      );

      expect(result['content'], 'Stay hungry');
      expect(result['author'], 'Steve Jobs');
      expect(result['from_who'], 'Steve Jobs');
      expect(result['from'], '');
      expect(result['type'], 'k');
      expect(result['provider'], 'zenquotes');
    });

    test('api_ninjas provider sends API key and category filters', () async {
      final l10n = lookupAppLocalizations(const Locale('zh'));

      final result = await ApiService.getDailyQuote(
        l10n,
        'k',
        provider: 'api_ninjas',
        apiNinjasCategories: const ['wisdom', 'success'],
        apiKeyResolver: (providerId) async {
          expect(providerId, 'api_ninjas');
          return 'secret-key';
        },
        httpGet: (
          url, {
          Map<String, String>? headers,
          int? timeoutSeconds,
        }) async {
          expect(
            url,
            'https://api.api-ninjas.com/v2/randomquotes?categories=wisdom,success',
          );
          expect(headers, {'X-Api-Key': 'secret-key'});
          return HttpResponse(
            '[{"quote":"Knowledge speaks","author":"Socrates","work":"Dialogues","categories":["wisdom"]}]',
            200,
          );
        },
      );

      expect(result['content'], 'Knowledge speaks');
      expect(result['author'], 'Socrates');
      expect(result['from'], 'Dialogues');
      expect(result['type'], 'k');
      expect(result['provider'], 'api_ninjas');
    });
  });
}
