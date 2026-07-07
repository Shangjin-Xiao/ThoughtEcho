import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/merge_report.dart';

void main() {
  group('MergeReport', () {
    test('start should initialize with current time and correct defaults', () {
      final report = MergeReport.start(sourceDevice: 'device1');
      expect(report.sourceDevice, 'device1');
      expect(report.insertedQuotes, 0);
      expect(report.endTime, isNull);
      expect(
        DateTime.now().difference(report.startTime).inSeconds,
        lessThan(2),
      );
    });

    test('completed should set endTime and calculate durationMs', () async {
      final report = MergeReport.start();
      await Future.delayed(const Duration(milliseconds: 10));
      final completedReport = report.completed();

      expect(completedReport.endTime, isNotNull);
      expect(completedReport.durationMs, greaterThanOrEqualTo(10));
    });

    test('counters should increment correctly and calculate totals', () {
      var report = MergeReport.start()
          .addInsertedQuote()
          .addUpdatedQuote()
          .addDeletedQuote()
          .addDeletedByTombstone()
          .addSkippedQuote()
          .addSameTimestampDiffQuote()
          .addInsertedCategory()
          .addUpdatedCategory()
          .addSkippedCategory()
          .addError('test error');

      expect(report.insertedQuotes, 1);
      expect(report.updatedQuotes, 1);
      expect(report.deletedQuotes, 1);
      expect(report.deletedByTombstoneQuotes, 1);
      expect(report.skippedQuotes, 1);
      expect(report.sameTimestampDiffQuotes, 1);

      expect(report.insertedCategories, 1);
      expect(report.updatedCategories, 1);
      expect(report.skippedCategories, 1);

      expect(report.errors, ['test error']);
      expect(report.hasErrors, isTrue);

      expect(report.totalProcessedQuotes, 6);
      expect(report.totalProcessedCategories, 3);
      expect(report.totalApplied, 4);
      expect(report.totalSkipped, 2);
    });

    test('summary and detailedLog should generate correct output', () {
      var report = MergeReport.start()
          .addInsertedQuote()
          .addDeletedQuote()
          .addSkippedCategory()
          .addError('sync failed');

      final summary = report.summary;
      expect(summary, contains('新增 1'));
      expect(summary, contains('删除 1'));
      expect(summary, contains('1 个错误'));

      final detailedLog = report.detailedLog;
      expect(detailedLog, contains('=== 合并报告 ==='));
      expect(detailedLog, contains('新增: 1'));
      expect(detailedLog, contains('sync failed'));
    });

    test('empty report should generate "无变更" summary', () {
      final report = MergeReport.start();
      expect(report.summary, '无变更');
    });

    test('toJson should serialize correctly', () {
      final report =
          MergeReport.start(sourceDevice: 'dev').addInsertedQuote().completed();
      final json = report.toJson();

      expect(json['insertedQuotes'], 1);
      expect(json['sourceDevice'], 'dev');
      expect(json['startTime'], isNotNull);
      expect(json['endTime'], isNotNull);
    });
  });

  group('MergeReportBuilder', () {
    test('should accumulate correctly and build report', () async {
      final builder = MergeReportBuilder(sourceDevice: 'device2');
      builder.addInsertedQuote();
      builder.addUpdatedQuote();
      builder.addDeletedQuote();
      builder.addDeletedByTombstone();
      builder.addSameTimestampDiffQuote();
      builder.addSkippedQuote();

      builder.addInsertedCategory();
      builder.addUpdatedCategory();
      builder.addSkippedCategory();

      builder.addError('builder error');

      await Future.delayed(const Duration(milliseconds: 5));
      final report = builder.build();

      expect(report.sourceDevice, 'device2');
      expect(report.insertedQuotes, 1);
      expect(report.updatedQuotes, 1);
      expect(report.deletedQuotes, 1);
      expect(report.deletedByTombstoneQuotes, 1);
      expect(report.sameTimestampDiffQuotes, 1);
      expect(report.skippedQuotes, 1);

      expect(report.insertedCategories, 1);
      expect(report.updatedCategories, 1);
      expect(report.skippedCategories, 1);

      expect(report.errors, ['builder error']);
      expect(report.endTime, isNotNull);
      expect(report.durationMs, greaterThanOrEqualTo(5));

      expect(report.totalProcessedQuotes, 6);
      expect(report.totalProcessedCategories, 3);
    });
  });
}
