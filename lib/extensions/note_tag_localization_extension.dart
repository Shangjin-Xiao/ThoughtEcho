import '../gen_l10n/app_localizations.dart';
import '../models/note_tag.dart';
import '../services/database_service.dart';

extension NoteTagLocalizationExtension on NoteTag {
  String localizedName(AppLocalizations l10n) {
    switch (id) {
      case DatabaseService.hiddenTagId:
        return l10n.hiddenTag;
      case DatabaseService.defaultTagIdHitokoto:
        return l10n.featureDailyQuote;
      case DatabaseService.defaultTagIdAnime:
        return l10n.hitokotoTypeA;
      case DatabaseService.defaultTagIdComic:
        return l10n.hitokotoTypeB;
      case DatabaseService.defaultTagIdGame:
        return l10n.hitokotoTypeC;
      case DatabaseService.defaultTagIdNovel:
        return l10n.hitokotoTypeD;
      case DatabaseService.defaultTagIdOriginal:
        return l10n.hitokotoTypeE;
      case DatabaseService.defaultTagIdInternet:
        return l10n.hitokotoTypeF;
      case DatabaseService.defaultTagIdOther:
        return l10n.hitokotoTypeG;
      case DatabaseService.defaultTagIdMovie:
        return l10n.hitokotoTypeH;
      case DatabaseService.defaultTagIdPoem:
        return l10n.hitokotoTypeI;
      case DatabaseService.defaultTagIdMusic:
        return l10n.hitokotoTypeJ;
      case DatabaseService.defaultTagIdPhilosophy:
        return l10n.hitokotoTypeK;
      case DatabaseService.defaultTagIdJoke:
        return l10n.hitokotoTypeJoke;
      default:
        return name;
    }
  }
}
