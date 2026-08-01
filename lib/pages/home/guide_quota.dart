/// 主页各 tab 上被动引导的打扰配额。
///
/// 「被动引导」指切到某个 tab 就自动弹出来的气泡，归这里管的有 9 个：
/// 首页 1、记录页 4、智能推送入口 1、设置页 3。不限量的话，新用户第一次把
/// 四个 tab 点一遍会在几十秒内被连续打断——光记录页一次就能排出 4 个。
///
/// 两层限制缺一不可：
/// - **每次进入页面最多 1 个**：只限会话总数的话，同一页里连弹的问题还在；
/// - **一次会话最多 [sessionQuota] 个**：只限每页 1 个的话，把四个 tab 点一遍
///   仍然会被打断四次。
///
/// 会话上限取 2 而不是 1，是因为这 9 个要靠它慢慢放：卡死在 1，排在后面的
/// 实际上永远不会露面。2 能让它们在五六次启动内摊完，同时任何单次使用都还算安静。
///
/// 两类引导**不**走这个配额：
/// - 用户操作直接触发的（删除笔记后提示回收站在哪）——那是对刚才那次操作的回应，
///   延后反而莫名其妙；
/// - 编辑器和新建笔记对话框里的 4 个——它们的节流是「每次打开只弹 1 个」，
///   由各自的 `showFirstAvailable` 负责，和 tab 切换无关。
class GuideQuota {
  GuideQuota({this.sessionQuota = 2});

  /// 一次会话（一个 [GuideQuota] 实例的生命周期）内允许弹出的被动引导总数。
  final int sessionQuota;

  int _sessionShown = 0;
  bool _shownOnCurrentVisit = false;
  int? _currentPage;

  /// 本次会话已经弹过的被动引导数量。
  int get sessionShown => _sessionShown;

  /// 现在还能不能弹。
  bool get isAvailable => _sessionShown < sessionQuota && !_shownOnCurrentVisit;

  /// 页面切换。切到不同页面才算一次新的「进入」，重新给一个名额；
  /// 停在同一页上反复触发（列表加载完、目标就位等）不该刷新配额。
  void onPageChanged(int page) {
    if (page == _currentPage) return;
    _currentPage = page;
    _shownOnCurrentVisit = false;
  }

  /// 记账：确实弹出了一个气泡。只有真的显示了才调用，
  /// 目标没渲染、条件不满足而没弹出来的不能算进配额。
  void consume() {
    _sessionShown++;
    _shownOnCurrentVisit = true;
  }
}
