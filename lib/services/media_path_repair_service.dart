import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/quote_model.dart';
import '../utils/app_logger.dart';
import '../utils/media_path_resolver.dart';
import 'database_service.dart';
import 'media_reference_service.dart';
import 'mmkv_service.dart';

/// 笔记媒体路径存量修复。
///
/// 笔记 Delta 里保存的是媒体文件绝对路径，而应用文档目录会在下列场景发生变化：
///
/// - 从其它设备同步/恢复笔记（WebDAV、局域网同步、备份还原）；
/// - iOS 重装或从设备备份恢复后容器 UUID 变化。
///
/// 这两种情况都会让老笔记里的路径指向本机不存在的目录：图片渲染不出来，
/// 媒体引用表也匹配不上，WebDAV 因此认为云端附件"无人引用"而不下载。
/// 本服务负责把这些失效路径重新指向本机 `media/` 目录，并重建媒体引用。
class MediaPathRepairService {
  const MediaPathRepairService._();

  /// 记录上次运行时的应用文档目录，用于发现 iOS 容器路径变化。
  static const String baseDirKey = 'media_path_base_dir';

  static const int _pageSize = 200;

  /// 应用文档目录相对上次运行发生变化时执行一次修复。
  ///
  /// 首次运行（没有历史记录）同样会扫描一次：老用户的库里可能已经存在从其它
  /// 设备同步进来的失效路径。之后每次启动只是一次 MMKV 读取，命中即返回。
  static Future<MediaPathRepairReport> repairIfBaseDirChanged({
    Database? database,
    MMKVService? mmkvService,
    String? appPath,
  }) async {
    try {
      final mmkv = mmkvService ?? MMKVService();
      await mmkv.init();

      final currentPath = p.normalize(
        appPath ?? (await getApplicationDocumentsDirectory()).path,
      );
      final lastPath = mmkv.getString(baseDirKey);

      if (lastPath == currentPath) {
        return const MediaPathRepairReport.skipped();
      }

      logInfo(
        lastPath == null || lastPath.isEmpty
            ? '首次检查笔记媒体路径基准目录，执行一次存量修复'
            : '检测到应用文档目录变化，开始修复笔记媒体路径（可能来自重装或系统备份恢复）',
        source: 'MediaPathRepairService',
      );

      final report = await repairAllQuotes(
        database: database,
        appPath: currentPath,
      );
      // 修复失败时不推进水位线，下次启动会重试。
      if (!report.hasErrors) {
        await mmkv.setString(baseDirKey, currentPath);
      }
      return report;
    } catch (e, stack) {
      // 启动路径上的可选修复，失败不能拖垮数据库初始化。
      logError(
        '媒体路径基准目录检查失败',
        error: e,
        stackTrace: stack,
        source: 'MediaPathRepairService',
      );
      return const MediaPathRepairReport.skipped();
    }
  }

  /// 扫描全部笔记，把指向其它设备/旧容器的媒体路径重定基到本机文档目录。
  ///
  /// 被改写的笔记会在同一个事务里重建媒体引用，让 WebDAV 的
  /// "云端附件是否被引用"判断能命中。
  ///
  /// 全程只使用传入的 [Database] 句柄，不经过 `DatabaseService` 的查询接口：
  /// 本方法会在数据库初始化过程中被调用，走查询接口会等待尚未完成的初始化。
  static Future<MediaPathRepairReport> repairAllQuotes({
    Database? database,
    String? appPath,
  }) async {
    final db = database ?? DatabaseService().database;
    final basePath =
        p.normalize(appPath ?? (await getApplicationDocumentsDirectory()).path);

    final stopwatch = Stopwatch()..start();
    int scanned = 0;
    int repaired = 0;
    final errors = <String>[];

    try {
      var offset = 0;
      while (true) {
        // 只取含 media 片段的笔记，避免纯文本笔记参与 JSON 解析。
        final rows = await db.rawQuery(
          "SELECT id, content, date, delta_content FROM quotes "
          "WHERE delta_content IS NOT NULL AND delta_content LIKE '%media%' "
          "ORDER BY id LIMIT ? OFFSET ?",
          [_pageSize, offset],
        );
        if (rows.isEmpty) break;

        final updates = <String, String>{};
        final repairedQuotes = <Quote>[];
        for (final row in rows) {
          scanned++;
          final id = row['id'] as String?;
          final deltaContent = row['delta_content'] as String?;
          if (id == null || deltaContent == null || deltaContent.isEmpty) {
            continue;
          }

          try {
            final result = MediaPathResolver.rebaseDelta(
              json.decode(deltaContent),
              basePath,
            );
            if (!result.changed) continue;

            final rebasedDelta = json.encode(result.delta);
            updates[id] = rebasedDelta;
            repairedQuotes.add(
              Quote(
                id: id,
                content: (row['content'] as String?) ?? '',
                date: (row['date'] as String?) ?? '',
                deltaContent: rebasedDelta,
              ),
            );
          } catch (e) {
            // 单条笔记解析失败不应中断整体修复，但也绝不静默。
            errors.add('笔记 $id 媒体路径修复失败: $e');
            logWarning('笔记 $id 媒体路径修复失败: $e', source: 'MediaPathRepairService');
          }
        }

        if (updates.isNotEmpty) {
          try {
            await db.transaction((txn) async {
              final batch = txn.batch();
              for (final entry in updates.entries) {
                batch.update(
                  'quotes',
                  {'delta_content': entry.value},
                  where: 'id = ?',
                  whereArgs: [entry.key],
                );
              }
              await batch.commit(noResult: true);

              // 引用表里存的是旧路径，必须按修复后的 Delta 重建，
              // 否则 WebDAV 仍会因为引用计数为 0 而跳过附件下载。
              for (final quote in repairedQuotes) {
                final rebuilt = await MediaReferenceService
                    .syncQuoteMediaReferencesWithTransaction(
                  txn,
                  quote,
                  cachedAppPath: basePath,
                );
                // 引用重建失败必须让整页回滚：若保留已重定基的 Delta 而只丢掉引用，
                // 下次重试时 rebaseDelta 会判定"无需改写"，这些引用将永远补不回来，
                // WebDAV 也就永远不会下载对应附件。
                if (!rebuilt) {
                  throw _MediaReferenceRebuildFailure(quote.id ?? '(未知ID)');
                }
              }
            });
            repaired += updates.length;
          } on _MediaReferenceRebuildFailure catch (e) {
            errors.add('笔记 ${e.quoteId} 媒体引用重建失败，本页修复已回滚');
            logWarning(
              '笔记 ${e.quoteId} 媒体引用重建失败，本页 ${updates.length} 条修复已回滚，将在下次启动重试',
              source: 'MediaPathRepairService',
            );
          }
        }

        offset += rows.length;
        if (rows.length < _pageSize) break;
      }

      if (repaired > 0) {
        logInfo(
          '媒体路径修复完成：扫描 $scanned 条笔记，重写 $repaired 条，'
          '耗时 ${stopwatch.elapsedMilliseconds}ms',
          source: 'MediaPathRepairService',
        );
      } else {
        logDebug(
          '媒体路径修复完成：扫描 $scanned 条笔记，无需重写，'
          '耗时 ${stopwatch.elapsedMilliseconds}ms',
          source: 'MediaPathRepairService',
        );
      }
    } catch (e, stack) {
      errors.add('媒体路径修复过程失败: $e');
      logError(
        '媒体路径修复过程失败',
        error: e,
        stackTrace: stack,
        source: 'MediaPathRepairService',
      );
    }

    return MediaPathRepairReport(
      scanned: scanned,
      repaired: repaired,
      errors: errors,
    );
  }
}

/// 媒体引用重建失败的内部信号，用于回滚当前批次的 Delta 改写。
class _MediaReferenceRebuildFailure implements Exception {
  const _MediaReferenceRebuildFailure(this.quoteId);

  final String quoteId;

  @override
  String toString() => '媒体引用重建失败: $quoteId';
}

/// 一次媒体路径修复的结果。
class MediaPathRepairReport {
  const MediaPathRepairReport({
    required this.scanned,
    required this.repaired,
    this.errors = const [],
  });

  const MediaPathRepairReport.skipped()
      : scanned = 0,
        repaired = 0,
        errors = const [];

  final int scanned;
  final int repaired;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
}
