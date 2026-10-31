// The edge strip the connection manager (CM) shrinks into once a visitor has
// been let in (01 §3.3 "贴边小条"; `.frame.pill` in A-P3.html). It is the same
// window made small, not another window: 320 × 48 (the mockup draws 48 in both
// interface modes).
//
// One connection: the visitor's avatar, a line that says what they do ("李四
// 正在远程控制本机", chosen by the caller by session type), the time connected
// and "断开". Several: the avatars, "N 个会话进行中" and "展开" (which of them to
// disconnect is decided after opening the window, in the tabs).

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_pressable.dart';

const double kLgCmPillHeight = 48;

/// A visitor on the strip: [identity] is the group (0..6) of the device ID.
class LgCmPillPerson {
  const LgCmPillPerson({required this.letter, required this.identity});

  final String letter;
  final int identity;
}

/// The strip. Pressing the title part or the empty part restores the window
/// ([onRestore]); the title part is a real button, so the keyboard can do it
/// too. Dragging the empty part calls [onStartDrag] (the strip slides along the
/// top edge of the screen).
class LgCmPill extends StatelessWidget {
  /// One connection: [title] is the whole line, [time] the time connected, and
  /// the button disconnects. [blockedHint] replaces the time while a click that
  /// came from the remote side is being refused ("无法远程执行此操作").
  const LgCmPill.single({
    super.key,
    required LgCmPillPerson person,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    this.time,
    this.blockedHint,
    this.onRestore,
    this.onStartDrag,
  }) : people = const [],
       _person = person,
       danger = true;

  /// Several connections: up to three avatars overlap, [title] is "N 个会话
  /// 进行中", the button expands the window.
  const LgCmPill.group({
    super.key,
    required this.people,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    this.onRestore,
    this.onStartDrag,
  }) : _person = null,
       time = null,
       blockedHint = null,
       danger = false;

  final List<LgCmPillPerson> people;
  final LgCmPillPerson? _person;
  final String title;
  final String? time;
  final String? blockedHint;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onRestore;
  final VoidCallback? onStartDrag;

  /// True for one connection (the button is the danger "断开"), false for the
  /// group (the plain "展开").
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final shown = _person != null ? [_person] : people.take(3).toList();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRestore,
      onPanStart: onStartDrag == null ? null : (_) => onStartDrag!(),
      child: Container(
        height: kLgCmPillHeight,
        color: c.surface,
        padding: const EdgeInsets.only(left: LgSpace.s3, right: LgSpace.s2),
        child: Row(
          children: [
            _Avatars(people: shown),
            const SizedBox(width: LgSpace.s3),
            Expanded(
              child: LgPressable(
                onPressed: onRestore,
                semanticLabel: title,
                builder: (context, states) => LgFocusRing(
                  show: states.contains(WidgetState.focused),
                  radius: BorderRadius.circular(LgRadius.r6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textM.copyWith(
                              color: c.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (blockedHint != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                LgIcon(LgIcons.info, size: 12, color: c.accent),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    blockedHint!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textS.copyWith(
                                      color: c.accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else if (time != null)
                            Text(
                              time!,
                              style: t.textS.copyWith(color: c.text2),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: LgSpace.s3),
            LgButton(
              label: actionLabel,
              kind: danger ? LgButtonKind.danger : LgButtonKind.secondary,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatars extends StatelessWidget {
  const _Avatars({required this.people});

  final List<LgCmPillPerson> people;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    const size = 28.0;
    // Each avatar starts 4 px inside the one before it (`.avs .av+.av`).
    const step = size - 4;
    final group = people.length > 1;
    return ExcludeSemantics(
      child: SizedBox(
        width: size + step * (people.length - 1),
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final (i, p) in people.indexed)
              Positioned(
                left: step * i,
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.identity[p.identity % c.identity.length].tint,
                    // A ring in the ground colour where two avatars meet.
                    boxShadow: group
                        ? [BoxShadow(color: c.surface, spreadRadius: 2)]
                        : null,
                  ),
                  child: Text(
                    p.letter.toUpperCase(),
                    maxLines: 1,
                    style: t.textS.copyWith(
                      color: c.identity[p.identity % c.identity.length].ink,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
