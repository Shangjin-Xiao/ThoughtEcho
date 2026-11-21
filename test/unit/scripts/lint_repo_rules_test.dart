import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String scriptPath;
  late String preCommitHookPath;
  late String dartExecutable;
  late Directory tempDir;

  setUpAll(() async {
    final repoRoot = _findRepoRoot();
    scriptPath =
        '$repoRoot${Platform.pathSeparator}scripts${Platform.pathSeparator}lint_repo_rules.dart';
    preCommitHookPath =
        '$repoRoot${Platform.pathSeparator}.githooks${Platform.pathSeparator}pre-commit';
    dartExecutable = await _resolveDartExecutable();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lint_repo_rules_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> initGitRepo() async {
    await _git(tempDir.path, ['init', '-b', 'main']);
    await _git(tempDir.path, ['config', 'user.email', 'ci@example.com']);
    await _git(tempDir.path, ['config', 'user.name', 'CI Bot']);
    await _writeFile(tempDir, 'README.md', '# Temp Repo\n');
    await _git(tempDir.path, ['add', 'README.md']);
    await _git(tempDir.path, ['commit', '-m', 'chore: initial commit']);
  }

  Future<ProcessResult> runLint(
    List<String> args, {
    String? workingDirectory,
  }) {
    return Process.run(
      dartExecutable,
      [scriptPath, ...args],
      workingDirectory: workingDirectory ?? tempDir.path,
      environment: {...Platform.environment, 'CI': 'true'},
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  group('Git failure hard-blocking & CLI validation', () {
    test(
      'fails with non-zero exit code when --base reference does not exist instead of passing with 0 lines',
      () async {
        await initGitRepo();

        final result = await runLint(['--base', 'origin/nonexistent-base']);

        expect(result.exitCode, isNonZero);
        expect(result.stderr as String, contains('Git command failed'));
        expect(result.stdout as String, isNot(contains('passed')));
      },
    );

    test(
      'fails with non-zero exit code when running git diff outside a Git repository',
      () async {
        final result = await runLint(const []);

        expect(result.exitCode, isNonZero);
        expect(result.stderr as String, contains('Git command failed'));
        expect(result.stdout as String, isNot(contains('passed')));
      },
    );

    test(
      'fails with non-zero exit code when --base is missing an argument or --files points to missing file',
      () async {
        await initGitRepo();

        final missingBase = await runLint(['--base']);
        expect(missingBase.exitCode, equals(2));
        expect(missingBase.stderr as String, contains('Invalid arguments'));

        final missingFile =
            await runLint(['--files', './lib/pages/ghost.dart']);
        expect(missingFile.exitCode, equals(2));
        expect(missingFile.stderr as String, contains('File does not exist'));
      },
    );
  });

  group('Path normalization & non-ASCII Chinese file paths', () {
    test(
      'detects violations in staged and committed non-ASCII Chinese file paths without quotePath bypass',
      () async {
        await initGitRepo();

        const chineseRelPath = 'lib/pages/中文笔记详情页.dart';
        await _writeFile(
          tempDir,
          chineseRelPath,
          '''
import 'package:flutter/material.dart';

Widget buildDemo() {
  return Container(color: Colors.red);
}
''',
        );

        await _git(tempDir.path, ['add', chineseRelPath]);
        final stagedResult = await runLint(['--staged']);
        expect(stagedResult.exitCode, equals(1));
        expect(
          stagedResult.stderr as String,
          contains('$chineseRelPath:4 [no-material-named-colors]'),
        );

        await _git(tempDir.path, ['commit', '-m', 'feat: add Chinese page']);
        final baseResult = await runLint(['--base', 'HEAD~1']);
        expect(baseResult.exitCode, equals(1));
        expect(
          baseResult.stderr as String,
          contains('$chineseRelPath:4 [no-material-named-colors]'),
        );
      },
    );

    test(
      'supports multi-commit --base SHA range and does not leak line numbers across deleted files',
      () async {
        await initGitRepo();

        await _writeFile(
          tempDir,
          'lib/pages/obsolete_page.dart',
          'void oldHelper() {}\n',
        );
        await _git(tempDir.path, ['add', 'lib/pages/obsolete_page.dart']);
        await _git(tempDir.path, ['commit', '-m', 'chore: add obsolete page']);

        final beforeSha = (await Process.run(
          'git',
          const ['rev-parse', 'HEAD'],
          workingDirectory: tempDir.path,
          stdoutEncoding: utf8,
        ))
            .stdout
            .toString()
            .trim();

        // Commit 1 in push: introduce violation in first_commit_page.dart
        await _writeFile(
          tempDir,
          'lib/pages/first_commit_page.dart',
          '''
import 'package:flutter/material.dart';

Widget buildFirst() => Container(color: Colors.amber);
''',
        );
        await _git(tempDir.path, ['add', 'lib/pages/first_commit_page.dart']);
        await _git(tempDir.path, ['commit', '-m', 'feat: commit 1']);

        // Commit 2 in push: delete obsolete_page.dart and add clean second_page.dart
        await File('${tempDir.path}/lib/pages/obsolete_page.dart').delete();
        await _writeFile(
          tempDir,
          'lib/pages/second_commit_page.dart',
          '''
import 'package:flutter/material.dart';

Widget buildSecond() => Container(color: Colors.transparent);
''',
        );
        await _git(tempDir.path, [
          'add',
          '-u',
          'lib/pages/obsolete_page.dart',
        ]);
        await _git(tempDir.path, ['add', 'lib/pages/second_commit_page.dart']);
        await _git(tempDir.path, ['commit', '-m', 'feat: commit 2']);

        final rangeResult = await runLint(['--base', beforeSha]);
        expect(rangeResult.exitCode, equals(1));
        final err = rangeResult.stderr as String;
        expect(
          err,
          contains(
            'lib/pages/first_commit_page.dart:3 [no-material-named-colors]',
          ),
        );
        expect(err, isNot(contains('obsolete_page.dart')));
        expect(err, isNot(contains('second_commit_page.dart')));
      },
    );

    test(
      'normalizes ./ relative paths and absolute paths in --files mode to repo-relative paths',
      () async {
        await initGitRepo();

        final targetFile = await _writeFile(
          tempDir,
          'lib/widgets/sample_card.dart',
          '''
import 'package:flutter/material.dart';

Widget buildSample() => Container(color: Colors.blue);
''',
        );

        final dotSlashResult = await runLint([
          '--files',
          './lib/widgets/sample_card.dart',
        ]);
        expect(dotSlashResult.exitCode, equals(1));
        expect(
          dotSlashResult.stderr as String,
          contains('lib/widgets/sample_card.dart:3 [no-material-named-colors]'),
        );

        final absPathResult = await runLint(['--files', targetFile.path]);
        expect(absPathResult.exitCode, equals(1));
        expect(
          absPathResult.stderr as String,
          contains('lib/widgets/sample_card.dart:3 [no-material-named-colors]'),
        );
      },
    );

    test(
      'handles paths containing spaces and " b/" segments in --staged and --base modes without git show failure',
      () async {
        await initGitRepo();

        const trickyPath = 'lib/pages/a b/spaced_page.dart';
        await _writeFile(
          tempDir,
          trickyPath,
          '''
import 'package:flutter/material.dart';

Widget buildSpaced() => Container(color: Colors.green);
''',
        );

        await _git(tempDir.path, ['add', trickyPath]);
        final stagedResult = await runLint(['--staged']);
        expect(stagedResult.exitCode, equals(1));
        expect(
          stagedResult.stderr as String,
          contains('$trickyPath:3 [no-material-named-colors]'),
        );
        expect(
          stagedResult.stderr as String,
          isNot(contains('Git command failed')),
        );

        await _git(tempDir.path, ['commit', '-m', 'feat: add spaced path']);
        final baseResult = await runLint(['--base', 'HEAD~1']);
        expect(baseResult.exitCode, equals(1));
        expect(
          baseResult.stderr as String,
          contains('$trickyPath:3 [no-material-named-colors]'),
        );
      },
    );

    test(
      'preserves exact line numbers when an added source line starts with ++ at column 0',
      () async {
        await initGitRepo();

        await _writeFile(
          tempDir,
          'lib/pages/prefix_inc_page.dart',
          '''
import 'package:flutter/material.dart';

int bumpCounter(int count) {
  return count;
}
''',
        );
        await _git(tempDir.path, ['add', 'lib/pages/prefix_inc_page.dart']);
        await _git(tempDir.path, ['commit', '-m', 'chore: add baseline']);

        await _writeFile(
          tempDir,
          'lib/pages/prefix_inc_page.dart',
          '''
import 'package:flutter/material.dart';

int bumpCounter(int count) {
++count;
  return count;
}

Widget buildBadAfterPlusPlus() => Container(color: Colors.red);
''',
        );

        final result = await runLint(const []);
        expect(result.exitCode, equals(1));
        expect(
          result.stderr as String,
          contains(
              'lib/pages/prefix_inc_page.dart:8 [no-material-named-colors]'),
        );
      },
    );
  });

  group('Multiline lexical windows & showSnackBar / comment / string stripping',
      () {
    test(
      'blocks multiline wrapped showSnackBar and local messenger variable aliases while ignoring strings, comments, and app_snackbar.dart',
      () async {
        await initGitRepo();

        await _writeFile(
          tempDir,
          'lib/widgets/note_sheet.dart',
          '''
import 'package:flutter/material.dart';

void notifyMultiline(BuildContext context) {
  // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ok')));
  const docHint = 'Do not call messenger.showSnackBar(bar) directly';
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(
    const SnackBar(content: Text(docHint)),
  );
}

void notifyViaAlias(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(content: Text('alias')),
  );
}

void notifyIgnored(BuildContext context) {
  // ignore: repo_lint
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('exempt')));
}
''',
        );

        await _writeFile(
          tempDir,
          'lib/widgets/app_snackbar.dart',
          '''
import 'package:flutter/material.dart';

class AppSnackBar {
  static void show(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('wrapper')));
  }
}
''',
        );

        await _git(tempDir.path, [
          'add',
          'lib/widgets/note_sheet.dart',
          'lib/widgets/app_snackbar.dart',
        ]);
        final result = await runLint(['--staged']);

        expect(result.exitCode, equals(1));
        final err = result.stderr as String;
        expect(
            err, contains('lib/widgets/note_sheet.dart:8 [no-raw-snackbar]'));
        expect(
          err,
          contains('lib/widgets/note_sheet.dart:15 [no-raw-snackbar]'),
        );
        expect(err, isNot(contains('note_sheet.dart:4')));
        expect(err, isNot(contains('note_sheet.dart:5')));
        expect(err, isNot(contains('note_sheet.dart:24')));
        expect(err, isNot(contains('app_snackbar.dart')));
      },
    );

    test(
      'scans multiline call window when an interior line changes without false-positiving on untouched legacy siblings',
      () async {
        await initGitRepo();

        await _writeFile(
          tempDir,
          'lib/pages/legacy_host_page.dart',
          '''
import 'package:flutter/material.dart';

Widget buildLegacyPage(BuildContext context) {
  return Column(
    children: [
      Container(
        color: Colors.red,
        child: const Text(
          'legacy',
          style: TextStyle(fontSize: 18),
        ),
      ),
      ElevatedButton(
        onPressed: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            const SnackBar(content: Text('before')),
          );
        },
        child: const Text('tap'),
      ),
    ],
  );
}
''',
        );
        await _git(tempDir.path, ['add', 'lib/pages/legacy_host_page.dart']);
        await _git(
            tempDir.path, ['commit', '-m', 'chore: baseline legacy file']);

        // Only touch line 18 inside the multiline showSnackBar call; legacy
        // Colors.red (line 7) and TextStyle(fontSize: 18) (line 10) remain untouched.
        await _writeFile(
          tempDir,
          'lib/pages/legacy_host_page.dart',
          '''
import 'package:flutter/material.dart';

Widget buildLegacyPage(BuildContext context) {
  return Column(
    children: [
      Container(
        color: Colors.red,
        child: const Text(
          'legacy',
          style: TextStyle(fontSize: 18),
        ),
      ),
      ElevatedButton(
        onPressed: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            const SnackBar(content: Text('after')),
          );
        },
        child: const Text('tap'),
      ),
    ],
  );
}
''',
        );

        final result = await runLint(const []);
        expect(result.exitCode, equals(1));
        final err = result.stderr as String;
        expect(
          err,
          contains('lib/pages/legacy_host_page.dart:17 [no-raw-snackbar]'),
        );
        expect(err, isNot(contains('[no-material-named-colors]')));
        expect(err, isNot(contains('[no-hardcoded-typography]')));
      },
    );

    test(
      'does not treat ignore_for_file or ignore directives inside string literals as real lint exemptions',
      () async {
        await initGitRepo();

        await _writeFile(
          tempDir,
          'lib/pages/sneaky_page_v2.dart',
          '''
import 'package:flutter/material.dart';

const fakeFileDirective = '// ignore_for_file: repo_lint';
const fakeRawDirective = r'// ignore_for_file: repo_lint';

Widget buildSneaky() {
  return Container(
    color: Colors.purple, // ignore: repo_lint
  );
}

Widget buildWithFakePrecedingLineString() {
  const fakeAbove = '// ignore: repo_lint';
  return Container(color: Colors.teal, key: const ValueKey(fakeAbove));
}

Widget buildWithFakeInlineString() {
  return Container(color: Colors.orange, key: const ValueKey('// ignore: repo_lint'));
}
''',
        );

        await _writeFile(
          tempDir,
          'lib/pages/exempted_legacy_v2.dart',
          '''
// ignore_for_file: repo_lint
import 'package:flutter/material.dart';

Widget buildExempted() => Container(color: Colors.purple);
''',
        );

        final result = await runLint([
          '--files',
          './lib/pages/sneaky_page_v2.dart',
          './lib/pages/exempted_legacy_v2.dart',
        ]);
        expect(result.exitCode, equals(1));
        final err = result.stderr as String;
        expect(
          err,
          contains('lib/pages/sneaky_page_v2.dart:1 [no-banned-file-suffix]'),
        );
        expect(
          err,
          contains(
            'lib/pages/sneaky_page_v2.dart:14 [no-material-named-colors]',
          ),
        );
        expect(
          err,
          contains(
            'lib/pages/sneaky_page_v2.dart:18 [no-material-named-colors]',
          ),
        );
        expect(err, isNot(contains('sneaky_page_v2.dart:8')));
        expect(err, isNot(contains('exempted_legacy_v2.dart')));
      },
    );
  });

  group('Expanded UI, architecture, suffix, and test sanitization rules', () {
    test(
      'blocks opacity and accent Colors.* variants while exempting Colors.transparent',
      () async {
        await initGitRepo();

        await _writeFile(
          tempDir,
          'lib/pages/colors_check_page.dart',
          '''
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;

List<Color> buildPalette() => [
      Colors.transparent,
      Colors.black54,
      Colors.white70,
      Colors.blueAccent,
      material.Colors.red,
    ];
''',
        );

        final result = await runLint([
          '--files',
          './lib/pages/colors_check_page.dart',
        ]);
        expect(result.exitCode, equals(1));
        final err = result.stderr as String;
        expect(err, isNot(contains('colors_check_page.dart:5')));
        expect(
          err,
          contains(
            'lib/pages/colors_check_page.dart:6 [no-material-named-colors]',
          ),
        );
        expect(
          err,
          contains(
            'lib/pages/colors_check_page.dart:7 [no-material-named-colors]',
          ),
        );
        expect(
          err,
          contains(
            'lib/pages/colors_check_page.dart:8 [no-material-named-colors]',
          ),
        );
        expect(
          err,
          contains(
            'lib/pages/colors_check_page.dart:9 [no-material-named-colors]',
          ),
        );
      },
    );

    test(
      'blocks numeric BorderRadius.circular(N) in UI widgets while allowing AppShapeTokens, 0/999, and exempted audit paths',
      () async {
        await initGitRepo();

        await _writeFile(
          tempDir,
          'lib/widgets/custom_surface_card.dart',
          '''
import 'package:flutter/material.dart';

BorderRadius badMultilineRadius() => BorderRadius.circular(
      12,
    );

BorderRadius zeroRadius() => BorderRadius.circular(0);
BorderRadius pillRadius() => BorderRadius.circular(999);
BorderRadius tokenRadius(double cardRadius) => BorderRadius.circular(cardRadius);
BorderRadius mixedBadRadius(bool isCard, double cardRadius) =>
    BorderRadius.circular(isCard ? cardRadius : 12);
BorderRadius mixedPillRadius(bool isPill, double cardRadius) =>
    BorderRadius.circular(isPill ? 999 : cardRadius);
''',
        );

        await _writeFile(
          tempDir,
          'lib/widgets/accessible_color_grid.dart',
          '''
import 'package:flutter/material.dart';

BorderRadius colorDotRadius() => BorderRadius.circular(21);
''',
        );

        final result = await runLint([
          '--files',
          './lib/widgets/custom_surface_card.dart',
          './lib/widgets/accessible_color_grid.dart',
        ]);
        expect(result.exitCode, equals(1));
        final err = result.stderr as String;
        expect(
          err,
          contains(
            'lib/widgets/custom_surface_card.dart:3 [no-hardcoded-border-radius]',
          ),
        );
        expect(err, isNot(contains('custom_surface_card.dart:7')));
        expect(err, isNot(contains('custom_surface_card.dart:8')));
        expect(err, isNot(contains('custom_surface_card.dart:9')));
        expect(
          err,
          contains(
            'lib/widgets/custom_surface_card.dart:11 [no-hardcoded-border-radius]',
          ),
        );
        expect(err, isNot(contains('custom_surface_card.dart:13')));
        expect(err, isNot(contains('accessible_color_grid.dart')));
      },
    );

    test(
      'blocks hardcoded fontSize, fontWeight, and height inside TextStyle while allowing SizedBox(height:) and rich-text exempted files',
      () async {
        await initGitRepo();

        await _writeFile(
          tempDir,
          'lib/pages/typography_check_page.dart',
          '''
import 'package:flutter/material.dart';

Widget buildTypographySample(ColorScheme scheme) {
  return Column(
    children: [
      const SizedBox(height: 16),
      Text(
        'title',
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.5,
        ),
      ),
      Text(
        'color-only',
        style: TextStyle(color: scheme.error),
      ),
    ],
  );
}
''',
        );

        await _writeFile(
          tempDir,
          'lib/widgets/quote_content_widget.dart',
          '''
import 'package:flutter/material.dart';

const richHeaderStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.1);
''',
        );

        final result = await runLint([
          '--files',
          './lib/pages/typography_check_page.dart',
          './lib/widgets/quote_content_widget.dart',
        ]);
        expect(result.exitCode, equals(1));
        final err = result.stderr as String;
        expect(
          err,
          contains(
            'lib/pages/typography_check_page.dart:11 [no-hardcoded-typography]',
          ),
        );
        expect(
          err,
          contains(
            'lib/pages/typography_check_page.dart:12 [no-hardcoded-typography]',
          ),
        );
        expect(
          err,
          contains(
            'lib/pages/typography_check_page.dart:13 [no-hardcoded-typography]',
          ),
        );
        expect(err, isNot(contains('typography_check_page.dart:6')));
        expect(err, isNot(contains('typography_check_page.dart:18')));
        expect(err, isNot(contains('quote_content_widget.dart')));
      },
    );

    test(
      'blocks raw Sentry.captureException outside unified_log_service/sentry_helper and blocks banned file suffixes',
      () async {
        await initGitRepo();

        await _writeFile(
          tempDir,
          'lib/services/sync_service_v2.dart',
          '''
class Sentry {
  static Future<void> captureException(Object error) async {}
}

Future<void> syncNotes() async {
  try {
    throw StateError('boom');
  } catch (e) {
    await Sentry.captureException(e);
  }
}
''',
        );

        await _writeFile(
          tempDir,
          'lib/services/unified_log_service.dart',
          '''
class Sentry {
  static Future<void> captureException(Object error) async {}
}

Future<void> forwardToSentry(Object error) => Sentry.captureException(error);
''',
        );

        final result = await runLint([
          '--files',
          './lib/services/sync_service_v2.dart',
          './lib/services/unified_log_service.dart',
        ]);
        expect(result.exitCode, equals(1));
        final err = result.stderr as String;
        expect(
          err,
          contains(
            'lib/services/sync_service_v2.dart:1 [no-banned-file-suffix]',
          ),
        );
        expect(
          err,
          contains('lib/services/sync_service_v2.dart:9 [no-raw-sentry]'),
        );
        expect(err, isNot(contains('unified_log_service.dart')));
      },
    );

    test(
      'blocks newly added concrete real place names in test/ while allowing synthetic placeholders',
      () async {
        await initGitRepo();

        // Construct concrete place names at runtime from code points so this
        // test source file itself remains 100% free of real place literals.
        final concreteCity =
            String.fromCharCodes(const [0x5317, 0x4EAC, 0x5E02]);
        final concreteDistrict =
            String.fromCharCodes(const [0x6D77, 0x6DC0, 0x533A]);
        final shortCityCd = String.fromCharCodes(const [0x6210, 0x90FD]);
        final shortCityXa = String.fromCharCodes(const [0x897F, 0x5B89]);
        final shortCityBd = String.fromCharCodes(const [0x4FDD, 0x5B9A]);
        final shortCityZs = String.fromCharCodes(const [0x4E2D, 0x5C71]);

        await _writeFile(
          tempDir,
          'test/unit/models/sample_location_test.dart',
          '''
void main() {
  const safeLocation = '示例省·示例市';
  const safePoi = 'MockPOI';
  // 任务完成都会释放资源，每次生成都正确，持续集成都通过，八成都在缓存里
  // 东西安放整齐，把东西安顿好，东西安装与选中山形图标、卡片中山水插画、确保定位回退均不会误报
  const normalWords = '时区与富文本选区不会误报，每次生成都和预期一致';
  const leakedLocation = '$concreteCity$concreteDistrict';
  const leakedSentenceA = '${shortCityCd}有哪些景点';
  const leakedSentenceB = '${shortCityCd}在这里';
  const leakedSentenceC = '${shortCityXa}安全检查';
  const leakedSentenceD = '到达${shortCityCd}正确吗';
  const leakedSentenceE = '选${shortCityZs}作为默认城市';
  const leakedActionA = '新建${shortCityCd}项目';
  const leakedActionB = '重构${shortCityCd}模块';
  const leakedActionC = '做完${shortCityCd}项目';
  const leakedActionD = '点击${shortCityZs}卡片';
  const leakedActionE = '明确${shortCityBd}路线';
  const leakedActionF = '股东${shortCityXa}会议';
}
''',
        );

        await _git(tempDir.path, [
          'add',
          'test/unit/models/sample_location_test.dart',
        ]);
        final result = await runLint(['--staged']);
        expect(result.exitCode, equals(1));
        final err = result.stderr as String;
        for (var line = 7; line <= 18; line++) {
          expect(
            err,
            contains(
              'test/unit/models/sample_location_test.dart:$line [no-real-place-names-in-tests]',
            ),
          );
        }
        for (var line = 2; line <= 6; line++) {
          expect(err, isNot(contains('sample_location_test.dart:$line')));
        }
      },
    );

    test(
      'blocks deleted API calls both with and without receiver qualifiers while allowing replacement APIs',
      () async {
        await initGitRepo();

        await _writeFile(
          tempDir,
          'lib/services/prompt_caller.dart',
          '''
class AIService {
  static Future<String> generateDailyPrompt() async => '';
  Future<String> streamGenerateDailyPrompt() async => '';
}

class SyncService {
  Future<void> receiveAndMerge() async {}
}

class TimeUtils {
  static String formatTime(DateTime dt) => '';
  static String formatRelativeDateTime(DateTime dt) => '';
}

Future<void> runCalls(AIService ai, SyncService sync, DateTime now) async {
  await AIService.generateDailyPrompt();
  await ai.streamGenerateDailyPrompt();
  await sync.receiveAndMerge();
  TimeUtils.formatTime(now);
  TimeUtils.formatRelativeDateTime(now);
}
''',
        );

        final result = await runLint([
          '--files',
          './lib/services/prompt_caller.dart',
        ]);
        expect(result.exitCode, equals(1));
        final err = result.stderr as String;
        expect(
          err,
          contains('lib/services/prompt_caller.dart:16 [no-deleted-api]'),
        );
        expect(
          err,
          contains('lib/services/prompt_caller.dart:18 [no-deleted-api]'),
        );
        expect(
          err,
          contains('lib/services/prompt_caller.dart:19 [no-deleted-api]'),
        );
        expect(err, isNot(contains('prompt_caller.dart:17')));
        expect(err, isNot(contains('prompt_caller.dart:20')));
      },
    );
  });

  group('Pre-commit hook SIGPIPE (141) regression guard', () {
    test(
      'blocks secret token on line 1 of a large (>256KB) staged diff without pipefail SIGPIPE bypass',
      () async {
        if (Platform.isWindows) {
          return;
        }
        await initGitRepo();

        // Copy scripts/lint_repo_rules.dart into temp repo so the hook can run end-to-end.
        await _writeFile(
          tempDir,
          'scripts/lint_repo_rules.dart',
          await File(scriptPath).readAsString(),
        );
        await _git(tempDir.path, ['add', 'scripts/lint_repo_rules.dart']);
        await _git(tempDir.path, ['commit', '-m', 'chore: add lint script']);

        // Stage an early secret followed by >300KB of padding lines to exceed OS pipe buffers.
        final fakeToken = 'sk-${'A1b2C3d4E5f6' * 3}';
        final largePayload = StringBuffer()
          ..writeln('const leaked = "$fakeToken";');
        for (var i = 0; i < 6000; i++) {
          largePayload.writeln(
            'const paddingLine$i = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";',
          );
        }
        await _writeFile(tempDir, 'notes_dump.txt', largePayload.toString());
        await _git(tempDir.path, ['add', 'notes_dump.txt']);

        final hookResult = await Process.run(
          'bash',
          [preCommitHookPath],
          workingDirectory: tempDir.path,
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );

        expect(hookResult.exitCode, equals(1));
        expect(
          hookResult.stderr as String,
          contains('Potential API key or secret token detected'),
        );
      },
    );
  });
}

String _findRepoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    final candidate = File(
      '${dir.path}${Platform.pathSeparator}scripts${Platform.pathSeparator}lint_repo_rules.dart',
    );
    if (candidate.existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Could not locate repository root from ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

Future<String> _resolveDartExecutable() async {
  final exeName = Platform.isWindows ? 'dart.exe' : 'dart';
  try {
    final probe = await Process.run(exeName, const ['--version']);
    if (probe.exitCode == 0) {
      return exeName;
    }
  } on ProcessException {
    // Fall back to resolving relative to flutter_tester inside Flutter SDK.
  }

  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = File('${dir.path}${Platform.pathSeparator}$exeName');
    if (candidate.existsSync()) {
      return candidate.path;
    }
    final binCandidate = File(
      '${dir.path}${Platform.pathSeparator}bin${Platform.pathSeparator}$exeName',
    );
    if (binCandidate.existsSync()) {
      return binCandidate.path;
    }
    dir = dir.parent;
  }
  return exeName;
}

Future<File> _writeFile(
  Directory root,
  String relativePath,
  String content,
) async {
  final normalized = relativePath.replaceAll('/', Platform.pathSeparator);
  final file = File('${root.path}${Platform.pathSeparator}$normalized');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  return file;
}

Future<void> _git(String workingDirectory, List<String> args) async {
  final res = await Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (res.exitCode != 0) {
    throw StateError(
      'git ${args.join(' ')} failed (${res.exitCode}): ${res.stderr}',
    );
  }
}
