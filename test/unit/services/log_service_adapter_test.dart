import 'package:flutter/widgets.dart';
import 'package:thoughtecho/services/log_service_adapter.dart';
import 'package:thoughtecho/services/unified_log_service.dart';
import 'package:thoughtecho/services/log_service.dart' as old_log;
import 'package:flutter_test/flutter_test.dart';

class ManualMockUnifiedLogService extends ChangeNotifier
    with WidgetsBindingObserver
    implements UnifiedLogService {
  final List<String> calls = [];
  final Map<String, dynamic> callArguments = {};

  @override
  List<old_log.LogEntry> get oldLogs {
    calls.add('oldLogs');
    return [];
  }

  @override
  old_log.LogLevel get oldCurrentLevel {
    calls.add('oldCurrentLevel');
    return old_log.LogLevel.info;
  }

  @override
  Future<void> setOldLogLevel(old_log.LogLevel newLevel) async {
    calls.add('setOldLogLevel');
    callArguments['setOldLogLevel'] = newLevel;
  }

  @override
  void log(
    UnifiedLogLevel level,
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    calls.add('log');
    callArguments['log'] = {
      'level': level,
      'message': message,
      'source': source,
      'error': error,
      'stackTrace': stackTrace,
    };
  }

  @override
  void verbose(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    calls.add('verbose');
    callArguments['verbose'] = {
      'message': message,
      'source': source,
      'error': error,
      'stackTrace': stackTrace,
    };
  }

  @override
  void debug(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    calls.add('debug');
    callArguments['debug'] = {
      'message': message,
      'source': source,
      'error': error,
      'stackTrace': stackTrace,
    };
  }

  @override
  void info(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    calls.add('info');
    callArguments['info'] = {
      'message': message,
      'source': source,
      'error': error,
      'stackTrace': stackTrace,
    };
  }

  @override
  void warning(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    calls.add('warning');
    callArguments['warning'] = {
      'message': message,
      'source': source,
      'error': error,
      'stackTrace': stackTrace,
    };
  }

  @override
  void error(
    String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  }) {
    calls.add('error');
    callArguments['error'] = {
      'message': message,
      'source': source,
      'error': error,
      'stackTrace': stackTrace,
    };
  }

  @override
  void clearMemoryLogs() {
    calls.add('clearMemoryLogs');
  }

  @override
  Future<void> clearAllLogs() async {
    calls.add('clearAllLogs');
  }

  @override
  Future<List<old_log.LogEntry>> queryOldLogs({
    old_log.LogLevel? level,
    String? searchText,
    String? source,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
    int offset = 0,
  }) async {
    calls.add('queryOldLogs');
    callArguments['queryOldLogs'] = {
      'level': level,
      'searchText': searchText,
      'source': source,
      'startDate': startDate,
      'endDate': endDate,
      'limit': limit,
      'offset': offset,
    };
    return [];
  }

  @override
  void addListener(VoidCallback listener) {
    calls.add('addListener');
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    calls.add('removeListener');
    super.removeListener(listener);
  }

  @override
  bool get hasListeners {
    calls.add('hasListeners');
    return super.hasListeners;
  }

  @override
  void notifyListeners() {
    calls.add('notifyListeners');
    super.notifyListeners();
  }

  @override
  void dispose() {
    calls.add('dispose');
    super.dispose();
  }

  // UnifiedLogService specific methods that we don't need for the adapter tests
  // but must implement because of the interface
  @override
  UnifiedLogLevel get currentLevel => UnifiedLogLevel.info;
  @override
  DateTime? get lastLogTime => null;
  @override
  Map<UnifiedLogLevel, int> get logStats => {};
  @override
  List<LogEntry> get logs => [];
  @override
  bool get isPersistenceEnabled => false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
  @override
  Future<void> flushLogs() async {}
  @override
  Map<String, dynamic> getLogSummary() => {};
  @override
  Future<Map<String, dynamic>> getDatabaseStatus() async => {};
  @override
  void resetLogStats() {}
  @override
  void setPersistenceEnabled(bool enabled) {}
  @override
  void registerGlobalErrorHandlers() {}
  @override
  Map<String, dynamic> getPerformanceStats() => {};
  @override
  void resetPerformanceStats() {}
  @override
  Future<void> exportLogsToFile(
    dynamic file, {
    UnifiedLogLevel? minLevel,
    DateTime? startDate,
    DateTime? endDate,
  }) async {}
  @override
  String exportLogsAsText({
    UnifiedLogLevel? minLevel,
    DateTime? startDate,
    DateTime? endDate,
  }) => '';

  @override
  Future<List<LogEntry>> queryLogs({
    UnifiedLogLevel? level,
    String? searchText,
    String? source,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 100,
    int offset = 0,
  }) async {
    return [];
  }

  @override
  Future<void> setLogLevel(UnifiedLogLevel newLevel) async {}
}

void main() {
  late LogServiceAdapter adapter;
  late ManualMockUnifiedLogService mockUnifiedService;

  setUp(() {
    mockUnifiedService = ManualMockUnifiedLogService();
    adapter = LogServiceAdapter(mockUnifiedService);
  });

  group('LogServiceAdapter', () {
    test('fromUnified factory creates an instance', () {
      final factoryAdapter = LogServiceAdapter.fromUnified(mockUnifiedService);
      expect(factoryAdapter, isA<LogServiceAdapter>());
    });

    test('logs getter delegates to unifiedService.oldLogs', () {
      final result = adapter.logs;
      expect(result, isEmpty);
      expect(mockUnifiedService.calls.contains('oldLogs'), isTrue);
    });

    test('currentLevel getter delegates to unifiedService.oldCurrentLevel', () {
      final result = adapter.currentLevel;
      expect(result, old_log.LogLevel.info);
      expect(mockUnifiedService.calls.contains('oldCurrentLevel'), isTrue);
    });

    test('setLogLevel delegates to unifiedService.setOldLogLevel', () async {
      await adapter.setLogLevel(old_log.LogLevel.warning);
      expect(mockUnifiedService.calls.contains('setOldLogLevel'), isTrue);
      expect(
        mockUnifiedService.callArguments['setOldLogLevel'],
        old_log.LogLevel.warning,
      );
    });

    test('log method delegates to unifiedService.log with mapped level', () {
      adapter.log(
        old_log.LogLevel.error,
        'error message',
        source: 'test_source',
        error: 'test_error',
      );

      expect(mockUnifiedService.calls.contains('log'), isTrue);
      final args = mockUnifiedService.callArguments['log'];
      expect(args['level'], UnifiedLogLevel.error);
      expect(args['message'], 'error message');
      expect(args['source'], 'test_source');
      expect(args['error'], 'test_error');
    });

    test('verbose delegates to unifiedService.verbose', () {
      adapter.verbose('verbose message', source: 'src');
      expect(mockUnifiedService.calls.contains('verbose'), isTrue);
      final args = mockUnifiedService.callArguments['verbose'];
      expect(args['message'], 'verbose message');
      expect(args['source'], 'src');
    });

    test('debug delegates to unifiedService.debug', () {
      adapter.debug('debug message', source: 'src');
      expect(mockUnifiedService.calls.contains('debug'), isTrue);
      final args = mockUnifiedService.callArguments['debug'];
      expect(args['message'], 'debug message');
      expect(args['source'], 'src');
    });

    test('info delegates to unifiedService.info', () {
      adapter.info('info message', source: 'src');
      expect(mockUnifiedService.calls.contains('info'), isTrue);
      final args = mockUnifiedService.callArguments['info'];
      expect(args['message'], 'info message');
      expect(args['source'], 'src');
    });

    test('warning delegates to unifiedService.warning', () {
      adapter.warning('warning message', source: 'src');
      expect(mockUnifiedService.calls.contains('warning'), isTrue);
      final args = mockUnifiedService.callArguments['warning'];
      expect(args['message'], 'warning message');
      expect(args['source'], 'src');
    });

    test('error delegates to unifiedService.error', () {
      adapter.error('error message', source: 'src');
      expect(mockUnifiedService.calls.contains('error'), isTrue);
      final args = mockUnifiedService.callArguments['error'];
      expect(args['message'], 'error message');
      expect(args['source'], 'src');
    });

    test('clearMemoryLogs delegates to unifiedService.clearMemoryLogs', () {
      adapter.clearMemoryLogs();
      expect(mockUnifiedService.calls.contains('clearMemoryLogs'), isTrue);
    });

    test('clearAllLogs delegates to unifiedService.clearAllLogs', () async {
      await adapter.clearAllLogs();
      expect(mockUnifiedService.calls.contains('clearAllLogs'), isTrue);
    });

    test('queryLogs delegates to unifiedService.queryOldLogs', () async {
      final startDate = DateTime(2023, 1, 1);
      final endDate = DateTime(2023, 1, 2);

      await adapter.queryLogs(
        level: old_log.LogLevel.info,
        searchText: 'search',
        source: 'src',
        startDate: startDate,
        endDate: endDate,
        limit: 50,
        offset: 10,
      );

      expect(mockUnifiedService.calls.contains('queryOldLogs'), isTrue);
      final args = mockUnifiedService.callArguments['queryOldLogs'];
      expect(args['level'], old_log.LogLevel.info);
      expect(args['searchText'], 'search');
      expect(args['source'], 'src');
      expect(args['startDate'], startDate);
      expect(args['endDate'], endDate);
      expect(args['limit'], 50);
      expect(args['offset'], 10);
    });

    test('addListener delegates to unifiedService', () {
      void listener() {}
      adapter.addListener(listener);
      expect(mockUnifiedService.calls.contains('addListener'), isTrue);
    });

    test('removeListener delegates to unifiedService', () {
      void listener() {}
      adapter.removeListener(listener);
      expect(mockUnifiedService.calls.contains('removeListener'), isTrue);
    });

    test('hasListeners delegates to unifiedService', () {
      final _ = adapter.hasListeners;
      expect(mockUnifiedService.calls.contains('hasListeners'), isTrue);
    });

    test('notifyListeners delegates to unifiedService', () {
      adapter.notifyListeners();
      expect(mockUnifiedService.calls.contains('notifyListeners'), isTrue);
    });

    test('dispose delegates to unifiedService', () {
      adapter.dispose();
      expect(mockUnifiedService.calls.contains('dispose'), isTrue);
    });
  });
}
