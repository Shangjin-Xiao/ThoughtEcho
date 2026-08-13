import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';
import 'package:thoughtecho/models/note_tag.dart';
import 'package:thoughtecho/services/feature_guide_service.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';
import 'package:thoughtecho/widgets/add_note_dialog.dart';

/// 键盘动画期间 showModalBottomSheet 会逐帧重跑 builder。弹窗状态没变的那些帧
/// 必须复用同一棵主体 Widget，Flutter 见到同一个实例才会整棵子树跳过 diff。
///
/// 用「同一个 TextField 实例是否还在」来观测：缓存命中就是原对象，
/// 缓存失效就会换成新构造的。
void main() {
  testWidgets('reuses the dialog body across keyboard-driven rebuilds',
      (tester) async {
    addTearDown(tester.view.reset);

    // 真实调用方传的是 UnmodifiableListView getter，每次取值都是新包装对象，
    // 不能拿它的 identity 判断入参有没有变。
    final sourceTags = <NoteTag>[
      NoteTag(id: 'tag-1', name: '标签一', iconName: 'tag'),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FeatureGuideService>(
            create: (_) => _MockFeatureGuideService(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => AddNoteDialog(
                      tags: UnmodifiableListView(sourceTags),
                      onSave: (_) {},
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final before = tester.widget<TextField>(find.byType(TextField).first);

    // 模拟键盘弹起的中间几帧：inset 在变，弹窗自身状态没有任何变化。
    for (final inset in <double>[60, 140, 220, 300]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
    }

    final after = tester.widget<TextField>(find.byType(TextField).first);

    expect(
      identical(before, after),
      isTrue,
      reason: '键盘每动一帧都重建整棵主体，缓存没命中',
    );

    await tester.pump(const Duration(seconds: 2));
  });
}

class _MockFeatureGuideService extends FeatureGuideService {
  _MockFeatureGuideService() : super(SafeMMKV());

  @override
  bool hasShown(String guideId) => true;

  @override
  Future<void> markAsShown(String guideId) async {}

  @override
  Future<void> resetGuide(String guideId) async {}

  @override
  Future<void> resetAllGuides() async {}
}
