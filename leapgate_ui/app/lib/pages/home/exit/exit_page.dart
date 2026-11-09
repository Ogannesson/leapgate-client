import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_directory.dart';
import 'package:flutter_hbb/leapgate/exit_nodes.dart';
import 'package:flutter_hbb/leapgate/tunnel_api.dart' show TunnelKind;

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/navigation.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_exit_card.dart';
import '../../../widgets/lg_exit_page.dart';
import 'exit_card_view.dart';
import 'exit_directory_view.dart';
import 'tunnel_section.dart';

// The exit page (01 P1 block I), "出口与隧道" since M9c (13 §1.3 block A): the exit nodes (a
// sentence, the cards in use, the directory, by ID) and the tunnels, drawn by [LgExitPage]
// (`LEAPGATE.md` §10.12 "组件接口", §10.18).

class ExitPage extends StatefulWidget {
  const ExitPage({super.key, required this.overlays});

  final TabOverlays overlays;

  @override
  State<ExitPage> createState() => _ExitPageState();
}

class _ExitPageState extends State<ExitPage> {
  final _id = TextEditingController();
  final _idFocus = FocusNode();

  /// Per card: the key to scroll to it, and how often it was marked ([LgFlash.count]).
  final _cardKeys = <String, GlobalKey>{};
  final _flashes = <String, int>{};
  var _badId = false;

  @override
  void initState() {
    super.initState();
    appCore.exitDirectory.open();
    exitPageRequests.addListener(_onRequest);
    // "Use as exit node" from elsewhere switched to this page.
    _onRequest();
  }

  @override
  void dispose() {
    appCore.exitDirectory.close();
    exitPageRequests.removeListener(_onRequest);
    _id.dispose();
    _idFocus.dispose();
    super.dispose();
  }

  void _onRequest() {
    final request = exitPageRequests.take();
    if (request == null) return;
    final tunnel = request.tunnel;
    // A new card logs in for the user who asked for it.
    if (!request.highlight) {
      tunnel == null
          ? focusExitPromptOf(request.id)
          : focusTunnelPromptOf(request.id, tunnel);
    }
    _scrollTo(
      tunnel == null ? request.id : _tunnelKey(request.id, tunnel),
      highlight: request.highlight,
    );
  }

  /// A tunnel card's entry in [_cardKeys] and [_flashes]; an exit card's is its ID.
  static String _tunnelKey(String id, TunnelKind kind) => '${kind.name}:$id';

  /// After the next frame, when the card is built.
  void _scrollTo(String key, {bool highlight = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _cardKeys[key]?.currentContext;
      if (context == null || !mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 200),
        alignment: 0.1,
      );
      if (highlight) setState(() => _flashes[key] = (_flashes[key] ?? 0) + 1);
    });
  }

  /// "Use" in the directory and by ID; a device that already has a card is only shown.
  void _use(String id, {String? name}) {
    final had = appCore.exitNodes.cardOf(id) != null;
    if (!had) focusExitPromptOf(id);
    appCore.exitNodes.use(id, name: name);
    _scrollTo(id, highlight: had);
  }

  void _useById() {
    final input = _id.text.trim();
    if (input.isEmpty) return;
    if (!isExitId(input)) {
      setState(() => _badId = true);
      // Enter took the focus out of the field.
      _idFocus.requestFocus();
      return;
    }
    _use(input.replaceAll(' ', ''));
    _id.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // "Refresh" follows the directory and the sign-in.
    return ListenableBuilder(
      listenable: Listenable.merge([appCore.exitDirectory, appCore.account]),
      builder: (context, _) => _page(l10n),
    );
  }

  Widget _page(AppLocalizations l10n) {
    return LgExitPage(
      // "出口与隧道" (R3-Q1): the exit nodes, then the tunnels.
      sectionTitle: l10n.tunnelSectionExits,
      sectionIcon: LgIcons.exit,
      tunnels: TunnelSection(
        overlays: widget.overlays,
        cardKey: (id, kind) =>
            _cardKeys.putIfAbsent(_tunnelKey(id, kind), GlobalKey.new),
        flashes: (id, kind) => _flashes[_tunnelKey(id, kind)] ?? 0,
      ),
      lede: l10n.exitLede,
      inUseTitle: l10n.exitInUseTitle,
      inUse: ListenableBuilder(
        listenable: appCore.exitNodes,
        builder: (context, _) {
          final cards = appCore.exitNodes.cards;
          if (cards.isEmpty) return LgExitEmptyNote(l10n.exitNoneInUse);
          return LgExitCardGrid(
            semanticLabel: l10n.exitInUseList,
            children: [
              for (final card in cards)
                LgFlash(
                  key: _cardKeys.putIfAbsent(card.id, GlobalKey.new),
                  count: _flashes[card.id] ?? 0,
                  child: ExitCardView(key: ValueKey(card), card: card),
                ),
            ],
          );
        },
      ),
      directoryTitle: l10n.exitAvailableTitle,
      refreshLabel: l10n.homeRefresh,
      onRefresh:
          const {
            ExitDirectoryState.loading,
            ExitDirectoryState.notLoggedIn,
          }.contains(appCore.exitDirectory.state)
          ? null
          : appCore.exitDirectory.load,
      directory: ExitDirectoryView(
        overlays: widget.overlays,
        onUse: (node) =>
            _use(node.id, name: node.hostname.isEmpty ? null : node.hostname),
        onShow: (id) => _scrollTo(id, highlight: true),
      ),
      byIdTitle: l10n.exitByIdTitle,
      byId: LgExitByIdRow(
        controller: _id,
        focusNode: _idFocus,
        placeholder: l10n.exitIdPlaceholder,
        semanticLabel: l10n.exitByIdTitle,
        useLabel: l10n.exitUse,
        onUse: _id.text.trim().isEmpty ? null : _useById,
        errorText: _badId ? l10n.exitBadId : null,
        onChanged: (_) => setState(() => _badId = false),
      ),
    );
  }
}
