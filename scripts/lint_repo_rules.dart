import 'dart:io';

/// Lightweight deterministic linter for ThoughtEcho repository conventions.
///
/// Enforces mechanical rules documented in `AGENTS.md` on newly added/modified
/// lines (or explicit files) without spinning up the full Dart analyzer.
///
/// Usage:
///   dart scripts/lint_repo_rules.dart                  # git diff HEAD
///   dart scripts/lint_repo_rules.dart --staged         # git diff --cached
///   dart scripts/lint_repo_rules.dart --base origin/main
///   dart scripts/lint_repo_rules.dart --files lib/pages/foo.dart
Future<void> main(List<String> args) async {
  final mode = _parseArgs(args);
  final linesToCheck = await _collectLines(mode);

  if (linesToCheck.isEmpty) {
    stdout.writeln('✅ Repo rules check passed (0 candidate lines).');
    return;
  }

  final violations = <String>[];
  for (final entry in linesToCheck) {
    _checkLine(entry, violations);
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

  stdout.writeln(
    '✅ Repo rules check passed (${linesToCheck.length} lines inspected).',
  );
}

enum _ScanModeType { workingTree, staged, baseRef, explicitFiles }

class _ScanMode {
  final _ScanModeType type;
  final String? baseRef;
  final List<String> files;

  const _ScanMode({
    required this.type,
    this.baseRef,
    this.files = const [],
  });
}

class _SourceLine {
  final String filePath;
  final int lineNumber;
  final String content;

  const _SourceLine({
    required this.filePath,
    required this.lineNumber,
    required this.content,
  });
}

_ScanMode _parseArgs(List<String> args) {
  if (args.isEmpty) {
    return const _ScanMode(type: _ScanModeType.workingTree);
  }
  if (args.contains('--staged')) {
    return const _ScanMode(type: _ScanModeType.staged);
  }
  final baseIdx = args.indexOf('--base');
  if (baseIdx != -1 && baseIdx + 1 < args.length) {
    return _ScanMode(
      type: _ScanModeType.baseRef,
      baseRef: args[baseIdx + 1],
    );
  }
  final filesIdx = args.indexOf('--files');
  if (filesIdx != -1) {
    return _ScanMode(
      type: _ScanModeType.explicitFiles,
      files: args.sublist(filesIdx + 1),
    );
  }
  return _ScanMode(
    type: _ScanModeType.explicitFiles,
    files: args.where((a) => !a.startsWith('-')).toList(),
  );
}

Future<List<_SourceLine>> _collectLines(_ScanMode mode) async {
  switch (mode.type) {
    case _ScanModeType.explicitFiles:
      final lines = <_SourceLine>[];
      for (final path in mode.files) {
        final file = File(path);
        if (!file.existsSync() || !path.endsWith('.dart')) continue;
        final rawLines = await file.readAsLines();
        for (var i = 0; i < rawLines.length; i++) {
          lines.add(
            _SourceLine(
              filePath: path.replaceAll('\\', '/'),
              lineNumber: i + 1,
              content: rawLines[i],
            ),
          );
        }
      }
      return lines;

    case _ScanModeType.staged:
      return _collectGitDiffLines(
          ['diff', '--cached', '--unified=0', '--', '*.dart']);

    case _ScanModeType.baseRef:
      return _collectGitDiffLines([
        'diff',
        '${mode.baseRef}...HEAD',
        '--unified=0',
        '--',
        '*.dart',
      ]);

    case _ScanModeType.workingTree:
      return _collectGitDiffLines(
          ['diff', 'HEAD', '--unified=0', '--', '*.dart']);
  }
}

Future<List<_SourceLine>> _collectGitDiffLines(List<String> gitArgs) async {
  final result = await Process.run('git', gitArgs);
  if (result.exitCode != 0) {
    return const [];
  }

  final output = result.stdout as String;
  final collected = <_SourceLine>[];
  String? currentFile;
  var currentNewLine = 0;

  final hunkHeader = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@');

  for (final rawLine in output.split('\n')) {
    if (rawLine.startsWith('+++ b/')) {
      currentFile = rawLine.substring(6).trim();
      continue;
    }
    final hunkMatch = hunkHeader.firstMatch(rawLine);
    if (hunkMatch != null) {
      currentNewLine = int.parse(hunkMatch.group(1)!);
      continue;
    }
    if (currentFile == null) continue;
    if (rawLine.startsWith('+') && !rawLine.startsWith('+++')) {
      collected.add(
        _SourceLine(
          filePath: currentFile,
          lineNumber: currentNewLine,
          content: rawLine.substring(1),
        ),
      );
      currentNewLine++;
    }
  }

  return collected;
}

final _tailwindHexRegex = RegExp(
  r'0xFF(6366F1|8B5CF6|10B981|F59E0B|EF4444|1E293B|0F172A|94A3B8)\b',
  caseSensitive: false,
);

final _materialNamedColorRegex = RegExp(
  r'\bColors\.(red|green|orange|grey|blue|white|black|amber|yellow|purple|pink|teal|cyan|indigo)\b',
);

final _rawSnackBarRegex = RegExp(
  r'ScaffoldMessenger\.of\([^)]*\)\.showSnackBar\s*\(',
);

final _themeStyleBranchRegex = RegExp(
  r'[!=]=\s*ThemeStyle\.(paper|plain|material)\b|\bThemeStyle\.(paper|plain|material)\s*[!=]=',
);

final _staticAppThemeRadiusRegex = RegExp(
  r'\bAppTheme\.(cardRadius|buttonRadius|inputRadius|dialogRadius|fabRadius)\b',
);

final _deletedApiRegex = RegExp(
  r'\b(generateDailyPrompt|receiveAndMerge)\s*\(|\bTimeUtils\.formatTime\s*\(',
);

void _checkLine(_SourceLine line, List<String> violations) {
  final trimmed = line.content.trimLeft();
  if (trimmed.startsWith('//') || line.content.contains('ignore: repo_lint')) {
    return;
  }

  final path = line.filePath;
  if (!path.startsWith('lib/')) {
    return;
  }

  final isUiLayer =
      path.startsWith('lib/pages/') || path.startsWith('lib/widgets/');

  if (_tailwindHexRegex.hasMatch(line.content)) {
    violations.add(
      '${line.filePath}:${line.lineNumber} [no-tailwind-hex] '
      'Do not use Tailwind palette literals; derive colors from ColorScheme or AppSemanticColors.',
    );
  }

  if (_deletedApiRegex.hasMatch(line.content)) {
    violations.add(
      '${line.filePath}:${line.lineNumber} [no-deleted-api] '
      'Call to deleted API detected (use streamGenerateDailyPrompt, formatRelativeDateTime/formatQuoteTime, or current sync flow).',
    );
  }

  if (!isUiLayer) return;

  if (_materialNamedColorRegex.hasMatch(line.content)) {
    violations.add(
      '${line.filePath}:${line.lineNumber} [no-material-named-colors] '
      'Use ColorScheme (onSurfaceVariant, surfaceContainerHighest, error) or AppSemanticColors instead of Colors.* in UI layer.',
    );
  }

  if (path != 'lib/widgets/app_snackbar.dart' &&
      _rawSnackBarRegex.hasMatch(line.content)) {
    violations.add(
      '${line.filePath}:${line.lineNumber} [no-raw-snackbar] '
      'Use AppSnackBar.info/success/warning/error instead of ScaffoldMessenger.of(context).showSnackBar.',
    );
  }

  if (path != 'lib/widgets/theme_style_selector.dart' &&
      path != 'lib/widgets/theme_style_preview.dart' &&
      _themeStyleBranchRegex.hasMatch(line.content)) {
    violations.add(
      '${line.filePath}:${line.lineNumber} [no-theme-style-branching] '
      'Do not branch on ThemeStyle in widgets; read shape/rule tokens from AppShapeTokens.of(context).',
    );
  }

  if (_staticAppThemeRadiusRegex.hasMatch(line.content)) {
    violations.add(
      '${line.filePath}:${line.lineNumber} [no-static-app-theme-radius] '
      'Use AppShapeTokens.of(context).cardRadius/buttonRadius/inputRadius/dialogRadius/fabRadius instead of static AppTheme.*Radius.',
    );
  }
}
