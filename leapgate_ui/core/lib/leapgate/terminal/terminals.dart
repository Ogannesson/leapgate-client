// The terminal view's tabs (13 §2.2; `LEAPGATE.md` §10.18). Upstream kept this in its terminal
// window (`desktop/pages/terminal_tab_page.dart`, `terminal_page.dart`); here a terminal view
// has one [TerminalTabs], the app draws it. [TerminalOpen] and [terminalOpenState] are step 0's.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/terminal_copy_shortcut.dart';
import 'package:flutter_hbb/models/terminal_model.dart';

import '../app_core.dart';
import '../connection.dart';
import '../session.dart';

/// The terminals of one `ConnType.terminal` session (`FFI.terminals`): numbering, closing,
/// keeping and restoring them, the clipboard requests.
class TerminalTabs extends ChangeNotifier {
  TerminalTabs(this._ffi) {
    _ffi.connection.addListener(_onConnection);
    _notice.addListener(notifyListeners);
  }

  final FFI _ffi;
  final _terminals = <TerminalModel>[];
  var _selected = 0;

  /// Numbers are this side's, from 1 and only growing (upstream `terminal_tab_page.dart:57`);
  /// a restored shell keeps the remote device's number.
  var _nextId = 1;
  var _connected = false;
  final _notice = TerminalClipboardNoticeCoordinator<TerminalModel>();
  Completer<bool>? _disconnectAsk;

  /// In tab order; empty until the first connection is up.
  List<TerminalModel> get terminals => List.unmodifiable(_terminals);

  int get selected => _selected;
  TerminalModel? get current =>
      _terminals.isEmpty ? null : _terminals[_selected];

  /// "+", "新建终端" and Ctrl+Shift+T work only while connected (13 §2.2.2 block B).
  bool get canAdd => _ffi.connection.stage == ConnStage.connected;

  void select(int index) {
    if (index < 0 || index >= _terminals.length || index == _selected) return;
    _selected = index;
    notifyListeners();
  }

  /// A new terminal, selected.
  void add() {
    if (!canAdd) return;
    final model = _add(_nextId++);
    _selected = _terminals.length - 1;
    notifyListeners();
    unawaited(model.openTerminal());
  }

  TerminalModel _add(int id) {
    final model = TerminalModel(_ffi, id);
    model.onClosed = () => _onShellExit(model);
    model.onPersistentSessions = _restore;
    // Upstream decides when the tab is made whether it may ask (`terminal_tab_page.dart:121`).
    if (_canHandleClipboardRequest) {
      model.onClipboardWriteBlocked = (text) => _onBlocked(model, text);
    }
    model.onClipboardWriteSucceeded = (_) {
      if (_notice.currentForSource(model) != null) _closeNotice();
    };
    _terminals.add(model);
    return model;
  }

  /// The peer's information came (upstream `model.dart:1415-1420`): the first connection opens
  /// the first terminal, a reconnection reopens every terminal.
  void onReady() {
    if (_terminals.isEmpty) {
      _add(_nextId++);
      notifyListeners();
    }
    for (final model in [..._terminals]) {
      model.onReady();
    }
  }

  /// The shells the remote device kept: each gets a tab of its own, after the open ones
  /// (upstream `terminal_tab_page.dart:558-608`, without the delay its tab controller needed).
  void _restore(List<int> ids) {
    var added = false;
    for (final id in [...ids]..sort()) {
      if (_terminals.any((m) => m.terminalId == id)) continue;
      final model = _add(id);
      if (id >= _nextId) _nextId = id + 1;
      unawaited(model.openTerminal());
      added = true;
    }
    if (added) notifyListeners();
  }

  /// `terminal_response` of this session (upstream `FFI.routeTerminalResponse`).
  void route(Map<String, dynamic> evt) {
    final id = TerminalModel.getTerminalIdFromEvt(evt);
    _terminals
        .where((m) => m.terminalId == id)
        .firstOrNull
        ?.handleTerminalResponse(evt);
  }

  /// "×" of a terminal while others are open: its shell ends whether sessions are kept or not
  /// (upstream `terminal_tab_page.dart:377-420`). The last one is the view's "断开".
  Future<void> closeTerminal(TerminalModel model) async {
    if (_terminals.length < 2 || !_terminals.contains(model)) return;
    _remove(model);
    await model.closeTerminal();
    model.dispose();
  }

  void _remove(TerminalModel model) {
    final index = _terminals.indexOf(model);
    _terminals.removeAt(index);
    if (index < _selected || _selected >= _terminals.length) {
      _selected = (_selected - 1).clamp(0, _terminals.length);
    }
    if (_notice.currentForSource(model) != null) _notice.clear();
    notifyListeners();
  }

  /// The remote shell exited: its tab closes; with the last one goes the view (and the tab
  /// with its last view).
  void _onShellExit(TerminalModel model) {
    if (!_terminals.contains(model)) return;
    if (_terminals.length > 1) {
      _remove(model);
      model.dispose();
    } else if (!_ffi.closed) {
      unawaited(appCore.sessions.close(_ffi));
    }
  }

  /// "断开连接后保持终端会话", this device's session option (13 §2.2.2 block F).
  bool get persistent => _ffi.options.getToggle(kOptionTerminalPersistent);

  Future<void> togglePersistent() async {
    await _ffi.options.toggle(kOptionTerminalPersistent);
    notifyListeners();
  }

  /// Disconnecting asks first: two terminals or more whose shells would end (R3-Q15).
  bool get needsDisconnectConfirm => _terminals.length >= 2 && !persistent;

  /// "断开终端？" waits for the view's answer.
  bool get askingDisconnect => _disconnectAsk != null;

  /// Asks "断开终端？" in the view; true for "断开". Asked again while it shows, the same
  /// question answers both.
  Future<bool> askDisconnect() {
    var ask = _disconnectAsk;
    if (ask == null) {
      ask = _disconnectAsk = Completer<bool>();
      notifyListeners();
    }
    return ask.future;
  }

  void answerDisconnect(bool disconnect) {
    final ask = _disconnectAsk;
    if (ask == null) return;
    _disconnectAsk = null;
    notifyListeners();
    ask.complete(disconnect);
  }

  /// The request the banner shows (13 §2.2.2 block E); `persistAllowed` false is the banner of
  /// a failed write ("复制到剪贴板", "关闭").
  TerminalClipboardNoticeRequest<TerminalModel>? get clipboardRequest =>
      _notice.current;

  /// The banner's buttons work: no answer is being saved.
  bool get clipboardActionsEnabled => _notice.canClaimAction;

  /// "允许" (writes the setting) or "复制到剪贴板": writes the latest request's text.
  Future<void> allowClipboard() async {
    final request = _notice.claimCurrentAction();
    if (request == null) return;
    var completed = false;
    try {
      completed = await completeTerminalClipboardWrite(
        clipboardText: request.text,
        canWrite: () => _canWrite(request.source),
        writeClipboard: writeTerminalClipboard,
        persistAllowed: request.persistAllowed
            ? () => appCore.options.local.set(
                kOptionAllowTerminalClipboardWrite,
                kTerminalClipboardWriteAllowed)
            : null,
      );
    } catch (e) {
      debugPrint('[TerminalTabs] Failed to complete clipboard write: $e');
    } finally {
      _notice.releaseAction();
    }
    if (completed) _closeNotice();
  }

  /// "拒绝" (writes the setting) or "关闭".
  Future<void> denyClipboard() async {
    final request = _notice.claimCurrentAction();
    if (request == null) return;
    if (request.persistAllowed) {
      try {
        await appCore.options.local.set(
            kOptionAllowTerminalClipboardWrite, kTerminalClipboardWriteDenied);
      } catch (e) {
        debugPrint('[TerminalTabs] Failed to save clipboard permission: $e');
        return;
      } finally {
        _notice.releaseAction();
      }
    }
    _closeNotice();
  }

  // Upstream `terminal_tab_page.dart:42-53`: hidden settings or a fixed option leave only
  // "allowed" to act on.
  bool get _canHandleClipboardRequest => canHandleTerminalClipboardWriteRequest(
        localOption:
            appCore.options.local.get(kOptionAllowTerminalClipboardWrite),
        canConfigurePermission: canConfigureTerminalClipboardPermission(
          settingsDisabled: bind.isDisableSettings(),
          optionFixed:
              appCore.options.isFixed(kOptionAllowTerminalClipboardWrite),
        ),
      );

  bool _canWrite(TerminalModel model) =>
      _canHandleClipboardRequest &&
      !_ffi.closed &&
      _ffi.ffiModel.permissions['clipboard'] != false &&
      _terminals.contains(model);

  void _onBlocked(TerminalModel model, String text) {
    final request = _notice.recordBlocked(
      source: model,
      text: text,
      option: appCore.options.local.get(kOptionAllowTerminalClipboardWrite),
      canWrite: _canWrite,
    );
    if (request != null) notifyListeners();
  }

  void _closeNotice() {
    _notice.clear();
    notifyListeners();
  }

  /// The banner goes with the connection: the connection panel covers the terminal then
  /// (13 §2.2.2 block E).
  void _onConnection() {
    final connected = canAdd;
    if (connected == _connected) return;
    _connected = connected;
    if (!connected) _notice.clear();
    notifyListeners();
  }

  /// The view closes (`FFI.close`): without "keep terminal sessions" every shell ends, with it
  /// none does (13 §2.2.2 block F; upstream `_closeAllTabs`, `terminal_tab_page.dart:335-365`).
  Future<void> close() async {
    _ffi.connection.removeListener(_onConnection);
    _notice.clear();
    answerDisconnect(false);
    final models = [..._terminals];
    _terminals.clear();
    if (!persistent) {
      await Future.wait(models.map((m) => m.closeTerminal()))
          .timeout(const Duration(seconds: 4), onTimeout: () => const []);
    }
    for (final m in models) {
      m.dispose();
    }
  }
}

/// Whether the tab of a device has a terminal view, and which (R3-Q9): the device menu and the
/// view switch offer only one of the normal and the administrator terminal at a time.
enum TerminalOpen { none, normal, admin }

/// [TerminalOpen] for device [id], from the views open in its tab.
TerminalOpen terminalOpenState(String id) {
  final terminal = appCore.sessions
      .sessionsOf(id)
      .where((s) => s.connType == ConnType.terminal)
      .firstOrNull;
  if (terminal == null) return TerminalOpen.none;
  return terminal.terminalAdmin ? TerminalOpen.admin : TerminalOpen.normal;
}
