// Devices in lists: the platform avatar, the list row, the "connect to" row of
// the connection box and the states of the list (empty, loading, no result).
// `.tile`, `.tr`, `.rrow`, `.box` and `.sk` in A-基础.html and A-P1.html.
//
// The components only draw: all text comes from the caller (localised) and
// nothing here knows the session or the peer model (docs LEAPGATE.md §10.8).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_hbb/leapgate/identity_color.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_pressable.dart';
import 'lg_status.dart';
import 'lg_tooltip.dart';

/// Platforms a device can have in the list (01 §3.1 block F: iOS cannot be
/// controlled, so it never appears).
enum LgPlatform { windows, macos, linux, android, unknown }

LgIcons lgPlatformIcon(LgPlatform platform) => switch (platform) {
  LgPlatform.windows => LgIcons.windows,
  LgPlatform.macos => LgIcons.macos,
  LgPlatform.linux => LgIcons.linux,
  LgPlatform.android => LgIcons.android,
  LgPlatform.unknown => LgIcons.monitor,
};

/// The platform icon of a device on its identity colour (01 §2.4): a tile of
/// the identity tint with the icon in the identity ink, or with [tile] false
/// only the icon (the list row of the mockups, `.tr .pf`).
///
/// [id] may be formatted ("123 456 789") or as stored; the colour is the same.
class LgDeviceAvatar extends StatelessWidget {
  const LgDeviceAvatar({
    super.key,
    required this.id,
    required this.platform,
    this.size = 44,
    this.tile = true,
  });

  final String id;
  final LgPlatform platform;

  /// Edge of the tile; with [tile] false the size of the icon.
  final double size;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final identity = LgTokens.of(
      context,
    ).colors.identity[identityGroup(id.replaceAll(' ', ''))];
    final icon = lgPlatformIcon(platform);
    if (!tile) return LgIcon(icon, size: size, color: identity.ink);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: identity.tint,
        borderRadius: BorderRadius.circular(
          size >= 40 ? LgRadius.r12 : LgRadius.r10,
        ),
      ),
      child: LgIcon(icon, size: size >= 40 ? 24 : 20, color: identity.ink),
    );
  }
}

/// Online state of a device in a list. `querying` is the neutral "still
/// asking" state shown while the first answer is on its way (01 §3.1).
enum LgDeviceStatus { online, offline, querying }

// Column widths of the list: the header and the rows must agree.
const double _statusWidth = 104;
const double _idWidth = 124;
const double _actionWidth = 112;
const double _columnGap = LgSpace.s3;
const int _nameFlex = 16;
const int _hostFlex = 15;
const int _sourceFlex = 10;

/// Surface the rows (`.tbl`) sit on.
class LgListSurface extends StatelessWidget {
  const LgListSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        LgSpace.s2,
        LgSpace.s1,
        LgSpace.s2,
        LgSpace.s2,
      ),
      decoration: BoxDecoration(
        color: LgTokens.of(context).colors.surface,
        borderRadius: BorderRadius.circular(LgRadius.r16),
      ),
      child: child,
    );
  }
}

/// Column titles above the rows (`.tr.th`). [source] is only passed when the
/// rows carry a source category (search results).
class LgDeviceListHeader extends StatelessWidget {
  const LgDeviceListHeader({
    super.key,
    required this.status,
    required this.name,
    required this.id,
    required this.userHost,
    this.source,
  });

  final String status;
  final String name;
  final String id;
  final String userHost;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final style = t.textS.copyWith(
      color: t.colors.text2,
      fontWeight: FontWeight.w700,
    );
    Widget cell(String text) =>
        Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Container(
      height: t.sizes.button,
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
      child: Row(
        children: [
          SizedBox(width: _statusWidth, child: cell(status)),
          const SizedBox(width: _columnGap),
          Expanded(flex: _nameFlex, child: cell(name)),
          const SizedBox(width: _columnGap),
          SizedBox(width: _idWidth, child: cell(id)),
          const SizedBox(width: _columnGap),
          Expanded(flex: _hostFlex, child: cell(userHost)),
          if (source != null) ...[
            const SizedBox(width: _columnGap),
            Expanded(flex: _sourceFlex, child: cell(source!)),
          ],
          const SizedBox(width: _columnGap),
          const SizedBox(width: _actionWidth),
        ],
      ),
    );
  }
}

/// One device in a list (`.tr`): state, name with the platform icon, ID,
/// `user@host`, and with [source] the category it came from. A click selects
/// ([onTap]), a double click or Enter connects ([onDoubleTap], [onConnect]);
/// while the pointer or the keyboard is on the row the "connect" button of
/// [onConnect] shows at its end. [highlighted] is the row the arrow keys of
/// the connection box moved to.
class LgDeviceRow extends StatefulWidget {
  const LgDeviceRow({
    super.key,
    required this.name,
    required this.id,
    required this.platform,
    required this.status,
    required this.statusLabel,
    this.userHost,
    this.source,
    this.selected = false,
    this.highlighted = false,
    this.topDivider = true,
    this.onTap,
    this.onDoubleTap,
    this.onConnect,
    this.connectLabel,
    this.focusNode,
  }) : assert(onConnect == null || connectLabel != null);

  final String name;

  /// Formatted ID ("123 456 789").
  final String id;
  final LgPlatform platform;
  final LgDeviceStatus status;

  /// "在线", "离线", "正在查询…".
  final String statusLabel;
  final String? userHost;
  final String? source;
  final bool selected;
  final bool highlighted;

  /// The 1 px line between rows; the first row of a list leaves it out.
  final bool topDivider;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onConnect;
  final String? connectLabel;
  final FocusNode? focusNode;

  @override
  State<LgDeviceRow> createState() => _LgDeviceRowState();
}

class _LgDeviceRowState extends State<LgDeviceRow> {
  static const _doubleClick = Duration(milliseconds: 300);
  Duration? _lastDown;

  // A click selects at once; a second click inside the window is a double
  // click. GestureDetector.onDoubleTap would delay the selection.
  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    final last = _lastDown;
    if (last != null && e.timeStamp - last <= _doubleClick) {
      _lastDown = null;
      widget.onDoubleTap?.call();
    } else {
      _lastDown = e.timeStamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    final label = [
      w.name,
      w.statusLabel,
      w.id,
      if (w.userHost != null) w.userHost!,
      if (w.source != null) w.source!,
    ].join(', ');
    final row = LgPressable(
      onPressed: w.onTap ?? w.onConnect,
      onActivate: w.onConnect ?? w.onTap,
      focusNode: w.focusNode,
      // The row the arrow keys moved to is "selected" for a screen reader too.
      selected: w.selected || w.highlighted,
      semanticLabel: label,
      builder: (context, states) {
        final hot =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        final focused = states.contains(WidgetState.focused);
        final on = w.selected || w.highlighted;
        final Color? bg = on ? c.active : (hot ? c.surface2 : null);
        final showConnect = w.onConnect != null && (hot || focused || on);
        final cellStyle = t.text.copyWith(color: c.text);
        final status = switch (w.status) {
          LgDeviceStatus.online => LgStatus.online,
          LgDeviceStatus.offline => LgStatus.offline,
          LgDeviceStatus.querying => LgStatus.querying,
        };
        return LgFocusRing(
          show: focused,
          radius: radius,
          inset: true,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: t.sizes.tableRow,
                padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
                decoration: BoxDecoration(color: bg, borderRadius: radius),
                foregroundDecoration: w.highlighted
                    ? BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(color: c.accent, width: 2),
                      )
                    : null,
                child: ExcludeSemantics(
                  child: DefaultTextStyle(
                    style: cellStyle,
                    maxLines: 1,
                    child: Row(
                      children: [
                        SizedBox(
                          width: _statusWidth,
                          child: LgStatusText(status, w.statusLabel),
                        ),
                        const SizedBox(width: _columnGap),
                        Expanded(
                          flex: _nameFlex,
                          child: Row(
                            children: [
                              LgDeviceAvatar(
                                id: w.id,
                                platform: w.platform,
                                size: t.sizes.icon,
                                tile: false,
                              ),
                              const SizedBox(width: LgSpace.s2),
                              Expanded(
                                child: LgEllipsisText(
                                  w.name,
                                  style: cellStyle.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: _columnGap),
                        SizedBox(
                          width: _idWidth,
                          child: Text(
                            w.id,
                            style: cellStyle.copyWith(color: c.text2),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: _columnGap),
                        Expanded(
                          flex: _hostFlex,
                          child: w.userHost == null
                              ? const SizedBox.shrink()
                              : LgEllipsisText(
                                  w.userHost!,
                                  style: cellStyle.copyWith(color: c.text2),
                                ),
                        ),
                        if (w.source != null) ...[
                          const SizedBox(width: _columnGap),
                          Expanded(
                            flex: _sourceFlex,
                            child: Text(
                              w.source!,
                              style: cellStyle.copyWith(color: c.text2),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        const SizedBox(width: _columnGap),
                        SizedBox(
                          width: _actionWidth,
                          child: showConnect
                              ? Align(
                                  alignment: Alignment.centerRight,
                                  child: _ConnectButton(
                                    label: w.connectLabel!,
                                    name: w.name,
                                    onPressed: w.onConnect!,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (w.topDivider && bg == null && !w.highlighted)
                Positioned(
                  left: LgSpace.s2,
                  right: LgSpace.s2,
                  top: -1,
                  height: 1,
                  child: ColoredBox(color: c.border),
                ),
            ],
          ),
        );
      },
    );
    return Listener(
      onPointerDown: _onPointerDown,
      child: w.onConnect == null
          ? row
          : Semantics(
              customSemanticsActions: {
                CustomSemanticsAction(label: w.connectLabel!): w.onConnect!,
              },
              child: row,
            ),
    );
  }
}

/// The "connect" button at the end of a hovered row (`.tr .ra .btn`): out of
/// the Tab order, the row itself takes the keyboard.
class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.label,
    required this.name,
    required this.onPressed,
  });

  final String label;
  final String name;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    return LgPressable(
      onPressed: onPressed,
      focusable: false,
      semanticLabel: '$label $name',
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        return Container(
          height: t.sizes.tableRow - 4,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: overlay == null
                ? c.accent
                : Color.alphaBlend(overlay, c.accent),
            borderRadius: radius,
          ),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: t.text.copyWith(
              color: c.onAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}

/// The first row of the search results, "连接到 ‹输入›" (`.rrow`): connects
/// to what was typed. [text] is the whole line; [emphasis] is the part of it
/// shown bold (the typed input).
class LgConnectToRow extends StatelessWidget {
  const LgConnectToRow({
    super.key,
    required this.text,
    required this.onTap,
    this.emphasis,
    this.highlighted = false,
    this.focusNode,
  });

  final String text;
  final String? emphasis;
  final bool highlighted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r12);
    final style = t.text.copyWith(color: c.text);
    final at = emphasis == null || emphasis!.isEmpty
        ? -1
        : text.lastIndexOf(emphasis!);
    return LgPressable(
      onPressed: onTap,
      focusNode: focusNode,
      selected: highlighted,
      semanticLabel: text,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        final base = highlighted
            ? Color.alphaBlend(c.active, c.surface)
            : c.surface;
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            height: t.sizes.row,
            padding: const EdgeInsets.only(left: LgSpace.s4, right: LgSpace.s2),
            decoration: BoxDecoration(
              color: overlay == null ? base : Color.alphaBlend(overlay, base),
              borderRadius: radius,
            ),
            foregroundDecoration: highlighted
                ? BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: c.accent, width: 2),
                  )
                : null,
            child: ExcludeSemantics(
              child: Row(
                children: [
                  LgIcon(LgIcons.login, size: 20, color: c.accent),
                  const SizedBox(width: LgSpace.s3),
                  Expanded(
                    child: Text.rich(
                      at < 0
                          ? TextSpan(text: text)
                          : TextSpan(
                              children: [
                                TextSpan(text: text.substring(0, at)),
                                TextSpan(
                                  text: emphasis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: text.substring(at + emphasis!.length),
                                ),
                              ],
                            ),
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Title above a list ("搜索结果", `.rtit`).
class LgSectionTitle extends StatelessWidget {
  const LgSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return SizedBox(
      height: t.sizes.nav,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          header: true,
          child: Text(
            text,
            style: t.text.copyWith(
              color: t.colors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// "未找到匹配的设备" under the "connect to" row (`.nores`).
class LgNoResultsNote extends StatelessWidget {
  const LgNoResultsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
      child: Text(text, style: t.text.copyWith(color: t.colors.text2)),
    );
  }
}

/// A list with nothing in it (`.box`): an icon tile and one sentence.
class LgEmptyState extends StatelessWidget {
  const LgEmptyState(this.text, {super.key, this.icon = LgIcons.monitor});

  final String text;
  final LgIcons icon;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Semantics(
      container: true,
      label: text,
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: LgSpace.s8,
            horizontal: LgSpace.s6,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(LgRadius.r16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(LgRadius.r12),
                ),
                child: LgIcon(icon, size: 24, color: c.text2),
              ),
              const SizedBox(height: LgSpace.s3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: t.text.copyWith(color: c.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder rows while the first answer is on its way (`.sk`). Still, so
/// that it does not ask for attention; [semanticLabel] tells a screen reader
/// that the list is loading.
class LgDeviceSkeleton extends StatelessWidget {
  const LgDeviceSkeleton({
    super.key,
    required this.semanticLabel,
    this.rows = 5,
  });

  final String semanticLabel;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    Widget bar(double? width, {double height = 12}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(LgRadius.r6),
      ),
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: LgListSurface(
          child: Column(
            children: [
              for (var i = 0; i < rows; i++)
                Container(
                  height: t.sizes.tableRow,
                  padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: _statusWidth,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: bar(56),
                        ),
                      ),
                      const SizedBox(width: _columnGap),
                      Expanded(
                        flex: _nameFlex,
                        child: Row(
                          children: [
                            bar(t.sizes.icon, height: t.sizes.icon),
                            const SizedBox(width: LgSpace.s2),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: bar(96),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: _columnGap),
                      SizedBox(
                        width: _idWidth,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: bar(84),
                        ),
                      ),
                      const SizedBox(width: _columnGap),
                      Expanded(
                        flex: _hostFlex,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: bar(120),
                        ),
                      ),
                      const SizedBox(width: _columnGap),
                      const SizedBox(width: _actionWidth),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
