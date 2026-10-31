import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';
import 'package:flutter_hbb/leapgate/prompts.dart';
import 'package:flutter_hbb/leapgate/session.dart';

/// The whole content area below the title bar: the window close confirmation covers every tab.
const Object kWindowScope = #window;

/// Where a dialog shows (03 §4.5, 01 §4.5): over one session tab (scope: the device ID), over
/// the home tab (scope: null) or over every tab ([kWindowScope]). Each scope is an [Overlay]
/// above that content, so a dialog in one tab leaves the others usable.
class TabOverlays extends ChangeNotifier {
  final _keys = <Object?, GlobalKey<OverlayState>>{};
  final _open = <Object?, int>{};

  GlobalKey<OverlayState> keyOf(Object? scope) =>
      _keys.putIfAbsent(scope, GlobalKey<OverlayState>.new);

  /// Whether a dialog covers [scope]; the session page then leaves the keyboard alone.
  bool isOpen(Object? scope) => (_open[scope] ?? 0) > 0;

  /// The tab of [scope] closed.
  void forget(Object? scope) {
    _keys.remove(scope);
    _open.remove(scope);
  }

  /// Shows [builder]'s layer (an `LgDialogScrim` with its dialog) over [scope] and completes
  /// with what it passes to its `close`; null when the scope is not shown.
  Future<T?> show<T>(Object? scope,
      Widget Function(BuildContext context, void Function(T? result) close)
          builder) {
    final overlay = _keys[scope]?.currentState;
    if (overlay == null) return Future.value(null);
    final done = Completer<T?>();
    late final OverlayEntry entry;
    void close(T? result) {
      if (done.isCompleted) return;
      entry.remove();
      _open[scope] = (_open[scope] ?? 1) - 1;
      notifyListeners();
      done.complete(result);
    }

    entry = OverlayEntry(builder: (context) => builder(context, close));
    overlay.insert(entry);
    _open[scope] = (_open[scope] ?? 0) + 1;
    notifyListeners();
    return done.future;
  }
}

/// [Prompter] over the tab overlays. M2a has nothing that asks yet: the file transfer prompts
/// come with the file transfer view (M7a), so for now a question is logged and closed without
/// an answer, which each prompt reads as its "closed" case.
class ShellPrompter implements Prompter {
  ShellPrompter(this.overlays);

  final TabOverlays overlays;

  @override
  Future<T?> ask<T>(Prompt<T> prompt, {FFI? session}) async {
    lgBind.leapgateLog(
        level: 2,
        msg: 'leapgate ui: no dialog yet for ${prompt.runtimeType}');
    return null;
  }
}
