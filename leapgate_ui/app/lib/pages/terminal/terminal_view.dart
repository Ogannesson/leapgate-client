import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/keyboard_shortcuts/shortcut_constants.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/connection.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/terminal/terminals.dart';
import 'package:flutter_hbb/models/terminal_copy_shortcut.dart';
import 'package:flutter_hbb/models/terminal_model.dart';
import 'package:flutter_hbb/models/terminal_mouse_handler.dart';
import 'package:xterm/xterm.dart';

import '../../icons/lg_icon.dart';
import '../../l10n/app_localizations.dart';
import '../../shell/tab_shortcuts.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_feedback.dart';
import '../../widgets/lg_menu.dart';
import '../../widgets/lg_term_tabs.dart';
import '../../widgets/lg_terminal_parts.dart';
import '../../widgets/lg_terminal_theme.dart';
import '../../widgets/lg_view_bar.dart';
import '../files/file_view.dart' show kFileCompactBelowHeight;
import '../session/connection_panel.dart';

/// Upstream's copy shortcuts without Ctrl+A, which goes to the remote terminal, and with
/// Ctrl+Shift+A selecting all (R3-Q10). The copied table stays upstream's.
Map<ShortcutActivator, Intent> leapgateTerminalShortcuts() => {
  for (final e
      in (platformTerminalShortcuts() ?? defaultTerminalShortcuts).entries)
    if (!_isCtrlA(e.key)) e.key: e.value,
  const SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
};

bool _isCtrlA(ShortcutActivator a) =>
    a is SingleActivator &&
    a.trigger == LogicalKeyboardKey.keyA &&
    a.control &&
    !a.shift &&
    !a.alt &&
    !a.meta;

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// The terminal view in its session tab (13 §2.2): the view title bar, the terminal tabs and the
/// terminal, the connection panel over them while not connected. Coder B's; the shell mounts it
/// in the tab's view container as it mounts `FileView` (`LEAPGATE.md` §10.18).
class TerminalViewPage extends StatefulWidget {
  const TerminalViewPage({
    super.key,
    required this.ffi,
    required this.active,
    required this.lastView,
    required this.viewSwitch,
    required this.route,
    required this.onDisconnect,
  });

  /// The `ConnType.terminal` session; `ffi.terminals` holds its tabs.
  final FFI ffi;

  /// This view is the one shown in the selected tab: it may take the keyboard.
  final bool active;

  /// No other view is open in the tab (`ConnectionPanel.lastView`).
  final bool lastView;

  /// The view switch, the same control as on the remote desktop toolbar.
  final Widget viewSwitch;

  /// The connection method mark.
  final Widget route;

  /// "断开" on the view title bar ([disconnectTerminalView]).
  final VoidCallback onDisconnect;

  @override
  State<TerminalViewPage> createState() => _TerminalViewPageState();
}

class _TerminalViewPageState extends State<TerminalViewPage> {
  TerminalTabs get _tabs => widget.ffi.terminals!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // One locale for every view: the lines the terminals write (13 §2.2.2 block C), in the
    // terminal's second foreground.
    final l10n = AppLocalizations.of(context)!;
    final term = LgTokens.of(context).term;
    terminalNoteText = (note, detail) => lgTerminalNote(
      switch (note) {
        TerminalNote.openFailed => l10n.termNoteOpenFailed(detail),
        TerminalNote.openTimeout => l10n.termNoteOpenTimeout,
        TerminalNote.error => l10n.termNoteError(detail),
        TerminalNote.reconnectedNewShell => l10n.termNoteReconnected,
      },
      term,
    );
  }

  /// "×" of a terminal: the last one is the view's "断开" (13 §2.2.2 block B).
  void _close(TerminalModel model) {
    if (_tabs.terminals.length > 1) {
      unawaited(_tabs.closeTerminal(model));
    } else {
      widget.onDisconnect();
    }
  }

  /// The terminal's own keys and the session shortcuts, before xterm (13 §2.2.4).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // A held key repeats: the repeats are stopped as the first press was, and do nothing more
    // (held Alt+→ would send `ESC[1;3C` to the remote terminal).
    final repeat = event is KeyRepeatEvent;
    final k = HardwareKeyboard.instance;
    // The tab switch and "关闭标签" belong to the window (`TabShortcuts`, a late handler): xterm
    // must not see them, and nothing in between may handle them. `ignored` would let xterm send
    // keys it knows (Ctrl+→) to the remote terminal instead.
    switch (matchShortcut(
      event.physicalKey,
      ctrl: k.isControlPressed,
      alt: k.isAltPressed,
      shift: k.isShiftPressed,
      meta: k.isMetaPressed,
    )) {
      case kShortcutActionSwitchTabNext ||
          kShortcutActionSwitchTabPrev ||
          kShortcutActionCloseTab:
        return KeyEventResult.skipRemainingHandlers;
    }
    final key = event.logicalKey;
    final tabs = _tabs;
    if (k.isControlPressed && k.isShiftPressed) {
      if (key == LogicalKeyboardKey.keyT) {
        if (!repeat) tabs.add();
        return KeyEventResult.handled;
      }
      final current = tabs.current;
      if (key == LogicalKeyboardKey.keyW && current != null) {
        // With one terminal it does nothing: neither the remote terminal nor the view gets it.
        if (!repeat && tabs.terminals.length > 1) _close(current);
        return KeyEventResult.handled;
      }
    }
    if (k.isAltPressed) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (!repeat) tabs.select(tabs.selected - 1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        if (!repeat) tabs.select(tabs.selected + 1);
        return KeyEventResult.handled;
      }
    }
    final digit = _digits.indexOf(key);
    if (k.isControlPressed && digit >= 0 && digit < tabs.terminals.length) {
      if (!repeat) tabs.select(digit);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<Widget> _menuItems(AppLocalizations l10n) => [
    LgMenuItem(
      label: l10n.termNew,
      icon: LgIcons.plus,
      shortcut: 'Ctrl+Shift+T',
      onPressed: _tabs.canAdd ? _tabs.add : null,
    ),
    LgMenuItem(
      label: l10n.termKeepSessions,
      checked: _tabs.persistent,
      onPressed: () => unawaited(_tabs.togglePersistent()),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final conn = widget.ffi.connection;
    final tabs = _tabs;
    return ExcludeFocus(
      excluding: !widget.active,
      child: ColoredBox(
        color: t.colors.bg,
        child: ListenableBuilder(
          listenable: Listenable.merge([conn, tabs]),
          builder: (context, _) {
            final connected = conn.stage == ConnStage.connected;
            final asking = tabs.askingDisconnect;
            final request = tabs.clipboardRequest;
            return Stack(
              children: [
                Column(
                  children: [
                    LgViewBar(
                      viewSwitch: widget.viewSwitch,
                      route: widget.route,
                      // Right click on the tabs opens the "⋯" menu (13 §2.2.2 block A, as
                      // upstream's tab menu).
                      middle: LgContextMenuRegion(
                        items: _menuItems(l10n),
                        child: LgTermTabs(
                          // Empty while the connection panel is up (13 §2.2.2 block A).
                          tabs: [
                            if (connected)
                              for (final m in tabs.terminals)
                                LgTermTabItem(
                                  label: l10n.termTab(m.terminalId),
                                  closeLabel: l10n.termCloseN(m.terminalId),
                                ),
                          ],
                          selected: tabs.selected,
                          onSelect: tabs.select,
                          onClose: (i) => _close(tabs.terminals[i]),
                          onNew: tabs.canAdd ? tabs.add : null,
                          semanticLabel: l10n.termTabs,
                          newLabel: l10n.termNew,
                          newTooltip: l10n.termNewTip,
                          allLabel: l10n.termAll,
                        ),
                      ),
                      more: LgViewMoreButton(
                        label: l10n.termMore,
                        items: _menuItems(l10n),
                      ),
                      disconnectLabel: l10n.termDisconnect,
                      onDisconnect: widget.onDisconnect,
                      compact:
                          MediaQuery.sizeOf(context).height <
                          kFileCompactBelowHeight,
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          if (tabs.terminals.isNotEmpty)
                            // Connected before: the terminal dims under the panel.
                            LgTerminalSurface(
                              dimmed: !connected,
                              child: ExcludeFocus(
                                excluding: !connected || asking,
                                child: IndexedStack(
                                  index: tabs.selected,
                                  sizing: StackFit.expand,
                                  children: [
                                    for (final (i, m)
                                        in tabs.terminals.indexed)
                                      _TerminalPane(
                                        key: ObjectKey(m),
                                        model: m,
                                        focused:
                                            widget.active &&
                                            connected &&
                                            !asking &&
                                            i == tabs.selected,
                                        onKey: _onKey,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (!connected) ...[
                            const ModalBarrier(dismissible: false),
                            ConnectionPanel(
                              ffi: widget.ffi,
                              active: widget.active,
                              lastView: widget.lastView,
                            ),
                          ],
                          if (connected && request != null)
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: _ClipboardBanner(
                                tabs: tabs,
                                persistAllowed: request.persistAllowed,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (asking)
                  LgDialogScrim(
                    onEscape: () => tabs.answerDisconnect(false),
                    child: LgConfirmDialog(
                      title: l10n.termDisconnectTitle,
                      body: l10n.termDisconnectBody(tabs.terminals.length),
                      actions: [
                        LgDialogAction(
                          label: l10n.connCancel,
                          onPressed: () => tabs.answerDisconnect(false),
                        ),
                        LgDialogAction(
                          label: l10n.termDisconnect,
                          kind: LgButtonKind.primary,
                          isDefault: true,
                          onPressed: () => tabs.answerDisconnect(true),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One terminal (upstream `desktop/pages/terminal_page.dart`): whole rows, the space left over
/// split above and below; right click copies the selection or pastes. The sides are the
/// surface's ([LgTerminalSurface]).
class _TerminalPane extends StatefulWidget {
  const _TerminalPane({
    super.key,
    required this.model,
    required this.focused,
    required this.onKey,
  });

  final TerminalModel model;

  /// It has the keyboard: the selected terminal of the shown view, connected, nothing over it.
  final bool focused;
  final FocusOnKeyEventCallback onKey;

  @override
  State<_TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<_TerminalPane> {
  static const _padding = EdgeInsets.symmetric(vertical: 2.0);

  final _focus = FocusNode(debugLabel: 'terminal');
  final _shortcuts = leapgateTerminalShortcuts();
  double? _cellHeight;

  @override
  void initState() {
    super.initState();
    widget.model.onResizeExternal = (w, h, pw, ph) {
      _cellHeight = ph * 1.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    };
    if (widget.focused) _requestFocus();
  }

  @override
  void didUpdateWidget(_TerminalPane old) {
    super.didUpdateWidget(old);
    if (widget.focused && !old.focused) _requestFocus();
  }

  @override
  void dispose() {
    widget.model.onResizeExternal = null;
    _focus.dispose();
    super.dispose();
  }

  void _requestFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.focused) _focus.requestFocus();
    });
  }

  // Upstream `terminal_page.dart:171-196`.
  EdgeInsets _paddingFor(double height) {
    final cell = _cellHeight;
    if (!height.isFinite || height <= 0 || cell == null || cell <= 0) {
      return _padding;
    }
    final rows = (height / cell).floor();
    if (rows <= 0) return _padding;
    return EdgeInsets.symmetric(
      horizontal: _padding.horizontal / 2,
      vertical: (height - rows * cell) / 2,
    );
  }

  Future<void> _onSecondaryTap(
    TapDownDetails details,
    CellOffset offset,
  ) async {
    final terminal = widget.model.terminal;
    final controller = widget.model.terminalController;
    final selection = controller.selection;
    if (selection != null) {
      final text = terminal.buffer.getText(selection);
      controller.clearSelection();
      await Clipboard.setData(ClipboardData(text: text));
    } else {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (text != null) terminal.paste(text);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => TerminalMouseInteraction(
      widget.model.terminal,
      controller: widget.model.terminalController,
      focusNode: _focus,
      theme: lgTerminalTheme(LgTokens.of(context).term),
      textStyle: lgTerminalStyle(),
      padding: _paddingFor(constraints.maxHeight),
      scrollbar: (controller, child) =>
          LgTerminalScrollbar(controller: controller, child: child),
      shortcuts: _shortcuts,
      onKeyEvent: terminalCopyHandler(
        widget.model.terminal,
        widget.model.terminalController,
        fallback: widget.onKey,
      ),
      onSecondaryTapDown: _onSecondaryTap,
    ),
  );
}

/// A remote program asks to write the clipboard (13 §2.2.2 block E): over the top of the
/// terminal, not pushing it down. While an answer is being saved the buttons do nothing
/// ([TerminalTabs.clipboardActionsEnabled]: the two calls return at once).
class _ClipboardBanner extends StatelessWidget {
  const _ClipboardBanner({required this.tabs, required this.persistAllowed});

  final TerminalTabs tabs;

  /// "允许" / "拒绝"; false after a write that failed: "复制到剪贴板" / "关闭".
  final bool persistAllowed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LgClipboardRequest(
      text: l10n.termClipboardRequest,
      allowLabel: persistAllowed
          ? l10n.termClipboardAllow
          : l10n.termClipboardCopy,
      denyLabel: persistAllowed
          ? l10n.termClipboardDeny
          : l10n.termClipboardDismiss,
      onAllow: () => unawaited(tabs.allowClipboard()),
      onDeny: () => unawaited(tabs.denyClipboard()),
      semanticLabel: l10n.termClipboardRequestName,
    );
  }
}

/// "断开" of the terminal view, and the tab's "×" when it is the tab's only view: with two
/// terminals or more whose shells would end it asks in the view first (R3-Q15; not the
/// "confirm before closing" setting, as R2-Q28), then closes this view (the tab goes with its
/// last view).
Future<void> disconnectTerminalView(FFI view) async {
  final tabs = view.terminals;
  if (tabs != null &&
      tabs.needsDisconnectConfirm &&
      !await tabs.askDisconnect()) {
    return;
  }
  await appCore.sessions.close(view);
}
