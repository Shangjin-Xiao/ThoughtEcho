import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/anniversary_participation.dart';
import 'package:thoughtecho/models/app_settings.dart';

void main() {
  group('AnniversaryParticipation', () {
    test('序列化保留届数、时间和版本', () {
      final record = AnniversaryParticipation(
        year: 2,
        seenAt: DateTime.utc(2027, 3, 24, 8, 12),
        appVersion: '4.1.0',
      );
      final json = record.toJson();
      expect(json['year'], 2);
      expect(json['seenAt'], '2027-03-24T08:12:00.000Z');
      expect(json['appVersion'], '4.1.0');
      expect(AnniversaryParticipation.fromJson(json), equals(record));
    });

    test('缺字段的记录只保留届数', () {
      final record = AnniversaryParticipation.fromJson({'year': 1});
      expect(record, isNotNull);
      expect(record!.seenAt, isNull);
      expect(record.appVersion, isNull);
      expect(record.toJson().containsKey('seenAt'), isFalse);
    });

    test('无效记录被丢弃', () {
      expect(AnniversaryParticipation.fromJson({'year': 0}), isNull);
      expect(AnniversaryParticipation.fromJson({'seenAt': 'x'}), isNull);
      expect(AnniversaryParticipation.fromJson('nope'), isNull);
    });
  });

  group('AppSettings 的庆典参与记录', () {
    test('一周年时期的 anniversaryShown 迁移成一条记录', () {
      final settings = AppSettings.fromJson({'anniversaryShown': true});
      expect(settings.anniversaryParticipation.length, 1);
      expect(settings.anniversaryParticipation.single.year, 1);
      expect(settings.anniversaryParticipation.single.seenAt, isNull);
      expect(settings.anniversaryShownYears, [1]);
    });

    test('没参与过的旧数据不产生记录', () {
      final settings = AppSettings.fromJson({'anniversaryShown': false});
      expect(settings.anniversaryParticipation, isEmpty);
      expect(settings.anniversaryShownYears, isEmpty);
    });

    test('记录按届数去重升序，无效项跳过', () {
      final settings = AppSettings.fromJson({
        'anniversaryParticipation': [
          {'year': 2, 'seenAt': '2027-03-24T08:12:00.000Z'},
          {'year': 1},
          {'year': 2, 'appVersion': '4.1.0'},
          {'year': -1},
          'garbage',
        ],
      });
      expect(settings.anniversaryShownYears, [1, 2]);
      // 同届后出现的记录覆盖先出现的。
      expect(settings.anniversaryParticipation.last.appVersion, '4.1.0');
    });

    test('toJson 仍写出旧版本认得的 anniversaryShown', () {
      final settings = AppSettings(
        anniversaryParticipation: const [AnniversaryParticipation(year: 1)],
      );
      expect(settings.toJson()['anniversaryShown'], isTrue);
      expect(
        AppSettings(
          anniversaryParticipation: const [AnniversaryParticipation(year: 2)],
        ).toJson()['anniversaryShown'],
        isFalse,
      );
    });
  });
}
