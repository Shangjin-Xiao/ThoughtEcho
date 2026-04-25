part of '../media_reference_service.dart';

/// 检测孤儿文件（没有被任何笔记引用的文件）
Future<List<String>> _detectOrphanFiles() async {
  try {
    final plan = await _planOrphanCleanupStreamed();
    logDebug(
      '检测到 ${plan.candidates.length} 个孤儿文件，待修复引用 ${plan.missingReferencePairs} 条',
    );
    return plan.candidates.map((c) => c.absolutePath).toList();
  } catch (e) {
    logDebug('检测孤儿文件失败: $e');
    return [];
  }
}

/// 清理孤儿文件
Future<int> _cleanupOrphanFiles({bool dryRun = false}) async {
  try {
    final plan = await _planOrphanCleanupStreamed();

    if (plan.missingReferencePairs > 0) {
      if (dryRun) {
        logDebug('检测到 ${plan.missingReferencePairs} 条缺失的引用记录，实际执行时将自动修复');
      } else {
        final healed = await _healMissingReferences(
          plan.missingReferenceIndex,
        );
        if (healed > 0) {
          logDebug('已自动修复 $healed 条缺失的媒体引用记录');
        }
      }
    }

    if (plan.candidates.isEmpty) {
      logDebug('${dryRun ? '模拟' : '实际'}清理完成：未发现孤儿文件');
      return 0;
    }

    int cleanedCount = 0;

    if (dryRun) {
      for (final candidate in plan.candidates) {
        logDebug('(模拟) 将删除孤儿文件: ${candidate.absolutePath}');
      }
      cleanedCount = plan.candidates.length;
    } else {
      for (final candidate in plan.candidates) {
        try {
          final file = File(candidate.absolutePath);
          if (await file.exists()) {
            await file.delete();
            cleanedCount++;
            logDebug('已删除孤儿文件: ${candidate.absolutePath}');
          }
        } catch (e) {
          logDebug('删除孤儿文件失败: ${candidate.absolutePath}, 错误: $e');
        }
      }
    }

    logDebug('${dryRun ? '模拟' : '实际'}清理完成，共处理 $cleanedCount 个孤儿文件');
    return cleanedCount;
  } catch (e) {
    logDebug('清理孤儿文件失败: $e');
    return 0;
  }
}

// ignore: unused_element
Future<_CleanupPlan> _planOrphanCleanup() async {
  final snapshot = await _buildReferenceSnapshot();
  final allMediaFiles = await _getAllMediaFiles();

  final candidates = <_OrphanCandidate>[];
  final missingReferences = <String, Map<String, Set<String>>>{};

  // 获取应用目录路径缓存
  final appDir = await getApplicationDocumentsDirectory();
  final appPath = path.normalize(appDir.path);

  for (final filePath in allMediaFiles) {
    final normalizedPath = await _normalizeFilePath(
      filePath,
      cachedAppPath: appPath,
    );
    final canonicalKey = _canonicalComparisonKey(normalizedPath);

    final storedVariants = snapshot.storedIndex[canonicalKey];
    final quoteVariants = snapshot.quoteIndex[canonicalKey];

    final hasStoredRefs = storedVariants != null &&
        storedVariants.values.any((refs) => refs.isNotEmpty);
    final hasQuoteRefs = quoteVariants != null &&
        quoteVariants.values.any((refs) => refs.isNotEmpty);

    if (hasQuoteRefs) {
      final variants = quoteVariants;
      if (!hasStoredRefs) {
        missingReferences[canonicalKey] = variants.map(
          (variantPath, ids) => MapEntry(variantPath, Set<String>.from(ids)),
        );
      }
      continue;
    }

    if (hasStoredRefs) {
      continue;
    }

    candidates.add(
      _OrphanCandidate(
        absolutePath: filePath,
        normalizedPath: normalizedPath,
        canonicalKey: canonicalKey,
      ),
    );
  }

  return _CleanupPlan(
    candidates: candidates,
    missingReferenceIndex: missingReferences,
  );
}

/// 迭代式构建清理计划，避免一次性加载所有笔记
Future<_CleanupPlan> _planOrphanCleanupStreamed() async {
  final storedIndex = await _fetchStoredReferenceIndex();
  final quoteIndex = await _collectQuoteReferenceIndexStreamed();
  final snapshot =
      ReferenceSnapshot(storedIndex: storedIndex, quoteIndex: quoteIndex);
  final allMediaFiles = await _getAllMediaFiles();
  final candidates = <_OrphanCandidate>[];
  final missingReferences = <String, Map<String, Set<String>>>{};

  // 获取应用目录路径缓存
  final appDir = await getApplicationDocumentsDirectory();
  final appPath = path.normalize(appDir.path);

  for (final filePath in allMediaFiles) {
    final normalizedPath = await _normalizeFilePath(
      filePath,
      cachedAppPath: appPath,
    );
    final canonicalKey = _canonicalComparisonKey(normalizedPath);

    final storedVariants = snapshot.storedIndex[canonicalKey];
    final quoteVariants = snapshot.quoteIndex[canonicalKey];

    final hasStoredRefs = storedVariants != null &&
        storedVariants.values.any((refs) => refs.isNotEmpty);
    final hasQuoteRefs = quoteVariants != null &&
        quoteVariants.values.any((refs) => refs.isNotEmpty);

    if (hasQuoteRefs) {
      final variants = quoteVariants;
      if (!hasStoredRefs) {
        missingReferences[canonicalKey] = variants.map(
          (variantPath, ids) => MapEntry(variantPath, Set<String>.from(ids)),
        );
      }
      continue;
    }

    if (hasStoredRefs) {
      continue;
    }

    candidates.add(
      _OrphanCandidate(
        absolutePath: filePath,
        normalizedPath: normalizedPath,
        canonicalKey: canonicalKey,
      ),
    );
  }

  return _CleanupPlan(
    candidates: candidates,
    missingReferenceIndex: missingReferences,
  );
}

/// 轻量级检查单个文件是否仍被引用（双重校验：引用表 + 笔记内容）
/// 返回 true 表示文件已被安全删除，false 表示文件仍被引用或删除失败
Future<bool> _quickCheckAndDeleteIfOrphan(
  String filePath, {
  String? cachedAppPath,
}) async {
  try {
    // 获取应用目录路径缓存
    final appPath = cachedAppPath ??
        path.normalize((await getApplicationDocumentsDirectory()).path);

    final normalizedPath = await _normalizeFilePath(
      filePath,
      cachedAppPath: appPath,
    );

    // 1. 优先查引用表（高性能）
    final refCount = await MediaReferenceService.getReferenceCount(
      normalizedPath,
      cachedAppPath: appPath,
    );
    if (refCount > 0) {
      return false; // 仍被引用，不删除
    }

    // 2. 二次确认：即使引用表说没有，也从笔记内容中全文搜索一次（防止引用表损坏/不同步导致的误删）
    // 注意：这步对于数据安全至关重要
    // 修复：搜索所有笔记（含回收站），避免误删仍可恢复笔记引用的媒体
    final dbService = DatabaseService();
    final quotesWithFile = await dbService.searchQuotesByContent(
      normalizedPath,
      includeDeleted: true,
    );

    if (quotesWithFile.isNotEmpty) {
      logDebug(
          '警告：文件 $filePath 在引用表中无记录，但在 ${quotesWithFile.length} 条笔记内容中发现引用。正在自动修复引用表并跳过删除。');
      // 自动修复逻辑：重建引用记录
      for (final quote in quotesWithFile) {
        if (quote.id != null) {
          await MediaReferenceService.addReference(
            normalizedPath,
            quote.id!,
            cachedAppPath: appPath,
          );
        }
      }
      return false;
    }

    // 引用计数为0且内容中未搜到，执行删除
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
      logDebug('已删除无引用文件: $filePath');
      return true;
    }

    return false;
  } catch (e) {
    logDebug('检查并删除文件失败: $filePath, 错误: $e');
    return false;
  }
}

/// 安全检查并清理单个媒体文件（使用快照机制，避免误删）
/// 返回 true 表示文件已被安全删除，false 表示文件仍被引用或删除失败
Future<bool> _safeCheckAndDeleteOrphan(
  String filePath, {
  String? cachedAppPath,
}) async {
  try {
    // 获取应用目录路径缓存
    final appPath = cachedAppPath ??
        path.normalize((await getApplicationDocumentsDirectory()).path);

    final snapshot = await _buildReferenceSnapshot();
    final normalizedPath = await _normalizeFilePath(
      filePath,
      cachedAppPath: appPath,
    );
    final canonicalKey = _canonicalComparisonKey(normalizedPath);

    final storedVariants = snapshot.storedIndex[canonicalKey];
    final quoteVariants = snapshot.quoteIndex[canonicalKey];

    final hasStoredRefs = storedVariants != null &&
        storedVariants.values.any((refs) => refs.isNotEmpty);
    final hasQuoteRefs = quoteVariants != null &&
        quoteVariants.values.any((refs) => refs.isNotEmpty);

    // 如果在笔记内容中找到引用，先尝试修复缺失的引用记录
    if (hasQuoteRefs) {
      final variants = quoteVariants;
      if (!hasStoredRefs) {
        logDebug('检测到文件 $filePath 在笔记中有引用但缺失引用记录，尝试修复...');
        for (final entry in variants.entries) {
          final variantPath = entry.key;
          for (final quoteId in entry.value) {
            await MediaReferenceService.addReference(
              variantPath,
              quoteId,
              cachedAppPath: appPath,
            );
          }
        }
        logDebug('已修复文件 $filePath 的引用记录');
      }
      // 文件仍被引用，不删除
      return false;
    }

    // 如果在引用表中有记录，不删除
    if (hasStoredRefs) {
      return false;
    }

    // 确认是孤儿文件，执行删除
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
      logDebug('安全删除孤儿文件: $filePath');
      return true;
    }

    return false;
  } catch (e) {
    logDebug('安全检查并删除文件失败: $filePath, 错误: $e');
    return false;
  }
}

class _CleanupPlan {
  final List<_OrphanCandidate> candidates;
  final Map<String, Map<String, Set<String>>> missingReferenceIndex;

  const _CleanupPlan({
    required this.candidates,
    required this.missingReferenceIndex,
  });

  int get missingReferencePairs {
    var total = 0;
    for (final variants in missingReferenceIndex.values) {
      for (final ids in variants.values) {
        total += ids.length;
      }
    }
    return total;
  }
}

class _OrphanCandidate {
  final String absolutePath;
  final String normalizedPath;
  final String canonicalKey;

  const _OrphanCandidate({
    required this.absolutePath,
    required this.normalizedPath,
    required this.canonicalKey,
  });
}
