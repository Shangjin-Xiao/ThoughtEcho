import 'dart:convert';
import 'dart:io';

/// Lightweight deterministic linter for ThoughtEcho repository conventions.
///
/// Enforces mechanical rules documented in `AGENTS.md` on newly added/modified
/// lines (or explicit files) using a pure-stdlib Dart lexical comment/string
/// stripper and balanced multiline expression/statement windows — without
/// spinning up the full Dart analyzer or requiring `pub get`.
///
/// Usage:
///   dart scripts/lint_repo_rules.dart                  # git diff HEAD
///   dart scripts/lint_repo_rules.dart --staged         # git diff --cached
///   dart scripts/lint_repo_rules.dart --base origin/main
///   dart scripts/lint_repo_rules.dart --files lib/pages/foo.dart
Future<void> main(List<String> args) async {
  try {
    final mode = _parseArgs(args);
    final scanPlan = await _buildScanPlan(mode);

    if (Platform.environment['CI'] != 'true') {
      await _checkGitHooksTip();
    }

    final violations = <String>[];
    final seenViolationKeys = <String>{};
    var totalCandidateLines = 0;

    for (final target in scanPlan.targets) {
      totalCandidateLines += target.addedLines.length;
      await _scanFileTarget(
        target,
        scanPlan,
        violations,
        seenViolationKeys,
      );
    }

    if (violations.isNotEmpty) {
      stderr.writeln(
        '❌ Found ${violations.length} repository rule violation(s):',
      );
      for (final v in violations) {
        stderr.writeln('  $v');
      }
      stderr.writeln(
        '\nSee AGENTS.md for approved alternatives, or append '
        '`// ignore: repo_lint` for a documented exception.',
      );
      exitCode = 1;
      return;
    }

    if (totalCandidateLines == 0) {
      stdout.writeln('✅ Repo rules check passed (0 candidate lines).');
      return;
    }

    stdout.writeln(
      '✅ Repo rules check passed ($totalCandidateLines lines inspected).',
    );
  } on _CliUsageException catch (e) {
    stderr.writeln('❌ Invalid arguments: ${e.message}');
    exitCode = 2;
  } on _GitCommandException catch (e) {
    stderr.writeln(
      '❌ Git command failed (exit code ${e.exitCode}): git ${e.args.join(' ')}',
    );
    if (e.stderrText.isNotEmpty) {
      stderr.writeln(e.stderrText);
    }
    exitCode = e.exitCode != 0 ? e.exitCode : 1;
  }
}

enum _ScanModeType { workingTree, staged, baseRef, explicitFiles }

class _ScanMode {
  final _ScanModeType type;
  final String? baseRef;
  final List<String> files;

  const _ScanMode({required this.type, this.baseRef, this.files = const []});
}

class _CliUsageException implements Exception {
  final String message;
  const _CliUsageException(this.message);
}

class _GitCommandException implements Exception {
  final List<String> args;
  final int exitCode;
  final String stderrText;

  const _GitCommandException({
    required this.args,
    required this.exitCode,
    required this.stderrText,
  });
}

enum _ContentSource { disk, stagedIndex, gitCommitRef }

class _FileScanTarget {
  /// Repository-root-relative path using forward slashes (e.g. `lib/pages/foo.dart`).
  final String repoPath;

  /// Absolute/resolvable disk path when reading from [disk].
  final String? diskPath;

  /// 1-indexed added/modified line numbers in the target revision.
  final Set<int> addedLines;

  /// Whether all lines are considered candidate lines (explicit `--files` mode).
  final bool fullFileScan;

  const _FileScanTarget({
    required this.repoPath,
    required this.addedLines,
    this.diskPath,
    this.fullFileScan = false,
  });
}

class _ScanPlan {
  final String repoRoot;
  final _ContentSource contentSource;
  final String? gitCommitRef;
  final List<_FileScanTarget> targets;

  const _ScanPlan({
    required this.repoRoot,
    required this.contentSource,
    required this.targets,
    this.gitCommitRef,
  });
}

_ScanMode _parseArgs(List<String> args) {
  if (args.isEmpty) {
    return const _ScanMode(type: _ScanModeType.workingTree);
  }
  if (args.length == 1 && args.first == '--staged') {
    return const _ScanMode(type: _ScanModeType.staged);
  }
  final baseIdx = args.indexOf('--base');
  if (baseIdx != -1) {
    if (baseIdx + 1 >= args.length) {
      throw const _CliUsageException(
          'Missing reference argument after --base.');
    }
    final ref = args[baseIdx + 1].trim();
    if (ref.isEmpty || ref.startsWith('-')) {
      throw _CliUsageException(
          'Invalid base reference: "${args[baseIdx + 1]}".');
    }
    if (args.length > 2) {
      throw const _CliUsageException(
        '--base accepts a single reference argument.',
      );
    }
    return _ScanMode(type: _ScanModeType.baseRef, baseRef: ref);
  }
  final filesIdx = args.indexOf('--files');
  if (filesIdx != -1) {
    final files = args
        .sublist(filesIdx + 1)
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();
    if (files.isEmpty) {
      throw const _CliUsageException('Missing file path(s) after --files.');
    }
    return _ScanMode(type: _ScanModeType.explicitFiles, files: files);
  }
  if (args.contains('--staged')) {
    throw const _CliUsageException(
        '--staged cannot be combined with other arguments.');
  }
  for (final arg in args) {
    if (arg.startsWith('-')) {
      throw _CliUsageException('Unknown option: "$arg".');
    }
  }
  return _ScanMode(
    type: _ScanModeType.explicitFiles,
    files: args.map((a) => a.trim()).where((a) => a.isNotEmpty).toList(),
  );
}

Future<String> _runGitOrFail(
  List<String> gitArgs, {
  String? workingDirectory,
}) async {
  final fullArgs = <String>['-c', 'core.quotePath=false', ...gitArgs];
  final ProcessResult result;
  try {
    result = await Process.run(
      'git',
      fullArgs,
      workingDirectory: workingDirectory,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException catch (e) {
    throw _GitCommandException(
      args: fullArgs,
      exitCode: 127,
      stderrText: e.message,
    );
  }
  if (result.exitCode != 0) {
    throw _GitCommandException(
      args: fullArgs,
      exitCode: result.exitCode,
      stderrText: (result.stderr as String).trim(),
    );
  }
  return result.stdout as String;
}

Future<String?> _tryResolveGitTopLevel() async {
  try {
    final out = await _runGitOrFail(['rev-parse', '--show-toplevel']);
    final trimmed = out.trim();
    return trimmed.isEmpty ? null : trimmed;
  } on _GitCommandException {
    return null;
  }
}

Future<_ScanPlan> _buildScanPlan(_ScanMode mode) async {
  switch (mode.type) {
    case _ScanModeType.explicitFiles:
      final topLevel = await _tryResolveGitTopLevel();
      final repoRoot = topLevel ?? Directory.current.absolute.path;
      final targets = <_FileScanTarget>[];
      for (final rawPath in mode.files) {
        final resolvedDiskFile = _resolveExplicitDiskFile(rawPath, repoRoot);
        if (!resolvedDiskFile.existsSync()) {
          throw _CliUsageException('File does not exist: "$rawPath".');
        }
        final repoPath = _normalizeRepoRelativePath(
          rawPath,
          repoRoot,
          existingFile: resolvedDiskFile,
        );
        Set<int> addedLines = const <int>{};
        if (repoPath.endsWith('.dart')) {
          final content = _normalizeLineEndings(
            await resolvedDiskFile.readAsString(),
          );
          final lineCount = content.isEmpty ? 0 : content.split('\n').length;
          addedLines = <int>{
            for (var i = 1; i <= lineCount; i++) i,
          };
        }
        targets.add(
          _FileScanTarget(
            repoPath: repoPath,
            diskPath: resolvedDiskFile.path,
            addedLines: addedLines,
            fullFileScan: true,
          ),
        );
      }
      return _ScanPlan(
        repoRoot: repoRoot,
        contentSource: _ContentSource.disk,
        targets: targets,
      );

    case _ScanModeType.staged:
      final repoRoot =
          (await _runGitOrFail(['rev-parse', '--show-toplevel'])).trim();
      final targets = await _collectGitDiffTargets(
        repoRoot: repoRoot,
        diffBaseArgs: const ['diff', '--cached', '--diff-filter=ACMR'],
      );
      return _ScanPlan(
        repoRoot: repoRoot,
        contentSource: _ContentSource.stagedIndex,
        targets: targets,
      );

    case _ScanModeType.baseRef:
      final repoRoot =
          (await _runGitOrFail(['rev-parse', '--show-toplevel'])).trim();
      final rawRef = mode.baseRef!;
      final String diffRange;
      final String targetCommit;
      if (rawRef.contains('...')) {
        diffRange = rawRef;
        final rhs = rawRef.split('...').last.trim();
        targetCommit = rhs.isEmpty ? 'HEAD' : rhs;
      } else if (rawRef.contains('..')) {
        diffRange = rawRef;
        final rhs = rawRef.split('..').last.trim();
        targetCommit = rhs.isEmpty ? 'HEAD' : rhs;
      } else {
        diffRange = '$rawRef...HEAD';
        targetCommit = 'HEAD';
      }
      final targets = await _collectGitDiffTargets(
        repoRoot: repoRoot,
        diffBaseArgs: ['diff', diffRange, '--diff-filter=ACMR'],
      );
      return _ScanPlan(
        repoRoot: repoRoot,
        contentSource: _ContentSource.gitCommitRef,
        gitCommitRef: targetCommit,
        targets: targets,
      );

    case _ScanModeType.workingTree:
      final repoRoot =
          (await _runGitOrFail(['rev-parse', '--show-toplevel'])).trim();
      final targets = await _collectGitDiffTargets(
        repoRoot: repoRoot,
        diffBaseArgs: const ['diff', 'HEAD', '--diff-filter=ACMR'],
      );
      return _ScanPlan(
        repoRoot: repoRoot,
        contentSource: _ContentSource.disk,
        targets: [
          for (final t in targets)
            _FileScanTarget(
              repoPath: t.repoPath,
              diskPath: '$repoRoot/${t.repoPath}',
              addedLines: t.addedLines,
            ),
        ],
      );
  }
}

File _resolveExplicitDiskFile(String rawPath, String repoRoot) {
  final direct = File(rawPath);
  if (direct.existsSync()) {
    return direct;
  }
  final normalizedRaw = rawPath.replaceAll('\\', '/');
  var stripped = normalizedRaw;
  while (stripped.startsWith('./')) {
    stripped = stripped.substring(2);
  }
  final fromRoot = File('$repoRoot/$stripped');
  if (fromRoot.existsSync()) {
    return fromRoot;
  }
  return direct;
}

String _normalizeRepoRelativePath(
  String rawPath,
  String repoRoot, {
  File? existingFile,
}) {
  final canonicalRoot = _tryResolveCanonicalDir(repoRoot);
  final absRoot = _cleanSlashes(
    Directory(repoRoot)
        .absolute
        .uri
        .normalizePath()
        .toFilePath(windows: Platform.isWindows),
  );

  if (existingFile != null && existingFile.existsSync()) {
    try {
      final canonicalFile =
          _cleanSlashes(existingFile.resolveSymbolicLinksSync());
      if (canonicalRoot != null &&
          canonicalFile.startsWith('$canonicalRoot/')) {
        return canonicalFile.substring(canonicalRoot.length + 1);
      }
    } catch (_) {}
  }

  final targetFile = existingFile ?? File(rawPath);
  final absFile = _cleanSlashes(
    targetFile.absolute.uri
        .normalizePath()
        .toFilePath(windows: Platform.isWindows),
  );
  if (absFile.startsWith('$absRoot/')) {
    return absFile.substring(absRoot.length + 1);
  }
  if (canonicalRoot != null && absFile.startsWith('$canonicalRoot/')) {
    return absFile.substring(canonicalRoot.length + 1);
  }

  var cleaned = _cleanSlashes(rawPath);
  while (cleaned.startsWith('./')) {
    cleaned = cleaned.substring(2);
  }
  return cleaned;
}

String? _tryResolveCanonicalDir(String dirPath) {
  try {
    final resolved = Directory(dirPath).resolveSymbolicLinksSync();
    return _cleanSlashes(resolved);
  } catch (_) {
    return null;
  }
}

String _cleanSlashes(String path) {
  var p = path.replaceAll('\\', '/');
  while (p.contains('//')) {
    p = p.replaceAll('//', '/');
  }
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

Future<List<_FileScanTarget>> _collectGitDiffTargets({
  required String repoRoot,
  required List<String> diffBaseArgs,
}) async {
  // 1. Obtain the unambiguous NUL-delimited list of added/copied/modified/renamed
  //    paths so paths containing spaces or ` b/` never produce bogus targets.
  final nameOnlyOutput = await _runGitOrFail(
    [...diffBaseArgs, '--name-only', '-z'],
    workingDirectory: repoRoot,
  );
  final addedLinesByFile = <String, Set<int>>{
    for (final rawName in nameOnlyOutput.split('\x00'))
      if (rawName.isNotEmpty) _cleanSlashes(rawName): <int>{},
  };
  if (addedLinesByFile.isEmpty) {
    return const <_FileScanTarget>[];
  }

  // 2. Collect 1-indexed added/modified line numbers from `--unified=0` hunks.
  final output = await _runGitOrFail(
    [...diffBaseArgs, '--unified=0'],
    workingDirectory: repoRoot,
  );

  String? currentFile;
  var currentNewLine = 0;
  var remainingOld = 0;
  var remainingNew = 0;

  final hunkHeader = RegExp(r'^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

  for (final raw in output.split('\n')) {
    final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;

    if (remainingOld > 0 || remainingNew > 0) {
      if (line.startsWith(r'\')) {
        continue;
      }
      if (line.startsWith('+') && remainingNew > 0) {
        if (currentFile != null) {
          addedLinesByFile[currentFile]!.add(currentNewLine);
        }
        currentNewLine++;
        remainingNew--;
        continue;
      }
      if (line.startsWith('-') && remainingOld > 0) {
        remainingOld--;
        continue;
      }
      if (line.startsWith(' ') && remainingOld > 0 && remainingNew > 0) {
        currentNewLine++;
        remainingOld--;
        remainingNew--;
        continue;
      }
      remainingOld = 0;
      remainingNew = 0;
    }

    if (line.startsWith('diff --git ')) {
      currentFile = null;
      continue;
    }
    if (line.startsWith('+++ ')) {
      final rhs = line.substring(4);
      if (rhs.trim() == '/dev/null') {
        currentFile = null;
      } else {
        final candidate = _cleanGitDiffPath(rhs);
        if (addedLinesByFile.containsKey(candidate)) {
          currentFile = candidate;
        } else {
          final trimmedCandidate = _cleanGitDiffPath(rhs.trim());
          currentFile = addedLinesByFile.containsKey(trimmedCandidate)
              ? trimmedCandidate
              : null;
        }
      }
      continue;
    }

    final hunkMatch = hunkHeader.firstMatch(line);
    if (hunkMatch != null) {
      remainingOld = int.parse(hunkMatch.group(1) ?? '1');
      currentNewLine = int.parse(hunkMatch.group(2)!);
      remainingNew = int.parse(hunkMatch.group(3) ?? '1');
      continue;
    }
  }

  return [
    for (final entry in addedLinesByFile.entries)
      _FileScanTarget(
        repoPath: entry.key,
        addedLines: entry.value,
      ),
  ];
}

String _cleanGitDiffPath(String raw) {
  // Git appends a trailing `\t` on `+++ b/<path>` headers when the path contains spaces.
  var value = raw.endsWith('\t') ? raw.substring(0, raw.length - 1) : raw;
  if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
    value = _unescapeGitQuotedString(value.substring(1, value.length - 1));
  }
  if (value.startsWith('b/')) {
    value = value.substring(2);
  }
  return _cleanSlashes(value);
}

String _unescapeGitQuotedString(String input) {
  final bytes = <int>[];
  var i = 0;
  while (i < input.length) {
    final ch = input.codeUnitAt(i);
    if (ch == 0x5C /* \ */ && i + 1 < input.length) {
      final next = input.codeUnitAt(i + 1);
      if (next >= 0x30 && next <= 0x37 && i + 3 < input.length) {
        final oct = input.substring(i + 1, i + 4);
        final parsed = int.tryParse(oct, radix: 8);
        if (parsed != null) {
          bytes.add(parsed);
          i += 4;
          continue;
        }
      }
      switch (next) {
        case 0x6E: // n
          bytes.add(0x0A);
          break;
        case 0x74: // t
          bytes.add(0x09);
          break;
        case 0x72: // r
          bytes.add(0x0D);
          break;
        case 0x5C: // \
          bytes.add(0x5C);
          break;
        case 0x22: // "
          bytes.add(0x22);
          break;
        default:
          bytes.add(next);
          break;
      }
      i += 2;
      continue;
    }
    bytes.addAll(utf8.encode(String.fromCharCode(ch)));
    i++;
  }
  return utf8.decode(bytes, allowMalformed: true);
}

Future<String> _readTargetContent(
  _FileScanTarget target,
  _ScanPlan plan,
) async {
  switch (plan.contentSource) {
    case _ContentSource.disk:
      final file =
          File(target.diskPath ?? '${plan.repoRoot}/${target.repoPath}');
      if (!file.existsSync()) return '';
      return _normalizeLineEndings(await file.readAsString());

    case _ContentSource.stagedIndex:
      final content = await _runGitOrFail(
        ['show', ':${target.repoPath}'],
        workingDirectory: plan.repoRoot,
      );
      return _normalizeLineEndings(content);

    case _ContentSource.gitCommitRef:
      final content = await _runGitOrFail(
        ['show', '${plan.gitCommitRef}:${target.repoPath}'],
        workingDirectory: plan.repoRoot,
      );
      return _normalizeLineEndings(content);
  }
}

String _normalizeLineEndings(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

// ---------------------------------------------------------------------------
// Rules & Exemptions
// ---------------------------------------------------------------------------

final _bannedFileSuffixRegex = RegExp(
  r'(?:^|/)[^/]+_(v\d+|new|clean|fixed|wrapper)(?:_test)?\.[A-Za-z0-9]+$',
  caseSensitive: false,
);

final _tailwindHexRegex = RegExp(
  r'\b0x[0-9A-Fa-f]{2}(6366F1|8B5CF6|10B981|F59E0B|EF4444|1E293B|0F172A|94A3B8)\b',
  caseSensitive: false,
);

/// Matches all `Colors.<member>` (including import-prefixed `material.Colors.*`,
/// opacity variants like `black54`/`white70`, and `*Accent` swatches) while
/// exempting `Colors.transparent`.
final _materialNamedColorRegex = RegExp(
  r'\bColors\s*\.\s*(?!transparent\b)([a-z][A-Za-z0-9_]*)\b',
);

final _themeStyleBranchRegex = RegExp(
  r'[!=]=\s*ThemeStyle\s*\.\s*(paper|plain|material)\b|\bThemeStyle\s*\.\s*(paper|plain|material)\s*[!=]=',
);

final _staticAppThemeRadiusRegex = RegExp(
  r'\bAppTheme\s*\.\s*(cardRadius|buttonRadius|inputRadius|dialogRadius|fabRadius)\b',
);

final _rawAptabaseRegex = RegExp(r'\bAptabase\s*\.\s*(instance|init)\b');

final _rawSnackBarCalleeRegex = RegExp(
  r'(?:\.\.|\?\.\.|\?\.|!\.|\.)\s*showSnackBar$',
);

final _rawSentryCalleeRegex = RegExp(
  r'(?:^|[^\w.$])Sentry\s*\.\s*captureException$',
);

final _deletedApiCalleeRegex = RegExp(
  r'(?:^|[^\w$])(?:generateDailyPrompt|receiveAndMerge)$|(?:^|[^\w$])TimeUtils\s*\.\s*formatTime$',
);

final _borderRadiusCircularCalleeRegex = RegExp(
  r'(?:^|[^\w.$])BorderRadius\s*\.\s*circular$',
);

final _borderRadiusAllCalleeRegex = RegExp(
  r'(?:^|[^\w.$])BorderRadius\s*\.\s*all$',
);

final _nestedRadiusCircularNumericRegex = RegExp(
  r'^\s*(?:const\s+)?Radius\s*\.\s*circular\s*\(([^)]*)\)\s*,?\s*$',
  dotAll: true,
);

bool _isHardcodedNumericRadiusArg(String directArgs) {
  var trimmed = directArgs.trim();
  if (trimmed.endsWith(',')) {
    trimmed = trimmed.substring(0, trimmed.length - 1).trim();
  }
  final directNum = double.tryParse(trimmed);
  if (directNum != null) {
    return directNum > 0 && directNum != 999;
  }
  final qIdx = trimmed.indexOf('?');
  final cIdx = trimmed.lastIndexOf(':');
  if (qIdx != -1 && cIdx > qIdx) {
    final thenNum = double.tryParse(trimmed.substring(qIdx + 1, cIdx).trim());
    final elseNum = double.tryParse(trimmed.substring(cIdx + 1).trim());
    return (thenNum != null && thenNum > 0 && thenNum != 999) ||
        (elseNum != null && elseNum > 0 && elseNum != 999);
  }
  return false;
}

bool _isHardcodedNestedRadiusCircular(String rawArgsText) {
  final m = _nestedRadiusCircularNumericRegex.firstMatch(rawArgsText);
  if (m == null) return false;
  return _isHardcodedNumericRadiusArg(m.group(1)!);
}

final _textStyleCalleeRegex = RegExp(
  r'(?:^|[^\w$])TextStyle$',
);

final _bodyTextThemeCopyWithRegex = RegExp(
  r'\btextTheme\s*\.\s*body(?:Large|Medium|Small)\s*(?:\?\.|!\.|\.)\s*copyWith$',
);

final _anyCopyWithCalleeRegex = RegExp(
  r'(?:\?\.|!\.|\.)\s*copyWith$',
);

final _hardcodedFontSizeArgRegex = RegExp(
  r'\bfontSize\s*:\s*\d+(?:\.\d+)?\b',
);

final _hardcodedFontWeightArgRegex = RegExp(
  r'\bfontWeight\s*:\s*FontWeight\s*\.\s*\w+\b',
);

final _hardcodedLineHeightArgRegex = RegExp(
  r'\bheight\s*:\s*\d+(?:\.\d+)?\b',
);

/// Exempted paths per `docs/theme-shape-migration-audit-2026-08-01.md` and
/// `docs/paper-ink-theme-handoff-2026-07-31.md`.
const _frozenAnnualReportPaths = <String>{
  'lib/pages/annual_report_page.dart',
  'lib/pages/ai_annual_report_webview.dart',
};

const _exemptBorderRadiusPaths = <String>{
  // Frozen annual report pages
  'lib/pages/annual_report_page.dart',
  'lib/pages/ai_annual_report_webview.dart',
  // Color swatch dots
  'lib/widgets/accessible_color_grid.dart',
  'lib/pages/note_editor/editor_color_and_media.dart',
  // Functional capsules & camera/voice overlays
  'lib/widgets/local_ai/ocr_capture_page.dart',
  'lib/widgets/local_ai/ocr_result_sheet.dart',
  'lib/widgets/local_ai/voice_result_sheet.dart',
  'lib/widgets/local_ai/voice_input_overlay.dart',
  // Celebration animation overlay & theme preview cards
  'lib/widgets/anniversary_animation_overlay.dart',
  'lib/widgets/theme_style_preview.dart',
};

const _exemptTypographyPaths = <String>{
  // Frozen annual report pages
  'lib/pages/annual_report_page.dart',
  'lib/pages/ai_annual_report_webview.dart',
  // Celebration overlay & theme preview mockup
  'lib/widgets/anniversary_animation_overlay.dart',
  'lib/widgets/theme_style_preview.dart',
  // Rich-text / Quill / Markdown rendering & toolbar config paths
  'lib/widgets/quote_content_widget.dart',
  'lib/widgets/note_list/collapsed_rich_text.dart',
  'lib/widgets/enhanced_markdown_widgets.dart',
  'lib/widgets/quill_enhanced_toolbar_unified.dart',
};

const _exemptRawSentryPaths = <String>{
  'lib/services/unified_log_service.dart',
  'lib/utils/sentry_helper.dart',
};

/// Synthetic location placeholders explicitly approved in `AGENTS.md`.
final _syntheticPlaceholdersRegex = RegExp(
  r'(示例省|示例市|示例区|示例县|示例街道|示例路|其他省|其他市|其他区|某省|某市|某区|测试省|测试市|测试区|虚拟省|虚拟市|MockPOI|MockCity|SampleCity)',
  caseSensitive: false,
);

/// Concrete real place names / administrative regions / famous POIs forbidden in
/// newly added `test/` fixtures & comments (`AGENTS.md` redaction rule).
final _realPlaceNameInTestRegex = RegExp(
  r'(北京市?|上海市?|天津市?|重庆市?|广州市?|深圳市?|杭州市?|南京市?|武汉市?|成都市|(?<!(?:[完生形组赞构变分造促养换加合]|[一二三四五六七八九十百几半]|(?<![到直抵])达)(?=成都[会是能要有在不已将可需应必只全均被把给让没未无还]))成都|西安市|(?<!东(?=西安[装全排心置稳静]))西安|苏州市?|郑州市?|长沙市?|东莞市?|沈阳市?|青岛市?|合肥市?|佛山市?|宁波市?|昆明市?|福州市?|无锡市?|厦门市?|哈尔滨市?|长春市?|南昌市?|济南市?|大连市?|贵阳市?|温州市?|石家庄市?|泉州市?|南宁市?|金华市?|常州市?|珠海市?|惠州市?|嘉兴市?|南通市?|太原市?|保定市?|中山市|(?<![选命击正集居](?=中山[形顶峰脚坡谷脉水林]))中山|台州市?|绍兴市?|烟台市?|兰州市?|海口市?|乌鲁木齐市?|呼和浩特市?|银川市?|西宁市?|拉萨市?|香港|澳门|台北市?|高雄市?|广东省?|浙江省?|江苏省?|山东省?|河南省?|四川省?|湖北省?|湖南省?|河北省?|福建省?|安徽省?|辽宁省?|陕西省?|江西省?|广西|云南省?|山西省?|贵州省?|吉林省?|黑龙江省?|内蒙古|新疆|甘肃省?|海南省?|宁夏|青海省?|西藏|台湾省?|海淀区?|朝阳区|西城区|东城区|浦东新区|浦东|静安区|徐汇区|黄浦区|南山区|福田区|西湖|苏堤|外滩|故宫|天安门|中关村|三里屯|陆家嘴|\b(?:Beijing|Shanghai|Guangzhou|Shenzhen|Hangzhou|Chengdu|Wuhan|Nanjing|Suzhou|Chongqing|Tianjin|Hong\s+Kong|Taipei)\b)',
  caseSensitive: false,
);

// ---------------------------------------------------------------------------
// File & Lexical Window Scanner
// ---------------------------------------------------------------------------

Future<void> _scanFileTarget(
  _FileScanTarget target,
  _ScanPlan plan,
  List<String> violations,
  Set<String> seenViolationKeys,
) async {
  final path = target.repoPath;
  final isDart = path.endsWith('.dart');
  final hasBannedSuffix = _bannedFileSuffixRegex.hasMatch(path);

  if (!hasBannedSuffix && (!isDart || target.addedLines.isEmpty)) {
    return;
  }

  String content = '';
  List<int> lineStarts = const <int>[0];
  _DartLexicalAnalysis? lex;

  if (isDart) {
    content = await _readTargetContent(target, plan);
    lineStarts = _computeLineStarts(content);
    lex = _analyzeDartSourceLexically(content, lineStarts);
    if (lex.hasFileIgnore) {
      return;
    }
  }

  if (hasBannedSuffix) {
    _recordViolation(
      violations: violations,
      seenKeys: seenViolationKeys,
      filePath: path,
      lineNumber: 1,
      ruleId: 'no-banned-file-suffix',
      message:
          'Do not use _v2/_new/_clean/_fixed/_wrapper file suffixes; name files directly after their current responsibility.',
    );
  }

  if (!isDart || target.addedLines.isEmpty || content.isEmpty || lex == null) {
    return;
  }

  final rawLines = content.split('\n');
  final sanitized = lex.sanitizedCode;

  if (path.startsWith('test/')) {
    _scanTestPlaceNames(
      filePath: path,
      rawLines: rawLines,
      lex: lex,
      lineStarts: lineStarts,
      addedLines: target.addedLines,
      violations: violations,
      seenViolationKeys: seenViolationKeys,
    );
    return;
  }

  if (!path.startsWith('lib/')) {
    return;
  }

  final isUiLayer =
      path.startsWith('lib/pages/') || path.startsWith('lib/widgets/');
  final isFrozenAnnualReport = _frozenAnnualReportPaths.contains(path);

  // 1. Token / operator rules evaluated on enclosing balanced clause windows.
  _scanRegexWithClauseWindows(
    regex: _tailwindHexRegex,
    ruleId: 'no-tailwind-hex',
    message:
        'Do not use Tailwind palette literals; derive colors from ColorScheme or AppSemanticColors.',
    filePath: path,
    lex: lex,
    lineStarts: lineStarts,
    addedLines: target.addedLines,
    violations: violations,
    seenViolationKeys: seenViolationKeys,
  );

  if (path != 'lib/utils/aptabase_helper.dart') {
    _scanRegexWithClauseWindows(
      regex: _rawAptabaseRegex,
      ruleId: 'no-raw-aptabase',
      message:
          'Use AptabaseHelper.trackEvent / trackPageView instead of calling Aptabase SDK directly.',
      filePath: path,
      lex: lex,
      lineStarts: lineStarts,
      addedLines: target.addedLines,
      violations: violations,
      seenViolationKeys: seenViolationKeys,
    );
  }

  if (isUiLayer) {
    _scanRegexWithClauseWindows(
      regex: _materialNamedColorRegex,
      ruleId: 'no-material-named-colors',
      message:
          'Use ColorScheme (onSurfaceVariant, surfaceContainerHighest, error) or AppSemanticColors instead of Colors.* in UI layer.',
      filePath: path,
      lex: lex,
      lineStarts: lineStarts,
      addedLines: target.addedLines,
      violations: violations,
      seenViolationKeys: seenViolationKeys,
    );

    if (path != 'lib/widgets/theme_style_selector.dart' &&
        path != 'lib/widgets/theme_style_preview.dart') {
      _scanRegexWithClauseWindows(
        regex: _themeStyleBranchRegex,
        ruleId: 'no-theme-style-branching',
        message:
            'Do not branch on ThemeStyle in widgets; read shape/rule tokens from AppShapeTokens.of(context).',
        filePath: path,
        lex: lex,
        lineStarts: lineStarts,
        addedLines: target.addedLines,
        violations: violations,
        seenViolationKeys: seenViolationKeys,
      );
    }

    if (!isFrozenAnnualReport) {
      _scanRegexWithClauseWindows(
        regex: _staticAppThemeRadiusRegex,
        ruleId: 'no-static-app-theme-radius',
        message:
            'Use AppShapeTokens.of(context).cardRadius/buttonRadius/inputRadius/dialogRadius/fabRadius instead of static AppTheme.*Radius.',
        filePath: path,
        lex: lex,
        lineStarts: lineStarts,
        addedLines: target.addedLines,
        violations: violations,
        seenViolationKeys: seenViolationKeys,
      );
    }
  }

  // 2. Call / constructor rules evaluated on balanced parenthesis expression windows.
  final callWindows = _extractCallWindows(sanitized);
  for (final call in callWindows) {
    final windowStartLine = _lineAtOffset(lineStarts, call.chainStart);
    final windowEndLine = _lineAtOffset(lineStarts, call.closeParen);

    if (!_rangeIntersectsAddedLines(
      windowStartLine,
      windowEndLine,
      target.addedLines,
    )) {
      continue;
    }

    final enclosingClause = _findEnclosingClauseOffsets(
      sanitized,
      call.chainStart,
      call.closeParen + 1,
    );
    final clauseStartLine = _lineAtOffset(lineStarts, enclosingClause.$1);
    final clauseEndLine = _lineAtOffset(lineStarts, enclosingClause.$2);

    if (_isWindowIgnored(lex, windowStartLine, windowEndLine) ||
        _isWindowIgnored(lex, clauseStartLine, clauseEndLine)) {
      continue;
    }

    final calleeLine = _lineAtOffset(lineStarts, call.calleeTokenOffset);

    if (_deletedApiCalleeRegex.hasMatch(call.calleeSlice)) {
      _recordViolation(
        violations: violations,
        seenKeys: seenViolationKeys,
        filePath: path,
        lineNumber: calleeLine,
        ruleId: 'no-deleted-api',
        message:
            'Call to deleted API detected (use streamGenerateDailyPrompt, formatRelativeDateTime/formatQuoteTime, or current sync flow).',
      );
    }

    if (!_exemptRawSentryPaths.contains(path) &&
        _rawSentryCalleeRegex.hasMatch(call.calleeSlice)) {
      _recordViolation(
        violations: violations,
        seenKeys: seenViolationKeys,
        filePath: path,
        lineNumber: calleeLine,
        ruleId: 'no-raw-sentry',
        message:
            'Use logError / AppLogger.e (routed via UnifiedLogService) instead of calling Sentry.captureException directly.',
      );
    }

    if (path != 'lib/widgets/app_snackbar.dart' &&
        _rawSnackBarCalleeRegex.hasMatch(call.calleeSlice)) {
      _recordViolation(
        violations: violations,
        seenKeys: seenViolationKeys,
        filePath: path,
        lineNumber: calleeLine,
        ruleId: 'no-raw-snackbar',
        message:
            'Use AppSnackBar.info/success/warning/error instead of calling showSnackBar directly.',
      );
    }

    if (!isUiLayer) continue;

    if (!_exemptBorderRadiusPaths.contains(path)) {
      if (_borderRadiusCircularCalleeRegex.hasMatch(call.calleeSlice) &&
          _isHardcodedNumericRadiusArg(call.directArgsText)) {
        _recordViolation(
          violations: violations,
          seenKeys: seenViolationKeys,
          filePath: path,
          lineNumber: calleeLine,
          ruleId: 'no-hardcoded-border-radius',
          message:
              'Use AppShapeTokens.of(context).cardRadius/buttonRadius/inputRadius/dialogRadius/fabRadius instead of hardcoded BorderRadius.circular(N).',
        );
      } else if (_borderRadiusAllCalleeRegex.hasMatch(call.calleeSlice) &&
          _isHardcodedNestedRadiusCircular(call.rawArgsText)) {
        _recordViolation(
          violations: violations,
          seenKeys: seenViolationKeys,
          filePath: path,
          lineNumber: calleeLine,
          ruleId: 'no-hardcoded-border-radius',
          message:
              'Use AppShapeTokens.of(context) shape tokens instead of hardcoded BorderRadius.all(Radius.circular(N)).',
        );
      }
    }

    if (!_exemptTypographyPaths.contains(path)) {
      final isTextStyleCtor = _textStyleCalleeRegex.hasMatch(call.calleeSlice);
      final isBodyCopyWith =
          _bodyTextThemeCopyWithRegex.hasMatch(call.chainSlice);
      final isAnyCopyWith = _anyCopyWithCalleeRegex.hasMatch(call.calleeSlice);

      if (isTextStyleCtor || isBodyCopyWith) {
        _checkTypographyArgs(
          call: call,
          checkFontSize: true,
          checkFontWeight: true,
          checkLineHeight: true,
          filePath: path,
          lineStarts: lineStarts,
          violations: violations,
          seenViolationKeys: seenViolationKeys,
        );
      } else if (isAnyCopyWith) {
        _checkTypographyArgs(
          call: call,
          checkFontSize: true,
          checkFontWeight: false,
          checkLineHeight: false,
          filePath: path,
          lineStarts: lineStarts,
          violations: violations,
          seenViolationKeys: seenViolationKeys,
        );
      }
    }
  }
}

void _checkTypographyArgs({
  required _CallWindow call,
  required bool checkFontSize,
  required bool checkFontWeight,
  required bool checkLineHeight,
  required String filePath,
  required List<int> lineStarts,
  required List<String> violations,
  required Set<String> seenViolationKeys,
}) {
  final argsText = call.directArgsText;
  final baseOffset = call.openParen + 1;

  if (checkFontSize) {
    final m = _hardcodedFontSizeArgRegex.firstMatch(argsText);
    if (m != null) {
      _recordViolation(
        violations: violations,
        seenKeys: seenViolationKeys,
        filePath: filePath,
        lineNumber: _lineAtOffset(lineStarts, baseOffset + m.start),
        ruleId: 'no-hardcoded-typography',
        message:
            'Do not hardcode fontSize in UI TextStyle; derive typography from Theme.of(context).textTheme.',
      );
    }
  }

  if (checkFontWeight) {
    final m = _hardcodedFontWeightArgRegex.firstMatch(argsText);
    if (m != null) {
      _recordViolation(
        violations: violations,
        seenKeys: seenViolationKeys,
        filePath: filePath,
        lineNumber: _lineAtOffset(lineStarts, baseOffset + m.start),
        ruleId: 'no-hardcoded-typography',
        message:
            'Do not hardcode fontWeight in TextStyle; derive typography from Theme.of(context).textTheme.',
      );
    }
  }

  if (checkLineHeight) {
    final m = _hardcodedLineHeightArgRegex.firstMatch(argsText);
    if (m != null) {
      _recordViolation(
        violations: violations,
        seenKeys: seenViolationKeys,
        filePath: filePath,
        lineNumber: _lineAtOffset(lineStarts, baseOffset + m.start),
        ruleId: 'no-hardcoded-typography',
        message:
            'Do not hardcode body text height in TextStyle; paper rule spacing depends on theme body line height.',
      );
    }
  }
}

void _scanRegexWithClauseWindows({
  required RegExp regex,
  required String ruleId,
  required String message,
  required String filePath,
  required _DartLexicalAnalysis lex,
  required List<int> lineStarts,
  required Set<int> addedLines,
  required List<String> violations,
  required Set<String> seenViolationKeys,
}) {
  final sanitized = lex.sanitizedCode;
  for (final match in regex.allMatches(sanitized)) {
    final clauseRange = _findEnclosingClauseOffsets(
      sanitized,
      match.start,
      match.end,
    );
    final windowStartLine = _lineAtOffset(lineStarts, clauseRange.$1);
    final windowEndLine = _lineAtOffset(lineStarts, clauseRange.$2);

    if (!_rangeIntersectsAddedLines(
      windowStartLine,
      windowEndLine,
      addedLines,
    )) {
      continue;
    }

    if (_isWindowIgnored(lex, windowStartLine, windowEndLine)) {
      continue;
    }

    final matchLine = _lineAtOffset(lineStarts, match.start);
    _recordViolation(
      violations: violations,
      seenKeys: seenViolationKeys,
      filePath: filePath,
      lineNumber: matchLine,
      ruleId: ruleId,
      message: message,
    );
  }
}

void _scanTestPlaceNames({
  required String filePath,
  required List<String> rawLines,
  required _DartLexicalAnalysis lex,
  required List<int> lineStarts,
  required Set<int> addedLines,
  required List<String> violations,
  required Set<String> seenViolationKeys,
}) {
  final sanitized = lex.sanitizedCode;
  final sortedLines = addedLines.toList()..sort();
  for (final lineNum in sortedLines) {
    if (lineNum < 1 || lineNum > rawLines.length) continue;

    final rawLine = rawLines[lineNum - 1];
    final lineOffset = lineStarts[lineNum - 1];
    final clauseOffsets = _findEnclosingClauseOffsets(
      sanitized,
      lineOffset,
      lineOffset + rawLine.length,
    );
    final clauseStartLine = _lineAtOffset(lineStarts, clauseOffsets.$1);
    final clauseEndLine = _lineAtOffset(lineStarts, clauseOffsets.$2);

    if (_isWindowIgnored(lex, lineNum, lineNum) ||
        _isWindowIgnored(lex, clauseStartLine, clauseEndLine)) {
      continue;
    }

    final scrubbed = rawLine.replaceAll(_syntheticPlaceholdersRegex, '');
    final match = _realPlaceNameInTestRegex.firstMatch(scrubbed);
    if (match != null) {
      _recordViolation(
        violations: violations,
        seenKeys: seenViolationKeys,
        filePath: filePath,
        lineNumber: lineNum,
        ruleId: 'no-real-place-names-in-tests',
        message:
            'Do not introduce real concrete place/POI names ("${match.group(0)}") in test/; use synthetic placeholders like 示例省·示例市 or MockPOI.',
      );
    }
  }
}

void _recordViolation({
  required List<String> violations,
  required Set<String> seenKeys,
  required String filePath,
  required int lineNumber,
  required String ruleId,
  required String message,
}) {
  final key = '$filePath:$lineNumber:$ruleId';
  if (seenKeys.add(key)) {
    violations.add('$filePath:$lineNumber [$ruleId] $message');
  }
}

bool _rangeIntersectsAddedLines(
  int startLine,
  int endLine,
  Set<int> addedLines,
) {
  for (var line = startLine; line <= endLine; line++) {
    if (addedLines.contains(line)) {
      return true;
    }
  }
  return false;
}

bool _isWindowIgnored(
  _DartLexicalAnalysis lex,
  int startLine,
  int endLine,
) {
  for (var line = startLine; line <= endLine; line++) {
    if (lex.inlineIgnoredLines.contains(line)) {
      return true;
    }
  }

  if (startLine > 1 &&
      lex.standaloneIgnoreCommentLines.contains(startLine - 1)) {
    return true;
  }

  return false;
}

// ---------------------------------------------------------------------------
// Pure-Stdlib Dart Lexical Sanitizer & Balanced Delimiter Parser
// ---------------------------------------------------------------------------

final _fileIgnoreCommentRegex = RegExp(
  r'\bignore_for_file\s*:\s*[^\n]*\brepo_lint\b',
);

final _lineIgnoreCommentRegex = RegExp(
  r'\bignore\s*:\s*[^\n]*\brepo_lint\b',
);

class _DartLexicalAnalysis {
  final String sanitizedCode;
  final bool hasFileIgnore;
  final Set<int> inlineIgnoredLines;
  final Set<int> standaloneIgnoreCommentLines;

  const _DartLexicalAnalysis({
    required this.sanitizedCode,
    required this.hasFileIgnore,
    required this.inlineIgnoredLines,
    required this.standaloneIgnoreCommentLines,
  });
}

class _ActiveStringState {
  final int quoteChar;
  final bool isTriple;

  const _ActiveStringState({required this.quoteChar, required this.isTriple});
}

class _InterpFrame {
  final _ActiveStringState outerString;
  int braceDepth;

  _InterpFrame({required this.outerString, required this.braceDepth});
}

/// Replaces comments and string literal contents with spaces (`0x20`) while
/// preserving every `\n` (`0x0A`) at its exact character index, preserving
/// `${...}` string interpolations as balanced `(...)` code expressions, and
/// extracting `ignore_for_file: repo_lint` / `ignore: repo_lint` exclusively
/// from genuine Dart comments (never from string literals).
_DartLexicalAnalysis _analyzeDartSourceLexically(
  String source,
  List<int> lineStarts,
) {
  final len = source.length;
  final out = List<int>.filled(len, 0x20);
  final interpStack = <_InterpFrame>[];
  _ActiveStringState? activeString;
  var hasFileIgnore = false;
  final inlineIgnoredLines = <int>{};
  final standaloneIgnoreCommentLines = <int>{};

  var i = 0;
  while (i < len) {
    if (activeString != null) {
      final cu = source.codeUnitAt(i);
      if (cu == 0x0A /* \n */) {
        out[i] = 0x0A;
        if (!activeString.isTriple) {
          activeString = null;
        }
        i++;
        continue;
      }
      if (cu == 0x5C /* \ */) {
        // Escape next character inside non-raw string.
        i++;
        if (i < len) {
          if (source.codeUnitAt(i) == 0x0A) {
            out[i] = 0x0A;
          }
          i++;
        }
        continue;
      }
      if (cu == 0x24 /* $ */ &&
          i + 1 < len &&
          source.codeUnitAt(i + 1) == 0x7B /* { */) {
        // String interpolation `${ ... }`: emit ` (` and enter code mode.
        out[i + 1] = 0x28; // '('
        interpStack.add(
          _InterpFrame(outerString: activeString, braceDepth: 1),
        );
        activeString = null;
        i += 2;
        continue;
      }
      if (cu == activeString.quoteChar) {
        if (activeString.isTriple) {
          if (i + 2 < len &&
              source.codeUnitAt(i + 1) == cu &&
              source.codeUnitAt(i + 2) == cu) {
            activeString = null;
            i += 3;
            continue;
          }
        } else {
          activeString = null;
          i++;
          continue;
        }
      }
      i++;
      continue;
    }

    final cu = source.codeUnitAt(i);
    if (cu == 0x0A /* \n */) {
      out[i] = 0x0A;
      i++;
      continue;
    }

    // Line comment `// ...`
    if (cu == 0x2F /* / */ &&
        i + 1 < len &&
        source.codeUnitAt(i + 1) == 0x2F /* / */) {
      final commentStart = i;
      i += 2;
      while (i < len && source.codeUnitAt(i) != 0x0A) {
        i++;
      }
      final commentBody = source.substring(commentStart + 2, i);
      if (_fileIgnoreCommentRegex.hasMatch(commentBody)) {
        hasFileIgnore = true;
      }
      if (_lineIgnoreCommentRegex.hasMatch(commentBody)) {
        final lineNum = _lineAtOffset(lineStarts, commentStart);
        inlineIgnoredLines.add(lineNum);
        final lineStartOffset = lineStarts[lineNum - 1];
        if (_isHorizontalWhitespaceSlice(
          source,
          lineStartOffset,
          commentStart,
        )) {
          standaloneIgnoreCommentLines.add(lineNum);
        }
      }
      continue;
    }

    // Nested block comment `/* ... */`
    if (cu == 0x2F /* / */ &&
        i + 1 < len &&
        source.codeUnitAt(i + 1) == 0x2A /* * */) {
      final commentStart = i;
      var depth = 1;
      i += 2;
      while (i < len && depth > 0) {
        final c = source.codeUnitAt(i);
        if (c == 0x0A) {
          out[i] = 0x0A;
          i++;
        } else if (c == 0x2F &&
            i + 1 < len &&
            source.codeUnitAt(i + 1) == 0x2A) {
          depth++;
          i += 2;
        } else if (c == 0x2A &&
            i + 1 < len &&
            source.codeUnitAt(i + 1) == 0x2F) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      final bodyEnd = i >= commentStart + 4 ? i - 2 : i;
      final commentBody = source.substring(commentStart + 2, bodyEnd);
      if (_fileIgnoreCommentRegex.hasMatch(commentBody)) {
        hasFileIgnore = true;
      }
      if (_lineIgnoreCommentRegex.hasMatch(commentBody)) {
        final startLine = _lineAtOffset(lineStarts, commentStart);
        final endLine = _lineAtOffset(lineStarts, i > 0 ? i - 1 : 0);
        for (var l = startLine; l <= endLine; l++) {
          inlineIgnoredLines.add(l);
        }
        final startLineOffset = lineStarts[startLine - 1];
        var endOfEndLine = i;
        while (endOfEndLine < len && source.codeUnitAt(endOfEndLine) != 0x0A) {
          endOfEndLine++;
        }
        if (_isHorizontalWhitespaceSlice(
              source,
              startLineOffset,
              commentStart,
            ) &&
            _isHorizontalWhitespaceSlice(source, i, endOfEndLine)) {
          standaloneIgnoreCommentLines.add(endLine);
        }
      }
      continue;
    }

    // Raw string `r'...'`, `r"..."`, `r'''...'''`, `r"""..."""`
    if (cu == 0x72 /* r */ &&
        (i == 0 || !_isIdentChar(source.codeUnitAt(i - 1))) &&
        i + 1 < len) {
      final next = source.codeUnitAt(i + 1);
      if (next == 0x27 /* ' */ || next == 0x22 /* " */) {
        final isTriple = i + 3 < len &&
            source.codeUnitAt(i + 2) == next &&
            source.codeUnitAt(i + 3) == next;
        i += isTriple ? 4 : 2;
        while (i < len) {
          final c = source.codeUnitAt(i);
          if (c == 0x0A) {
            out[i] = 0x0A;
            i++;
            if (!isTriple) break;
          } else if (c == next) {
            if (isTriple) {
              if (i + 2 < len &&
                  source.codeUnitAt(i + 1) == next &&
                  source.codeUnitAt(i + 2) == next) {
                i += 3;
                break;
              }
              i++;
            } else {
              i++;
              break;
            }
          } else {
            i++;
          }
        }
        continue;
      }
    }

    // Normal single or triple quoted string
    if (cu == 0x27 /* ' */ || cu == 0x22 /* " */) {
      final isTriple = i + 2 < len &&
          source.codeUnitAt(i + 1) == cu &&
          source.codeUnitAt(i + 2) == cu;
      activeString = _ActiveStringState(quoteChar: cu, isTriple: isTriple);
      i += isTriple ? 3 : 1;
      continue;
    }

    // String interpolation brace tracking
    if (interpStack.isNotEmpty) {
      if (cu == 0x7B /* { */) {
        interpStack.last.braceDepth++;
        out[i] = cu;
        i++;
        continue;
      }
      if (cu == 0x7D /* } */) {
        interpStack.last.braceDepth--;
        if (interpStack.last.braceDepth == 0) {
          activeString = interpStack.removeLast().outerString;
          out[i] = 0x29; // ')'
          i++;
          continue;
        }
      }
    }

    out[i] = cu;
    i++;
  }

  return _DartLexicalAnalysis(
    sanitizedCode: String.fromCharCodes(out),
    hasFileIgnore: hasFileIgnore,
    inlineIgnoredLines: inlineIgnoredLines,
    standaloneIgnoreCommentLines: standaloneIgnoreCommentLines,
  );
}

bool _isHorizontalWhitespaceSlice(String s, int start, int end) {
  for (var idx = start; idx < end; idx++) {
    final cu = s.codeUnitAt(idx);
    if (cu != 0x20 && cu != 0x09 && cu != 0x0D) {
      return false;
    }
  }
  return true;
}

bool _isIdentChar(int cu) =>
    (cu >= 0x41 && cu <= 0x5A) || // A-Z
    (cu >= 0x61 && cu <= 0x7A) || // a-z
    (cu >= 0x30 && cu <= 0x39) || // 0-9
    cu == 0x5F || // _
    cu == 0x24; // $

bool _isWhitespace(int cu) =>
    cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D;

List<int> _computeLineStarts(String content) {
  final starts = <int>[0];
  for (var i = 0; i < content.length; i++) {
    if (content.codeUnitAt(i) == 0x0A) {
      starts.add(i + 1);
    }
  }
  return starts;
}

int _lineAtOffset(List<int> lineStarts, int offset) {
  if (offset <= 0) return 1;
  var low = 0;
  var high = lineStarts.length - 1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (lineStarts[mid] <= offset) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return high + 1;
}

class _CallWindow {
  final int chainStart;
  final int calleeStart;
  final int calleeTokenOffset;
  final int openParen;
  final int closeParen;
  final String chainSlice;
  final String calleeSlice;
  final String rawArgsText;
  final String directArgsText;

  const _CallWindow({
    required this.chainStart,
    required this.calleeStart,
    required this.calleeTokenOffset,
    required this.openParen,
    required this.closeParen,
    required this.chainSlice,
    required this.calleeSlice,
    required this.rawArgsText,
    required this.directArgsText,
  });
}

class _OpenParenEntry {
  final int openParen;
  final int bracketDepthAtOpen;
  final int braceDepthAtOpen;

  const _OpenParenEntry({
    required this.openParen,
    required this.bracketDepthAtOpen,
    required this.braceDepthAtOpen,
  });
}

List<_CallWindow> _extractCallWindows(String sanitized) {
  final len = sanitized.length;
  final parenStack = <_OpenParenEntry>[];
  final matchedClose = <int, int>{};
  var bracketDepth = 0;
  var braceDepth = 0;

  for (var i = 0; i < len; i++) {
    final cu = sanitized.codeUnitAt(i);
    switch (cu) {
      case 0x28: // (
        parenStack.add(
          _OpenParenEntry(
            openParen: i,
            bracketDepthAtOpen: bracketDepth,
            braceDepthAtOpen: braceDepth,
          ),
        );
        break;
      case 0x29: // )
        if (parenStack.isNotEmpty) {
          final top = parenStack.removeLast();
          bracketDepth = top.bracketDepthAtOpen;
          braceDepth = top.braceDepthAtOpen;
          matchedClose[top.openParen] = i;
        }
        break;
      case 0x5B: // [
        bracketDepth++;
        break;
      case 0x5D: // ]
        if (bracketDepth > 0) bracketDepth--;
        break;
      case 0x7B: // {
        braceDepth++;
        break;
      case 0x7D: // }
        if (braceDepth > 0) braceDepth--;
        break;
    }
  }

  final windows = <_CallWindow>[];
  final sortedOpens = matchedClose.keys.toList()..sort();

  for (final openIdx in sortedOpens) {
    final closeIdx = matchedClose[openIdx]!;
    final prefixInfo = _scanCallPrefix(sanitized, openIdx);
    if (prefixInfo == null) continue;

    final rawArgs = sanitized.substring(openIdx + 1, closeIdx);
    final directArgs = _maskNestedDelimiters(rawArgs);

    windows.add(
      _CallWindow(
        chainStart: prefixInfo.chainStart,
        calleeStart: prefixInfo.calleeStart,
        calleeTokenOffset: prefixInfo.calleeTokenOffset,
        openParen: openIdx,
        closeParen: closeIdx,
        chainSlice:
            sanitized.substring(prefixInfo.chainStart, prefixInfo.prefixEnd),
        calleeSlice:
            sanitized.substring(prefixInfo.calleeStart, prefixInfo.prefixEnd),
        rawArgsText: rawArgs,
        directArgsText: directArgs,
      ),
    );
  }

  return windows;
}

class _CallPrefixInfo {
  final int chainStart;
  final int calleeStart;
  final int calleeTokenOffset;
  final int prefixEnd;

  const _CallPrefixInfo({
    required this.chainStart,
    required this.calleeStart,
    required this.calleeTokenOffset,
    required this.prefixEnd,
  });
}

_CallPrefixInfo? _scanCallPrefix(String s, int openParen) {
  var pos = openParen - 1;
  while (pos >= 0 && _isWhitespace(s.codeUnitAt(pos))) {
    pos--;
  }

  // Skip optional generic type arguments `<...>` right before `(`
  if (pos >= 0 && s.codeUnitAt(pos) == 0x3E /* > */) {
    final afterLt = _skipBalancedTypeArgsBackward(s, pos);
    if (afterLt != null) {
      pos = afterLt;
      while (pos >= 0 && _isWhitespace(s.codeUnitAt(pos))) {
        pos--;
      }
    }
  }

  if (pos < 0 || !_isIdentChar(s.codeUnitAt(pos))) {
    return null;
  }

  final prefixEnd = pos + 1;
  while (pos >= 0 && _isIdentChar(s.codeUnitAt(pos))) {
    pos--;
  }
  final calleeTokenOffset = pos + 1;
  final tokenName = s.substring(calleeTokenOffset, prefixEnd);
  if (_dartControlKeywords.contains(tokenName)) {
    return null;
  }

  // Capture immediate qualifier/operator for `calleeSlice`, e.g.:
  // `.showSnackBar`, `..showSnackBar`, `?.showSnackBar`, `BorderRadius.circular`, `Sentry.captureException`
  var calleeStart = calleeTokenOffset;
  var scan = pos;
  while (scan >= 0 && _isWhitespace(s.codeUnitAt(scan))) {
    scan--;
  }
  if (scan >= 0 && s.codeUnitAt(scan) == 0x2E /* . */) {
    var dotStart = scan;
    if (dotStart - 1 >= 0 && s.codeUnitAt(dotStart - 1) == 0x2E /* .. */) {
      dotStart--;
      if (dotStart - 1 >= 0 && s.codeUnitAt(dotStart - 1) == 0x3F /* ?.. */) {
        dotStart--;
      }
      calleeStart = dotStart;
    } else if (dotStart - 1 >= 0 &&
        (s.codeUnitAt(dotStart - 1) == 0x3F /* ?. */ ||
            s.codeUnitAt(dotStart - 1) == 0x21 /* !. */)) {
      dotStart--;
      calleeStart = dotStart;
    } else {
      calleeStart = dotStart;
      // Check if preceded by a simple type/namespace identifier (e.g. `BorderRadius.circular`)
      var prev = dotStart - 1;
      while (prev >= 0 && _isWhitespace(s.codeUnitAt(prev))) {
        prev--;
      }
      if (prev >= 0 && _isIdentChar(s.codeUnitAt(prev))) {
        while (prev >= 0 && _isIdentChar(s.codeUnitAt(prev))) {
          prev--;
        }
        calleeStart = prev + 1;
      }
    }
  }

  // Walk further backwards across chained calls, indexing, cascades, and identifiers for `chainStart`.
  var chainStart = calleeStart;
  var cur = calleeStart - 1;
  while (cur >= 0) {
    var p = cur;
    while (p >= 0 && _isWhitespace(s.codeUnitAt(p))) {
      p--;
    }
    if (p < 0) break;

    final cu = s.codeUnitAt(p);
    if (_isIdentChar(cu)) {
      while (p >= 0 && _isIdentChar(s.codeUnitAt(p))) {
        p--;
      }
      final ident = s.substring(p + 1, cur + 1).trim();
      if (_dartStatementKeywords.contains(ident)) {
        break;
      }
      chainStart = p + 1;
      cur = p;
      continue;
    }
    if (cu == 0x2E /* . */ || cu == 0x3F /* ? */ || cu == 0x21 /* ! */) {
      cur = p - 1;
      continue;
    }
    if (cu == 0x29 /* ) */ || cu == 0x5D /* ] */) {
      final openMatch = _skipBalancedGroupBackward(s, p);
      if (openMatch == null) break;
      chainStart = openMatch;
      cur = openMatch - 1;
      continue;
    }
    if (cu == 0x3E /* > */) {
      final beforeLt = _skipBalancedTypeArgsBackward(s, p);
      if (beforeLt == null) break;
      cur = beforeLt;
      continue;
    }
    break;
  }

  return _CallPrefixInfo(
    chainStart: chainStart,
    calleeStart: calleeStart,
    calleeTokenOffset: calleeTokenOffset,
    prefixEnd: prefixEnd,
  );
}

const _dartControlKeywords = <String>{
  'if',
  'for',
  'while',
  'switch',
  'catch',
  'assert',
};

const _dartStatementKeywords = <String>{
  'return',
  'final',
  'var',
  'const',
  'await',
  'yield',
  'throw',
  'case',
  'else',
  'new',
};

int? _skipBalancedGroupBackward(String s, int closeIdx) {
  final closeCu = s.codeUnitAt(closeIdx);
  final openCu = closeCu == 0x29 ? 0x28 : 0x5B;
  var depth = 1;
  var i = closeIdx - 1;
  while (i >= 0 && depth > 0) {
    final c = s.codeUnitAt(i);
    if (c == closeCu) {
      depth++;
    } else if (c == openCu) {
      depth--;
    }
    if (depth == 0) return i;
    i--;
  }
  return null;
}

int? _skipBalancedTypeArgsBackward(String s, int gtIdx) {
  var depth = 1;
  var i = gtIdx - 1;
  while (i >= 0 && depth > 0) {
    final c = s.codeUnitAt(i);
    if (c == 0x3E /* > */) {
      depth++;
    } else if (c == 0x3C /* < */) {
      depth--;
      if (depth == 0) return i - 1;
    } else if (!_isIdentChar(c) &&
        !_isWhitespace(c) &&
        c != 0x2C /* , */ &&
        c != 0x2E /* . */ &&
        c != 0x3F /* ? */) {
      return null;
    }
    i--;
  }
  return null;
}

String _maskNestedDelimiters(String text) {
  final units = List<int>.filled(text.length, 0x20);
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final cu = text.codeUnitAt(i);
    if (cu == 0x0A) {
      units[i] = 0x0A;
      continue;
    }
    if (cu == 0x28 || cu == 0x5B || cu == 0x7B) {
      if (depth == 0) {
        units[i] = cu;
      }
      depth++;
      continue;
    }
    if (cu == 0x29 || cu == 0x5D || cu == 0x7D) {
      if (depth > 0) depth--;
      if (depth == 0) {
        units[i] = cu;
      }
      continue;
    }
    if (depth == 0) {
      units[i] = cu;
    }
  }
  return String.fromCharCodes(units);
}

/// Finds the enclosing leaf clause/statement `[startOffset, endOffset]` bounded
/// by `(`, `[`, `{`, `,`, or `;` at depth 0 relative to `[matchStart..matchEnd]`.
(int, int) _findEnclosingClauseOffsets(
  String sanitized,
  int matchStart,
  int matchEnd,
) {
  final len = sanitized.length;
  if (len == 0) return (0, 0);

  final clampedStart = matchStart.clamp(0, len - 1);
  final clampedEnd = matchEnd.clamp(clampedStart, len);

  var left = clampedStart - 1;
  var depth = 0;
  while (left >= 0) {
    final cu = sanitized.codeUnitAt(left);
    if (cu == 0x29 || cu == 0x5D || cu == 0x7D) {
      depth++;
    } else if (cu == 0x28 || cu == 0x5B || cu == 0x7B) {
      if (depth == 0) break;
      depth--;
    } else if (depth == 0 && (cu == 0x3B /* ; */ || cu == 0x2C /* , */)) {
      break;
    }
    left--;
  }
  var clauseStart = left + 1;
  while (clauseStart < clampedStart &&
      _isWhitespace(sanitized.codeUnitAt(clauseStart))) {
    clauseStart++;
  }

  var right = clampedEnd;
  depth = 0;
  while (right < len) {
    final cu = sanitized.codeUnitAt(right);
    if (cu == 0x28 || cu == 0x5B || cu == 0x7B) {
      depth++;
    } else if (cu == 0x29 || cu == 0x5D || cu == 0x7D) {
      if (depth == 0) break;
      depth--;
    } else if (depth == 0 && (cu == 0x3B /* ; */ || cu == 0x2C /* , */)) {
      right++;
      break;
    }
    right++;
  }
  var clauseEnd = right > 0 ? right - 1 : 0;
  while (clauseEnd > clampedStart &&
      _isWhitespace(sanitized.codeUnitAt(clauseEnd))) {
    clauseEnd--;
  }

  return (clauseStart, clauseEnd);
}

Future<void> _checkGitHooksTip() async {
  try {
    final res = await Process.run('git', ['config', 'core.hooksPath']);
    final current = (res.stdout as String).trim();
    if (current != '.githooks') {
      stdout.writeln(
        '💡 Tip: Run "git config core.hooksPath .githooks" to enable automatic pre-commit checks.',
      );
    }
  } catch (_) {}
}
