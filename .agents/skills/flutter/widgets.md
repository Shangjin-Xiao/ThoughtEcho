# Widget Traps

- Context in initState — `context` not fully available, defer to `didChangeDependencies`
- BuildContext after async — may be unmounted, check `mounted` first
- GlobalKey across routes — can cause "already has a parent" error
- Scaffold.of(context) — context must be below Scaffold, not same level
- Theme.of(context) — same issue, use Builder widget to get correct context
- Widget identity — same runtime type + key = same widget, state preserved
- SizedBox vs Container — SizedBox is const-friendly, prefer for fixed sizes
- Expensive build method — move computation to initState or FutureBuilder
