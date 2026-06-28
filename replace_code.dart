import 'dart:io';

void main() {
  var file = File('lib/pages/webdav_sync_page.dart');
  var content = file.readAsStringSync();

  content = content.replaceAll(
    "Text(l10n.webdavNoConflicts, style: theme.textTheme.titleMedium),",
    "Text(AppLocalizations.of(context)!.webdavNoConflicts, style: theme.textTheme.titleMedium),"
  );

  content = content.replaceAll(
    "Text(l10n.webdavAllConflictsResolved,",
    "Text(AppLocalizations.of(context)!.webdavAllConflictsResolved,"
  );

  file.writeAsStringSync(content);
}
