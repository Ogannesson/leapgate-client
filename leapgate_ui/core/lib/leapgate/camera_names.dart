import 'dart:convert';

import '../common.dart' show SessionID;
import 'session.dart';

// The names of a camera session's cameras (13 §3.2 block B, R3-Q18; `LEAPGATE.md` §10.18): the
// displays JSON of the peer info has none, block 2's `leapgate_session_display_names` reads them
// from Rust's copy of the peer info.

/// `leapgate_session_display_names`: a JSON array of strings, the names in the order of the
/// numbers, `[]` without a session or before the login. Tests set a fake.
// TODO(M9 整合): `lgBind.leapgateSessionDisplayNames(sessionId: sessionId)` once the bridge is
// regenerated.
String Function(SessionID sessionId) sessionDisplayNames =
    (_) => throw UnimplementedError('TODO(M9 整合)');

/// Read once per peer info, kept with its first display: each peer info makes new ones.
final _names = Expando<List<String>>();

/// The name of each of [ffi]'s cameras, by number; an empty string where the remote device gave
/// none. The list comes only with the login (13 §3.4.4), so it is read once the peer info is in.
List<String> cameraNames(FFI ffi) {
  final displays = ffi.ffiModel.pi.displays;
  if (displays.isEmpty) return const [];
  return _names[displays.first] ??= () {
    final names = jsonDecode(sessionDisplayNames(ffi.sessionId)) as List;
    return [
      for (var i = 0; i < displays.length; i++)
        i < names.length ? '${names[i]}' : '',
    ];
  }();
}
