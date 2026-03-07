# Navigation Traps

- Context after pop — Navigator.pop may invalidate context, don't use after
- `pushReplacement` — previous route disposed, can't go back
- Route arguments type safety — use generic `Navigator.push<T>` and cast result
- Deep link parsing — check null, validate format before navigating
- Named routes with arguments — pass via `RouteSettings.arguments`, retrieve with `ModalRoute.of(context)`
- Multiple navigation stacks — Navigator.push keeps old route in memory
- Back button handling — use `WillPopScope` (deprecated) or `PopScope` (3.16+)
- Route observer — must register with Navigator to receive callbacks
