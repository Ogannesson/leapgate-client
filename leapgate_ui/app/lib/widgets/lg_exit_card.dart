// The exit card of the exit page (01 §3.1 block I, "正在使用"; `.xc` and the
// `p1-xc-*` frames of A-P1.html), the card grid, and the short flash that
// shows which card a click on "使用中" or "用作出口" went to.
//
// The card only draws: every state is a parameter, every text comes from the
// caller (localised) and nothing here knows the exit session or the exit model
// (docs LEAPGATE.md §10.8, §10.12). The caller maps the state of one card to
// these values; which buttons a state has is 01's table, written out in
// `LEAPGATE.md` §10.12 "组件接口".

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_device.dart';
import 'lg_panel_inputs.dart';
import 'lg_selection.dart';
import 'lg_status.dart';
import 'lg_text_field.dart';
import 'lg_tooltip.dart';

/// Narrowest an exit card gets (01 block I): the grid makes fewer, wider
/// columns rather than narrower ones.
const double kLgExitCardMinWidth = 440;

/// What the status line of a card shows.
enum LgExitStatusKind {
  /// A turning arc in the accent colour: connecting, verifying, waiting for the
  /// other side to accept.
  busy,

  /// A key: the card asks for the password.
  password,

  /// A shield: the card asks for the verification code.
  code,

  /// "可用 · 直连": the route mark of the direct connection.
  direct,

  /// "可用 · 经中继": the route mark of the relayed connection.
  relay,

  /// A triangle in the warning colour: the tunnel is down for now.
  warning,

  /// A circled cross in the error colour: stopped, or the port is taken.
  error,
}

/// The status line (`.xs`): a mark and a bold [label] in the colour of the
/// kind, then optionally [reason] in regular weight and the text colour
/// ("已停止：" and why), [elapsed] after the label, and a small grey [note]
/// beside it ("流量由中继服务器转发，速度可能较慢"). A long label wraps; the
/// mark stays on the first line.
///
/// Only the mark, the [label] and the [reason] are announced when the status
/// changes. [elapsed] ("（已等待 0:12）", ticking once a second) and [note]
/// are read as text of their own: a clock in the announced part would be read
/// out every second (the connection panel keeps its "已等待" line out of it
/// too). Put the space before [elapsed] into the string where the language
/// needs one (" (0:12)").
class LgExitStatus {
  const LgExitStatus(
    this.kind,
    this.label, {
    this.reason,
    this.elapsed,
    this.note,
  });

  final LgExitStatusKind kind;
  final String label;
  final String? reason;
  final String? elapsed;
  final String? note;
}

/// One local proxy address with its copy button (`.xa`): "socks5h://127.0.0.1:
/// 21180" and "复制 SOCKS5 地址". The address is long text and ends in "…" when
/// the card is narrow; [copyLabel] is the visible name of the button and the
/// accessible one.
class LgExitAddress {
  const LgExitAddress({
    required this.address,
    required this.copyLabel,
    required this.onCopy,
  });

  final String address;
  final String copyLabel;
  final VoidCallback? onCopy;
}

/// A button of the card's bottom row. [leadingActions] are text buttons at the
/// left ("修改端口", "浏览器设置说明"), [actions] the buttons at the right (a
/// primary one and an outlined one: "重试" and "移除", "停止"). A non-null
/// [expanded] adds the arrow of a button that unfolds something and tells a
/// screen reader whether it is open.
class LgExitAction {
  const LgExitAction({
    required this.label,
    required this.onPressed,
    this.kind = LgButtonKind.text,
    this.icon,
    this.expanded,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final LgButtonKind kind;
  final LgIcons? icon;
  final bool? expanded;
  final String? semanticLabel;
}

/// The card asks for a password: the password field with the show button, the
/// "记住密码" check box. [onSubmitted] is Enter in the field. [errorText]
/// ("密码错误") turns the frame red and shows the text under it.
///
/// Focus: the field asks for the keyboard when it is first built (`autofocus`),
/// which only works while nothing else on the page has the focus. A card that
/// gets here because of what the user did (a click on "使用", "重试") passes a
/// [focusNode] and calls `requestFocus()` on it itself; a card that is asked
/// for the password again after a reconnect must not take the focus away. The
/// code area and the port field work the same way.
class LgExitPasswordArea {
  const LgExitPasswordArea({
    required this.controller,
    required this.semanticLabel,
    required this.placeholder,
    required this.showLabel,
    required this.hideLabel,
    required this.rememberLabel,
    required this.remember,
    required this.onRememberChanged,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.errorText,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String semanticLabel;
  final String placeholder;
  final String showLabel;
  final String hideLabel;
  final String rememberLabel;
  final bool remember;
  final ValueChanged<bool>? onRememberChanged;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final String? errorText;
  final bool enabled;
}

/// The card asks for a verification code: the same boxes and the same check
/// box ("信任本机") as the connection panel. [onCompleted] is called each time
/// the last digit is typed. The check box is drawn only when [trustLabel] and
/// [trust] are both given: the other side offers "trust this device" only when
/// it has trusted devices turned on.
class LgExitCodeArea {
  const LgExitCodeArea({
    required this.semanticLabel,
    this.trustLabel,
    this.trust,
    this.onTrustChanged,
    this.onCompleted,
    this.onChanged,
    this.controller,
    this.focusNode,
    this.errorText,
    this.enabled = true,
    this.length = 6,
  });

  final String semanticLabel;
  final String? trustLabel;
  final bool? trust;
  final ValueChanged<bool>? onTrustChanged;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? errorText;
  final bool enabled;
  final int length;
}

/// A note on the card that does not interrupt (`.bnr.xnote`): one target was
/// blocked by the other side, or the application sent a virtual address. [id]
/// is the reason: a note keeps its place when another one goes.
class LgExitNotice {
  const LgExitNotice({
    required this.id,
    required this.text,
    required this.dismissLabel,
    required this.onDismiss,
  });

  final String id;
  final String text;
  final String dismissLabel;
  final VoidCallback onDismiss;
}

/// The card's port edited in place (`p1-xc-port`): digits only, at most five,
/// "确定" and "取消". Enter confirms, Esc cancels. [onConfirm] null disables
/// "确定" (nothing typed, or a number that cannot be a port). [errorText] turns
/// the frame red and shows the text under the row; without it [hint] ("代理
/// 地址将改为新端口，需同步修改应用中的代理设置。") shows there.
class LgExitPortEdit {
  const LgExitPortEdit({
    required this.controller,
    required this.semanticLabel,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
    this.hint,
    this.errorText,
    this.focusNode,
  });

  final TextEditingController controller;
  final String semanticLabel;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback onCancel;
  final String? hint;
  final String? errorText;
  final FocusNode? focusNode;
}

/// A line of the browser setup help: [text], then [code] in a monospace face
/// that can be selected and copied by hand, then [after] ("。").
class LgExitHelpItem {
  const LgExitHelpItem(this.text, {this.code, this.after});

  final String text;
  final String? code;
  final String? after;
}

/// The unfolded "浏览器设置说明" (`.xhelp`): a bold title and a bullet list.
class LgExitHelp {
  const LgExitHelp({required this.title, required this.items});

  final String title;
  final List<LgExitHelpItem> items;
}

/// One exit in use. The parts follow the order of the mockup: the device, the
/// status, what the card asks for (password or code), the two local proxy
/// addresses, the notes, then either the port being edited or the buttons, and
/// last the unfolded help. A part that is null or empty is left out and the
/// card closes up; the card grows and shrinks with the state instead of
/// jumping.
///
/// Inside [LgExitCardGrid] the cards of one row are as tall as the tallest.
/// Wrap a card in [LgFlash] to mark it for a moment.
class LgExitCard extends StatelessWidget {
  const LgExitCard({
    super.key,
    required this.name,
    required this.id,
    required this.platform,
    required this.status,
    this.password,
    this.code,
    this.addresses = const [],
    this.notices = const [],
    this.portEdit,
    this.leadingActions = const [],
    this.actions = const [],
    this.help,
    this.semanticLabel,
  });

  /// The device name, or the ID when the device has none.
  final String name;

  /// The device ID, formatted ("912 345 678"); also gives the identity colour.
  final String id;
  final LgPlatform platform;
  final LgExitStatus status;
  final LgExitPasswordArea? password;
  final LgExitCodeArea? code;
  final List<LgExitAddress> addresses;
  final List<LgExitNotice> notices;

  /// While set, the buttons are left out: the field has its own.
  final LgExitPortEdit? portEdit;
  final List<LgExitAction> leadingActions;
  final List<LgExitAction> actions;
  final LgExitHelp? help;

  /// The card as a whole for a screen reader; the device name and ID by
  /// default.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final parts = <Widget>[
      // The group's name says the device; the header is for the eyes.
      ExcludeSemantics(
        child: _Header(name: name, id: id, platform: platform),
      ),
      _StatusLine(status),
      if (password != null) _PasswordBlock(password!),
      if (code != null) _CodeBlock(code!),
      for (final a in addresses) _AddressRow(a),
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
      if (portEdit != null)
        _PortEditBlock(portEdit!)
      else if (leadingActions.isNotEmpty || actions.isNotEmpty)
        _ActionRow(leading: leadingActions, trailing: actions),
    ];
    final column = <Widget>[];
    for (final (i, part) in parts.indexed) {
      if (i > 0) {
        // `.xa+.xa`: two addresses stand 4 px apart, everything else 12.
        final both = part is _AddressRow && parts[i - 1] is _AddressRow;
        column.add(SizedBox(height: both ? LgSpace.s1 : LgSpace.s3));
      }
      column.add(part);
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel ?? '$name $id',
      child: Container(
        padding: const EdgeInsets.all(LgSpace.s4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(LgRadius.r16),
        ),
        // The line under a wrong field is in regular weight here, as in the
        // dialogs (`p1-xc-pw-wrong`).
        child: LgDialogFields(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...column,
              _Reveal(child: help == null ? null : _HelpBlock(help!)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The platform tile, the name and the ID (`.xh`).
class _Header extends StatelessWidget {
  const _Header({required this.name, required this.id, required this.platform});

  final String name;
  final String id;
  final LgPlatform platform;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Row(
      children: [
        LgDeviceAvatar(id: id, platform: platform),
        const SizedBox(width: LgSpace.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LgEllipsisText(
                name,
                style: t.textN.copyWith(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.textS.copyWith(color: c.text2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The status line (`.xs`). The mark, the label and the reason are announced
/// when they change: a card that asks for a password or goes down is news for
/// a screen reader. The elapsed time and the note are not (see [LgExitStatus]).
class _StatusLine extends StatelessWidget {
  const _StatusLine(this.status);

  final LgExitStatus status;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final Widget text;
    final Color labelColor;
    switch (status.kind) {
      case LgExitStatusKind.direct:
      case LgExitStatusKind.relay:
        labelColor = status.kind == LgExitStatusKind.direct ? c.direct : c.relay;
        text = DefaultTextStyle(
          style: t.textM.copyWith(color: c.text),
          child: LgRouteMark(
            route: status.kind == LgExitStatusKind.direct
                ? LgRoute.direct
                : LgRoute.relay,
            label: status.label,
          ),
        );
      default:
        final (mark, color) = switch (status.kind) {
          LgExitStatusKind.busy => (
            LgSpinner(icon: LgIcons.markSpin, size: 12, color: c.connecting),
            c.connecting,
          ),
          LgExitStatusKind.password => (
            LgIcon(LgIcons.key, size: 16, color: c.accent),
            c.accent,
          ),
          LgExitStatusKind.code => (
            LgIcon(LgIcons.shield, size: 16, color: c.accent),
            c.accent,
          ),
          LgExitStatusKind.warning => (
            LgIcon(LgIcons.markTri, size: 12, color: c.warning),
            c.warning,
          ),
          _ => (LgIcon(LgIcons.markX, size: 12, color: c.error), c.error),
        };
        labelColor = color;
        text = Text.rich(
          TextSpan(
            children: [
              WidgetSpan(alignment: PlaceholderAlignment.middle, child: mark),
              const WidgetSpan(child: SizedBox(width: 6)),
              TextSpan(
                text: status.label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
              if (status.reason != null)
                TextSpan(
                  text: status.reason,
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w400),
                ),
            ],
          ),
          style: t.textM,
        );
    }
    final live = Semantics(liveRegion: true, container: true, child: text);
    if (status.elapsed == null && status.note == null) return live;
    final routed =
        status.kind == LgExitStatusKind.direct ||
        status.kind == LgExitStatusKind.relay;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // With a note, the mark and its words keep their width and the note
        // takes the rest; otherwise the words may wrap.
        if (routed && status.note != null) live else Flexible(child: live),
        if (status.elapsed != null)
          Text(
            status.elapsed!,
            style: t.textM.copyWith(
              color: labelColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (status.note != null) ...[
          const SizedBox(width: LgSpace.s3),
          Expanded(
            child: Text(
              status.note!,
              style: t.textS.copyWith(color: c.text2),
            ),
          ),
        ],
      ],
    );
  }
}

class _PasswordBlock extends StatelessWidget {
  const _PasswordBlock(this.area);

  final LgExitPasswordArea area;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LgPasswordField(
          controller: area.controller,
          focusNode: area.focusNode,
          placeholder: area.placeholder,
          semanticLabel: area.semanticLabel,
          showLabel: area.showLabel,
          hideLabel: area.hideLabel,
          errorText: area.errorText,
          enabled: area.enabled,
          autofocus: true,
          onChanged: area.onChanged,
          onSubmitted: area.onSubmitted,
        ),
        const SizedBox(height: LgSpace.s2),
        Align(
          alignment: Alignment.centerLeft,
          child: LgCheckbox(
            value: area.remember,
            label: area.rememberLabel,
            onChanged: area.enabled ? area.onRememberChanged : null,
          ),
        ),
      ],
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.area);

  final LgExitCodeArea area;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LgCodeField(
          semanticLabel: area.semanticLabel,
          length: area.length,
          controller: area.controller,
          focusNode: area.focusNode,
          autofocus: true,
          enabled: area.enabled,
          errorText: area.errorText,
          onChanged: area.onChanged,
          onCompleted: area.onCompleted,
        ),
        if (area.trustLabel != null && area.trust != null) ...[
          const SizedBox(height: LgSpace.s2),
          Align(
            alignment: Alignment.centerLeft,
            child: LgCheckbox(
              value: area.trust!,
              label: area.trustLabel!,
              onChanged: area.enabled ? area.onTrustChanged : null,
            ),
          ),
        ],
      ],
    );
  }
}

/// `.xa`: the address on the page background, the copy button at its end.
class _AddressRow extends StatelessWidget {
  const _AddressRow(this.address);

  final LgExitAddress address;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s3,
        LgSpace.s1,
        LgSpace.s1,
        LgSpace.s1,
      ),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(LgRadius.r10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              address.address,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: t.textM.copyWith(
                color: c.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: LgSpace.s3),
          LgButton(
            label: address.copyLabel,
            icon: LgIcons.copy,
            iconSize: 18,
            kind: LgButtonKind.text,
            onPressed: address.onCopy,
          ),
        ],
      ),
    );
  }
}

/// `.xf`: text buttons at the left, the card's main buttons at the right. The
/// first text button stands 8 px out, so that its icon lines up with the text
/// above (the mockup's negative margin).
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.leading, required this.trailing});

  final List<LgExitAction> leading;
  final List<LgExitAction> trailing;

  static Widget _button(LgExitAction a, {required bool leading}) {
    final primary = a.kind == LgButtonKind.primary;
    return LgButton(
      label: a.label,
      semanticLabel: a.semanticLabel,
      kind: a.kind,
      icon: a.icon,
      iconSize: primary ? 20 : 18,
      trailingIcon: a.expanded == null
          ? null
          : (a.expanded! ? LgIcons.chevU : LgIcons.chevD),
      expanded: a.expanded,
      horizontalPadding: leading ? LgSpace.s2 : null,
      onPressed: a.onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Transform.translate(
            offset: const Offset(-LgSpace.s2, 0),
            child: Wrap(
              spacing: LgSpace.s2,
              runSpacing: LgSpace.s1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [for (final a in leading) _button(a, leading: true)],
            ),
          ),
        ),
        for (final (i, a) in trailing.indexed) ...[
          if (i > 0 || leading.isNotEmpty) const SizedBox(width: LgSpace.s2),
          _button(a, leading: false),
        ],
      ],
    );
  }
}

class _PortEditBlock extends StatelessWidget {
  const _PortEditBlock(this.edit);

  final LgExitPortEdit edit;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): edit.onCancel},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: LgTextField(
                    controller: edit.controller,
                    focusNode: edit.focusNode,
                    semanticLabel: edit.semanticLabel,
                    autofocus: true,
                    errorText: edit.errorText,
                    // The text goes under the whole row, not under the field.
                    showErrorText: false,
                    maxLength: 5,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => edit.onConfirm?.call(),
                  ),
                ),
              ),
              const SizedBox(width: LgSpace.s2),
              LgButton(
                label: edit.confirmLabel,
                kind: LgButtonKind.primary,
                large: true,
                onPressed: edit.onConfirm,
              ),
              const SizedBox(width: LgSpace.s2),
              LgButton(
                label: edit.cancelLabel,
                kind: LgButtonKind.text,
                large: true,
                onPressed: edit.onCancel,
              ),
            ],
          ),
          if (edit.errorText != null) ...[
            const SizedBox(height: LgSpace.s2),
            // Read as part of the field's name (see `LgTextField._withError`).
            ExcludeSemantics(child: LgFieldError(edit.errorText!)),
          ] else if (edit.hint != null) ...[
            const SizedBox(height: LgSpace.s3),
            Text(edit.hint!, style: t.textS.copyWith(color: c.text2)),
          ],
        ],
      ),
    );
  }
}

/// Opens and closes the unfolded help (the gap above it included) in 160 ms,
/// without motion when the system asks for none.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final body = child == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(top: LgSpace.s3),
            child: child,
          );
    if (MediaQuery.disableAnimationsOf(context)) return body;
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: body,
    );
  }
}

const _monoFamily = 'Consolas';
const _monoFallback = ['Cascadia Mono', 'Courier New'];

/// `.xhelp`: the browser setup help on the page background, a bold title and a
/// bullet list. Everything in it can be selected; the start parameter is set
/// in a monospace face.
class _HelpBlock extends StatelessWidget {
  const _HelpBlock(this.help);

  final LgExitHelp help;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final style = t.textM.copyWith(color: c.text);
    final bullet = (t.sizes.lhM - 5) / 2;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LgSpace.s4,
        vertical: LgSpace.s3,
      ),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(LgRadius.r12),
      ),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                help.title,
                style: style.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: LgSpace.s2),
            for (final (i, item) in help.items.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : LgSpace.s1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: LgSpace.s5,
                      child: Padding(
                        padding: EdgeInsets.only(top: bullet, left: 1),
                        child: ExcludeSemantics(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.text,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox(width: 5, height: 5),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: item.text),
                            if (item.code != null)
                              TextSpan(
                                text: item.code,
                                style: const TextStyle(
                                  fontFamily: _monoFamily,
                                  fontFamilyFallback: [
                                    ..._monoFallback,
                                    ...LgFixed.fontFamilyFallback,
                                  ],
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [],
                                ),
                              ),
                            if (item.after != null) TextSpan(text: item.after),
                          ],
                        ),
                        style: style,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Marks its child for a moment with a 2 px frame in the accent colour inside
/// the edge (`.xc.flash`): the card that "使用中" or "用作出口" scrolled to.
/// Each time [count] goes up (and only then) the frame appears at once, stays
/// about a second and fades. With the system asking for no motion it appears
/// and disappears without the fade. [showing] holds it on (the gallery).
class LgFlash extends StatefulWidget {
  const LgFlash({
    super.key,
    required this.child,
    this.count = 0,
    this.showing = false,
    this.radius = LgRadius.r16,
  });

  final Widget child;
  final int count;
  final bool showing;
  final double radius;

  @override
  State<LgFlash> createState() => _LgFlashState();
}

class _LgFlashState extends State<LgFlash> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didUpdateWidget(LgFlash old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Full for the first 60 %, then a fade out; no fade without motion.
  double _opacity(bool still) {
    final v = _controller.value;
    if (!_controller.isAnimating) return 0;
    if (still) return 1;
    return v < .6 ? 1 : 1 - (v - .6) / .4;
  }

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    final still = MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(widget.radius);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final a = widget.showing ? 1.0 : _opacity(still);
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: a <= 0
              ? const BoxDecoration()
              : BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: c.accent.withValues(alpha: a),
                    width: 2,
                  ),
                ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// The cards of the exit page in as many columns as fit, each at least
/// [minWidth] wide (440) with 12 px between (`.xgrid`). The cards of a row are
/// as tall as the tallest, whatever state each is in; they keep their order
/// and the order of the columns when the window changes size. No scrolling of
/// its own: put it in the page's scroll view.
class LgExitCardGrid extends StatelessWidget {
  const LgExitCardGrid({
    super.key,
    required this.children,
    this.semanticLabel,
    this.minWidth = kLgExitCardMinWidth,
    this.gap = LgSpace.s3,
  });

  final List<Widget> children;

  /// Name of the list for a screen reader ("正在使用的出口").
  final String? semanticLabel;
  final double minWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: _GridLayout(minWidth: minWidth, gap: gap, children: children),
    );
  }
}

class _GridLayout extends MultiChildRenderObjectWidget {
  const _GridLayout({
    required this.minWidth,
    required this.gap,
    required super.children,
  });

  final double minWidth;
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGrid(minWidth, gap);

  @override
  void updateRenderObject(BuildContext context, _RenderGrid renderObject) {
    renderObject
      ..minWidth = minWidth
      ..gap = gap;
  }
}

class _GridParentData extends ContainerBoxParentData<RenderBox> {}

const _unboundedWidth =
    'LgExitCardGrid needs a bounded width: the number of columns follows it. '
    'Put it in a column of the page, not in a row or a horizontal scroll view.';

/// Lays the children out in rows of equal columns; a row is as tall as its
/// tallest child, and the others are laid out again at that height.
class _RenderGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _GridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _GridParentData> {
  _RenderGrid(this._minWidth, this._gap);

  double _minWidth;
  double _gap;

  double get minWidth => _minWidth;
  set minWidth(double v) {
    if (v == _minWidth) return;
    _minWidth = v;
    markNeedsLayout();
  }

  double get gap => _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _GridParentData) {
      child.parentData = _GridParentData();
    }
  }

  int _columns(double width) =>
      math.max(1, ((width + _gap) / (_minWidth + _gap)).floor());

  double _columnWidth(double width, int columns) =>
      (width - _gap * (columns - 1)) / columns;

  Iterable<List<RenderBox>> _rows(int columns) sync* {
    var child = firstChild;
    while (child != null) {
      final row = <RenderBox>[];
      while (child != null && row.length < columns) {
        row.add(child);
        child = childAfter(child);
      }
      yield row;
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => _minWidth;

  @override
  double computeMaxIntrinsicWidth(double height) => _minWidth;

  double _intrinsicHeight(double width) {
    final columns = _columns(width);
    final cw = _columnWidth(width, columns);
    var total = 0.0;
    var rows = 0;
    for (final row in _rows(columns)) {
      total += row.fold<double>(
        0,
        (h, c) => math.max(h, c.getMaxIntrinsicHeight(cw)),
      );
      rows++;
    }
    return rows == 0 ? 0 : total + _gap * (rows - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    assert(constraints.hasBoundedWidth, _unboundedWidth);
    final width = constraints.maxWidth;
    final columns = _columns(width);
    final cw = _columnWidth(width, columns);
    var total = 0.0;
    var rows = 0;
    for (final row in _rows(columns)) {
      total += row.fold<double>(
        0,
        (h, c) => math.max(
          h,
          c.getDryLayout(BoxConstraints.tightFor(width: cw)).height,
        ),
      );
      rows++;
    }
    return constraints.constrain(
      Size(width, rows == 0 ? 0 : total + _gap * (rows - 1)),
    );
  }

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth, _unboundedWidth);
    final width = constraints.maxWidth;
    final columns = _columns(width);
    final cw = _columnWidth(width, columns);
    var y = 0.0;
    var rows = 0;
    for (final row in _rows(columns)) {
      var h = 0.0;
      for (final child in row) {
        child.layout(BoxConstraints.tightFor(width: cw), parentUsesSize: true);
        h = math.max(h, child.size.height);
      }
      for (final (i, child) in row.indexed) {
        if (child.size.height != h) {
          // A minimum, not a tight height: a tight box would be a relayout
          // boundary, and a card that grows (the help unfolding) would not
          // reach the row any more.
          child.layout(
            BoxConstraints(minWidth: cw, maxWidth: cw, minHeight: h),
            parentUsesSize: true,
          );
        }
        (child.parentData! as _GridParentData).offset = Offset(
          i * (cw + _gap),
          y,
        );
      }
      y += h + _gap;
      rows++;
    }
    size = constraints.constrain(Size(width, rows == 0 ? 0 : y - _gap));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
