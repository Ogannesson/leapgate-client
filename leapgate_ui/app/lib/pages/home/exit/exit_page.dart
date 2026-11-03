import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/exit_directory.dart';
import 'package:flutter_hbb/leapgate/exit_nodes.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shell/navigation.dart';
import '../../../shell/tab_overlays.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_text_field.dart';
import 'exit_card_view.dart';
import 'exit_directory_view.dart';

// The exit page (01 P1 block I): a sentence, the cards in use, the directory, by ID. Placeholder
// layout until designer's page frame (`LEAPGATE.md` §10.12 "组件").

/// Each column of cards is at least this wide (01 P1 block I).
const double _cardMinWidth = 440;

/// How long a card stays marked after the page scrolled to it.
const _highlightFor = Duration(seconds: 2);

class ExitPage extends StatefulWidget {
  const ExitPage({super.key, required this.overlays});

  final TabOverlays overlays;

  @override
  State<ExitPage> createState() => _ExitPageState();
}

class _ExitPageState extends State<ExitPage> {
  final _id = TextEditingController();
  final _cardKeys = <String, GlobalKey>{};
  var _badId = false;
  String? _highlighted;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    appCore.exitDirectory.open();
    _id.addListener(_onIdChanged);
    exitPageRequests.addListener(_onRequest);
    // "Use as exit node" from elsewhere switched to this page.
    _onRequest();
  }

  @override
  void dispose() {
    appCore.exitDirectory.close();
    exitPageRequests.removeListener(_onRequest);
    _highlightTimer?.cancel();
    _id.dispose();
    super.dispose();
  }

  void _onIdChanged() => setState(() => _badId = false);

  void _onRequest() {
    final request = exitPageRequests.take();
    if (request != null) _scrollTo(request.id, highlight: request.highlight);
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
      if (!highlight) return;
      _highlightTimer?.cancel();
      setState(() => _highlighted = id);
      _highlightTimer = Timer(_highlightFor, () {
        if (mounted) setState(() => _highlighted = null);
      });
    });
  }

  /// "Use" in the directory and by ID; a device that already has a card is only shown.
  void _use(String id, {String? name}) {
    final had = appCore.exitNodes.cardOf(id) != null;
    appCore.exitNodes.use(id, name: name);
    _scrollTo(id, highlight: had);
  }

  void _useById() {
    final input = _id.text.trim();
    if (input.isEmpty) return;
    if (!isExitId(input)) {
      setState(() => _badId = true);
      return;
    }
    _use(input.replaceAll(' ', ''));
    _id.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final c = t.colors;
    Widget heading(String text, [Widget? trailing]) => Padding(
      padding: const EdgeInsets.only(top: LgSpace.s5, bottom: LgSpace.s2),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: t.text.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: LgSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.exitLede, style: t.text.copyWith(color: c.text2)),
          heading(l10n.exitInUseTitle),
          ListenableBuilder(
            listenable: appCore.exitNodes,
            builder: (context, _) {
              final cards = appCore.exitNodes.cards;
              if (cards.isEmpty) {
                return Text(
                  l10n.exitNoneInUse,
                  style: t.text.copyWith(color: c.text2),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  const gap = LgSpace.s3;
                  final columns =
                      ((constraints.maxWidth + gap) ~/ (_cardMinWidth + gap))
                          .clamp(1, cards.length);
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final card in cards)
                        SizedBox(
                          key: _cardKeys.putIfAbsent(card.id, GlobalKey.new),
                          width: width,
                          child: ExitCardView(
                            card: card,
                            highlighted: _highlighted == card.id,
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
          heading(
            l10n.exitAvailableTitle,
            ListenableBuilder(
              listenable: Listenable.merge([
                appCore.exitDirectory,
                appCore.account,
              ]),
              builder: (context, _) => LgButton(
                label: l10n.homeRefresh,
                kind: LgButtonKind.text,
                onPressed:
                    const {
                      ExitDirectoryState.loading,
                      ExitDirectoryState.notLoggedIn,
                    }.contains(appCore.exitDirectory.state)
                    ? null
                    : appCore.exitDirectory.load,
              ),
            ),
          ),
          ExitDirectoryView(
            overlays: widget.overlays,
            onUse: (node) => _use(
              node.id,
              name: node.hostname.isEmpty ? null : node.hostname,
            ),
            onShow: (id) => _scrollTo(id, highlight: true),
          ),
          heading(l10n.exitByIdTitle),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LgTextField(
                  controller: _id,
                  placeholder: l10n.exitIdPlaceholder,
                  semanticLabel: l10n.exitByIdTitle,
                  errorText: _badId ? l10n.exitBadId : null,
                  onSubmitted: (_) => _useById(),
                ),
              ),
              const SizedBox(width: LgSpace.s2),
              LgButton(
                label: l10n.exitUse,
                kind: LgButtonKind.primary,
                onPressed: _id.text.trim().isEmpty ? null : _useById,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
