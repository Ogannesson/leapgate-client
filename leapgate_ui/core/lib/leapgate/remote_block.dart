import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../common.dart';
import '../consts.dart';
import '../models/platform_model.dart';

/// Whether the remote user may not use this device's home page (01 P1 block J), from what the
/// two inputs say, as upstream `canBeBlocked` (`flutter/lib/common.dart:3138-3160`): the
/// control permission the service reports wins ("true": may use it, "false": may not);
/// otherwise view-only access may not, and a custom access mode may not unless "allow remote
/// configuration modification" is on.
bool blockedForRemote({
  required String controlPermission,
  required String accessMode,
  required String allowRemoteConfig,
}) {
  if (controlPermission == 'true') return false;
  if (controlPermission == 'false') return true;
  final custom = accessMode != 'full' && accessMode != 'view';
  return accessMode == 'view' ||
      (custom &&
          !option2bool(
              kOptionAllowRemoteConfigModification, allowRemoteConfig));
}

/// The cover over the home page while the pointer on it belongs to the remote user (upstream
/// `shouldBeBlocked`, `buildRemoteBlock`, `flutter/lib/common.dart:3162-3205`): when the pointer
/// enters, ask Rust for the time of the last remote input and look 120 ms later; a remote input
/// since then blocks. Leaving unblocks.
class RemoteBlock extends ChangeNotifier {
  static const _window = Duration(milliseconds: 120);

  bool _blocked = false;
  Timer? _timer;

  bool get blocked => _blocked;

  /// The pointer entered the page, or the app came back to the foreground.
  Future<void> check() async {
    if (!await _canBeBlocked()) {
      _set(false);
      return;
    }
    final time0 = clock.now().millisecondsSinceEpoch;
    await bind.mainCheckMouseTime();
    _timer?.cancel();
    _timer = Timer(_window, () async {
      final d = time0 - await bind.mainGetMouseTime();
      _set(d < _window.inMilliseconds);
    });
  }

  void leave() {
    _timer?.cancel();
    _set(false);
  }

  Future<bool> _canBeBlocked() async => blockedForRemote(
        controlPermission: await bind.mainGetCommon(
            key: 'is-remote-modify-enabled-by-control-permissions'),
        accessMode: await bind.mainGetOption(key: kOptionAccessMode),
        allowRemoteConfig:
            await bind.mainGetOption(key: kOptionAllowRemoteConfigModification),
      );

  void _set(bool blocked) {
    if (_blocked == blocked) return;
    _blocked = blocked;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
