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
          expect(Quote.isSelfAuthor('-- $word'), isTrue, reason: word);
          expect(Quote.isSelfAuthor('- $word'), isTrue, reason: word);
          expect(Quote.isSelfAuthor('「$word」'), isTrue, reason: word);
          expect(Quote.isSelfAuthor('【$word】'), isTrue, reason: word);
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
        final note1 = createNote(source: '鲁迅 - 狂人日记');
        expect(note1.isSelfAttributed(), isFalse);
        expect(note1.isExcerpt(), isTrue);
        expect(note1.isOriginal(), isFalse);
        expect(note1.attributionKind, 'excerpt');

        final note2 = createNote(source: '作者：鲁迅 - 狂人日记');
        expect(note2.isSelfAttributed(), isFalse);
        expect(note2.isExcerpt(), isTrue);
        expect(note2.isOriginal(), isFalse);
        expect(note2.attributionKind, 'excerpt');

        final note3 = createNote(source: 'author: Lu Xun - Diary of a Madman');
        expect(note3.isSelfAttributed(), isFalse);
        expect(note3.isExcerpt(), isTrue);
        expect(note3.isOriginal(), isFalse);
        expect(note3.attributionKind, 'excerpt');
      });

      test('配置 userAliases 时，个人笔名（如“阿澈”）随笔正确识别为原创，未配置时为摘录', () {
        const aliases = ['阿澈'];

        // 场景 1：文末署名「——写于夜跑归来，阿澈」且 author 为「阿澈」
        final noteNightRun = createNote(
          content:
              '夜跑西湖十公里，微风拂面，苏堤上游人渐稀。汗水顺着脸颊流下来，所有的杂念都被脚步声踩碎在夜色里。——写于夜跑归来，阿澈',
          author: '阿澈',
        );
        // 配置别名后（来自 Dreaming 或记忆）确定性命中原创
        expect(noteNightRun.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteNightRun.isExcerpt(userAliases: aliases), isFalse);
        expect(noteNightRun.resolveAttributionKind(userAliases: aliases),
            'original');
        // 未配置别名时底层 Model 绝不靠正文猜语义，正确保持元数据严格性
        expect(noteNightRun.isSelfAttributed(), isFalse);
        expect(noteNightRun.isExcerpt(), isTrue);
        expect(noteNightRun.attributionKind, 'excerpt');

        // 场景 2：自指随笔「致五年后的阿澈」
        final noteToFuture = createNote(
          content: '致五年后的阿澈：希望你依然对构建好产品保持好奇与热情，依然会在深夜为优雅的代码心动，依然敢于做出改变一生的决定。',
          author: '阿澈',
        );
        expect(noteToFuture.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteToFuture.isExcerpt(userAliases: aliases), isFalse);
        expect(noteToFuture.resolveAttributionKind(userAliases: aliases),
            'original');

        // 场景 3：破折号署名随笔「——阿澈随笔」（包含 source: 形式与 author: 形式）
        final noteSunsetSource = createNote(
          content: '海创园的晚霞烧红了半边天，坐在长椅上吹着晚风，突然觉得生活除了赶进度，还有这些停顿的片刻值得铭记。——阿澈随笔',
          source: '——阿澈随笔',
        );
        expect(noteSunsetSource.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteSunsetSource.isExcerpt(userAliases: aliases), isFalse);
        expect(noteSunsetSource.resolveAttributionKind(userAliases: aliases),
            'original');

        final noteSunsetAuthor = createNote(
          content: '海创园的晚霞烧红了半边天，坐在长椅上吹着晚风，突然觉得生活除了赶进度，还有这些停顿的片刻值得铭记。——阿澈随笔',
          author: '阿澈',
        );
        expect(noteSunsetAuthor.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteSunsetAuthor.isExcerpt(userAliases: aliases), isFalse);
        expect(noteSunsetAuthor.resolveAttributionKind(userAliases: aliases),
            'original');

        final noteJournal = createNote(
          content: '黄山云海极壮观，拾级而上。——阿澈手记',
          author: '阿澈',
        );
        expect(noteJournal.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteJournal.isExcerpt(userAliases: aliases), isFalse);
        expect(noteJournal.resolveAttributionKind(userAliases: aliases),
            'original');

        // 场景 4：纯外部名人名言文末带作者（如“——泰戈尔”），无第一人称/日记场景，仍准确归为摘录
        final noteTagore = createNote(
          content: '生如夏花之绚烂，死如秋叶之静美。——泰戈尔',
          author: '泰戈尔',
        );
        expect(noteTagore.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteTagore.isExcerpt(userAliases: aliases), isTrue);
        expect(
            noteTagore.resolveAttributionKind(userAliases: aliases), 'excerpt');

        // 场景 5：外部名家名言包含第一人称“我/我们/今天”，即便 author 或 source 带有破折号（“——加缪”、“——笛卡尔”），坚决不被误判为原创
        final noteCamus = createNote(
          content: '在隆冬，我终于知道，我身上有一个不可战胜的夏天。——加缪',
          author: '加缪',
        );
        expect(noteCamus.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteCamus.isExcerpt(userAliases: aliases), isTrue);

        final noteCamusWithDash = createNote(
          content: '在隆冬，我终于知道，我身上有一个不可战胜的夏天。',
          author: '——加缪',
        );
        expect(
            noteCamusWithDash.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteCamusWithDash.isExcerpt(userAliases: aliases), isTrue);

        final noteDescartes = createNote(
          content: '我思故我在。——笛卡尔',
          author: '笛卡尔',
        );
        expect(noteDescartes.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteDescartes.isExcerpt(userAliases: aliases), isTrue);

        final noteDescartesSource = createNote(
          content: '我思故我在。',
          source: '——笛卡尔',
        );
        expect(noteDescartesSource.isSelfAttributed(userAliases: aliases),
            isFalse);
        expect(noteDescartesSource.isExcerpt(userAliases: aliases), isTrue);

        final noteChurchill = createNote(
          content: '今天我们所经历的困难，都将成为过去的插曲。——丘吉尔',
          author: '丘吉尔',
        );
        expect(noteChurchill.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteChurchill.isExcerpt(userAliases: aliases), isTrue);

        final noteChurchillWithDash = createNote(
          content: '今天我们所经历的困难，都将成为过去的插曲。',
          author: '——丘吉尔',
        );
        expect(noteChurchillWithDash.isSelfAttributed(userAliases: aliases),
            isFalse);
        expect(noteChurchillWithDash.isExcerpt(userAliases: aliases), isTrue);

        final noteDostoevsky = createNote(
          content: '我爱生活，胜过爱生活的意义。——陀思妥耶夫斯基',
          author: '陀思妥耶夫斯基',
        );
        expect(noteDostoevsky.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteDostoevsky.isExcerpt(userAliases: aliases), isTrue);

        final noteLinSheng = createNote(
          content: '山外青山楼外楼，西湖歌舞几时休。——林升',
          author: '林升',
        );
        expect(noteLinSheng.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteLinSheng.isExcerpt(userAliases: aliases), isTrue);

        // 场景 6：外部作者的作品名即便包含“日记”（如《狂人日记》），只要作者不是自己，绝不误判为原创
        final noteLuXunDiary = createNote(
          content: '今天全没月光，我很怀疑。',
          author: '鲁迅',
          work: '狂人日记',
        );
        expect(noteLuXunDiary.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteLuXunDiary.isExcerpt(userAliases: aliases), isTrue);

        // 场景 7：具备设备天气/位置或交互清单、图片附件的随笔配合别名识别为原创
        final noteWithWeather = Quote(
          content: '清晨湖边慢跑，空气很清爽。——阿澈',
          date: '2026-08-20',
          sourceAuthor: '阿澈',
          weather: 'clear',
          location: '西湖·苏堤',
        );
        expect(noteWithWeather.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteWithWeather.isExcerpt(userAliases: aliases), isFalse);

        final noteTodo = Quote(
          content: '出行清单：\n- [x] 登山杖\n- [ ] 充电宝',
          date: '2026-08-20',
          sourceAuthor: '阿澈',
          sourceWork: '备忘',
        );
        expect(noteTodo.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteTodo.isExcerpt(userAliases: aliases), isFalse);

        final noteMedia = Quote(
          content: '集贤亭晚霞很美：\n[图片:sunset.jpg]\n晚风很温柔。——阿澈',
          date: '2026-08-20',
          sourceAuthor: '阿澈',
          sourceWork: '西湖日记',
        );
        expect(noteMedia.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteMedia.isExcerpt(userAliases: aliases), isFalse);
      });

      test('配置 userAliases 时，古建与风物学者“林晚”的田野随笔与测绘笔记正确识别为原创，外部古籍精准隔离', () {
        const aliases = ['林晚'];

        // 场景 1：文末署名「——录于晋东南，林晚」，author 为「林晚」
        final notePagoda = createNote(
          content:
              '应县木塔下仰望斗栱层叠如初绽莲瓣，千年前工匠砍削辽代落叶松的松脂气，仿佛仍锁在粗粝的榫卯咬合之间。——录于晋东南，林晚',
          author: '林晚',
        );
        expect(notePagoda.isSelfAttributed(userAliases: aliases), isTrue);
        expect(notePagoda.isExcerpt(userAliases: aliases), isFalse);
        expect(notePagoda.resolveAttributionKind(userAliases: aliases),
            'original');

        // 未配置别名时为摘录
        expect(notePagoda.isSelfAttributed(), isFalse);
        expect(notePagoda.isExcerpt(), isTrue);

        // 场景 2：田野拍摄「——摄于五台山佛光寺，林晚」
        final noteTemple = createNote(
          content: '佛光寺东大殿梁架雄浑简远，斗栱出跳深远如飞鸟展翼，唐代木构的气象令人肃然起敬。——摄于五台山佛光寺，林晚',
          author: '林晚',
        );
        expect(noteTemple.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteTemple.isExcerpt(userAliases: aliases), isFalse);
        expect(noteTemple.resolveAttributionKind(userAliases: aliases),
            'original');

        // 场景 3：个人工作笔记出处带后缀「——林晚田野笔记」
        final noteFieldNotes = createNote(
          content: '歙县渔梁坝前看新安江水漫过巨石古闸，清代徽州水利营造之法，尽在石缝灰浆之中。——林晚田野笔记',
          author: '林晚',
          work: '林晚田野笔记',
        );
        expect(noteFieldNotes.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteFieldNotes.isExcerpt(userAliases: aliases), isFalse);
        expect(
            noteFieldNotes.attributionKind, 'excerpt'); // 没有传 alias 时为 excerpt
        expect(noteFieldNotes.resolveAttributionKind(userAliases: aliases),
            'original');

        // 场景 4：地方风味记述「——林晚食记」
        final noteFood = createNote(
          content: '徽州深山里古法发酵的毛豆腐，表面菌丝洁白如羊绒，落入菜籽油锅滋啦作响，外焦里嫩。——林晚食记',
          author: '林晚',
          work: '食记',
        );
        expect(noteFood.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteFood.isExcerpt(userAliases: aliases), isFalse);
        expect(
            noteFood.resolveAttributionKind(userAliases: aliases), 'original');

        // 场景 5：含文言第一人称代词「余/吾」与自记标记的笔记
        final noteClassicalPronoun = createNote(
          content: '余过平遥南门，见城堞苍茫，古砖砖缝苔痕斑驳，感念世代匠人劳苦。——记于平遥南门，林晚',
          author: '林晚',
        );
        expect(noteClassicalPronoun.isSelfAttributed(userAliases: aliases),
            isTrue);
        expect(noteClassicalPronoun.isExcerpt(userAliases: aliases), isFalse);
        expect(
            noteClassicalPronoun.resolveAttributionKind(userAliases: aliases),
            'original');

        // 场景 5b：含自署名手札落款的田野随笔
        final noteClassicalDirectSign = createNote(
          content: '余过平遥南门，见城堞苍茫，古砖砖缝苔痕斑驳，感念世代匠人劳苦。——林晚手札',
          author: '林晚',
        );
        expect(noteClassicalDirectSign.isSelfAttributed(userAliases: aliases),
            isTrue);
        expect(
            noteClassicalDirectSign.isExcerpt(userAliases: aliases), isFalse);
        expect(
            noteClassicalDirectSign.resolveAttributionKind(
                userAliases: aliases),
            'original');

        // 场景 5c：多样化田野动词调查/访/辑/采风/测绘/整理落款
        for (final verb in ['调查于', '访于', '辑于', '采风于', '测绘于', '整理于']) {
          final noteFieldVerb = createNote(
            content: '古建筑大木构架测绘记录，檐下斗栱出跳深远。——$verb，林晚',
            author: '林晚',
          );
          expect(noteFieldVerb.isSelfAttributed(userAliases: aliases), isTrue,
              reason: verb);
          expect(noteFieldVerb.isExcerpt(userAliases: aliases), isFalse,
              reason: verb);
          expect(noteFieldVerb.resolveAttributionKind(userAliases: aliases),
              'original',
              reason: verb);
        }

        // 场景 5d：手札与测绘记录类出处配合署名
        final noteHandNotes = createNote(
          content: '大木作暗销与驼峰垫木节点实测。——林晚手札',
          author: '林晚',
          work: '徽州大木作手札',
        );
        expect(noteHandNotes.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteHandNotes.isExcerpt(userAliases: aliases), isFalse);
        expect(noteHandNotes.resolveAttributionKind(userAliases: aliases),
            'original');

        final noteSurveyRecord = createNote(
          content: '晋东南宋金木构实测数据汇总。——林晚测绘记录',
          author: '林晚',
          work: '晋东南古建测绘记录',
        );
        expect(noteSurveyRecord.isSelfAttributed(userAliases: aliases), isTrue);
        expect(noteSurveyRecord.isExcerpt(userAliases: aliases), isFalse);
        expect(noteSurveyRecord.resolveAttributionKind(userAliases: aliases),
            'original');

        // 场景 6：林晚摘录的营造经典（梁思成《中国建筑史》、李诫《营造法式》、汪曾祺《人间草木》）即便传入 aliases 绝不误判为原创
        final noteLiang = createNote(
          content: '中国建筑以木构架为其结构之骨干，其柱梁枋斗栱之相互咬合，具有极高之抗震弹性。',
          author: '梁思成',
          work: '中国建筑史',
        );
        expect(noteLiang.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteLiang.isExcerpt(userAliases: aliases), isTrue);
        expect(
            noteLiang.resolveAttributionKind(userAliases: aliases), 'excerpt');

        final noteLiJie = createNote(
          content: '凡造屋之制，先以材为祖。材有八等，度屋之大小，因而用之。',
          author: '李诫',
          work: '营造法式',
        );
        expect(noteLiJie.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteLiJie.isExcerpt(userAliases: aliases), isTrue);
        expect(
            noteLiJie.resolveAttributionKind(userAliases: aliases), 'excerpt');

        final noteWang = createNote(
          content: '栀子花粗粗大大的，又香得呛人，这就有点叫人受不住，但这才是江南夏天应有的霸道。',
          author: '汪曾祺',
          work: '人间草木',
        );
        expect(noteWang.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteWang.isExcerpt(userAliases: aliases), isTrue);
        expect(
            noteWang.resolveAttributionKind(userAliases: aliases), 'excerpt');

        // 场景 6b：无出处的外部历史名家名言绝不误判为原创
        final noteLuXunQuote = createNote(
          content: '横眉冷对千夫指，俯首甘为孺子牛。——鲁迅',
          author: '鲁迅',
        );
        expect(noteLuXunQuote.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteLuXunQuote.isExcerpt(userAliases: aliases), isTrue);
        expect(noteLuXunQuote.resolveAttributionKind(userAliases: aliases),
            'excerpt');

        // 场景 6c：含第一人称代词但属于外部正规出版书籍的文学摘录绝不误判为原创
        final noteLuXunDiary = createNote(
          content: '今天全没月光，我便知道不妙。——鲁迅',
          author: '鲁迅',
          work: '狂人日记',
        );
        expect(noteLuXunDiary.isSelfAttributed(userAliases: aliases), isFalse);
        expect(noteLuXunDiary.isExcerpt(userAliases: aliases), isTrue);
        expect(noteLuXunDiary.resolveAttributionKind(userAliases: aliases),
            'excerpt');
      });
    });
  });
}
