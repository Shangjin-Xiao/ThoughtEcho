import '../gen_l10n/app_localizations.dart';
import '../models/note_category.dart';
import '../services/database_service.dart';

extension NoteCategoryLocalizationExtension on NoteCategory {
  String localizedName(AppLocalizations l10n) {
    switch (id) {
      case DatabaseService.hiddenTagId:
        return l10n.hiddenTag;
      case DatabaseService.defaultCategoryIdHitokoto:
        return l10n.featureDailyQuote;
      case DatabaseService.defaultCategoryIdAnime:
        return l10n.hitokotoTypeA;
      case DatabaseService.defaultCategoryIdComic:
        return l10n.hitokotoTypeB;
      case DatabaseService.defaultCategoryIdGame:
        return l10n.hitokotoTypeC;
      case DatabaseService.defaultCategoryIdNovel:
        return l10n.hitokotoTypeD;
      case DatabaseService.defaultCategoryIdOriginal:
        return l10n.hitokotoTypeE;
      case DatabaseService.defaultCategoryIdInternet:
        return l10n.hitokotoTypeF;
      case DatabaseService.defaultCategoryIdOther:
        return l10n.hitokotoTypeG;
      case DatabaseService.defaultCategoryIdMovie:
        return l10n.hitokotoTypeH;
      case DatabaseService.defaultCategoryIdPoem:
        return l10n.hitokotoTypeI;
      case DatabaseService.defaultCategoryIdMusic:
        return l10n.hitokotoTypeJ;
      case DatabaseService.defaultCategoryIdPhilosophy:
        return l10n.hitokotoTypeK;
      default:
        return name;
    }
  }
}
