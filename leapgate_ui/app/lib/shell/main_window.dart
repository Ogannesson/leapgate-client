import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/local_status.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../pages/home/home_page.dart';
import '../widgets/lg_title_bar.dart';

/// The main window: the custom title bar with the in-app tabs and the content
/// of the selected tab (01 §2.1). M0 has only the home tab.
class MainWindow extends StatefulWidget {
  const MainWindow({super.key, required this.status});

  final LocalStatusModel status;

  @override
  State<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends State<MainWindow> with WindowListener {
  bool _maximized = false;
  bool _fullScreen = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _readWindowState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The taskbar title follows the current tab: "Leapgate" on the home tab,
    // "‹device name› - Leapgate" on a session tab (01 §2.1).
    windowManager.setTitle(AppLocalizations.of(context)!.appName);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _readWindowState() async {
    final maximized = await windowManager.isMaximized();
    final fullScreen = await windowManager.isFullScreen();
    if (mounted) {
      setState(() {
        _maximized = maximized;
        _fullScreen = fullScreen;
      });
    }
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  // Full screen hides the whole bar (01 §2.1); entered from session pages later.
  @override
  void onWindowEnterFullScreen() => setState(() => _fullScreen = true);

  @override
  void onWindowLeaveFullScreen() => setState(() => _fullScreen = false);

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_fullScreen)
            LgTitleBar(
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
              sessions: const [],
              selected: 0,
              onSelect: (_) {},
              onCloseTab: (_) {},
              // "+" switches to the home tab; focusing the connect box comes with it (M2a).
              onNewTab: () {},
              maximized: _maximized,
              onMinimize: windowManager.minimize,
              onToggleMaximize: _toggleMaximize,
              // Closing asks first once sessions exist (Q6, M2a); until then it quits.
              onClose: windowManager.close,
              onStartDrag: windowManager.startDragging,
              onStartResize: (edge) =>
                  windowManager.startResizing(switch (edge) {
                    LgResizeEdge.top => ResizeEdge.top,
                    LgResizeEdge.topLeft => ResizeEdge.topLeft,
                    LgResizeEdge.topRight => ResizeEdge.topRight,
                  }),
            ),
          Expanded(child: HomePage(status: widget.status)),
        ],
      ),
    );
  }
}
