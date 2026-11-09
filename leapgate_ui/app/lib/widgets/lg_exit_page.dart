// The exit page around the cards (01 §3.1 block I; `p1-exit-*`, `p1-ex-*`
// frames of A-P1.html): the page with its three sections, the directory of
// exits you may use in its five states, the row of the directory, the thin
// bar of a list that loads, and the row that names an exit by its ID.
//
// The components only draw: all text comes from the caller (localised) and
// nothing here knows the directory model or the exit cards (docs LEAPGATE.md
// §10.8, §10.12). The title "出口" above the page is the home page's own.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_device.dart';
import 'lg_page_section.dart';
import 'lg_pressable.dart';
import 'lg_text_field.dart';
import 'lg_tooltip.dart';

/// The width an ID field and the field of the by-ID row stop growing at
/// (`.xidrow .field`).
const double kLgExitIdFieldMaxWidth = 520;

/// The page body: a sentence, then "正在使用", "可用的出口" and "按 ID 指定出口",
/// each under a section title, in one scroll view. [inUse] is the card grid
/// ([LgExitCardGrid]) or the note of none ([LgExitEmptyNote]); [directory] is
/// one of the states of [LgExitDirectory]; [byId] is [LgExitByIdRow].
///
/// Put it right under the page title with 4 px between, and give it the room
/// that is left. Scroll to a card with `Scrollable.ensureVisible` on the key
/// of the card, and flash it ([LgFlash]).
class LgExitPage extends StatelessWidget {
  const LgExitPage({
    super.key,
    required this.lede,
    required this.inUseTitle,
    required this.inUse,
    required this.directoryTitle,
    required this.refreshLabel,
    required this.onRefresh,
    required this.directory,
    required this.byIdTitle,
    required this.byId,
    this.controller,
    this.sectionTitle,
    this.sectionIcon,
    this.tunnels,
  });

  /// "通过其他设备的网络访问互联网。仅对已配置代理的应用生效，且只支持 TCP 连接。"
  final String lede;
  final String inUseTitle;
  final Widget inUse;
  final String directoryTitle;

  /// "刷新", at the end of the directory's title; null disables it (the
  /// directory is loading).
  final String refreshLabel;
  final VoidCallback? onRefresh;
  final Widget directory;
  final String byIdTitle;
  final Widget byId;
  final ScrollController? controller;

  /// "出口". With it the page has three levels of heading (`A-P8-隧道.html`): the page title the
  /// home page draws, then this section with [sectionIcon] and [lede] under it (an
  /// [LgPageSection]), and the three parts ("正在使用", "可用的出口", "按 ID 指定出口") as
  /// small titles inside it. Without it the page is as the M5 mockups show: [lede] right under
  /// the page title and the three parts as section titles.
  final String? sectionTitle;
  final LgIcons? sectionIcon;

  /// The second section, "隧道": an [LgPageSection] that is not `first`, with the tunnel cards
  /// ([LgTunnelStack]) in it. Only drawn with [sectionTitle].
  final Widget? tunnels;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    if (sectionTitle != null) return _threeLevels();
    return SingleChildScrollView(
      controller: controller,
      child: Padding(
        padding: const EdgeInsets.only(bottom: LgSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(lede, style: t.textM.copyWith(color: t.colors.text2)),
            LgExitSection(title: inUseTitle),
            const SizedBox(height: LgSpace.s2),
            inUse,
            LgExitSection(
              title: directoryTitle,
              action: LgButton(
                label: refreshLabel,
                icon: LgIcons.refresh,
                kind: LgButtonKind.text,
                onPressed: onRefresh,
              ),
            ),
            directory,
            LgExitSection(title: byIdTitle),
            const SizedBox(height: LgSpace.s2),
            byId,
          ],
        ),
      ),
    );
  }

  Widget _threeLevels() {
    const sub = LgExitSectionLevel.sub;
    return SingleChildScrollView(
      controller: controller,
      child: Padding(
        padding: const EdgeInsets.only(bottom: LgSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LgPageSection(
              first: true,
              icon: sectionIcon,
              title: sectionTitle!,
              lede: lede,
              children: [
                LgExitSection(title: inUseTitle, level: sub),
                const SizedBox(height: LgSpace.s2),
                inUse,
                LgExitSection(
                  title: directoryTitle,
                  level: sub,
                  action: LgButton(
                    label: refreshLabel,
                    icon: LgIcons.refresh,
                    kind: LgButtonKind.text,
                    onPressed: onRefresh,
                  ),
                ),
                directory,
                LgExitSection(title: byIdTitle, level: sub),
                const SizedBox(height: LgSpace.s2),
                byId,
              ],
            ),
            if (tunnels != null) tunnels!,
          ],
        ),
      ),
    );
  }
}

/// How high in the page a title [LgExitSection] is.
enum LgExitSectionLevel {
  /// `.xsec`: bold at the number size, in the text colour.
  section,

  /// `.xsub`, a part of an [LgPageSection] (level three): bold at the body size, in the second
  /// colour.
  sub,
}

/// A section title (`.xsec`; with [level] `sub` `.xsub`): bold, 24 px above, at
/// least as high as a button, with an optional button at its end. The button
/// stands 8 px out of the content column, so that its words line up with the
/// right edge.
class LgExitSection extends StatelessWidget {
  const LgExitSection({
    super.key,
    required this.title,
    this.action,
    this.level = LgExitSectionLevel.section,
  });

  final String title;
  final Widget? action;
  final LgExitSectionLevel level;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final sub = level == LgExitSectionLevel.sub;
    return Padding(
      padding: const EdgeInsets.only(top: LgSpace.s6),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: t.sizes.button),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                headingLevel: sub ? 3 : null,
                child: Text(
                  title,
                  style: (sub ? t.text : t.textN).copyWith(
                    color: sub ? t.colors.text2 : t.colors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (action != null)
              Transform.translate(
                offset: const Offset(LgSpace.s2, 0),
                child: action,
              ),
          ],
        ),
      ),
    );
  }
}

/// "暂无正在使用的出口" (`p1-ex-inuse-empty`): one sentence on a card.
class LgExitEmptyNote extends StatelessWidget {
  const LgExitEmptyNote(this.text, {super.key});

  final String text;

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
            vertical: LgSpace.s5,
            horizontal: LgSpace.s6,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(LgRadius.r16),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: t.text.copyWith(color: c.text),
          ),
        ),
      ),
    );
  }
}

/// A 4 px bar with a segment running along it, for a list that loads (`.sl` in
/// `p1-ex-dir-loading`). Without motion (the system asks for none) the segment
/// stands still in the first half. [semanticLabel] tells a screen reader what
/// is loading.
class LgIndeterminateBar extends StatefulWidget {
  const LgIndeterminateBar({super.key, required this.semanticLabel});

  final String semanticLabel;

  @override
  State<LgIndeterminateBar> createState() => _LgIndeterminateBarState();
}

class _LgIndeterminateBarState extends State<LgIndeterminateBar>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 4,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _BarPainter(
                track: c.track,
                fill: c.accent,
                // The segment is 36 % long; it enters at the left and leaves
                // at the right. Still: the mockup's place, from 18 %.
                start: still
                    ? .18
                    : -.36 + 1.36 * Curves.easeInOut.transform(_controller.value),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.track,
    required this.fill,
    required this.start,
  });

  final Color track;
  final Color fill;
  final double start;

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(2),
    );
    canvas.drawRRect(bar, Paint()..color = track);
    canvas.save();
    canvas.clipRRect(bar);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * start, 0, size.width * .36, size.height),
        const Radius.circular(2),
      ),
      Paint()..color = fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.track != track || old.fill != fill || old.start != start;
}

/// One exit of the directory, as [LgExitDirectory.rows] takes it.
class LgExitEntry {
  const LgExitEntry({
    required this.name,
    required this.id,
    required this.platform,
    required this.owner,
    required this.actionLabel,
    required this.onPressed,
    this.inUse = false,
  });

  /// The host name, or the ID when the device has none.
  final String name;

  /// Formatted ("912 345 678").
  final String id;
  final LgPlatform platform;

  /// "我的" or "所有者：李四".
  final String owner;

  /// "使用", or "使用中" when [inUse]: the exit already has a card, and the
  /// button takes you to it.
  final String actionLabel;
  final VoidCallback onPressed;
  final bool inUse;
}

// Columns of the directory table (`p1-exit-light`): name and owner share the
// room 1.4 : 1, the ID and the button have a width.
const double _idWidth = 124;
const double _buttonColumn = 128;
const int _nameFlex = 14;
const int _ownerFlex = 10;

/// A row of the directory (`.tr` of `p1-exit-light`): the platform icon and the
/// host name, the ID, the owner and the button that uses the exit. No online
/// dot: the directory lists only exits that are online (01 block I).
class LgExitDirectoryRow extends StatelessWidget {
  const LgExitDirectoryRow({
    super.key,
    required this.entry,
    this.topDivider = true,
  });

  final LgExitEntry entry;

  /// The 1 px line between rows; the first row of a list leaves it out.
  final bool topDivider;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final cell = t.text.copyWith(color: c.text);
    final e = entry;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${e.name} ${e.id} ${e.owner}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: t.sizes.tableRow,
            padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
            child: DefaultTextStyle(
              style: cell,
              maxLines: 1,
              child: Row(
                children: [
                  // The cells are for the eyes: the row's name says them once.
                  Expanded(
                    flex: _nameFlex,
                    child: ExcludeSemantics(
                      child: Row(
                        children: [
                          LgDeviceAvatar(
                            id: e.id,
                            platform: e.platform,
                            size: t.sizes.icon,
                            tile: false,
                          ),
                          const SizedBox(width: LgSpace.s2),
                          Flexible(
                            child: LgEllipsisText(
                              e.name,
                              style: cell.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: LgSpace.s3),
                  SizedBox(
                    width: _idWidth,
                    child: ExcludeSemantics(
                      child: Text(
                        e.id,
                        overflow: TextOverflow.ellipsis,
                        style: t.textS.copyWith(
                          color: c.text2,
                          fontWeight: FontWeight.w600,
                          // The groups of the mockup stand 6 px apart (`.id3.sm`).
                          wordSpacing: 2.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: LgSpace.s3),
                  Expanded(
                    flex: _ownerFlex,
                    child: ExcludeSemantics(
                      child: LgEllipsisText(
                        e.owner,
                        style: cell.copyWith(color: c.text2),
                      ),
                    ),
                  ),
                  const SizedBox(width: LgSpace.s3),
                  SizedBox(
                    width: _buttonColumn,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _UseButton(entry: e),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (topDivider)
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
  }
}

/// "使用" (`.btn.pri`) or "使用中" (`.btn.soft` with a check), as high as the
/// row less 4 px. The accessible name carries the device: a list of identical
/// buttons is no list for a screen reader.
class _UseButton extends StatelessWidget {
  const _UseButton({required this.entry});

  final LgExitEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    final inUse = entry.inUse;
    return LgPressable(
      onPressed: entry.onPressed,
      semanticLabel: '${entry.actionLabel} ${entry.name}',
      builder: (context, states) {
        final base = inUse ? c.surface2 : c.accent;
        final overlay = lgStateOverlay(c, states);
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            height: t.sizes.tableRow - 4,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: overlay == null ? base : Color.alphaBlend(overlay, base),
              borderRadius: radius,
            ),
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (inUse) ...[
                    LgIcon(LgIcons.check, size: 20, color: c.text),
                    const SizedBox(width: LgSpace.s2),
                  ],
                  Flexible(
                    child: Text(
                      entry.actionLabel,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: t.text.copyWith(
                        color: inUse ? c.text : c.onAccent,
                        fontWeight: FontWeight.w700,
                      ),
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

enum _DirectoryState { loading, unsupported, notLoggedIn, empty, error, rows }

/// What stands under the title "可用的出口", in its six states. The states
/// leave 8 px above themselves (12 for the bar), the rows none, as the mockup
/// does.
class LgExitDirectory extends StatelessWidget {
  /// Loading: the bar; [semanticLabel] says "正在加载出口目录".
  const LgExitDirectory.loading({super.key, required String this.semanticLabel})
    : _state = _DirectoryState.loading,
      text = null,
      actionLabel = null,
      onAction = null,
      entries = const [];

  /// "当前服务器不提供出口目录。仍可按 ID 指定出口。" in a banner.
  const LgExitDirectory.unsupported({super.key, required String this.text})
    : _state = _DirectoryState.unsupported,
      semanticLabel = null,
      actionLabel = null,
      onAction = null,
      entries = const [];

  /// "登录后可查看出口目录" and the button "登录".
  const LgExitDirectory.notLoggedIn({
    super.key,
    required String this.text,
    required String this.actionLabel,
    required VoidCallback this.onAction,
  }) : _state = _DirectoryState.notLoggedIn,
       semanticLabel = null,
       entries = const [];

  /// "暂无可用的出口。此处仅列出……的设备。"
  const LgExitDirectory.empty({super.key, required String this.text})
    : _state = _DirectoryState.empty,
      semanticLabel = null,
      actionLabel = null,
      onAction = null,
      entries = const [];

  /// "无法加载出口目录" and the button "重试".
  const LgExitDirectory.error({
    super.key,
    required String this.text,
    required String this.actionLabel,
    required VoidCallback this.onAction,
  }) : _state = _DirectoryState.error,
       semanticLabel = null,
       entries = const [];

  /// The exits, one row each.
  const LgExitDirectory.rows({super.key, required this.entries})
    : _state = _DirectoryState.rows,
      semanticLabel = null,
      text = null,
      actionLabel = null,
      onAction = null;

  final _DirectoryState _state;
  final String? semanticLabel;
  final String? text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<LgExitEntry> entries;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    final Widget body;
    switch (_state) {
      case _DirectoryState.loading:
        return Padding(
          padding: const EdgeInsets.only(top: LgSpace.s3),
          child: LgIndeterminateBar(semanticLabel: semanticLabel!),
        );
      case _DirectoryState.unsupported:
        body = LgBanner(tone: LgTone.info, slim: true, text: text);
      case _DirectoryState.notLoggedIn:
        body = LgEmptyState(
          text!,
          icon: LgIcons.exit,
          actionLabel: actionLabel,
          actionIcon: LgIcons.login,
          onAction: onAction,
        );
      case _DirectoryState.empty:
        body = LgEmptyState(text!, icon: LgIcons.exit);
      case _DirectoryState.error:
        body = LgEmptyState(
          text!,
          icon: LgIcons.wifiOff,
          iconColor: c.error,
          actionLabel: actionLabel,
          actionIcon: LgIcons.refresh,
          onAction: onAction,
        );
      case _DirectoryState.rows:
        body = LgListSurface(
          child: Column(
            children: [
              for (final (i, e) in entries.indexed)
                LgExitDirectoryRow(entry: e, topDivider: i > 0),
            ],
          ),
        );
    }
    // The rows follow the title with no gap; the other states stand 8 px off it.
    return _state == _DirectoryState.rows
        ? body
        : Padding(
            padding: const EdgeInsets.only(top: LgSpace.s2),
            child: body,
          );
  }
}

/// "按 ID 指定出口": the ID field and "使用" (`.xidrow`). The field grows to
/// 520 px; the button follows it, as high as the field. [onUse] null disables
/// the button (nothing typed); Enter in the field does what the button does.
/// [errorText] ("ID 格式不正确") turns the frame red and shows the text under
/// it.
class LgExitByIdRow extends StatelessWidget {
  const LgExitByIdRow({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.semanticLabel,
    required this.useLabel,
    required this.onUse,
    this.focusNode,
    this.errorText,
    this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String placeholder;
  final String semanticLabel;
  final String useLabel;
  final VoidCallback? onUse;
  final FocusNode? focusNode;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: kLgExitIdFieldMaxWidth,
            ),
            // The line under a wrong field is in regular weight (`p1-ex-id-err`).
            child: LgDialogFields(
              child: LgTextField(
                controller: controller,
                focusNode: focusNode,
                placeholder: placeholder,
                semanticLabel: semanticLabel,
                errorText: errorText,
                enabled: enabled,
                onChanged: onChanged,
                onSubmitted: (_) => onUse?.call(),
              ),
            ),
          ),
        ),
        const SizedBox(width: LgSpace.s2),
        LgButton(
          label: useLabel,
          kind: LgButtonKind.primary,
          large: true,
          onPressed: enabled ? onUse : null,
        ),
      ],
    );
  }
}
