import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../shell/tab_overlays.dart';
import 'settings_registry.dart';

/// The page's [SettingsSectionContext] for the section on screen; tests build one directly.
class SettingsSectionState extends ChangeNotifier
    implements SettingsSectionContext {
  SettingsSectionState(
      {required this.overlays,
      required this.saveFailedText,
      bool locked = false})
      : _locked = locked;

  @override
  final TabOverlays overlays;

  /// "无法保存设置" in the current language; the page sets it again on every build, so a line
  /// already shown follows a change of language.
  String saveFailedText;

  bool _locked;
  final _keys = <String, GlobalKey>{};
  final _errors = <String, String>{};

  /// Items whose last save failed: their line is [saveFailedText] as it is now.
  final _saveFailed = <String>{};
  String? _marked;
  Timer? _markTimer;

  @override
  bool get locked => _locked;

  set locked(bool value) {
    if (value == _locked) return;
    _locked = value;
    notifyListeners();
  }

  @override
  GlobalKey keyOf(String item) =>
      _keys.putIfAbsent(item, () => GlobalKey(debugLabel: item));

  @override
  bool isMarked(String item) => _marked == item;

  /// Marks [item] for about 2 seconds (02 §1.2.4).
  void mark(String item) {
    _markTimer?.cancel();
    _marked = item;
    notifyListeners();
    _markTimer = Timer(const Duration(seconds: 2), () {
      _marked = null;
      notifyListeners();
    });
  }

  @override
  String? errorOf(String item) =>
      _saveFailed.contains(item) ? saveFailedText : _errors[item];

  @override
  void setError(String item, String? error) {
    final hadSaveFailed = _saveFailed.remove(item);
    if (error == null) {
      if (_errors.remove(item) == null && !hadSaveFailed) return;
    } else {
      _errors[item] = error;
    }
    notifyListeners();
  }

  /// A [write] that throws counts as not saved; the error still goes on to the app's log.
  @override
  Future<bool> save(String item, Future<bool> Function() write) async {
    var ok = false;
    try {
      ok = await write();
    } finally {
      _errors.remove(item);
      if (ok) {
        _saveFailed.remove(item);
      } else {
        _saveFailed.add(item);
      }
      notifyListeners();
    }
    return ok;
  }

  bool _disposed = false;

  /// A save handed over as the page switched away (the page takes the focus first, so a number
  /// field commits) finishes after its section's context is gone; it has nothing to tell then.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _markTimer?.cancel();
    super.dispose();
  }
}
