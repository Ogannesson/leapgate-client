import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/account_api.dart';
import 'package:flutter_hbb/leapgate/address_book.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_banner.dart';
import '../../../widgets/lg_button.dart';
import '../../../widgets/lg_device.dart';
import '../../../widgets/lg_device_parts.dart';
import '../../../widgets/lg_menu.dart';
import '../../../widgets/lg_menu_items.dart';
import '../../../widgets/lg_pressable.dart';

// The address book's own controls (01 P1 block G), drawn with the M0~M3 components until the
// designer's (`ui/m4-ds`: the book switcher, the tag filter bar, the list states) replace them;
// what they show and do stays here.

/// [book]'s name: the personal one in the UI's language.
String abBookName(AppLocalizations l10n, AbProfile book) =>
    appCore.addressBook.isPersonal(book) ? l10n.abPersonal : book.name;

/// "只读 / 可编辑 / 完全控制", and "所有者：‹名字›" for a shared book (01 P1 block G).
String abBookRights(AppLocalizations l10n, AbProfile book) {
  final ab = appCore.addressBook;
  if (ab.isPersonal(book)) return l10n.abRuleFullControl;
  final rule = switch (ShareRule.fromValue(book.rule)) {
    ShareRule.fullControl => l10n.abRuleFullControl,
    ShareRule.readWrite => l10n.abRuleReadWrite,
    _ => l10n.abRuleRead,
  };
  return book.owner.isEmpty ? rule : '$rule · ${l10n.abOwner(book.owner)}';
}

/// The second sentence of an error: what the server said, or that it could not be reached.
String abReason(AppLocalizations l10n, ApiError error) =>
    error.kind == ApiErrorKind.network
    ? l10n.abNetworkReason
    : l10n.abServerSaid(error.text.isEmpty ? error.kind.name : error.text);

/// A tag's colour in the current book; upstream's default when it has none.
Color abTagColor(String tag) =>
    Color(appCore.addressBook.tagColor(tag) ?? abDefaultTagColor(tag));

/// The book switcher and the "More" menu (`p1-ab-switch`, `p1-ab-more`, `p1-ab-readonly`).
class AbBookBar extends StatelessWidget {
  const AbBookBar({super.key, required this.more});

  /// The "More" menu's items.
  final List<Widget> more;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final t = LgTokens.of(context);
    final ab = appCore.addressBook;
    final current = ab.current!;
    return Padding(
      padding: const EdgeInsets.only(bottom: LgSpace.s2),
      child: Row(
        children: [
          LgMenuAnchor(
            items: [
              for (final b in ab.books)
                LgMenuItem(
                  label: abBookName(l10n, b),
                  description: abBookRights(l10n, b),
                  checked: b.guid == current.guid,
                  onPressed: () => ab.select(b),
                ),
              const LgMenuDivider(),
              LgMenuItem(label: l10n.abSharedNote, onPressed: null),
            ],
            builder: (context, controller) => LgButton(
              label: abBookName(l10n, current),
              icon: LgIcons.book,
              semanticLabel: l10n.abSwitchBook,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
          const SizedBox(width: LgSpace.s3),
          Flexible(
            child: Text(
              abBookRights(l10n, current),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textS.copyWith(color: t.colors.text2),
            ),
          ),
          const Spacer(),
          LgMenuAnchor(
            items: more,
            builder: (context, controller) => LgIconButton(
              icon: LgIcons.more,
              label: l10n.abMore,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry of the tag filter bar or of a dialog's tag choice: the tag chip, outlined with a
/// check while [selected] (not filled with the tag colour, 01 P1 block G).
class AbTagToggle extends StatelessWidget {
  const AbTagToggle({
    super.key,
    required this.label,
    required this.color,
    required this.selected,
    required this.onPressed,
    this.onContextMenu,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onPressed;
  final void Function(Offset globalPosition)? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    return LgPressable(
      onPressed: onPressed,
      semanticLabel: label,
      toggled: selected,
      onSecondaryTapUp: onContextMenu == null
          ? null
          : (d) => onContextMenu!(d.globalPosition),
      builder: (context, states) => Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? c.accent : Colors.transparent,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(LgRadius.r6 + 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LgTagChip(LgDeviceTag(label, color)),
            if (selected) LgIcon(LgIcons.check, size: 14, color: c.accent),
          ],
        ),
      ),
    );
  }
}

/// The tag filter bar (`p1-ab-tags`): "未标记" first, then the current book's tags; a right click
/// on a tag opens [tagMenu] when the book can be written.
class AbTagBar extends StatelessWidget {
  const AbTagBar({super.key, required this.tagMenu});

  final List<Widget> Function(String tag) tagMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = LgTokens.of(context).colors;
    final ab = appCore.addressBook;
    final selected = ab.selectedTags;
    return Padding(
      padding: const EdgeInsets.only(bottom: LgSpace.s2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            AbTagToggle(
              label: l10n.abUntagged,
              color: c.accent,
              selected: selected.contains(kAbUntagged),
              onPressed: () => ab.toggleTag(kAbUntagged),
            ),
            for (final tag in ab.tags) ...[
              const SizedBox(width: LgSpace.s2),
              AbTagToggle(
                label: tag.name,
                color: Color(tag.color),
                selected: selected.contains(tag.name),
                onPressed: () => ab.toggleTag(tag.name),
                onContextMenu: ab.canWrite
                    ? (at) => showLgMenuAt(
                        context,
                        globalPosition: at,
                        items: tagMenu(tag.name),
                      )
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The closable error banner above the list with "重试" (`p1-st-banner`).
class AbBanner extends StatelessWidget {
  const AbBanner({
    super.key,
    required this.text,
    required this.onRetry,
    required this.onClose,
  });

  final String text;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: LgSpace.s2),
      child: Row(
        children: [
          Expanded(
            child: LgBanner(tone: LgTone.error, text: text),
          ),
          const SizedBox(width: LgSpace.s2),
          LgButton(label: l10n.abRetry, onPressed: onRetry),
          LgIconButton(
            icon: LgIcons.x,
            label: l10n.abDismiss,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// A list state with one sentence and a button ("登录", "重试"; `p1-st-nologin-ab`,
/// `p1-st-neterr`).
class AbStateWithAction extends StatelessWidget {
  const AbStateWithAction({
    super.key,
    required this.text,
    required this.icon,
    required this.action,
    required this.onPressed,
  });

  final String text;
  final LgIcons icon;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          LgEmptyState(text, icon: icon),
          const SizedBox(height: LgSpace.s3),
          LgButton(
            label: action,
            kind: LgButtonKind.primary,
            onPressed: onPressed,
          ),
        ],
      ),
    );
  }
}
