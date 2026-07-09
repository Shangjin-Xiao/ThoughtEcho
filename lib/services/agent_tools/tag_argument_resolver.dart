import '../database_service.dart';

class ResolvedTagArguments {
  const ResolvedTagArguments({
    required this.ids,
    required this.names,
    this.errorMessage,
  });

  final List<String> ids;
  final List<String> names;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
}

Future<ResolvedTagArguments> resolveTagArguments(
  DatabaseService databaseService,
  Map<String, Object?> arguments,
) async {
  final categories = await databaseService.getCategories();
  final visibleCategories =
      categories.where((tag) => tag.id != DatabaseService.hiddenTagId).toList();

  final idToName = <String, String>{
    for (final tag in visibleCategories) tag.id: tag.name,
  };
  final nameToIds = <String, List<String>>{};
  for (final tag in visibleCategories) {
    final name = tag.name.trim();
    if (name.isEmpty) continue;
    nameToIds.putIfAbsent(name, () => <String>[]).add(tag.id);
  }

  final rawNames = arguments['tag_names'];
  final requestedNames = rawNames is List
      ? rawNames
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList()
      : <String>[];

  final rawIds = arguments['tag_ids'];
  final requestedIds = rawIds is List
      ? rawIds
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList()
      : <String>[];

  final resolvedIds = <String>[];
  final resolvedNames = <String>[];
  final unknownNames = <String>[];
  final unknownIds = <String>[];
  final ambiguousNames = <String>[];

  for (final id in requestedIds) {
    final name = idToName[id];
    if (name == null) {
      unknownIds.add(id);
      continue;
    }
    if (!resolvedIds.contains(id)) {
      resolvedIds.add(id);
      resolvedNames.add(name);
    }
  }

  for (final name in requestedNames) {
    final ids = nameToIds[name] ?? const <String>[];
    if (ids.length > 1) {
      ambiguousNames.add(name);
      continue;
    }
    final id = ids.isEmpty ? null : ids.single;
    if (id == null) {
      unknownNames.add(name);
      continue;
    }
    if (!resolvedIds.contains(id)) {
      resolvedIds.add(id);
      resolvedNames.add(name);
    }
  }

  if (ambiguousNames.isNotEmpty ||
      unknownNames.isNotEmpty ||
      unknownIds.isNotEmpty) {
    final parts = <String>[
      if (ambiguousNames.isNotEmpty)
        '标签名称不唯一，请改用标签 ID：${ambiguousNames.join(', ')}',
      if (unknownNames.isNotEmpty) '不存在的标签名称：${unknownNames.join(', ')}',
      if (unknownIds.isNotEmpty) '不存在的标签 ID：${unknownIds.join(', ')}',
    ];
    return ResolvedTagArguments(
      ids: const <String>[],
      names: const <String>[],
      errorMessage: parts.join('；'),
    );
  }

  return ResolvedTagArguments(ids: resolvedIds, names: resolvedNames);
}
