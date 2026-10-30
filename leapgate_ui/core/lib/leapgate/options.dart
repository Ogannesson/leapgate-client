import 'package:flutter/foundation.dart';

import '../common.dart';
import '../models/platform_model.dart';

class _KeyNotifier extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Per-key change notification. Only writes made through this object notify; a value changed
/// elsewhere (the service process, a server policy, another scope object) does not.
mixin _KeyNotifiers {
  final _notifiers = <String, _KeyNotifier>{};

  /// Fires after every write of [key] made through this object, whether or not the value
  /// changed. Listeners read the new value with the scope's getter.
  Listenable listenable(String key) =>
      _notifiers.putIfAbsent(key, _KeyNotifier.new);

  void _changed(String key) => _notifiers[key]?.fire();
}

/// One place options are stored: Config, LocalConfig, or one remote device's options.
/// Reads are synchronous (Rust answers from memory or the peer's file). An empty value means
/// "not set"; writing '' removes the key.
abstract class OptionScope with _KeyNotifiers {
  String get(String key);

  Future<void> _write(String key, String value);

  bool getBool(String key) => option2bool(key, get(key));

  /// Returns whether the value was saved. Until S9 (03 §6.1) Rust reports no result, so this is
  /// true once the bridge call returns; an exception from the bridge propagates. After S9 it
  /// returns Rust's answer.
  Future<bool> set(String key, String value) async {
    await _write(key, value);
    _changed(key);
    return true;
  }

  Future<bool> setBool(String key, bool value) =>
      set(key, bool2option(key, value));
}

/// Config: this device's settings (`Leapgate2.toml` options). On the installed version the
/// service process owns them; the UI process reads its copy, which Rust refreshes over IPC, and a
/// write goes to the service over IPC.
class _ConfigScope extends OptionScope {
  @override
  String get(String key) => bind.mainGetOptionSync(key: key);

  @override
  Future<void> _write(String key, String value) =>
      bind.mainSetOption(key: key, value: value);
}

/// LocalConfig: this user's UI preferences (`Leapgate_local.toml`).
class _LocalScope extends OptionScope {
  @override
  String get(String key) => bind.mainGetLocalOption(key: key);

  @override
  Future<void> _write(String key, String value) =>
      bind.mainSetLocalOption(key: key, value: value);
}

/// One remote device's options (its peer file). While a session to that device is open, read
/// and write them through the session's [SessionOptions] instead: the session reads its own
/// in-memory copy and does not see writes made here.
class _PeerScope extends OptionScope {
  final String id;

  _PeerScope(this.id);

  @override
  String get(String key) => bind.mainGetPeerOptionSync(id: id, key: key);

  @override
  Future<void> _write(String key, String value) =>
      bind.mainSetPeerOption(id: id, key: key, value: value);
}

/// Options of this device and of remote devices, plus the environment flags pages need.
/// One instance for the whole app (held by the global model holder): notifications only reach
/// listeners of the same instance.
class OptionsModel {
  final OptionScope config = _ConfigScope();
  final OptionScope local = _LocalScope();
  final _peers = <String, OptionScope>{};

  /// The same object for the same [id], so its listeners hear every write made through it.
  OptionScope peer(String id) => _peers.putIfAbsent(id, () => _PeerScope(id));

  /// The key is overridden by built-in settings and can't be changed. Never true in Leapgate
  /// today (02 §1.1, R2-Q4); the settings page keeps the read-only style for it.
  bool isFixed(String key) => bind.mainIsOptionFixed(key: key);

  /// Installed version, as opposed to the portable one.
  bool get isInstalled => bind.mainIsInstalled();
}

/// One session's options: the peer options as the session sees them (its in-memory copy, saved
/// to the peer file on write) and the session's toggle options. Toggle options are 'Y' or empty,
/// so use [getToggle] / [toggle] for them, not [option2bool] / [bool2option] (upstream
/// common.dart:1676-1678).
class SessionOptions with _KeyNotifiers {
  final SessionID sessionId;

  SessionOptions(this.sessionId);

  /// Null once Rust no longer has the session.
  Future<String?> get(String key) =>
      bind.sessionGetOption(sessionId: sessionId, arg: key);

  /// Returns whether the value was saved; see [OptionScope.set].
  Future<bool> set(String key, String value) async {
    await bind.sessionPeerOption(sessionId: sessionId, name: key, value: value);
    _changed(key);
    return true;
  }

  /// False once Rust no longer has the session.
  bool getToggle(String key) =>
      bind.sessionGetToggleOptionSync(sessionId: sessionId, arg: key);

  /// Flips the toggle option. Returns whether it was saved; see [OptionScope.set].
  Future<bool> toggle(String key) async {
    await bind.sessionToggleOption(sessionId: sessionId, value: key);
    _changed(key);
    return true;
  }
}
