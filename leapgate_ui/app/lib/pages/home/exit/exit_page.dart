import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_directory.dart';
import 'package:flutter_hbb/leapgate/exit_nodes.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/navigation.dart';
import '../../../shell/tab_overlays.dart';
import '../../../widgets/lg_exit_card.dart';
import '../../../widgets/lg_exit_page.dart';
import 'exit_card_view.dart';
import 'exit_directory_view.dart';

// The exit page (01 P1 block I): a sentence, the cards in use, the directory, by ID, drawn by
// [LgExitPage] (`LEAPGATE.md` §10.12 "组件接口").

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
    // A new card logs in for the user who asked for it.
    if (!request.highlight) focusExitPromptOf(request.id);
    _scrollTo(request.id, highlight: request.highlight);
  }

  /// After the next frame, when the card is built.
  void _scrollTo(String id, {bool highlight = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _cardKeys[id]?.currentContext;
      if (context == null || !mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 200),
        alignment: 0.1,
      );
      if (highlight) setState(() => _flashes[id] = (_flashes[id] ?? 0) + 1);
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
