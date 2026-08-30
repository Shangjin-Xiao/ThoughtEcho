import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/quote_model.dart';

void main() {
  group('Quote attribution classification & identity heuristics', () {
    Quote createNote({
      String? author,
      String? work,
      String? source,
      String content = '这是一段笔记内容',
    }) =>
        Quote(
          content: content,
          date: '2026-08-30T10:00:00Z',
          sourceAuthor: author,
          sourceWork: work,
          source: source,
        );

    group('hasAttribution', () {
      test('returns false when no attribution fields are present', () {
        final note = createNote();
        expect(note.hasAttribution, isFalse);
      });

      test('returns false when attribution fields are only whitespace', () {
        final note = createNote(author: '   ', work: '\t', source: '\n');
        expect(note.hasAttribution, isFalse);
      });

      test('returns true when any attribution field is populated', () {
        expect(createNote(author: '作者').hasAttribution, isTrue);
        expect(createNote(work: '作品').hasAttribution, isTrue);
        expect(createNote(source: '来源').hasAttribution, isTrue);
      });
    });

    group('isSelfAuthor', () {
      test('identifies built-in Chinese self-referential words', () {
        const selfWords = ['我', '自己', '本人', '自作', '自撰', '原创', '自述', '笔者', '作者'];
        for (final word in selfWords) {
          expect(Quote.isSelfAuthor(word), isTrue, reason: word);
          expect(Quote.isSelfAuthor('  $word  '), isTrue, reason: word);
          expect(Quote.isSelfAuthor('作者：$word'), isTrue, reason: word);
          expect(Quote.isSelfAuthor('——$word'), isTrue, reason: word);
        }
      });

      test(
          'identifies built-in English self-referential words case-insensitively',
          () {
        const selfWords = ['me', 'myself', 'i', 'self', 'author', 'original'];
        for (final word in selfWords) {
          expect(Quote.isSelfAuthor(word), isTrue, reason: word);
          expect(Quote.isSelfAuthor(word.toUpperCase()), isTrue, reason: word);
          expect(Quote.isSelfAuthor('by $word'), isTrue, reason: word);
          expect(Quote.isSelfAuthor('Author: $word'), isTrue, reason: word);
        }
      });

      test('identifies userNickname', () {
        expect(Quote.isSelfAuthor('上晋', userNickname: '上晋'), isTrue);
        expect(Quote.isSelfAuthor('上晋', userNickname: '  上晋  '), isTrue);
        expect(Quote.isSelfAuthor('Alice', userNickname: 'alice'), isTrue);
        expect(Quote.isSelfAuthor('鲁迅', userNickname: '上晋'), isFalse);
      });

      test('identifies defaultAuthor', () {
        expect(Quote.isSelfAuthor('上晋', defaultAuthor: '上晋'), isTrue);
        expect(Quote.isSelfAuthor('Bob', defaultAuthor: 'bob'), isTrue);
        expect(Quote.isSelfAuthor('苏轼', defaultAuthor: '上晋'), isFalse);
      });

      test('identifies custom userAliases', () {
        expect(
          Quote.isSelfAuthor('小明', userAliases: ['上晋', '小明', 'Echo']),
          isTrue,
        );
        expect(
          Quote.isSelfAuthor('未知作者', userAliases: ['上晋', '小明']),
          isFalse,
        );
      });

      test('returns false for null or empty input', () {
        expect(Quote.isSelfAuthor(null), isFalse);
        expect(Quote.isSelfAuthor(''), isFalse);
        expect(Quote.isSelfAuthor('   '), isFalse);
      });
    });

    group('isSelfAttributed, isExcerpt, isOriginal & resolveAttributionKind',
        () {
      test('unannotated note is classified as original', () {
        final note = createNote();
        expect(note.isSelfAttributed(), isFalse);
        expect(note.isExcerpt(), isFalse);
        expect(note.isOriginal(), isTrue);
        expect(note.attributionKind, 'original');
      });

      test('self-signed note with built-in keyword is original', () {
        final note = createNote(author: '我');
        expect(note.isSelfAttributed(), isTrue);
        expect(note.isExcerpt(), isFalse);
        expect(note.isOriginal(), isTrue);
        expect(note.attributionKind, 'original');
      });

      test('self-signed note with author and personal work is original', () {
        final note = createNote(author: '我', work: '随笔集');
        expect(note.isSelfAttributed(), isTrue);
        expect(note.isExcerpt(), isFalse);
        expect(note.isOriginal(), isTrue);
        expect(note.attributionKind, 'original');
      });

      test('self-signed note with userNickname is original', () {
        final note = createNote(author: 'Shangjin');
        expect(
          note.resolveAttributionKind(userNickname: 'shangjin'),
          'original',
        );
        expect(note.isExcerpt(userNickname: 'shangjin'), isFalse);
        expect(note.isOriginal(userNickname: 'shangjin'), isTrue);
      });

      test('self-signed note with defaultAuthor is original', () {
        final note = createNote(author: '上晋');
        expect(
          note.resolveAttributionKind(defaultAuthor: '上晋'),
          'original',
        );
        expect(note.isExcerpt(defaultAuthor: '上晋'), isFalse);
        expect(note.isOriginal(defaultAuthor: '上晋'), isTrue);
      });

      test('note with personal journal keyword in sourceWork is original', () {
        for (final keyword in ['日记', '随笔', '随手记', '我的日记', 'Diary', 'Journal']) {
          final note = createNote(work: keyword);
          expect(note.isSelfAttributed(), isTrue, reason: keyword);
          expect(note.isExcerpt(), isFalse, reason: keyword);
          expect(note.isOriginal(), isTrue, reason: keyword);
          expect(note.attributionKind, 'original', reason: keyword);
        }
      });

      test('note with defaultSource in sourceWork is original', () {
        final note = createNote(work: '2026读书记录');
        expect(
          note.resolveAttributionKind(defaultSource: '2026读书记录'),
          'original',
        );
        expect(note.isExcerpt(defaultSource: '2026读书记录'), isFalse);
      });

      test('legacy composite source with self-author is original', () {
        final note1 = createNote(source: '本人 - 读书感悟');
        expect(note1.isSelfAttributed(), isTrue);
        expect(note1.isExcerpt(), isFalse);
        expect(note1.attributionKind, 'original');

        final note2 = createNote(source: '上晋 —— 随笔');
        expect(
          note2.resolveAttributionKind(userNickname: '上晋'),
          'original',
        );
      });

      test('external author and work is classified as excerpt', () {
        final note = createNote(author: '加缪', work: '局外人');
        expect(note.isSelfAttributed(), isFalse);
        expect(note.isExcerpt(), isTrue);
        expect(note.isOriginal(), isFalse);
        expect(note.attributionKind, 'excerpt');
      });

      test(
          'external book in sourceWork without author is classified as excerpt',
          () {
        final note = createNote(work: '百年孤独');
        expect(note.isSelfAttributed(), isFalse);
        expect(note.isExcerpt(), isTrue);
        expect(note.isOriginal(), isFalse);
        expect(note.attributionKind, 'excerpt');
      });

      test(
          'legacy composite source with external author is classified as excerpt',
          () {
        final note = createNote(source: '鲁迅 - 狂人日记');
        expect(note.isSelfAttributed(), isFalse);
        expect(note.isExcerpt(), isTrue);
        expect(note.isOriginal(), isFalse);
        expect(note.attributionKind, 'excerpt');
      });
    });
  });
}
