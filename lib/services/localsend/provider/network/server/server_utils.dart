import 'package:refena_flutter/refena_flutter.dart';
import 'package:common/model/state/server/server_state.dart';

class ServerUtils {
  final Ref Function() refFunc;
  final ServerState Function() getState;
  final ServerState? Function() getStateOrNull;
  final void Function(ServerState Function(ServerState?) builder) setState;

  ServerUtils({
    required this.refFunc,
    required this.getState,
    required this.getStateOrNull,
    required this.setState,
  });
}
