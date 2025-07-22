import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtecho/utils/mmkv_ffi_fix.dart';
import 'package:thoughtecho/services/mmkv_service.dart';

void main() {
  group('SafeMMKV 32-bit Device Compatibility Tests', () {
    test('SafeMMKV should initialize successfully', () async {
      final safeMMKV = SafeMMKV();
      expect(() async => await safeMMKV.initialize(), returnsNormally);
    });

    test('MMKVService should handle initialization gracefully', () async {
      final mmkvService = MMKVService();
      
      // Should not throw exception during initialization
      expect(() async => await mmkvService.init(), returnsNormally);
    });

    test('Basic storage operations should work', () async {
      final safeMMKV = SafeMMKV();
      await safeMMKV.initialize();
      
      // Test string operations
      const testKey = 'test_key';
      const testValue = 'test_value';
      
      final setResult = await safeMMKV.setString(testKey, testValue);
      expect(setResult, isTrue);
      
      final getValue = safeMMKV.getString(testKey);
      expect(getValue, equals(testValue));
      
      // Test removal
      final removeResult = await safeMMKV.remove(testKey);
      expect(removeResult, isTrue);
      
      final getAfterRemove = safeMMKV.getString(testKey);
      expect(getAfterRemove, isNull);
    });

    test('Should handle different data types', () async {
      final safeMMKV = SafeMMKV();
      await safeMMKV.initialize();
      
      // Test int
      await safeMMKV.setInt('int_key', 42);
      expect(safeMMKV.getInt('int_key'), equals(42));
      
      // Test bool
      await safeMMKV.setBool('bool_key', true);
      expect(safeMMKV.getBool('bool_key'), isTrue);
      
      // Test double
      await safeMMKV.setDouble('double_key', 3.14);
      expect(safeMMKV.getDouble('double_key'), equals(3.14));
      
      // Test string list
      const testList = ['item1', 'item2', 'item3'];
      await safeMMKV.setStringList('list_key', testList);
      expect(safeMMKV.getStringList('list_key'), equals(testList));
    });

    test('Should handle large amounts of data gracefully on 32-bit devices', () async {
      final safeMMKV = SafeMMKV();
      await safeMMKV.initialize();
      
      // Test storing a moderately large string (simulating 32-bit memory constraints)
      final largeString = 'x' * 10000; // 10KB string
      const largeKey = 'large_key';
      
      final setResult = await safeMMKV.setString(largeKey, largeString);
      expect(setResult, isTrue);
      
      final getValue = safeMMKV.getString(largeKey);
      expect(getValue, equals(largeString));
      
      // Clean up
      await safeMMKV.remove(largeKey);
    });
  });
}