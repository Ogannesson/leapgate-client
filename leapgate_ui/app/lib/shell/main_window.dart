import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/identity_color.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/settings/unlock.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../pages/home/home_page.dart';
import '../pages/session/connection_panel.dart';
import '../pages/session/reasons.dart';
import '../pages/session/session_names.dart';
import '../widgets/lg_feedback.dart';
import '../widgets/lg_status.dart';
import '../widgets/lg_tab_tip.dart';
import '../widgets/lg_title_bar.dart';
import 'keep_display_on.dart';
import 'navigation.dart';
import 'session_views.dart';
import 'tab_menu.dart';
import 'tab_overlays.dart';
import 'tab_shortcuts.dart';
import 'toast_view.dart';
import 'window_close.dart';

/// Keeps the screen on or lets it sleep; tests watch it.
@visibleForTesting
void Function(bool on) displayKeeper = keepDisplayOn;

/// The main window: the custom title bar with the in-app tabs and the content of the selected
/// tab (01 §2.1). One tab per device, following the session registry; each tab's content has
/// its own overlay for the dialogs that belong to it (03 §4.5).
class MainWindow extends StatefulWidget {
  const MainWindow({super.key, required this.status});

  final LocalStatusModel status;

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow>
    with WindowListener
    implements MainNavigation {
  bool _maximized = false;
  final _overlays = TabOverlays();

  /// The selected tab's device; null is the home tab.
  String? _selected;

  /// The tabs as last seen, to pick a neighbour when the selected one closes.
  List<String> _devices = const [];
  String? _title;

  /// The view each tab shows, by device; a tab whose view closed shows its first one.
  final _current = <String, FFI>{};

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _readWindowState();
    mainNavigation = this;
    appCore.prompter = ShellPrompter(_overlays);
    _devices = appCore.sessions.devices;
    appCore.sessions.addListener(_onSessions);
    appCore.options.local
        .listenable(kOptionKeepAwakeDuringOutgoingSessions)
        .addListener(_keepDisplayOn);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    appCore.sessions.removeListener(_onSessions);
    appCore.options.local
        .listenable(kOptionKeepAwakeDuringOutgoingSessions)
        .removeListener(_keepDisplayOn);
    super.dispose();
  }

  Future<void> _readWindowState() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = maximized);
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  // Maximized, minimized, then restored: the plugin reports "restore", not
  // "maximize", so ask again.
  @override
  void onWindowRestore() => _readWindowState();

  // Full screen is a session's (toolbar); the window can also leave it by itself.
  @override
  void onWindowLeaveFullScreen() => stateGlobal.setFullscreen(false);

  // Hidden to the tray or to run in the background: the settings lock again (02 §1.2.6).
  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'hide') settingsUnlock.lock();
  }

  // Alt+F4 and the taskbar: the window does not close by itself (prevent close is on).
  @override
  void onWindowClose() => _close();

  void _close() {
    if (_overlays.isOpen(kWindowScope)) return;
    closeMainWindow(_overlays);
  }

  /// When the selected tab closes, the tab before it is selected (upstream's tab bar does the
  /// same), the home tab before the first.
  void _onSessions() {
    final devices = appCore.sessions.devices;
    var selected = _selected;
    if (selected != null && !devices.contains(selected)) {
      final i = _devices.indexOf(selected);
      selected = _devices
          .take(i < 0 ? 0 : i)
          .lastWhere(devices.contains, orElse: () => '');
      if (selected.isEmpty) selected = null;
    }
    for (final d in _devices) {
      if (!devices.contains(d)) _overlays.forget(d);
    }
    _current.removeWhere((d, _) => !devices.contains(d));
    _devices = devices;
    _keepDisplayOn();
    // The remote desktop in full screen closed and its tab now shows the file view, which has
    // no way out of full screen.
    if (selected != null &&
        selected == _selected &&
        stateGlobal.fullscreen.isTrue &&
        isFileView(_currentOf(selected))) {
      stateGlobal.setFullscreen(false);
    }
    _select(selected);
  }

  /// Whether the screen is kept on now.
  bool _displayKeptOn = false;

  /// While a session tab is open, unless "传出会话期间保持屏幕常亮" is off (02 §1.4.3); a change of
  /// the setting applies to the open sessions at once.
  void _keepDisplayOn() {
    final on = _devices.isNotEmpty &&
        appCore.options.local.getBool(kOptionKeepAwakeDuringOutgoingSessions);
    if (on == _displayKeptOn) return;
    _displayKeptOn = on;
    displayKeeper(on);
  }

  /// Full screen belongs to the session it was entered in; another tab shows the title bar.
  void _select(String? device) {
    if (device == _selected) {
      if (mounted) setState(() {});
      return;
    }
    if (stateGlobal.fullscreen.isTrue) stateGlobal.setFullscreen(false);
    // Leaving the home tab leaves the settings page (02 §1.2.6).
    if (device != null) settingsUnlock.lock();
    _dropComposition();
    if (mounted) setState(() => _selected = device);
    // Once the tab takes focus again (its `ExcludeFocus` lifts with this frame).
    if (device != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _overlays.refocus(device));
    }
  }

  /// Shows [view] in its tab and selects the tab: a view just opened, or one picked in the view
  /// switch. Full screen belongs to the remote desktop view, and an IME composition to the view
  /// being left, as for a tab ([_select]).
  void _show(FFI view) {
    if (_selected == view.id && _currentOf(view.id) != view) {
      if (stateGlobal.fullscreen.isTrue) stateGlobal.setFullscreen(false);
      _dropComposition();
    }
    _current[view.id] = view;
    _select(view.id);
  }

  FFI _currentOf(String device) {
    final views = appCore.sessions.sessionsOf(device);
    final current = _current[device];
    return views.contains(current) ? current! : views.first;
  }

  /// An IME composition in the tab being left is dropped, not typed (04-M2a §4 item 4): losing
  /// focus, Flutter only clears the composing range and the Windows engine commits it, so the
  /// text would stay in the field. The composed text is removed before the tab lets go.
  void _dropComposition() {
    final editable = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>();
    if (editable == null) return;
    final value = editable.textEditingValue;
    final composing = value.composing;
    if (!composing.isValid || composing.isCollapsed) return;
    editable.widget.controller.value = TextEditingValue(
      text: composing.textBefore(value.text) + composing.textAfter(value.text),
      selection: TextSelection.collapsed(offset: composing.start),
    );
  }

  // MainNavigation

  /// Upstream `connect` (`flutter/lib/common.dart:2572-2600`): spaces dropped, a `/r` suffix
  /// turned into a forced relay by Rust; the tab is keyed by the ID that comes back.
  @override
  Future<void> connect(String id,
      {String password = '',
      bool isSharedPassword = false,
      bool forceRelay = false,
      String switchUuid = ''}) async {
    id = id.replaceAll(' ', '');
    if (id.isEmpty) return;
    final oldId = id;
    id = await bind.mainHandleRelayId(id: id);
    // "/r" alone leaves nothing to connect to.
    if (id.isEmpty) return;
    forceRelay = id != oldId || forceRelay;
    _show(appCore.sessions.open(id, ConnType.defaultConn,
        forceRelay: forceRelay,
        password: password,
        isSharedPassword: isSharedPassword,
        switchUuid: switchUuid));
  }

  /// As [connect], for the file transfer view (02 §2.1.1).
  @override
  Future<void> openFileTransfer(String id,
          {String password = '',
          bool isSharedPassword = false,
          bool forceRelay = false}) =>
      openView(id, ConnType.fileTransfer,
          password: password,
          isSharedPassword: isSharedPassword,
          forceRelay: forceRelay);

  /// As [connect], for a view of [kind] (`LEAPGATE.md` §10.18).
  @override
  Future<void> openView(String id, ConnType kind,
      {bool terminalAdmin = false,
      String password = '',
      bool isSharedPassword = false,
      bool forceRelay = false}) async {
    assert(kind == ConnType.defaultConn ||
        kind == ConnType.fileTransfer ||
        kind == ConnType.terminal ||
        kind == ConnType.viewCamera);
    id = id.replaceAll(' ', '');
    if (id.isEmpty) return;
    final oldId = id;
    id = await bind.mainHandleRelayId(id: id);
    if (id.isEmpty) return;
    forceRelay = id != oldId || forceRelay;
    _show(appCore.sessions.open(id, kind,
        terminalAdmin: terminalAdmin,
        forceRelay: forceRelay,
        password: password,
        isSharedPassword: isSharedPassword));
  }

  @override
  void showHome({bool focusConnectBox = false, String? connectBoxText}) {
    _select(null);
    if (focusConnectBox || connectBoxText != null) {
      connectBoxFocusRequests.request(text: connectBoxText);
    }
  }

  @override
  void showSettings(SettingsSectionId section, {String? item}) {
    _select(null);
    settingsPageRequests.request(section, item: item);
  }

  /// Next or previous tab, wrapping around; home is the first (01 §2.1).
  void _selectBy(int step) {
    final devices = appCore.sessions.devices;
    final current = _selected == null ? 0 : devices.indexOf(_selected!) + 1;
    final next = (current + step) % (devices.length + 1);
    _select(next == 0 ? null : devices[next - 1]);
  }

  /// The tab's status mark and hover content (01 §2.1, P2 block A), over the tab's [views]: the
  /// worst of them shows, an error first, then "connecting", then the connection method
  /// (unencrypted worst, relayed next); the hover has a line per view with its method. Unread
  /// messages are the remote desktop's; the ring and the reminder mark are the file transfer's
  /// (02 §3.2).
  LgSessionTab _tabOf(List<FFI> views, AppLocalizations l10n) {
    final s = views.first;
    final name = deviceName(s);
    Widget status;
    var disconnected = false;
    final lines = <String>[];
    final routed = [
      for (final v in views)
        if (showsRoute(v.connection)) v
    ];
    LgRouteMark mark(bool direct, bool encrypted, {bool worstOnly = false}) =>
        LgRouteMark(
          route: direct ? LgRoute.direct : LgRoute.relay,
          label: direct ? l10n.sessionDirect : l10n.sessionRelayed,
          encrypted: encrypted,
          unencryptedLabel: l10n.sessionUnencrypted,
          worstOnly: worstOnly,
        );
    final failed = views
        .where((v) => v.connection.stage == ConnStage.failed)
        .firstOrNull;
    if (failed != null) {
      final conn = failed.connection;
      final reason = conn.reason!;
      lines.add(failureText(l10n, failed));
      final countdown = conn.retryCountdown;
      if (countdown != null) {
        status = LgStatusText(LgStatus.warning, l10n.sessionInterrupted);
        lines.add(l10n.connRetryIn(countdown, conn.retryAttempt));
      } else if (isDisconnected(reason)) {
        status = LgStatusText(LgStatus.offline, l10n.sessionDisconnected);
        // The name greys once every view has ended.
        disconnected = views.every((v) =>
            v.connection.stage == ConnStage.failed &&
            isDisconnected(v.connection.reason!));
      } else {
        status = LgStatusText(LgStatus.warning, l10n.sessionFailed);
      }
    } else if (routed.length < views.length) {
      status = LgStatusText(LgStatus.connecting, l10n.sessionConnecting);
    } else {
      status = mark(routed.every((v) => v.connection.direct!),
          routed.every((v) => v.connection.secure != false),
          worstOnly: true);
    }
    final remote = views.where((v) => !isFileView(v)).firstOrNull;
    final files = views.where(isFileView).firstOrNull;
    final summary =
        files == null ? null : fileTransferFor(files).jobs.summary;
    return LgSessionTab(
      name: name,
      identity: identityGroup(s.id),
      status: status,
      unread: remote == null ? 0 : tabUnread(remote),
      disconnected: disconnected,
      progress: summary?.progress,
      alert: (summary?.waitingConfirm ?? 0) > 0,
      markLabel: summary == null ? null : transferMarkLabel(l10n, summary),
      tooltip: LgTabTip(
        name: name,
        id: formatPeerId(s.id),
        views: [
          for (final v in routed)
            (
              viewName(l10n, v.connType),
              mark(v.connection.direct!, v.connection.secure != false)
            ),
        ],
        lines: lines,
      ),
    );
  }

  Future<void> _closeTab(String device) =>
      closeSessionTab(_overlays, device, show: () => _select(device));

  /// The taskbar title follows the selected tab (01 §2.1).
  void _syncTitle(String title) {
    if (title == _title) return;
    _title = title;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => windowManager.setTitle(title));
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Widget _scope(Object? scope, bool active, Widget child) => TickerMode(
        enabled: active,
        // A tab in the background keeps no focus: a text field there closes its input
        // connection, so an IME composition does not carry over to the next tab (§4 item 4).
        child: ExcludeFocus(
          excluding: !active,
          child: Stack(
            children: [
              Positioned.fill(child: child),
              Positioned.fill(child: Overlay(key: _overlays.keyOf(scope))),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final devices = appCore.sessions.devices;
    final tabs = [for (final d in devices) appCore.sessions.sessionsOf(d)];
    final views = tabs.expand((t) => t);
    final selectedIndex =
        _selected == null ? 0 : devices.indexOf(_selected!) + 1;

    final titleBar = ListenableBuilder(
      listenable: Listenable.merge([
        for (final s in views) ...[
          s.connection,
          s.ffiModel,
          s.chatModel,
          if (isFileView(s)) fileTransferFor(s).jobs,
        ],
        appCore.backgroundListenable,
      ]),
      builder: (context, _) {
        _syncTitle(_selected == null
            ? l10n.appName
            : l10n.sessionWindowTitle(deviceName(_currentOf(_selected!))));
        final exits = appCore.backgroundCount;
        return LgTitleBar(
          labels: LgTitleBarLabels(
            home: l10n.home,
            newTab: l10n.newConnection,
            allTabs: l10n.allTabs,
            closeTab: l10n.closeTab,
            minimize: l10n.minimize,
            maximize: l10n.maximize,
            restore: l10n.restore,
            close: l10n.close,
          ),
          sessions: [for (final t in tabs) _tabOf(t, l10n)],
          selected: selectedIndex,
          // The exit nodes running and whether one waits for the user (M5-8).
          homeBadge: exits,
          homeAlert: exits > 0 && appCore.backgroundAttention,
          homeSemanticLabel: exits == 0
              ? null
              : appCore.backgroundAttention
              ? l10n.exitHomeLabelAttention(exits)
              : l10n.exitHomeLabel(exits),
          onSelect: (i) => _select(i == 0 ? null : devices[i - 1]),
          onCloseTab: (i) => _closeTab(devices[i - 1]),
          onNewTab: () => showHome(focusConnectBox: true),
          onTabContextMenu: (i, position) => showSessionTabMenu(
            context,
            devices[i - 1],
            position,
            onClose: () => _closeTab(devices[i - 1]),
            onCloseOthers: () => closeOtherTabs(_overlays, devices[i - 1]),
          ),
          maximized: _maximized,
          onMinimize: windowManager.minimize,
          onToggleMaximize: _toggleMaximize,
          onClose: _close,
          onStartDrag: windowManager.startDragging,
          onStartResize: (edge) => windowManager.startResizing(switch (edge) {
            LgResizeEdge.top => ResizeEdge.top,
            LgResizeEdge.topLeft => ResizeEdge.topLeft,
            LgResizeEdge.topRight => ResizeEdge.topRight,
          }),
        );
      },
    );

    final selected = _selected;
    return TabShortcuts(
      onNext: () => _selectBy(1),
      onPrevious: () => _selectBy(-1),
      // The file transfer view has no session shortcuts of its own; the remote desktop's
      // "关闭标签" is its session's (`toolbar/session_shortcuts.dart`).
      onCloseTab: selected != null && isFileView(_currentOf(selected))
          ? () => _closeTab(selected)
          : null,
      child: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Full screen hides the whole bar (01 §2.1).
          Obx(() => stateGlobal.fullscreen.isTrue
              ? const SizedBox.shrink()
              : titleBar),
          Expanded(
            child: ListenableBuilder(
              listenable: appCore.toasts,
              builder: (context, content) => LgToastHost(
                  text: toastText(l10n, appCore.toasts.current?.key),
                  child: content!),
              child: Stack(
              children: [
                IndexedStack(
                  index: selectedIndex,
                  sizing: StackFit.expand,
                  children: [
                    _scope(null, _selected == null,
                        HomePage(status: widget.status, overlays: _overlays)),
                    for (final d in devices)
                      KeyedSubtree(
                        key: ValueKey(d),
                        child: _scope(
                          d,
                          d == _selected,
                          SessionTabView(
                              views: appCore.sessions.sessionsOf(d),
                              current: _currentOf(d),
                              selected: d == _selected,
                              overlays: _overlays),
                        ),
                      ),
                  ],
                ),
                Positioned.fill(
                    child: Overlay(key: _overlays.keyOf(kWindowScope))),
              ],
            ),
            ),
          ),
        ],
      ),
    ));
  }
}
