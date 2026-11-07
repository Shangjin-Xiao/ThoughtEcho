import 'dart:convert';
import 'dart:typed_data';
import 'platform_helper.dart';

/// Value types stored inside a Tencent MMKV v1.3.x data file.
enum MmkvValueType {
  string,
  stringList,
  boolValue,
  intValue,
  doubleValue,
  rawBytes,
}

/// Parsed metadata from an `mmkv.default.crc` companion file (`MMKVMetaInfo.hpp`).
class MmkvCrcMetaInfo {
  final int crcDigest;
  final int version;
  final int sequence;
  final int actualSize;
  final int lastActualSize;
  final int lastCrcDigest;
  final int flags;

  const MmkvCrcMetaInfo({
    required this.crcDigest,
    required this.version,
    required this.sequence,
    required this.actualSize,
    required this.lastActualSize,
    required this.lastCrcDigest,
    this.flags = 0,
  });

  /// True when MMKV meta flags indicate AES CFB-128 encryption is enabled.
  bool get isEncrypted => (flags & 0x01) != 0;

  Map<String, Object?> toJson() => {
        'crcDigest': crcDigest,
        'version': version,
        'sequence': sequence,
        'actualSize': actualSize,
        'lastActualSize': lastActualSize,
        'lastCrcDigest': lastCrcDigest,
        'flags': flags,
        'isEncrypted': isEncrypted,
      };
}

/// Result of parsing an MMKV binary file (`mmkv.default`) and optional `.crc` file.
class MmkvParseResult {
  final bool fileExists;
  final String filePath;
  final int fileByteLength;
  final int actualSize;
  final int? itemSizeHolder;
  final MmkvCrcMetaInfo? crcMeta;
  final int computedCrc32;
  final bool? crcMatched;
  final bool usedLastConfirmed;
  final Map<String, Object?> entries;
  final Map<String, Uint8List> rawEntries;
  final int totalRecordsRead;
  final int tombstoneRecordsRead;
  final List<String> warnings;
  final int parseDurationMicroseconds;

  const MmkvParseResult({
    required this.fileExists,
    required this.filePath,
    required this.fileByteLength,
    required this.actualSize,
    this.itemSizeHolder,
    this.crcMeta,
    required this.computedCrc32,
    required this.crcMatched,
    this.usedLastConfirmed = false,
    required this.entries,
    required this.rawEntries,
    this.totalRecordsRead = 0,
    this.tombstoneRecordsRead = 0,
    required this.warnings,
    required this.parseDurationMicroseconds,
  });

  factory MmkvParseResult.notFound(String filePath) {
    return MmkvParseResult(
      fileExists: false,
      filePath: filePath,
      fileByteLength: 0,
      actualSize: 0,
      itemSizeHolder: null,
      crcMeta: null,
      computedCrc32: 0,
      crcMatched: null,
      usedLastConfirmed: false,
      entries: const {},
      rawEntries: const {},
      totalRecordsRead: 0,
      tombstoneRecordsRead: 0,
      warnings: const [],
      parseDurationMicroseconds: 0,
    );
  }
}

/// Schema registry for ThoughtEcho's MMKV keys so pure-Dart binary parsing can
/// deterministically decode raw MMKV value bytes without ambiguity.
class MmkvKeySchema {
  static const Set<String> boolKeys = {
    // Core lifecycle & SettingsService flags
    'app_installed_v2',
    'app_upgraded_v2',
    'initial_database_setup_complete',
    'database_migration_complete',
    'mmkv_migration_complete',
    'kv_engine_migrated_v1',
    'ai_auto_enable_pending_v1',
    'agent_memory_enabled',
    'agent_memory_notice_shown',
    'dreaming_enabled',
    'dreaming_on_idle_enabled',
    'dreaming_after_insight_enabled',
    'dont_show_agent_experimental_notice',
    'sync_skip_confirm',
    'sync_default_include_media',
    'hasCompletedOnboarding',
    // AppTheme flags
    'use_custom_color',
    'use_dynamic_color',
    // WebDAV flags
    'webdav_enabled',
    'webdav_sync_on_launch',
    'webdav_sync_on_change',
    'webdav_sync_on_cellular',
    'webdav_sync_notes_only_on_cellular',
    'webdav_ignore_experimental_warning',
    // Clipboard, logging, smart push flags
    'enable_clipboard_monitoring',
    'clipboard_monitoring_enabled',
    'log_level_user_set',
    'smart_push_auto_start_granted',
    'smart_push_pico_ble_enabled',
    // Legacy / test keys
    'ai_legacy_migrated',
    'legacy_key_migrated',
    'encryption_status_checked',
    'secure_storage_accessible',
    'favorite_Enabled',
    'daily_quote_use_offline',
    'first_open_skip_confirm',
    'report_skip_warning',
    'pref_show_favorite_button',
    'pref_prioritize_bold_content',
    'pref_use_local_quotes_only',
    'hitokoto_include_400',
    'skip_non_exact_alarm_Check',
    'has_reported_crashes',
    'first_launch',
    'onboarding_completed',
    'user_logged_in',
    'biometric_enabled',
    'auto_sync_enabled',
    'notification_enabled',
    'location_service_enabled',
    'analytics_enabled',
    'crash_reporting_enabled',
    'performance_monitoring_enabled',
    'beta_features_enabled',
    'developer_mode_enabled',
    'experimental_ui_enabled',
    'auto_backup_enabled',
    'ai_card_generation_enabled',
    'ai_insight_analysis_enabled',
    'ai_writing_assistant_enabled',
  };

  static const Set<String> intKeys = {
    'agent_memory_last_dreaming_at',
    'custom_color',
    'log_level',
    'sort_order',
    'report_reminder_threshold',
    'crash_log_max_file_size',
    'crash_log_max_files',
    'database_version',
    'migration_status',
    'last_sync_timestamp',
    'last_backup_timestamp',
  };

  static const Set<String> doubleKeys = {
    'font_scale',
  };

  static const Set<String> stringListKeys = {
    'app_logs',
    'crash_log_paths',
    'recent_searches',
    'favorite_tags',
    'pinned_notes',
  };

  static const Set<String> stringKeys = {
    // SettingsService JSON & strings
    'app_settings',
    'multi_ai_settings',
    'local_ai_settings',
    'ai_settings',
    'device_id_v1',
    'lastVersion',
    'last_seen_release_version',
    'explore_ai_assistant_mode',
    'explore_selected_period',
    'note_ai_assistant_mode',
    'user_nickname',
    'recent_cities_json_v1',
    // AppTheme strings
    'theme_mode',
    'theme_style',
    'theme_accent',
    'theme_accent_material',
    'theme_accent_paper',
    'theme_accent_plain',
    // WebDAV strings
    'webdav_provider',
    'webdav_url',
    'webdav_username',
    'webdav_last_sync_time',
    'webdav_last_sync_error',
    'webdav_sync_status',
    // Migration, media, & legacy secure storage strings
    'lastRunVersionBuildNumber',
    'media_path_base_dir',
    'provider_api_keys',
    // SmartPush strings & JSON
    'smart_push_settings_v2',
    'smart_push_settings',
    'smart_push_scheduled_times_today',
    'smart_push_today_pushed_date',
    'smart_push_today_pushed_note_ids',
    'smart_push_today_daily_quote_pushed',
    'smart_push_daily_quote_pushed_date',
    'smart_push_last_daily_quote',
    'smart_push_last_daily_quote_date',
    'smart_push_pending_home_daily_quote',
    'smart_push_app_open_times',
    'smart_push_notification_metrics',
    'smart_push_content_scores',
    'smart_push_last_dismissal',
    'smart_push_unengaged_streak',
    'smart_push_pending_send',
    'smart_push_daily_count',
    // Structured & cache JSON strings
    'periodic_insights_history',
    'geocode_cache',
    'weather_cache',
    'weather_cache_expiry',
    // Legacy / test keys
    'locale_code',
    'hitokoto_type',
    'daily_quote_provider',
    'api Ninjas_categories',
    'app_version',
    'last_update_check',
    'backup_frequency',
    'backup_location',
    'ai_provider_selected',
    'ai_model_preference',
    'sync_device_id',
    'sync_device_name',
  };

  /// Returns the expected [MmkvValueType] for [key], or `null` if unknown.
  static MmkvValueType? typeForKey(String key) {
    final normalizedKey = key.startsWith('flutter.') ? key.substring(8) : key;

    if (boolKeys.contains(normalizedKey) ||
        normalizedKey.startsWith('feature_guide_shown_')) {
      return MmkvValueType.boolValue;
    }
    if (intKeys.contains(normalizedKey)) {
      return MmkvValueType.intValue;
    }
    if (doubleKeys.contains(normalizedKey)) {
      return MmkvValueType.doubleValue;
    }
    if (stringListKeys.contains(normalizedKey)) {
      return MmkvValueType.stringList;
    }
    if (stringKeys.contains(normalizedKey) ||
        normalizedKey.startsWith('draft_') ||
        normalizedKey.startsWith('theme_accent_') ||
        normalizedKey.startsWith('smart_push_') ||
        normalizedKey.startsWith('webdav_')) {
      return MmkvValueType.string;
    }
    return null;
  }
}

/// Pure-Dart reader for Tencent MMKV v1.3.x binary files (`mmkv.default` and `mmkv.default.crc`).
///
/// Mirrors the exact wire format implemented in Tencent MMKV C++ Core:
/// - `Core/MMKV_IO.cpp` (`loadFromFile`, `checkLoadCRC`, `memmoveDictionary`)
/// - `Core/MiniPBCoder.cpp` (`decodeOneMap`)
/// - `Core/CodedInputData.cpp` (`readRawVarint32`, `readInt64`, `readDouble`, `readData`)
/// - `Core/MMKVMetaInfo.hpp` (`MMKVMetaInfo::write` / `read`)
class MmkvBinaryReader {
  /// Standard IEEE 802.3 CRC32 lookup table (polynomial `0xEDB88320`).
  static final Uint32List _crc32Table = _buildCrc32Table();

  static Uint32List _buildCrc32Table() {
    final table = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        if ((c & 1) != 0) {
          c = 0xEDB88320 ^ (c >>> 1);
        } else {
          c = c >>> 1;
        }
      }
      table[i] = c;
    }
    return table;
  }

  /// Computes standard IEEE 802.3 CRC32 over `bytes[start..start+length]`.
  static int computeCrc32(Uint8List bytes, [int start = 0, int? length]) {
    final end = length != null ? (start + length) : bytes.length;
    if (start < 0 || end > bytes.length || start > end) {
      throw RangeError.range(end, start, bytes.length, 'length');
    }
    var crc = 0xFFFFFFFF;
    for (var i = start; i < end; i++) {
      final index = (crc ^ bytes[i]) & 0xFF;
      crc = (crc >>> 8) ^ _crc32Table[index];
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// Parses an `mmkv.default.crc` byte array (`MMKVMetaInfo.hpp`).
  static MmkvCrcMetaInfo? parseCrcBytes(Uint8List crcBytes) {
    if (crcBytes.length < 40) {
      return null;
    }
    final bd = ByteData.sublistView(crcBytes);
    final crcDigest = bd.getUint32(0, Endian.little);
    final version = bd.getUint32(4, Endian.little);
    final sequence = bd.getUint32(8, Endian.little);
    // Offset 12..27 is m_vector[16] (AES IV when encrypted)
    final actualSize = bd.getUint32(28, Endian.little);
    final lastActualSize = bd.getUint32(32, Endian.little);
    final lastCrcDigest = bd.getUint32(36, Endian.little);
    var flags = 0;
    if (crcBytes.length >= 112) {
      flags = bd.getUint64(104, Endian.little);
    }
    return MmkvCrcMetaInfo(
      crcDigest: crcDigest,
      version: version,
      sequence: sequence,
      actualSize: actualSize,
      lastActualSize: lastActualSize,
      lastCrcDigest: lastCrcDigest,
      flags: flags,
    );
  }

  /// Parses an `mmkv.default` file from disk along with its sibling `.crc` file if present.
  static Future<MmkvParseResult> parseFile(
    String mmkvFilePath, {
    String? crcFilePath,
  }) async {
    final dataBytes = await PlatformHelper.readFileBytesIfExists(mmkvFilePath);
    if (dataBytes == null) {
      return MmkvParseResult.notFound(mmkvFilePath);
    }

    final resolvedCrcPath = crcFilePath ?? '$mmkvFilePath.crc';
    final crcBytes =
        await PlatformHelper.readFileBytesIfExists(resolvedCrcPath);

    return parseBytes(
      dataBytes,
      crcBytes: crcBytes,
      filePath: mmkvFilePath,
    );
  }

  /// Parses an in-memory `mmkv.default` buffer and optional `mmkv.default.crc` buffer.
  static MmkvParseResult parseBytes(
    Uint8List dataBytes, {
    Uint8List? crcBytes,
    String filePath = '<memory>',
  }) {
    final stopwatch = Stopwatch()..start();
    final warnings = <String>[];

    if (dataBytes.length < 4) {
      stopwatch.stop();
      return MmkvParseResult(
        fileExists: true,
        filePath: filePath,
        fileByteLength: dataBytes.length,
        actualSize: 0,
        itemSizeHolder: null,
        crcMeta: crcBytes != null ? parseCrcBytes(crcBytes) : null,
        computedCrc32: 0,
        crcMatched: null,
        entries: const {},
        rawEntries: const {},
        warnings: [
          if (dataBytes.isNotEmpty)
            'MMKV file shorter than 4-byte header (${dataBytes.length} bytes)',
        ],
        parseDurationMicroseconds: stopwatch.elapsedMicroseconds,
      );
    }

    final bd = ByteData.sublistView(dataBytes);
    var actualSize = bd.getUint32(0, Endian.little);
    final crcMeta = crcBytes != null ? parseCrcBytes(crcBytes) : null;

    if (crcMeta != null && crcMeta.isEncrypted) {
      warnings.add(
        'MMKV CRC metadata indicates AES encryption is enabled (flags=${crcMeta.flags}); '
        'plaintext decoding may fail.',
      );
    }

    var usedLastConfirmed = false;
    bool? crcMatched;
    var computedCrc32 = 0;

    // Validate actualSize against physical file length (4-byte header + payload).
    if (actualSize > dataBytes.length - 4) {
      warnings.add(
        'Header actualSize ($actualSize) exceeds available payload (${dataBytes.length - 4} bytes).',
      );
      if (crcMeta != null &&
          crcMeta.lastActualSize <= dataBytes.length - 4 &&
          crcMeta.lastActualSize > 0) {
        actualSize = crcMeta.lastActualSize;
        usedLastConfirmed = true;
        warnings.add(
          'Fell back to crcMeta.lastActualSize ($actualSize bytes).',
        );
      } else {
        actualSize = dataBytes.length - 4;
      }
    }

    if (actualSize > 0) {
      computedCrc32 = computeCrc32(dataBytes, 4, actualSize);
      if (crcMeta != null) {
        if (!usedLastConfirmed && computedCrc32 == crcMeta.crcDigest) {
          crcMatched = true;
        } else if (usedLastConfirmed &&
            computedCrc32 == crcMeta.lastCrcDigest) {
          crcMatched = true;
        } else if (crcMeta.lastActualSize > 0 &&
            crcMeta.lastActualSize <= dataBytes.length - 4) {
          // Try falling back to lastActualSize / lastCrcDigest just like MMKV C++ checkLoadCRC()
          final fallbackCrc =
              computeCrc32(dataBytes, 4, crcMeta.lastActualSize);
          if (fallbackCrc == crcMeta.lastCrcDigest) {
            actualSize = crcMeta.lastActualSize;
            computedCrc32 = fallbackCrc;
            crcMatched = true;
            usedLastConfirmed = true;
            warnings.add(
              'Primary CRC32 mismatch; recovered using lastConfirmed (size=$actualSize).',
            );
          } else {
            crcMatched = false;
            warnings.add(
              'CRC32 mismatch: computed 0x${computedCrc32.toRadixString(16)} '
              'vs expected 0x${crcMeta.crcDigest.toRadixString(16)}.',
            );
          }
        } else {
          crcMatched = false;
          warnings.add(
            'CRC32 mismatch: computed 0x${computedCrc32.toRadixString(16)} '
            'vs expected 0x${crcMeta.crcDigest.toRadixString(16)}.',
          );
        }
      }
    } else if (crcMeta != null) {
      crcMatched = crcMeta.crcDigest == 0;
    }

    if (actualSize == 0) {
      stopwatch.stop();
      return MmkvParseResult(
        fileExists: true,
        filePath: filePath,
        fileByteLength: dataBytes.length,
        actualSize: 0,
        itemSizeHolder: null,
        crcMeta: crcMeta,
        computedCrc32: computedCrc32,
        crcMatched: crcMatched,
        usedLastConfirmed: usedLastConfirmed,
        entries: const {},
        rawEntries: const {},
        totalRecordsRead: 0,
        tombstoneRecordsRead: 0,
        warnings: warnings,
        parseDurationMicroseconds: stopwatch.elapsedMicroseconds,
      );
    }

    final reader = _CodedInputReader(dataBytes, 4, 4 + actualSize);
    int? itemSizeHolder;
    final rawMap = <String, Uint8List>{};
    var totalRecords = 0;
    var tombstoneRecords = 0;

    try {
      // At offset 4 (position == 0 of payload), MiniPBCoder::decodeOneMap()
      // unconditionally skips the container ItemSizeHolder varint32 (commonly 0x00ffffff).
      itemSizeHolder = reader.readRawVarint32();

      while (!reader.isAtEnd) {
        final recordStartOffset = reader.offset;
        final keyLen = reader.readRawVarint32();
        if (keyLen < 0 || keyLen > reader.remaining) {
          warnings.add(
            'Truncated key length ($keyLen) at byte offset $recordStartOffset; '
            'stopping sequential scan with ${rawMap.length} valid keys.',
          );
          break;
        }

        final keyBytes = reader.readBytes(keyLen);
        String key;
        try {
          key = utf8.decode(keyBytes);
        } on FormatException {
          warnings.add(
            'Invalid UTF-8 key at byte offset $recordStartOffset ($keyLen bytes); '
            'stopping scan.',
          );
          break;
        }

        if (reader.isAtEnd) {
          warnings.add(
            'Unexpected EOF after key "$key" at offset ${reader.offset}; stopping scan.',
          );
          break;
        }

        final valueLen = reader.readRawVarint32();
        if (valueLen < 0 || valueLen > reader.remaining) {
          warnings.add(
            'Truncated value length ($valueLen) for key "$key" at offset $recordStartOffset; '
            'stopping scan with ${rawMap.length} valid keys.',
          );
          break;
        }

        totalRecords++;
        if (valueLen == 0) {
          // Tombstone record (MMKV::removeValueForKey writes a 0-length value holder)
          if (key.isNotEmpty) {
            rawMap.remove(key);
          }
          tombstoneRecords++;
        } else {
          final valueBytes = reader.readBytes(valueLen);
          if (key.isNotEmpty) {
            rawMap[key] = valueBytes;
          }
        }
      }
    } on FormatException catch (e) {
      warnings.add(
        'Malformed varint while scanning MMKV payload at offset ${reader.offset}: ${e.message}. '
        'Recovered ${rawMap.length} keys prior to corruption.',
      );
    }

    final decodedEntries = <String, Object?>{};
    for (final entry in rawMap.entries) {
      try {
        decodedEntries[entry.key] = decodeValueForKey(
          entry.key,
          entry.value,
          warnings: warnings,
        );
      } catch (e) {
        warnings.add('Failed to decode value for key "${entry.key}": $e');
        decodedEntries[entry.key] = entry.value;
      }
    }

    stopwatch.stop();
    return MmkvParseResult(
      fileExists: true,
      filePath: filePath,
      fileByteLength: dataBytes.length,
      actualSize: actualSize,
      itemSizeHolder: itemSizeHolder,
      crcMeta: crcMeta,
      computedCrc32: computedCrc32,
      crcMatched: crcMatched,
      usedLastConfirmed: usedLastConfirmed,
      entries: decodedEntries,
      rawEntries: rawMap,
      totalRecordsRead: totalRecords,
      tombstoneRecordsRead: tombstoneRecords,
      warnings: warnings,
      parseDurationMicroseconds: stopwatch.elapsedMicroseconds,
    );
  }

  /// Decodes a single MMKV record's raw value bytes according to [MmkvKeySchema]
  /// or wire-format heuristics.
  ///
  /// Recall Tencent MMKV Flutter plugin encoding:
  /// - `encodeString` calls `encodeBytes` -> `MMKV::set(const MMBuffer&)` ->
  ///   `setDataForKey(..., isDataHolder = true)`. Thus the outer value wrapper
  ///   contains an inner `strByteLen = readRawVarint32()` followed by `strByteLen`
  ///   UTF-8 bytes! An empty string `""` has `rawValueBytes = [0x00]`.
  /// - `encodeBool`: `isDataHolder = false`, 1-byte varint (`0x00` or `0x01`).
  /// - `encodeInt`: `isDataHolder = false`, 64-bit Protobuf Varint (`readInt64()`).
  /// - `encodeDouble`: `isDataHolder = false`, 8-byte Little-Endian IEEE 754 float64.
  static Object? decodeValueForKey(
    String key,
    Uint8List rawValueBytes, {
    List<String>? warnings,
  }) {
    final schemaType = MmkvKeySchema.typeForKey(key);
    switch (schemaType) {
      case MmkvValueType.boolValue:
        return _decodeBool(rawValueBytes);
      case MmkvValueType.intValue:
        return _decodeInt64(rawValueBytes);
      case MmkvValueType.doubleValue:
        return _decodeDouble(rawValueBytes);
      case MmkvValueType.string:
        return _decodeString(rawValueBytes);
      case MmkvValueType.stringList:
        final str = _decodeString(rawValueBytes);
        return _tryDecodeStringList(str) ?? <String>[str];
      case MmkvValueType.rawBytes:
        return rawValueBytes;
      case null:
        return _decodeHeuristic(key, rawValueBytes, warnings: warnings);
    }
  }

  static bool _decodeBool(Uint8List rawBytes) {
    final reader = _CodedInputReader(rawBytes, 0, rawBytes.length);
    return reader.readRawVarint32() != 0;
  }

  static int _decodeInt64(Uint8List rawBytes) {
    final reader = _CodedInputReader(rawBytes, 0, rawBytes.length);
    return reader.readInt64();
  }

  static double _decodeDouble(Uint8List rawBytes) {
    if (rawBytes.length < 8) {
      throw FormatException(
        'Expected 8 bytes for IEEE 754 double, got ${rawBytes.length}',
      );
    }
    final bd = ByteData.sublistView(rawBytes, 0, 8);
    return bd.getFloat64(0, Endian.little);
  }

  static String _decodeString(Uint8List rawBytes) {
    final reader = _CodedInputReader(rawBytes, 0, rawBytes.length);
    final innerLen = reader.readRawVarint32();
    if (innerLen >= 0 && reader.remaining == innerLen) {
      final strBytes = reader.readBytes(innerLen);
      return utf8.decode(strBytes);
    }
    // Fallback if stored directly without inner length prefix
    return utf8.decode(rawBytes);
  }

  static List<String>? _tryDecodeStringList(String decodedStr) {
    final trimmed = decodedStr.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
      return null;
    }
    try {
      final decodedJson = json.decode(trimmed);
      if (decodedJson is List) {
        return decodedJson.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // Not a JSON array
    }
    return null;
  }

  static Object? _decodeHeuristic(
    String key,
    Uint8List rawBytes, {
    List<String>? warnings,
  }) {
    // 1. Check if rawBytes strictly matches `isDataHolder = true` (inner length varint + UTF-8 bytes)
    // For length >= 1 where innerLen > 0 (or innerLen == 0 when rawBytes == [0x00] and key looks string-like):
    try {
      final reader = _CodedInputReader(rawBytes, 0, rawBytes.length);
      final innerLen = reader.readRawVarint32();
      if (innerLen >= 0 && reader.remaining == innerLen) {
        if (innerLen > 0) {
          final strBytes = reader.readBytes(innerLen);
          final str = utf8.decode(strBytes);
          return str;
        }
      }
    } catch (_) {
      // Not an isDataHolder UTF-8 string
    }

    // 2. Single-byte 0x00 or 0x01 for boolean-like keys, or integer
    if (rawBytes.length == 1) {
      final byte = rawBytes[0];
      if ((byte == 0 || byte == 1) &&
          (key.contains('enabled') ||
              key.contains('skip') ||
              key.contains('migrated') ||
              key.contains('completed') ||
              key.contains('use_') ||
              key.startsWith('is_') ||
              key.startsWith('has_'))) {
        return byte != 0;
      }
      if (byte < 0x80) {
        return byte;
      }
    }

    // 3. Try decoding as 64-bit Protobuf Varint if all bytes form a single valid varint
    try {
      final reader = _CodedInputReader(rawBytes, 0, rawBytes.length);
      final intVal = reader.readInt64();
      if (reader.isAtEnd) {
        return intVal;
      }
    } catch (_) {
      // Not a varint
    }

    // 4. If 8 bytes, decode as IEEE 754 double
    if (rawBytes.length == 8) {
      return _decodeDouble(rawBytes);
    }

    warnings?.add(
      'Key "$key" (${rawBytes.length} bytes) did not match known schema; kept as raw bytes.',
    );
    return rawBytes;
  }
}

/// Low-level Protobuf varint / byte reader matching Tencent MMKV's `CodedInputData`.
class _CodedInputReader {
  final Uint8List _buffer;
  int _position;
  final int _limit;

  _CodedInputReader(this._buffer, int start, this._limit) : _position = start;

  bool get isAtEnd => _position >= _limit;
  int get offset => _position;
  int get remaining => _limit - _position;

  int _readRawByte() {
    if (_position >= _limit) {
      throw const FormatException('Truncated MMKV input buffer');
    }
    return _buffer[_position++];
  }

  /// Mirrors `CodedInputData::readRawVarint32()` in `Core/CodedInputData.cpp`.
  int readRawVarint32() {
    var tmp = _readRawByte();
    if (tmp < 0x80) {
      return tmp;
    }
    var result = tmp & 0x7f;
    tmp = _readRawByte();
    if (tmp < 0x80) {
      result |= tmp << 7;
    } else {
      result |= (tmp & 0x7f) << 7;
      tmp = _readRawByte();
      if (tmp < 0x80) {
        result |= tmp << 14;
      } else {
        result |= (tmp & 0x7f) << 14;
        tmp = _readRawByte();
        if (tmp < 0x80) {
          result |= tmp << 21;
        } else {
          result |= (tmp & 0x7f) << 21;
          tmp = _readRawByte();
          result |= (tmp & 0x0f) << 28;
          if (tmp >= 0x80) {
            // Discard upper 32 bits of negative 64-bit sign-extended varint32
            for (var i = 0; i < 5; i++) {
              final b = _readRawByte();
              if (b < 0x80) {
                return result.toSigned(32);
              }
            }
            throw const FormatException('Malformed varint32 in MMKV buffer');
          }
        }
      }
    }
    return result.toSigned(32);
  }

  /// Mirrors `CodedInputData::readInt64()` in `Core/CodedInputData.cpp`.
  int readInt64() {
    var shift = 0;
    var result = 0;
    while (shift < 64) {
      final b = _readRawByte();
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) {
        return result;
      }
      shift += 7;
    }
    throw const FormatException('Malformed varint64 in MMKV buffer');
  }

  Uint8List readBytes(int length) {
    if (length < 0 || _position + length > _limit) {
      throw FormatException(
        'Requested $length bytes at offset $_position, but only $remaining remain',
      );
    }
    final slice = Uint8List.sublistView(_buffer, _position, _position + length);
    _position += length;
    return slice;
  }
}

/// Binary encoder that produces byte-exact Tencent MMKV v1.3.x payloads and `.crc`
/// files for unit testing and diagnostic verification.
class MmkvBinaryEncoder {
  /// Default container size placeholder written at offset 4 by `MMKV_IO.cpp` (`0x00ffffff`).
  static const int defaultItemSizeHolder = 0x00FFFFFF;

  final BytesBuilder _payload = BytesBuilder(copy: false);

  MmkvBinaryEncoder({int itemSizeHolder = defaultItemSizeHolder}) {
    _writeRawVarint32(_payload, itemSizeHolder);
  }

  /// Appends a String or StringList entry (matching Flutter `MMKV.encodeString` -> `isDataHolder = true`).
  void writeString(String key, String value) {
    _writeKey(key);
    final utf8Bytes = utf8.encode(value);
    final innerHolder = BytesBuilder(copy: false);
    _writeRawVarint32(innerHolder, utf8Bytes.length);
    innerHolder.add(utf8Bytes);
    final wrappedBytes = innerHolder.toBytes();
    _writeRawVarint32(_payload, wrappedBytes.length);
    _payload.add(wrappedBytes);
  }

  /// Appends a boolean entry (`isDataHolder = false`, 1-byte varint).
  void writeBool(String key, bool value) {
    _writeKey(key);
    _writeRawVarint32(_payload, 1);
    _payload.addByte(value ? 1 : 0);
  }

  /// Appends a 64-bit integer entry (`isDataHolder = false`, Protobuf varint64).
  void writeInt(String key, int value) {
    _writeKey(key);
    final intHolder = BytesBuilder(copy: false);
    _writeRawVarint64(intHolder, value);
    final encodedInt = intHolder.toBytes();
    _writeRawVarint32(_payload, encodedInt.length);
    _payload.add(encodedInt);
  }

  /// Appends a 64-bit IEEE 754 float entry (`isDataHolder = false`, 8-byte Little-Endian).
  void writeDouble(String key, double value) {
    _writeKey(key);
    _writeRawVarint32(_payload, 8);
    final bd = ByteData(8)..setFloat64(0, value, Endian.little);
    _payload.add(bd.buffer.asUint8List());
  }

  /// Appends a tombstone deletion record (`valueWrapperLen = 0`) for [key].
  void writeTombstone(String key) {
    _writeKey(key);
    _writeRawVarint32(_payload, 0);
  }

  void _writeKey(String key) {
    final keyBytes = utf8.encode(key);
    _writeRawVarint32(_payload, keyBytes.length);
    _payload.add(keyBytes);
  }

  /// Builds the full `mmkv.default` file buffer (with optional page-aligned zero padding).
  Uint8List toFileBytes({int minTotalSize = 0}) {
    final payloadBytes = _payload.toBytes();
    final actualSize = payloadBytes.length;
    final totalSize =
        (4 + actualSize) < minTotalSize ? minTotalSize : (4 + actualSize);
    final out = Uint8List(totalSize);
    final bd = ByteData.sublistView(out);
    bd.setUint32(0, actualSize, Endian.little);
    out.setRange(4, 4 + actualSize, payloadBytes);
    return out;
  }

  /// Builds a matching `mmkv.default.crc` 4096-byte metadata buffer.
  Uint8List toCrcBytes({
    int version = 4,
    int sequence = 1,
    int? overrideCrcDigest,
    int? overrideActualSize,
    int? lastActualSize,
    int? lastCrcDigest,
    int flags = 0,
  }) {
    final payloadBytes = _payload.toBytes();
    final actualSize = overrideActualSize ?? payloadBytes.length;
    final crcDigest =
        overrideCrcDigest ?? MmkvBinaryReader.computeCrc32(payloadBytes);
    final out = Uint8List(128);
    final bd = ByteData.sublistView(out);
    bd.setUint32(0, crcDigest, Endian.little);
    bd.setUint32(4, version, Endian.little);
    bd.setUint32(8, sequence, Endian.little);
    bd.setUint32(28, actualSize, Endian.little);
    bd.setUint32(32, lastActualSize ?? actualSize, Endian.little);
    bd.setUint32(36, lastCrcDigest ?? crcDigest, Endian.little);
    bd.setUint64(104, flags, Endian.little);
    return out;
  }

  static void _writeRawVarint32(BytesBuilder builder, int value) {
    var v = value & 0xFFFFFFFF;
    while ((v & ~0x7F) != 0) {
      builder.addByte((v & 0x7F) | 0x80);
      v = v >>> 7;
    }
    builder.addByte(v & 0x7F);
  }

  static void _writeRawVarint64(BytesBuilder builder, int value) {
    var v = value;
    for (var i = 0; i < 9; i++) {
      if ((v & ~0x7F) == 0) {
        builder.addByte(v & 0x7F);
        return;
      }
      builder.addByte((v & 0x7F) | 0x80);
      v = v >>> 7;
    }
    builder.addByte(v & 0xFF);
  }
}
