part of '../media_reference_service.dart';

class ReferenceSnapshot {
  final Map<String, Map<String, Set<String>>> storedIndex;
  final Map<String, Map<String, Set<String>>> quoteIndex;

  const ReferenceSnapshot({
    required this.storedIndex,
    required this.quoteIndex,
  });
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
