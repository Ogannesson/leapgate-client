// The cards of the "隧道" section of the exit page (`A-P8-隧道.html`): the TCP
// tunnel card, which lists every port forward of one device, and the RDP card;
// the kind mark at the end of their head; the question area that opens under the
// head when a forward asks for something; and the stack the cards stand in.
//
// The cards are built from the same parts as the exit card ([LgExitCardFrame],
// [LgExitCardHeader], [LgExitStatusLine], [LgExitActionRow]) and the table of
// [LgForwardList]. They only draw: every state is a parameter and every text
// comes from the caller (localised); nothing here knows the tunnel model
// (docs LEAPGATE.md §10.8, §10.18).

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_device.dart';
import 'lg_exit_card.dart';
import 'lg_exit_page.dart';
import 'lg_forward_list.dart';
import 'lg_status.dart';

/// The widest a question area gets (`.xq`): wider cards leave the rest empty.
const double kLgTunnelQuestionMaxWidth = 520;

/// What kind of card this is, at the end of its head (`.tkind`): a small block on the second
/// surface colour with an icon and bold words, "TCP 隧道" or "RDP · 端口 3389". It is for the eyes;
/// the card's name for a screen reader already says it.
class LgTunnelKindMark extends StatelessWidget {
  const LgTunnelKindMark({super.key, required this.icon, required this.label});

  final LgIcons icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return ExcludeSemantics(
      child: Container(
        height: t.sizes.button - 8,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(LgRadius.r6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgIcon(icon, size: 16, color: c.text2),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: t.textS.copyWith(
                color: c.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Ask { password, code, busy, insecure }

/// The part of a card that asks the user for something (`.xq`): on the page's background with a
/// 2 px frame in the accent colour (the warning colour for an insecure connection), at most
/// [kLgTunnelQuestionMaxWidth] wide, under the head. A card has one, whichever forward asked, and
/// it closes when no forward is still waiting for an answer.
///
/// * [LgTunnelQuestion.password] and [LgTunnelQuestion.code]: the title (a key, a shield), the
///   field, the check box ("记住密码", "信任本机") and the buttons at the end, [confirm] ("连接",
///   "验证") and [cancel] ("取消"). The fields are those of [LgExitPasswordArea] and
///   [LgExitCodeArea], as on the exit card.
/// * [LgTunnelQuestion.busy]: one line, a turning arc, [text] ("正在验证…", "正在等待对方接受…")
///   with the [elapsed] time after it, and [cancel].
/// * [LgTunnelQuestion.insecure]: a warning with a bold [title] ("未加密") and the [message]; the
///   answer to give up ([confirm], "断开") is the one that takes the keyboard (`autofocus`), and
///   the other ([cancel], "继续") is outlined. It is a live region.
///
/// The area is a group named [semanticLabel] (the title by default).
class LgTunnelQuestion extends StatelessWidget {
  const LgTunnelQuestion.password({
    super.key,
    required this.title,
    required LgExitPasswordArea this.password,
    required LgExitAction this.confirm,
    required this.cancel,
    this.semanticLabel,
  }) : _ask = _Ask.password,
       code = null,
       message = null,
       elapsed = null;

  const LgTunnelQuestion.code({
    super.key,
    required this.title,
    required LgExitCodeArea this.code,
    required LgExitAction this.confirm,
    required this.cancel,
    this.semanticLabel,
  }) : _ask = _Ask.code,
       password = null,
       message = null,
       elapsed = null;

  const LgTunnelQuestion.busy({
    super.key,
    required String text,
    this.elapsed,
    required this.cancel,
    this.semanticLabel,
  }) : _ask = _Ask.busy,
       title = text,
       password = null,
       code = null,
       message = null,
       confirm = null;

  const LgTunnelQuestion.insecure({
    super.key,
    required this.title,
    required String this.message,
    required LgExitAction this.confirm,
    required this.cancel,
    this.semanticLabel,
  }) : _ask = _Ask.insecure,
       password = null,
       code = null,
       elapsed = null;

  final _Ask _ask;

  /// The title of the question; for [LgTunnelQuestion.busy] the text of the line.
  final String title;
  final LgExitPasswordArea? password;
  final LgExitCodeArea? code;
  final String? message;

  /// "（已等待 0:12）", ticking once a second; the space before it is part of the string where
  /// the language needs one. Read as the line is, not announced each second.
  final String? elapsed;
  final LgExitAction? confirm;
  final LgExitAction cancel;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final warn = _ask == _Ask.insecure;
    final line = _ask == _Ask.busy;
    final radius = BorderRadius.circular(LgRadius.r12);
    final Widget body;
    switch (_ask) {
      case _Ask.password:
      case _Ask.code:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LgExitStatusLine(
              LgExitStatus(
                _ask == _Ask.password
                    ? LgExitStatusKind.password
                    : LgExitStatusKind.code,
                title,
              ),
            ),
            const SizedBox(height: LgSpace.s3),
            if (_ask == _Ask.password)
              LgExitPasswordBlock(password!)
            else
              LgExitCodeBlock(code!),
            // The 12 px of the card's gap and 4 more (`.xq .xf`).
            const SizedBox(height: LgSpace.s4),
            LgExitActionRow(trailing: [confirm!, cancel]),
          ],
        );
      case _Ask.busy:
        body = Row(
          children: [
            LgSpinner(icon: LgIcons.markSpin, size: 12, color: c.connecting),
            const SizedBox(width: 6),
            Expanded(
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title),
                      if (elapsed != null) TextSpan(text: elapsed),
                    ],
                  ),
                  style: t.text.copyWith(
                    color: c.connecting,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: LgSpace.s3),
            LgButton(
              label: cancel.label,
              semanticLabel: cancel.semanticLabel,
              kind: cancel.kind,
              focusNode: cancel.focusNode,
              onPressed: cancel.onPressed,
            ),
          ],
        );
      case _Ask.insecure:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LgIcon(LgIcons.warn, size: 22, color: c.warning),
                const SizedBox(width: LgSpace.s3),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: '\n$message'),
                      ],
                    ),
                    style: t.text.copyWith(color: c.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LgSpace.s4),
            LgExitActionRow(trailing: [confirm!, cancel]),
          ],
        );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kLgTunnelQuestionMaxWidth),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          liveRegion: warn,
          label: semanticLabel ?? title,
          child: Container(
            padding: line
                ? const EdgeInsets.symmetric(
                    vertical: LgSpace.s3,
                    horizontal: LgSpace.s4,
                  )
                : const EdgeInsets.all(LgSpace.s4),
            decoration: BoxDecoration(
              color: warn ? c.warningBg : c.bg,
              borderRadius: radius,
            ),
            // The mockup's frame is an inset shadow: drawn inside, no layout effect.
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: warn ? c.warning : c.accent, width: 2),
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// A card of the tunnel section: a TCP tunnel (the table of forwards, [forwards]) or an RDP
/// connection (no table, two text buttons at the left of the buttons row). The parts follow the
/// mockup's order: the head with the [kindMark] at its end, the [question], the [status] line
/// (the state of the card as a whole: "可用 · 经中继", "已停止：本机已有连接此设备的出口"), the
/// table or [emptyText] ("暂无端口转发") where it would be, the [addRow], the [notices], then the
/// buttons. A part that is null or empty is left out and the card closes up.
///
/// It is a group for a screen reader named [semanticLabel] ("书房台式机 · TCP 隧道"). Wrap it in
/// [LgFlash] to mark it for a moment.
class LgTunnelCard extends StatelessWidget {
  const LgTunnelCard({
    super.key,
    required this.name,
    required this.id,
    required this.platform,
    required this.kindMark,
    required this.semanticLabel,
    this.question,
    this.status,
    this.forwards,
    this.emptyText,
    this.addRow,
    this.notices = const [],
    this.leadingActions = const [],
    this.actions = const [],
  });

  /// The device name, or the ID when the device has none.
  final String name;

  /// The device ID, formatted ("123 456 789"); also gives the identity colour.
  final String id;
  final LgPlatform platform;

  /// [LgTunnelKindMark].
  final Widget kindMark;
  final String semanticLabel;
  final LgTunnelQuestion? question;
  final LgExitStatus? status;
  final LgForwardList? forwards;
  final String? emptyText;
  final LgForwardAddRow? addRow;
  final List<LgExitNotice> notices;
  final List<LgExitAction> leadingActions;
  final List<LgExitAction> actions;

  @override
  Widget build(BuildContext context) {
    return LgExitCardFrame(
      semanticLabel: semanticLabel,
      parts: [
        // The group's name says the device; the head is for the eyes.
        ExcludeSemantics(
          child: LgExitCardHeader(
            name: name,
            id: id,
            platform: platform,
            trailing: kindMark,
          ),
        ),
        if (question != null) question!,
        if (status != null) LgExitStatusLine(status!),
        if (forwards != null)
          forwards!
        else if (emptyText != null)
          LgForwardEmpty(emptyText!),
        if (addRow != null) addRow!,
        for (final n in notices)
          KeyedSubtree(
            key: ValueKey('notice-${n.id}'),
            child: LgBanner(
              tone: LgTone.info,
              slim: true,
              text: n.text,
              dismissLabel: n.dismissLabel,
              onDismiss: n.onDismiss,
            ),
          ),
        if (leadingActions.isNotEmpty || actions.isNotEmpty)
          LgExitActionRow(leading: leadingActions, trailing: actions),
      ],
    );
  }
}

/// The cards of the tunnel section one under the other, 12 px apart and 16 px under the section's
/// head (`.tstack`), each as wide as the page. Without cards, [emptyText] ("暂无正在使用的隧道")
/// stands on a card of its own ([LgExitEmptyNote]).
class LgTunnelStack extends StatelessWidget {
  const LgTunnelStack({
    super.key,
    required this.children,
    this.emptyText,
    this.semanticLabel,
  });

  final List<Widget> children;
  final String? emptyText;

  /// Name of the list for a screen reader ("正在使用的隧道").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: LgSpace.s4),
        child: emptyText == null
            ? const SizedBox.shrink()
            : LgExitEmptyNote(emptyText!),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s4),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: semanticLabel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const SizedBox(height: LgSpace.s3),
              child,
            ],
          ],
        ),
      ),
    );
  }
}
