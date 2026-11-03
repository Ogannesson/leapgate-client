// The exit node directory (01 P1 block I "可用的出口", 第四期 D2): fetched when the exit page
// opens and on "Refresh", never polled.
import 'package:flutter/foundation.dart';

import 'account.dart';
import 'app_core.dart';
import 'exit_api.dart';

enum ExitDirectoryState { loading, ok, empty, unsupported, notLoggedIn, error }

class ExitDirectoryModel extends ChangeNotifier implements AccountData {
  ExitDirectoryModel(this._api);

  final ExitApi _api;

  var _state = ExitDirectoryState.loading;
  var _exits = const <ExitNode>[];
  var _open = false;
  var _confirming = false;

  /// Counts the loads and resets, so an answer that comes after a newer one is dropped.
  var _generation = 0;

  /// Signed out it is [ExitDirectoryState.notLoggedIn] without asking the server.
  ExitDirectoryState get state =>
      appCore.account.loggedIn ? _state : ExitDirectoryState.notLoggedIn;

  List<ExitNode> get exits =>
      state == ExitDirectoryState.ok ? _exits : const [];

  /// The exit page shows: loads once, and again after signing in.
  void open() {
    _open = true;
    load();
  }

  void close() => _open = false;

  /// Opening the page and "Refresh" / "Retry".
  Future<void> load() async {
    if (!appCore.account.loggedIn) {
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    _state = ExitDirectoryState.loading;
    notifyListeners();
    final answer = await _api.directory();
    if (generation != _generation) return;
    if (answer.status == ExitDirectoryStatus.notLoggedIn &&
        appCore.account.loggedIn &&
        !_confirming) {
      // The server no longer takes the token while the account area says signed in: the
      // account asks once (08 §2.3). A 401 there signs out (M4), which resets this; otherwise
      // its pull loads this again, and a second "not signed in" stays.
      _confirming = true;
      try {
        await appCore.account.refresh();
      } finally {
        _confirming = false;
      }
      if (generation != _generation) return;
    }
    _exits = answer.exits;
    _state = switch (answer.status) {
      ExitDirectoryStatus.ok =>
        answer.exits.isEmpty ? ExitDirectoryState.empty : ExitDirectoryState.ok,
      ExitDirectoryStatus.unsupported => ExitDirectoryState.unsupported,
      ExitDirectoryStatus.notLoggedIn => ExitDirectoryState.notLoggedIn,
      ExitDirectoryStatus.error => ExitDirectoryState.error,
    };
    notifyListeners();
  }

  // AccountData

  @override
  Future<void> loadCache() async {}

  /// After signing in or the account check: only while the page is open (no polling).
  @override
  Future<void> pull() async {
    if (_open) await load();
  }

  @override
  void reset() {
    _generation++;
    _state = ExitDirectoryState.loading;
    _exits = const [];
    notifyListeners();
  }
}
