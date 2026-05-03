import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/anniversary_display_utils.dart';

void main() {
  group('AnniversaryDisplayUtils', () {
    test('isAnniversarySeason returns true within anniversary window', () {
      expect(
        AnniversaryDisplayUtils.isAnniversarySeason(DateTime(2026, 3, 23)),
        isTrue,
      );
      expect(
        AnniversaryDisplayUtils.isAnniversarySeason(
          DateTime(2026, 4, 30, 23, 59, 59),
        ),
        isTrue,
      );
    });

    test('isAnniversarySeason returns false outside anniversary window', () {
      expect(
        AnniversaryDisplayUtils.isAnniversarySeason(
          DateTime(2026, 3, 22, 23, 59, 59),
        ),
        isFalse,
      );
      expect(
        AnniversaryDisplayUtils.isAnniversarySeason(DateTime(2026, 5, 1)),
        isFalse,
      );
    });

    test(
      'shouldShowSettingsBanner allows developer preview before anniversary',
      () {
        expect(
          AnniversaryDisplayUtils.shouldShowSettingsBanner(
            now: DateTime(2026, 3, 1),
            developerMode: true,
          ),
          isTrue,
        );
        expect(
          AnniversaryDisplayUtils.shouldShowSettingsBanner(
            now: DateTime(2026, 3, 1),
            developerMode: false,
          ),
          isFalse,
        );
      },
    );

    test(
      'shouldAutoShowAnimation allows developer preview outside date window',
      () {
        expect(
          AnniversaryDisplayUtils.shouldAutoShowAnimation(
            now: DateTime(2026, 3, 25),
            developerMode: false,
            anniversaryShown: false,
            anniversaryAnimationEnabled: true,
          ),
          isTrue,
        );
        expect(
          AnniversaryDisplayUtils.shouldAutoShowAnimation(
            now: DateTime(2026, 3, 25),
            developerMode: false,
            anniversaryShown: true,
            anniversaryAnimationEnabled: true,
          ),
          isFalse,
        );
        expect(
          AnniversaryDisplayUtils.shouldAutoShowAnimation(
            now: DateTime(2026, 3, 25),
            developerMode: false,
            anniversaryShown: false,
            anniversaryAnimationEnabled: false,
          ),
          isFalse,
        );
        expect(
          AnniversaryDisplayUtils.shouldAutoShowAnimation(
            now: DateTime(2026, 3, 1),
            developerMode: false,
            anniversaryShown: false,
            anniversaryAnimationEnabled: true,
          ),
          isFalse,
        );
        expect(
          AnniversaryDisplayUtils.shouldAutoShowAnimation(
            now: DateTime(2026, 3, 1),
            developerMode: true,
            anniversaryShown: false,
            anniversaryAnimationEnabled: true,
          ),
          isTrue,
        );
        expect(
          AnniversaryDisplayUtils.shouldAutoShowAnimation(
            now: DateTime(2026, 3, 1),
            developerMode: true,
            anniversaryShown: true,
            anniversaryAnimationEnabled: true,
          ),
          isFalse,
        );
      },
    );
  });
}
