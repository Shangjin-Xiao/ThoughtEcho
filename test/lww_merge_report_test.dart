import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/models/merge_report.dart';

void main() {
  test('MergeReport counters work', () {
    final start = MergeReport.start(sourceDevice: 'test');
    final done = start
        .addInsertedQuote()
        .addUpdatedQuote()
        .addSkippedQuote()
        .addSameTimestampDiffQuote()
        .addInsertedCategory()
        .addUpdatedCategory()
        .addSkippedCategory()
        .completed();

    expect(done.insertedQuotes, 1);
    expect(done.updatedQuotes, 1);
    expect(done.skippedQuotes, 1);
    expect(done.sameTimestampDiffQuotes, 1);
    expect(done.insertedCategories, 1);
    expect(done.updatedCategories, 1);
    expect(done.skippedCategories, 1);
    expect(done.appliedQuotes, 2); // inserted + updated
    expect(done.appliedCategories, 2); // inserted + updated
    expect(done.totalApplied, 4);
  });
}
