import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/prompts.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../pages/files/file_dialogs.dart';

/// The whole content area below the title bar: the window close confirmation covers every tab.
const Object kWindowScope = #window;

/// Where a dialog shows (03 §4.5, 01 §4.5): over one session tab (scope: the device ID), over
/// the home tab (scope: null) or over every tab ([kWindowScope]). Each scope is an [Overlay]
/// above that content, so a dialog in one tab leaves the others usable.
class TabOverlays extends ChangeNotifier {
  final _keys = <Object?, GlobalKey<OverlayState>>{};
  final _open = <Object?, int>{};

  /// The dialogs shown over each scope, the last on top.
  final _shown = <Object?, List<_Shown>>{};

  GlobalKey<OverlayState> keyOf(Object? scope) =>
      _keys.putIfAbsent(scope, GlobalKey<OverlayState>.new);

  /// Whether a dialog covers [scope]; the session page then leaves the keyboard alone.
  bool isOpen(Object? scope) => (_open[scope] ?? 0) > 0;

  /// The tab of [scope] closed: what it still asks is answered with null.
  void forget(Object? scope) {
    for (final d in [...?_shown.remove(scope)]) {
      d.close(null);
    }
    _keys.remove(scope);
    _open.remove(scope);
  }

  /// The tab of [scope] is shown again: the top dialog takes the keyboard back, the button or
  /// field it had. One shown while the tab was in the background never had it (its autofocus
  /// failed under `ExcludeFocus`): it is built again, and takes it as on opening.
  void refocus(Object? scope) {
    final shown = _shown[scope]?.lastOrNull;
    final context = shown?.content.currentContext;
    if (shown == null || context == null) return;
    final node = FocusScope.of(context);
    if (node.hasFocus) return;
    if (node.focusedChild != null) {
      node.requestFocus();
    } else {
      shown.rebuild();
    }
  }

  /// Shows [builder]'s layer (an `LgDialogScrim` with its dialog) over [scope] and completes
  /// with what it passes to its `close`; null when the scope is not shown.
  Future<T?> show<T>(Object? scope,
      Widget Function(BuildContext context, void Function(T? result) close)
          builder) {
    final overlay = _keys[scope]?.currentState;
    if (overlay == null) return Future.value(null);
    final done = Completer<T?>();
    late final _Shown shown;
    void close(T? result) {
      if (done.isCompleted) return;
      shown.entry.remove();
      _shown[scope]?.remove(shown);
      _open[scope] = (_open[scope] ?? 1) - 1;
      notifyListeners();
      done.complete(result);
    }

    shown = _Shown((context) => builder(context, close),
        (result) => close(result as T?));
    overlay.insert(shown.entry);
    (_shown[scope] ??= []).add(shown);
    _open[scope] = (_open[scope] ?? 0) + 1;
    notifyListeners();
    return done.future;
  }
}

/// A dialog over a scope, in a focus scope of its own (what [TabOverlays.refocus] looks at).
class _Shown {
  _Shown(Widget Function(BuildContext context) builder, this.close) {
    entry = OverlayEntry(
        builder: (context) => FocusScope(
            child: Builder(key: content, builder: builder)));
  }

  late final OverlayEntry entry;

  /// Closes it unanswered.
  final void Function(Object? result) close;
  GlobalKey content = GlobalKey();

  /// Builds the dialog anew under a new key.
  void rebuild() {
    content = GlobalKey();
    entry.markNeedsBuild();
  }
}

/// [Prompter] over the tab overlays: the file transfer view's questions over the session's tab
/// (`pages/files/file_dialogs.dart`).
class ShellPrompter implements Prompter {
  ShellPrompter(this.overlays);

  final TabOverlays overlays;

  @override
  Future<T?> ask<T>(Prompt<T> prompt, {FFI? session}) =>
      showFilePrompt(overlays, session?.id, prompt);
}
