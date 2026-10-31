import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/identity_color.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../pages/home/home_page.dart';
import '../pages/session/reasons.dart';
import '../pages/session/session_names.dart';
import '../pages/session/session_page.dart';
import '../widgets/lg_feedback.dart';
import '../widgets/lg_status.dart';
import '../widgets/lg_tab_tip.dart';
import '../widgets/lg_title_bar.dart';
import 'keep_display_on.dart';
import 'navigation.dart';
import 'tab_overlays.dart';
import 'toast_view.dart';
import 'window_close.dart';

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

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _readWindowState();
    mainNavigation = this;
    appCore.prompter = ShellPrompter(_overlays);
    _devices = appCore.sessions.devices;
    appCore.sessions.addListener(_onSessions);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    appCore.sessions.removeListener(_onSessions);
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
    if (devices.isEmpty != _devices.isEmpty) keepDisplayOn(devices.isNotEmpty);
    _devices = devices;
    _select(selected);
  }

  /// Full screen belongs to the session it was entered in; another tab shows the title bar.
  void _select(String? device) {
    if (device == _selected) {
      if (mounted) setState(() {});
      return;
    }
    if (stateGlobal.fullscreen.isTrue) stateGlobal.setFullscreen(false);
    _dropComposition();
    if (mounted) setState(() => _selected = device);
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
    appCore.sessions.open(id, ConnType.defaultConn,
        forceRelay: forceRelay,
        password: password,
        isSharedPassword: isSharedPassword,
        switchUuid: switchUuid);
    _select(id);
  }

  @override
  void showHome({bool focusConnectBox = false, String? connectBoxText}) {
    _select(null);
    if (focusConnectBox || connectBoxText != null) {
      connectBoxFocusRequests.request(text: connectBoxText);
    }
  }

  // M2a opens one view per tab, the remote desktop.
  FFI _viewOf(String device) => appCore.sessions.sessionsOf(device).first;

  /// The tab's status mark and hover content (01 §2.1, P2 block A).
  LgSessionTab _tabOf(FFI s, AppLocalizations l10n) {
    final conn = s.connection;
    final name = deviceName(s);
    Widget status;
    var disconnected = false;
    final lines = <String>[];
    final tipViews = <(String, Widget)>[];
    if (conn.stage == ConnStage.failed) {
      final reason = conn.reason!;
      lines.add(reasonView(l10n, reason, s.id).text);
      final countdown = conn.retryCountdown;
      if (countdown != null) {
        status = LgStatusText(LgStatus.warning, l10n.sessionInterrupted);
        lines.add(l10n.connRetryIn(countdown, conn.retryAttempt));
      } else if (isDisconnected(reason)) {
        status = LgStatusText(LgStatus.offline, l10n.sessionDisconnected);
        disconnected = true;
      } else {
        status = LgStatusText(LgStatus.warning, l10n.sessionFailed);
      }
    } else if (!showsRoute(conn)) {
      status = LgStatusText(LgStatus.connecting, l10n.sessionConnecting);
    } else {
      LgRouteMark mark({bool worstOnly = false}) => LgRouteMark(
            route: conn.direct! ? LgRoute.direct : LgRoute.relay,
            label: conn.direct! ? l10n.sessionDirect : l10n.sessionRelayed,
            encrypted: conn.secure != false,
            unencryptedLabel: l10n.sessionUnencrypted,
            worstOnly: worstOnly,
          );
      status = mark(worstOnly: true);
      tipViews.add((l10n.toolbarRemoteDesktop, mark()));
    }
    return LgSessionTab(
      name: name,
      identity: identityGroup(s.id),
      status: status,
      disconnected: disconnected,
      tooltip: LgTabTip(
          name: name, id: formatPeerId(s.id), views: tipViews, lines: lines),
    );
  }

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
    final views = [for (final d in devices) _viewOf(d)];
    final selectedIndex =
        _selected == null ? 0 : devices.indexOf(_selected!) + 1;

    final titleBar = ListenableBuilder(
      listenable: Listenable.merge([
        for (final s in views) ...[s.connection, s.ffiModel],
      ]),
      builder: (context, _) {
        _syncTitle(_selected == null
            ? l10n.appName
            : l10n.sessionWindowTitle(deviceName(_viewOf(_selected!))));
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
          sessions: [for (final s in views) _tabOf(s, l10n)],
          selected: selectedIndex,
          onSelect: (i) => _select(i == 0 ? null : devices[i - 1]),
          onCloseTab: (i) => appCore.sessions.closeDevice(devices[i - 1]),
          onNewTab: () => showHome(focusConnectBox: true),
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

    return Scaffold(
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
                        HomePage(status: widget.status)),
                    for (final s in views)
                      KeyedSubtree(
                        key: ObjectKey(s),
                        child: _scope(
                          s.id,
                          s.id == _selected,
                          SessionPage(
                              ffi: s,
                              active: s.id == _selected,
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
    );
  }
}
