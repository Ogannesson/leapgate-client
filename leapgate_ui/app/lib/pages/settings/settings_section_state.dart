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

  /// "无法保存设置" in the current language.
  final String saveFailedText;

  bool _locked;
  final _keys = <String, GlobalKey>{};
  final _errors = <String, String>{};
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
  String? errorOf(String item) => _errors[item];

  @override
  void setError(String item, String? error) {
    if (error == null) {
      if (_errors.remove(item) == null) return;
    } else {
      _errors[item] = error;
    }
    notifyListeners();
  }

  @override
  Future<bool> save(String item, Future<bool> Function() write) async {
    final ok = await write();
    if (ok) {
      _errors.remove(item);
    } else {
      _errors[item] = saveFailedText;
    }
    notifyListeners();
    return ok;
  }

  @override
  void dispose() {
    _markTimer?.cancel();
    super.dispose();
  }
}
