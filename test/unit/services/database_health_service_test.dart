import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/services/database_health_service.dart';

void main() {
  group('DatabaseHealthService Query Tracking Tests', () {
    late DatabaseHealthService service;

    setUp(() {
      service = DatabaseHealthService();
    });

    test('initial state should be empty', () {
      final report = service.getQueryPerformanceReport();
      expect(report['totalQueries'], 0);
      expect(report['cacheHits'], 0);
      expect(report['cacheHitRate'], '0%');
      expect(report['queryTypes'], isEmpty);
    });

    test('recordQueryStats should track multiple query types correctly', () {
      service.recordQueryStats('SELECT', 10);
      service.recordQueryStats('SELECT', 20);
      service.recordQueryStats('INSERT', 30);

      final report = service.getQueryPerformanceReport();
      expect(report['totalQueries'], 3);

      final queryTypes = report['queryTypes'] as Map<String, dynamic>;
      expect(queryTypes.containsKey('SELECT'), true);
      expect(queryTypes.containsKey('INSERT'), true);

      expect(queryTypes['SELECT']['count'], 2);
      expect(queryTypes['SELECT']['totalTime'], '30ms');
      expect(queryTypes['SELECT']['avgTime'], '15.00ms');

      expect(queryTypes['INSERT']['count'], 1);
      expect(queryTypes['INSERT']['totalTime'], '30ms');
      expect(queryTypes['INSERT']['avgTime'], '30.00ms');
    });

    test('recordCacheHit should update cache hit rate correctly', () {
      service.recordQueryStats('SELECT', 10); // total 1
      service.recordCacheHit(); // hit 1

      var report = service.getQueryPerformanceReport();
      expect(report['totalQueries'], 1);
      expect(report['cacheHits'], 1);
      expect(report['cacheHitRate'], '100.00%');

      service.recordQueryStats('SELECT', 10); // total 2
      report = service.getQueryPerformanceReport();
      expect(report['totalQueries'], 2);
      expect(report['cacheHits'], 1);
      expect(report['cacheHitRate'], '50.00%');

      service.recordQueryStats('SELECT', 10); // total 3
      service.recordQueryStats('SELECT', 10); // total 4
      report = service.getQueryPerformanceReport();
      expect(report['totalQueries'], 4);
      expect(report['cacheHits'], 1);
      expect(report['cacheHitRate'], '25.00%');
    });

    test('avgTime should handle query stats correctly', () {
      service.recordQueryStats('DELETE', 100);
      final report = service.getQueryPerformanceReport();
      expect(report['queryTypes']['DELETE']['avgTime'], '100.00ms');
    });
  });
}
