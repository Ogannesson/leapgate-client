// The information header of the connection manager (CM) and the note of the
// sessions that have no permissions (01 §3.3; `.cm-head`, `.cm-exit` in
// A-P3.html).
//
// The header sits on a fixed light-teal ground (`cmBand`), not on the
// visitor's identity colour: that one would be mistaken for the warning and
// error grounds (01 §2.4). The identity colour is only the avatar.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';
import 'lg_status.dart';
import 'lg_tooltip.dart';

/// Where the visitor is in the connection, which decides the marker and the
/// colour of the status line. The voice phases replace "已连接" while a voice
/// call is asked for or running; they have no marker, only the coloured words.
enum LgCmPhase {
  /// Waiting for the person at this computer to decide.
  requesting,
  connected,
  disconnected,
  voiceRequesting,
  voiceActive,
}

/// The status line: "正在请求连接本机…", "已连接 00:12:34", "已断开".
class LgCmStatusLine {
  const LgCmStatusLine({required this.phase, required this.label, this.time});

  final LgCmPhase phase;
  final String label;

  /// The time connected ("00:12:34"); the voice phases keep it, a call has no
  /// time of its own.
  final String? time;
}

/// The round button at the top right of the header that opens the side panel
/// (chat on a remote desktop or camera session, file records on a file
/// transfer). Not there before the visitor is let in, nor on terminal, port
/// forwarding and exit sessions.
class LgCmSideButton {
  const LgCmSideButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.unread = 0,
    this.semanticLabel,
  });

  final LgIcons icon;

  /// "聊天", "文件记录": the tooltip and, unless [semanticLabel] says more, the
  /// accessible name.
  final String label;
  final VoidCallback? onPressed;

  /// The side panel is open.
  final bool selected;

  /// Unread chat messages, drawn on the button when above zero.
  final int unread;
  final String? semanticLabel;
}

/// The header: avatar, name, ID, session type and the status line. [type] is
/// the whole line ("远程桌面", "端口转发：10.0.0.5:8080"). [id] is the formatted
/// ID; its groups are set apart by the gap of the mockup.
class LgCmHeader extends StatelessWidget {
  const LgCmHeader({
    super.key,
    required this.name,
    required this.id,
    required this.identity,
    required this.type,
    required this.status,
    this.avatarText,
    this.avatarImage,
    this.sideButton,
  });

  final String name;
  final String id;

  /// The group (0..6) of the visitor's device ID (`identityGroup()`).
  final int identity;
  final String type;
  final LgCmStatusLine status;

  /// The letter on the avatar; the first character of [name] when null.
  final String? avatarText;

  /// The visitor's picture, when there is one; it replaces the letter.
  final ImageProvider? avatarImage;
  final LgCmSideButton? sideButton;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final s = t.sizes;
    final groups = id.trim().split(RegExp(r'\s+'));
    return Container(
      height: s.cmHead,
      color: c.cmBand,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
            child: Row(
              children: [
                _Avatar(
                  size: s.cmAvatar,
                  identity: c.identity[identity % c.identity.length],
                  onIdentity: c.onIdentity,
                  text: avatarText ?? _firstCharacter(name),
                  image: avatarImage,
                ),
                SizedBox(width: s.cmHeadGap),
                Expanded(
                  child: MergeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          // Clears the side button.
                          padding: EdgeInsets.only(
                            right: sideButton == null ? 0 : LgSpace.s6,
                          ),
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LgTokens.style(
                              s.fsCmName,
                              s.lhCmName,
                              FontWeight.w700,
                            ).copyWith(color: c.text),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (i, g) in groups.indexed) ...[
                              if (i > 0) const SizedBox(width: LgSpace.s2),
                              Text(
                                g,
                                style: LgTokens.style(
                                  s.fs,
                                  s.lh,
                                  FontWeight.w600,
                                ).copyWith(color: c.text),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          type,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.copyWith(color: c.text2),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: _StatusRow(status: status),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (sideButton != null)
            Positioned(
              right: LgSpace.s2,
              top: LgSpace.s1,
              child: _SideButton(spec: sideButton!),
            ),
        ],
      ),
    );
  }
}

String _firstCharacter(String name) =>
    name.isEmpty ? '' : String.fromCharCode(name.runes.first);

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.size,
    required this.identity,
    required this.onIdentity,
    required this.text,
    required this.image,
  });

  final double size;
  final LgIdentityColor identity;
  final Color onIdentity;
  final String text;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: identity.solid),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        style: LgTokens.style(
          LgFixed.fsCmAvatar,
          LgFixed.fsCmAvatar + 4,
          FontWeight.w700,
        ).copyWith(color: onIdentity),
      ),
    );
    return ExcludeSemantics(
      child: image == null
          ? letter
          // A picture that does not load falls back to the letter, as upstream's
          // `buildAvatarWidget` does.
          : ClipOval(
              child: Image(
                image: image!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => letter,
              ),
            ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status});

  final LgCmStatusLine status;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final voice =
        status.phase == LgCmPhase.voiceRequesting ||
        status.phase == LgCmPhase.voiceActive;
    final style = voice ? t.textM : t.text;
    final Widget label;
    switch (status.phase) {
      case LgCmPhase.requesting:
        // Not a `.stt`: the spinner and plain words, 8 px apart.
        label = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgSpinner(icon: LgIcons.markSpin, size: 12, color: c.connecting),
            const SizedBox(width: LgSpace.s2),
            Flexible(
              child: Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.connecting),
              ),
            ),
          ],
        );
      case LgCmPhase.connected:
        label = LgStatusText(LgStatus.online, status.label);
      case LgCmPhase.disconnected:
        label = LgStatusText(LgStatus.offline, status.label);
      case LgCmPhase.voiceRequesting:
      case LgCmPhase.voiceActive:
        label = Text(
          status.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: status.phase == LgCmPhase.voiceActive
                ? c.online
                : c.connecting,
          ),
        );
    }
    return DefaultTextStyle.merge(
      style: style,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: label),
          if (status.time != null) ...[
            const SizedBox(width: LgSpace.s2),
            Text(status.time!, style: style.copyWith(color: c.text)),
          ],
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({required this.spec});

  final LgCmSideButton spec;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final side = t.sizes.button;
    final radius = BorderRadius.circular(LgRadius.r10);
    return LgTooltip(
      message: spec.label,
      child: LgPressable(
        onPressed: spec.onPressed,
        selected: spec.selected,
        semanticLabel: spec.semanticLabel ?? spec.label,
        builder: (context, states) {
          final overlay = spec.selected ? null : lgStateOverlay(c, states);
          return LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: radius,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: side,
                  height: side,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: spec.selected ? c.active : overlay,
                    borderRadius: radius,
                  ),
                  child: LgIcon(
                    spec.icon,
                    size: t.sizes.icon,
                    color: spec.selected ? c.accent : c.text2,
                  ),
                ),
                if (spec.unread > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: ExcludeSemantics(
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(LgRadius.r6),
                        ),
                        child: Text(
                          '${spec.unread}',
                          style: t.textS.copyWith(
                            color: c.onAccent,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// What an exit session shows instead of permissions: an icon and one sentence
/// on a quiet ground ("对方正在通过本机访问网络（仅 TCP），无法查看本机屏幕。").
/// The session has no permissions, no chat and no record of where it goes
/// (01 §3.3).
class LgCmNoteBlock extends StatelessWidget {
  const LgCmNoteBlock({
    super.key,
    required this.text,
    this.icon = LgIcons.exit,
  });

  final String text;
  final LgIcons icon;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Padding(
      // The header's 8 below plus 12.
      padding: const EdgeInsets.only(top: LgSpace.s3),
      child: Container(
        padding: const EdgeInsets.all(LgSpace.s4),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(LgRadius.r16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(LgRadius.r12),
              ),
              child: LgIcon(icon, size: 24, color: c.accent),
            ),
            const SizedBox(width: LgSpace.s3),
            Expanded(
              child: Text(text, style: t.text.copyWith(color: c.text)),
            ),
          ],
        ),
      ),
    );
  }
}
