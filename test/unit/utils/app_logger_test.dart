import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/app_logger.dart';
import 'package:thoughtecho/services/unified_log_service.dart';

class FakeUnifiedLogService implements UnifiedLogService {
  final List<Map<String, dynamic>> logRecords = [];

  @override
  void verbose(String message,
      {String? source, Object? error, StackTrace? stackTrace}) {
    log(UnifiedLogLevel.verbose, message,
        source: source, error: error, stackTrace: stackTrace);
  }

  @override
  void debug(String message,
      {String? source, Object? error, StackTrace? stackTrace}) {
    log(UnifiedLogLevel.debug, message,
        source: source, error: error, stackTrace: stackTrace);
  }

  @override
  void info(String message,
      {String? source, Object? error, StackTrace? stackTrace}) {
    log(UnifiedLogLevel.info, message,
        source: source, error: error, stackTrace: stackTrace);
  }

  @override
  void warning(String message,
      {String? source, Object? error, StackTrace? stackTrace}) {
    log(UnifiedLogLevel.warning, message,
        source: source, error: error, stackTrace: stackTrace);
  }

  @override
  void error(String message,
      {String? source, Object? error, StackTrace? stackTrace}) {
    log(UnifiedLogLevel.error, message,
        source: source, error: error, stackTrace: stackTrace);
  }

  @override
  void log(UnifiedLogLevel level, String message,
      {String? source, Object? error, StackTrace? stackTrace}) {
    logRecords.add({
      'level': level,
      'message': message,
      'source': source,
      'error': error,
      'stackTrace': stackTrace,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AppLogger Test', () {
    late FakeUnifiedLogService fakeService;

    setUp(() {
      fakeService = FakeUnifiedLogService();
      AppLogger.serviceForTesting = fakeService;
    });

    test('AppLogger methods route to UnifiedLogService correctly', () {
      AppLogger.v('verbose msg', source: 'src_v');
      AppLogger.d('debug msg', source: 'src_d');
      AppLogger.i('info msg', source: 'src_i');
      AppLogger.w('warning msg', source: 'src_w');
      AppLogger.e('error msg', source: 'src_e');
      AppLogger.log(UnifiedLogLevel.info, 'log msg', source: 'src_l');

      expect(fakeService.logRecords.length, 6);

      expect(fakeService.logRecords[0]['level'], UnifiedLogLevel.verbose);
      expect(fakeService.logRecords[0]['message'], 'verbose msg');
      expect(fakeService.logRecords[0]['source'], 'src_v');

      expect(fakeService.logRecords[1]['level'], UnifiedLogLevel.debug);
      expect(fakeService.logRecords[1]['message'], 'debug msg');
      expect(fakeService.logRecords[1]['source'], 'src_d');

      expect(fakeService.logRecords[2]['level'], UnifiedLogLevel.info);
      expect(fakeService.logRecords[2]['message'], 'info msg');
      expect(fakeService.logRecords[2]['source'], 'src_i');

      expect(fakeService.logRecords[3]['level'], UnifiedLogLevel.warning);
      expect(fakeService.logRecords[3]['message'], 'warning msg');
      expect(fakeService.logRecords[3]['source'], 'src_w');

      expect(fakeService.logRecords[4]['level'], UnifiedLogLevel.error);
      expect(fakeService.logRecords[4]['message'], 'error msg');
      expect(fakeService.logRecords[4]['source'], 'src_e');

      expect(fakeService.logRecords[5]['level'], UnifiedLogLevel.info);
      expect(fakeService.logRecords[5]['message'], 'log msg');
      expect(fakeService.logRecords[5]['source'], 'src_l');
    });

    test('Global logging functions route correctly', () {
      appLog('appLog msg', level: UnifiedLogLevel.warning, source: 'src_app');
      logDebug('logDebug msg', source: 'src_dbg');
      logError('logError msg', source: 'src_err');
      logInfo('logInfo msg', source: 'src_inf');
      logWarning('logWarning msg', source: 'src_wrn');

      expect(fakeService.logRecords.length, 5);

      expect(fakeService.logRecords[0]['level'], UnifiedLogLevel.warning);
      expect(fakeService.logRecords[0]['message'], 'appLog msg');

      expect(fakeService.logRecords[1]['level'], UnifiedLogLevel.debug);
      expect(fakeService.logRecords[1]['message'], 'logDebug msg');

      expect(fakeService.logRecords[2]['level'], UnifiedLogLevel.error);
      expect(fakeService.logRecords[2]['message'], 'logError msg');

      expect(fakeService.logRecords[3]['level'], UnifiedLogLevel.info);
      expect(fakeService.logRecords[3]['message'], 'logInfo msg');

      expect(fakeService.logRecords[4]['level'], UnifiedLogLevel.warning);
      expect(fakeService.logRecords[4]['message'], 'logWarning msg');
    });

    test('logDebug ignores null or empty messages', () {
      logDebug(null);
      logDebug('');
      expect(fakeService.logRecords.length, 0);
    });

    test('Specific category logging functions route correctly', () {
      logHttp('http msg', source: 'custom_http');
      logRetry('retry msg');
      logAI('ai msg');
      logDio('dio msg');
      logDatabase('db msg');
      logFile('file msg');
      logPerformance('perf msg');
      logUserAction('action msg');
      logSecurity('security msg');

      expect(fakeService.logRecords.length, 9);
      expect(fakeService.logRecords[0]['source'], 'custom_http');
      expect(fakeService.logRecords[1]['source'], 'RETRY');
      expect(fakeService.logRecords[2]['source'], 'AI');
      expect(fakeService.logRecords[3]['source'], 'DIO');
      expect(fakeService.logRecords[4]['source'], 'Database');
      expect(fakeService.logRecords[5]['source'], 'File');
      expect(fakeService.logRecords[6]['source'], 'Performance');
      expect(fakeService.logRecords[7]['source'], 'UserAction');
      expect(fakeService.logRecords[8]['source'], 'Security');
    });

    test('logConditional routes correctly based on condition', () {
      logConditional(false, 'false msg');
      expect(fakeService.logRecords.length, 0);

      logConditional(true, 'true msg',
          level: UnifiedLogLevel.warning, source: 'cond');
      expect(fakeService.logRecords.length, 1);
      expect(fakeService.logRecords[0]['level'], UnifiedLogLevel.warning);
      expect(fakeService.logRecords[0]['message'], 'true msg');
      expect(fakeService.logRecords[0]['source'], 'cond');
    });
  });
}
