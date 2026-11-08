import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/models/quote_model.dart';
import 'package:thoughtecho/widgets/note_list_view.dart';
import 'package:thoughtecho/widgets/quote_item_widget.dart';

Quote _createQuote(String id, {String content = 'Test Note Content'}) {
  return Quote(
    id: id,
    content: content,
    date: DateTime(2026, 11, 7).toIso8601String(),
  );
}

void main() {
  group('QuoteItemMemo.matches', () {
    late Quote quote;
    late Map<String, NoteTag> tagMap;
    late List<String> selectedTagIds;
    late Widget mockWidget;

    setUp(() {
      quote = _createQuote('quote-1');
      tagMap = <String, NoteTag>{};
      selectedTagIds = <String>[];
      mockWidget = const SizedBox();
    });

    QuoteItemMemo createMemo({
      Quote? customQuote,
      bool isFirstItem = false,
      Map<String, NoteTag>? customTagMap,
      List<String>? customSelectedTagIds,
      bool isExpanded = false,
      bool isSelected = false,
      bool selectionMode = false,
      bool hasGenerateCard = false,
      bool hasFavorite = false,
      bool hasLongPressFavorite = false,
      GlobalKey? favoriteGuideKey,
      GlobalKey? moreGuideKey,
      GlobalKey? foldGuideKey,
    }) {
      return QuoteItemMemo(
        widget: mockWidget,
        quote: customQuote ?? quote,
        isFirstItem: isFirstItem,
        tagMap: customTagMap ?? tagMap,
        selectedTagIds: customSelectedTagIds ?? selectedTagIds,
        isExpanded: isExpanded,
        isSelected: isSelected,
        selectionMode: selectionMode,
        hasGenerateCard: hasGenerateCard,
        hasFavorite: hasFavorite,
        hasLongPressFavorite: hasLongPressFavorite,
        favoriteGuideKey: favoriteGuideKey,
        moreGuideKey: moreGuideKey,
        foldGuideKey: foldGuideKey,
      );
    }

    test('非首行卡片行号平移时保持 isFirstItem == false 并命中缓存', () {
      final memo = createMemo(isFirstItem: false);

      // 行号由 index 1 平移至 index 2、index 3，但 isFirstItem 均为 false
      final matched = memo.matches(
        quote: quote,
        isFirstItem: false,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
        isExpanded: false,
        isSelected: false,
        selectionMode: false,
        hasGenerateCard: false,
        hasFavorite: false,
        hasLongPressFavorite: false,
        favoriteGuideKey: null,
        moreGuideKey: null,
        foldGuideKey: null,
      );

      expect(matched, isTrue);
    });

    test('首行卡片跨越至非首行时 isFirstItem 改变导致缓存失效以重置边距', () {
      final memo = createMemo(isFirstItem: true);

      // 原第 0 行卡片平移至第 1 行（isFirstItem 变为 false）
      final matched = memo.matches(
        quote: quote,
        isFirstItem: false,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
        isExpanded: false,
        isSelected: false,
        selectionMode: false,
        hasGenerateCard: false,
        hasFavorite: false,
        hasLongPressFavorite: false,
        favoriteGuideKey: null,
        moreGuideKey: null,
        foldGuideKey: null,
      );

      expect(matched, isFalse);
    });

    test('非首行卡片平移至首行时 isFirstItem 改变导致缓存失效以应用首行边距', () {
      final memo = createMemo(isFirstItem: false);

      // 原第 1 行卡片平移至第 0 行（isFirstItem 变为 true）
      final matched = memo.matches(
        quote: quote,
        isFirstItem: true,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
        isExpanded: false,
        isSelected: false,
        selectionMode: false,
        hasGenerateCard: false,
        hasFavorite: false,
        hasLongPressFavorite: false,
        favoriteGuideKey: null,
        moreGuideKey: null,
        foldGuideKey: null,
      );

      expect(matched, isFalse);
    });

    test('quote 实例变更时判定未命中', () {
      final memo = createMemo(isFirstItem: false);
      final newQuote = _createQuote('quote-1', content: 'Updated Content');

      final matched = memo.matches(
        quote: newQuote,
        isFirstItem: false,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
        isExpanded: false,
        isSelected: false,
        selectionMode: false,
        hasGenerateCard: false,
        hasFavorite: false,
        hasLongPressFavorite: false,
        favoriteGuideKey: null,
        moreGuideKey: null,
        foldGuideKey: null,
      );

      expect(matched, isFalse);
    });

    test('selectedTagIds 列表按内容等价比对命中，不同内容则失效', () {
      final memo = createMemo(
        isFirstItem: false,
        customSelectedTagIds: ['tag-a', 'tag-b'],
      );

      // 等价的新列表实例
      final sameContentTags = ['tag-a', 'tag-b'];
      expect(
        memo.matches(
          quote: quote,
          isFirstItem: false,
          tagMap: tagMap,
          selectedTagIds: sameContentTags,
          isExpanded: false,
          isSelected: false,
          selectionMode: false,
          hasGenerateCard: false,
          hasFavorite: false,
          hasLongPressFavorite: false,
          favoriteGuideKey: null,
          moreGuideKey: null,
          foldGuideKey: null,
        ),
        isTrue,
      );

      // 不同内容
      final differentContentTags = ['tag-a', 'tag-c'];
      expect(
        memo.matches(
          quote: quote,
          isFirstItem: false,
          tagMap: tagMap,
          selectedTagIds: differentContentTags,
          isExpanded: false,
          isSelected: false,
          selectionMode: false,
          hasGenerateCard: false,
          hasFavorite: false,
          hasLongPressFavorite: false,
          favoriteGuideKey: null,
          moreGuideKey: null,
          foldGuideKey: null,
        ),
        isFalse,
      );
    });
  });

  group('列表首部增删卡片时的行号平移记忆化模拟', () {
    QuoteItemWidget obtainItem({
      required Map<String, QuoteItemMemo> memos,
      required Quote quote,
      required int index,
      required Map<String, NoteTag> tagMap,
      required List<String> selectedTagIds,
    }) {
      final quoteId = quote.id!;
      final isFirstItem = index == 0;
      final cached = memos[quoteId];
      if (cached != null &&
          cached.matches(
            quote: quote,
            isFirstItem: isFirstItem,
            tagMap: tagMap,
            selectedTagIds: selectedTagIds,
            isExpanded: false,
            isSelected: false,
            selectionMode: false,
            hasGenerateCard: false,
            hasFavorite: false,
            hasLongPressFavorite: false,
            favoriteGuideKey: null,
            moreGuideKey: null,
            foldGuideKey: null,
          )) {
        return cached.widget as QuoteItemWidget;
      }

      final widget = QuoteItemWidget(
        quote: quote,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
        isExpanded: false,
        isSelected: false,
        selectionMode: false,
        topMarginOverride:
            isFirstItem ? QuoteItemWidget.firstItemTopMargin : null,
        onToggleExpanded: (_) {},
        onEdit: () {},
        onDelete: () {},
        onAskAI: () {},
      );

      memos[quoteId] = QuoteItemMemo(
        widget: widget,
        quote: quote,
        isFirstItem: isFirstItem,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
        isExpanded: false,
        isSelected: false,
        selectionMode: false,
        hasGenerateCard: false,
        hasFavorite: false,
        hasLongPressFavorite: false,
        favoriteGuideKey: null,
        moreGuideKey: null,
        foldGuideKey: null,
      );

      return widget;
    }

    test('首部插入卡片后，除跨越首行边界的卡片外其余非首行卡片完全命中缓存且指针恒定', () {
      final memos = <String, QuoteItemMemo>{};
      final tagMap = <String, NoteTag>{};
      final selectedTagIds = <String>[];

      final quoteA = _createQuote('quote-a');
      final quoteB = _createQuote('quote-b');
      final quoteC = _createQuote('quote-c');

      // 初始列表: [quoteA (0), quoteB (1), quoteC (2)]
      final widgetA0 = obtainItem(
        memos: memos,
        quote: quoteA,
        index: 0,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );
      final widgetB1 = obtainItem(
        memos: memos,
        quote: quoteB,
        index: 1,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );
      final widgetC2 = obtainItem(
        memos: memos,
        quote: quoteC,
        index: 2,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );

      expect(widgetA0.topMarginOverride, QuoteItemWidget.firstItemTopMargin);
      expect(widgetB1.topMarginOverride, isNull);
      expect(widgetC2.topMarginOverride, isNull);

      // 在列表首部插入 quoteNew，列表变为 [quoteNew (0), quoteA (1), quoteB (2), quoteC (3)]
      final quoteNew = _createQuote('quote-new');
      final widgetNew0 = obtainItem(
        memos: memos,
        quote: quoteNew,
        index: 0,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );
      final widgetA1 = obtainItem(
        memos: memos,
        quote: quoteA,
        index: 1,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );
      final widgetB2 = obtainItem(
        memos: memos,
        quote: quoteB,
        index: 2,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );
      final widgetC3 = obtainItem(
        memos: memos,
        quote: quoteC,
        index: 3,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );

      // 验证新增首条设置了首条顶部边距
      expect(widgetNew0.topMarginOverride, QuoteItemWidget.firstItemTopMargin);

      // 验证 quoteA 从首行位移至第 1 行后，isFirstItem 变化穿透缓存，重新构建以剥离首行边距
      expect(identical(widgetA1, widgetA0), isFalse);
      expect(widgetA1.topMarginOverride, isNull);

      // 验证原非首行卡片（quoteB, quoteC）虽然绝对行号由 1->2、2->3，但均命中缓存且实例指针恒定
      expect(identical(widgetB2, widgetB1), isTrue);
      expect(identical(widgetC3, widgetC2), isTrue);
    });

    test('首部删除卡片后，新变为首行的卡片重新构建注入边距，其余卡片命中缓存且指针恒定', () {
      final memos = <String, QuoteItemMemo>{};
      final tagMap = <String, NoteTag>{};
      final selectedTagIds = <String>[];

      final quoteHead = _createQuote('quote-head');
      final quoteA = _createQuote('quote-a');
      final quoteB = _createQuote('quote-b');
      final quoteC = _createQuote('quote-c');

      // 初始列表: [quoteHead (0), quoteA (1), quoteB (2), quoteC (3)]
      obtainItem(
        memos: memos,
        quote: quoteHead,
        index: 0,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );
      final widgetA1 = obtainItem(
        memos: memos,
        quote: quoteA,
        index: 1,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );
      final widgetB2 = obtainItem(
        memos: memos,
        quote: quoteB,
        index: 2,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );
      final widgetC3 = obtainItem(
        memos: memos,
        quote: quoteC,
        index: 3,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );

      // 删除首条 quoteHead，列表平移为 [quoteA (0), quoteB (1), quoteC (2)]
      memos.remove(quoteHead.id);

      final widgetA0 = obtainItem(
        memos: memos,
        quote: quoteA,
        index: 0,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );
      final widgetB1 = obtainItem(
        memos: memos,
        quote: quoteB,
        index: 1,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );
      final widgetC2 = obtainItem(
        memos: memos,
        quote: quoteC,
        index: 2,
        tagMap: tagMap,
        selectedTagIds: selectedTagIds,
      );

      // quoteA 晋升为第 0 行，缓存失效并重新构建获得首行边距
      expect(identical(widgetA0, widgetA1), isFalse);
      expect(widgetA0.topMarginOverride, QuoteItemWidget.firstItemTopMargin);

      // quoteB (2->1) 与 quoteC (3->2) 命中缓存且实例指针保持恒定
      expect(identical(widgetB1, widgetB2), isTrue);
      expect(identical(widgetC2, widgetC3), isTrue);
    });
  });

  group('NoteListViewState 记忆化测试属性暴露', () {
    test('初始状态为空 Map 与计数 0，并能正常存取 QuoteItemMemo 实例', () {
      final state = NoteListViewState();
      expect(state.quoteItemMemosForTest, isEmpty);
      expect(state.quoteItemMemoHitsForTest, 0);
      expect(state.quoteItemMemoMissesForTest, 0);

      final memo = QuoteItemMemo(
        widget: const SizedBox(),
        quote: _createQuote('test-1'),
        isFirstItem: true,
        tagMap: const {},
        selectedTagIds: const [],
        isExpanded: false,
        isSelected: false,
        selectionMode: false,
        hasGenerateCard: false,
        hasFavorite: false,
        hasLongPressFavorite: false,
        favoriteGuideKey: null,
        moreGuideKey: null,
        foldGuideKey: null,
      );

      state.quoteItemMemosForTest['test-1'] = memo;
      expect(state.quoteItemMemosForTest['test-1'], same(memo));
      expect(state.quoteItemMemosForTest.length, 1);
    });
  });

  group('折叠回调动态行号解析逻辑 (dynamicIndex resolution)', () {
    int resolveTargetIndex({
      required List<Quote> quotes,
      required String quoteId,
      required int capturedIndex,
    }) {
      final dynamicIndex = quotes.indexWhere((q) => q.id == quoteId);
      return dynamicIndex != -1 ? dynamicIndex : capturedIndex;
    }

    test('When quote list has not shifted, returns same index', () {
      final quotes = [
        _createQuote('quote-0'),
        _createQuote('quote-1'),
        _createQuote('quote-2'),
      ];
      final targetIndex = resolveTargetIndex(
        quotes: quotes,
        quoteId: 'quote-1',
        capturedIndex: 1,
      );
      expect(targetIndex, equals(1));
    });

    test(
        'When items are inserted before the quote, dynamic index resolves to shifted index',
        () {
      final quotes = [
        _createQuote('quote-inserted'),
        _createQuote('quote-0'),
        _createQuote('quote-1'),
        _createQuote('quote-2'),
      ];
      final targetIndex = resolveTargetIndex(
        quotes: quotes,
        quoteId: 'quote-1',
        capturedIndex: 1,
      );
      expect(targetIndex, equals(2));
    });

    test(
        'When items before the quote are deleted, dynamic index resolves to shifted index',
        () {
      final quotes = [
        _createQuote('quote-1'),
        _createQuote('quote-2'),
      ];
      final targetIndex = resolveTargetIndex(
        quotes: quotes,
        quoteId: 'quote-1',
        capturedIndex: 1,
      );
      expect(targetIndex, equals(0));
    });

    test(
        'When the quote itself was deleted, gracefully falls back to the captured index to prevent negative indexing',
        () {
      final quotes = [
        _createQuote('quote-0'),
        _createQuote('quote-2'),
      ];
      final targetIndex = resolveTargetIndex(
        quotes: quotes,
        quoteId: 'quote-1',
        capturedIndex: 1,
      );
      expect(targetIndex, equals(1));
      expect(targetIndex >= 0, isTrue);
    });
  });
}
