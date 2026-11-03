// The people of the team devices (01 §3.1 block H; `.ppl`, `.pp` in
// A-P1.html, `p1-group`): a search field and one row per person, yourself
// first and marked. A click shows only that person's devices; a click on the
// chosen person, or on the "×" at the end of the row, shows everybody's again.
//
// Only drawing: who the people are, the filtering by what was typed, and what
// a click does belong to the caller.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_account.dart';
import 'lg_pressable.dart';
import 'lg_text_field.dart';
import 'lg_tooltip.dart';

/// One person of [LgPeopleList].
@immutable
class LgPerson {
  const LgPerson({
    required this.id,
    required this.initial,
    required this.name,
    this.isMe = false,
  });

  /// What the callbacks get back (the user name).
  final String id;

  /// The letter in the avatar.
  final String initial;
  final String name;

  /// Yourself: the row gets the [LgPeopleList.meLabel] after the name.
  final bool isMe;
}

/// The search field and the rows. Give it the width of the column
/// ([width], 208 in the mockup); it is as high as its rows.
class LgPeopleList extends StatelessWidget {
  const LgPeopleList({
    super.key,
    required this.people,
    required this.selectedId,
    required this.onSelect,
    required this.onClear,
    required this.searchController,
    required this.searchPlaceholder,
    required this.meLabel,
    required this.clearLabel,
    this.onSearchChanged,
    this.semanticLabel,
    this.width = 208,
  });

  /// The people to show, already filtered by what was typed in the field.
  final List<LgPerson> people;

  /// The chosen person, or null for everybody.
  final String? selectedId;

  /// A person that is not chosen was clicked.
  final ValueChanged<String> onSelect;

  /// The chosen person was clicked, or its "×".
  final VoidCallback onClear;
  final TextEditingController searchController;
  final ValueChanged<String>? onSearchChanged;
  final String searchPlaceholder;

  /// "我", after the name of the row that is you.
  final String meLabel;

  /// Name of the "×" ("取消筛选").
  final String clearLabel;

  /// Name of the list for a screen reader ("人员").
  final String? semanticLabel;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LgTextField(
            controller: searchController,
            placeholder: searchPlaceholder,
            semanticLabel: searchPlaceholder,
            dense: true,
            leading: LgIcon(LgIcons.search, size: 20, color: c.text2),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: LgSpace.s2),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: semanticLabel,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, person) in people.indexed) ...[
                  if (i > 0) const SizedBox(height: LgSpace.s1),
                  _PersonRow(
                    person: person,
                    meLabel: meLabel,
                    clearLabel: clearLabel,
                    selected: person.id == selectedId,
                    onTap: person.id == selectedId
                        ? onClear
                        : () => onSelect(person.id),
                    onClear: onClear,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.meLabel,
    required this.clearLabel,
    required this.selected,
    required this.onTap,
    required this.onClear,
  });

  final LgPerson person;
  final String meLabel;
  final String clearLabel;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r12);
    final label = person.isMe ? '${person.name} $meLabel' : person.name;
    return LgPressable(
      onPressed: onTap,
      semanticLabel: label,
      selected: selected,
      builder: (context, states) {
        final overlay = selected ? null : lgStateOverlay(c, states);
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: Container(
            height: t.sizes.row,
            padding: const EdgeInsets.symmetric(horizontal: LgSpace.s3),
            decoration: BoxDecoration(
              color: selected ? c.active : overlay,
              borderRadius: radius,
            ),
            foregroundDecoration: selected
                ? BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: c.accent, width: 2),
                  )
                : null,
            child: Row(
              children: [
                LgPersonAvatar(
                  initial: person.initial,
                  size: 28,
                  onTint: selected,
                ),
                const SizedBox(width: LgSpace.s3),
                Expanded(
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        Flexible(
                          child: LgEllipsisText(
                            person.name,
                            style: t.text.copyWith(
                              color: c.text,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (person.isMe) ...[
                          const SizedBox(width: LgSpace.s3),
                          Text(
                            meLabel,
                            maxLines: 1,
                            softWrap: false,
                            style: t.textS.copyWith(color: c.text2),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (selected)
                  // Its own node: the row's click also clears, the button is
                  // for whoever looks for it by name.
                  Semantics(
                    container: true,
                    child: LgPressable(
                      onPressed: onClear,
                      focusable: false,
                      semanticLabel: clearLabel,
                      builder: (context, states) => Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: lgStateOverlay(c, states),
                          borderRadius: BorderRadius.circular(LgRadius.r6),
                        ),
                        child: LgIcon(LgIcons.x, size: 20, color: c.text2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
