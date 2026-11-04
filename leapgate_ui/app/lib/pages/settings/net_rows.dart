import 'package:flutter/material.dart';

import '../../shell/tab_overlays.dart';
import '../../theme/lg_tokens.dart';
import '../../widgets/lg_banner.dart';
import '../../widgets/lg_button.dart';
import '../../widgets/lg_feedback.dart';
import '../../widgets/lg_status.dart';
import 'settings_registry.dart';

// Placeholder rows of coder B's sections (exit node, connection methods, appearance, network and
// server, account), on the M0~M5 components. TODO(M6 整合): replace with the designer's setting
// row, subheading, status-and-button row and in-page confirmation (09 §2.2).

/// One item: name, description, control; the line under it ([SettingsSectionContext.errorOf]
/// or [note]); marked for about 2 seconds after search or a link.
class NetRow extends StatelessWidget {
  const NetRow({
    super.key,
    required this.ctx,
    required this.item,
    required this.name,
    this.description,
    this.control,
    this.note,
    this.indent = false,
    this.children = const [],
  });

  final SettingsSectionContext ctx;
  final String item;
  final String name;
  final String? description;
  final Widget? control;

  /// A neutral line under the item ("关闭“打洞直连”时始终启用").
  final String? note;
  final bool indent;

  /// More under the description (status lines, an input with its unit).
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final error = ctx.errorOf(item);
    return Container(
      key: ctx.keyOf(item),
      color: ctx.isMarked(item) ? c.hover : null,
      padding: EdgeInsets.fromLTRB(
          indent ? LgSpace.s6 : 0, LgSpace.s2, 0, LgSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: LgSpace.s4,
            runSpacing: LgSpace.s2,
            children: [
              Text(name, style: t.text.copyWith(color: c.text)),
              if (control != null) control!,
            ],
          ),
          if (description != null)
            Text(description!, style: t.textS.copyWith(color: c.text2)),
          ...children,
          if (note != null)
            Text(note!, style: t.textS.copyWith(color: c.text2)),
          if (error != null)
            Text(error, style: t.textS.copyWith(color: c.error)),
        ],
      ),
    );
  }
}

/// A subheading inside a section ("高级", "无人值守").
class NetSubheading extends StatelessWidget {
  const NetSubheading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s4, bottom: LgSpace.s1),
      child: Semantics(
        header: true,
        child: Text(text,
            style: t.text
                .copyWith(color: t.colors.text, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// A status line: passing or a warning, always with its text, and an optional button.
class NetStatusLine extends StatelessWidget {
  const NetStatusLine(
      {super.key,
      required this.ok,
      required this.text,
      this.action,
      this.onAction});

  final bool ok;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: LgSpace.s3,
        children: [
          LgStatusText(ok ? LgStatus.online : LgStatus.warning, text),
          if (action != null)
            LgButton(
                label: action!, kind: LgButtonKind.text, onPressed: onAction),
        ],
      );
}

/// A note at the top of a section, with a link ("网络和服务器").
class NetNote extends StatelessWidget {
  const NetNote(
      {super.key,
      required this.text,
      required this.link,
      required this.onLink,
      this.tone = LgTone.warning});

  final String text;
  final String link;
  final VoidCallback onLink;
  final LgTone tone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: LgSpace.s2),
        child: LgBanner(
            tone: tone, text: text, slim: true, actionLabel: link, onAction: onLink),
      );
}

/// The in-page confirmation (02 §3.5) over the home tab; true when confirmed.
Future<bool> confirmInSettings(
  TabOverlays overlays, {
  required String title,
  String? body,
  required String action,
  required String cancel,
  bool danger = false,
}) async =>
    await overlays.show<bool>(
      null,
      (context, close) => LgDialogScrim(
        onEscape: () => close(false),
        child: LgConfirmDialog(
          title: title,
          body: body,
          actions: [
            LgDialogAction(label: cancel, onPressed: () => close(false)),
            LgDialogAction(
              label: action,
              kind: danger ? LgButtonKind.dangerSolid : LgButtonKind.primary,
              isDefault: true,
              onPressed: () => close(true),
            ),
          ],
        ),
      ),
    ) ??
    false;
