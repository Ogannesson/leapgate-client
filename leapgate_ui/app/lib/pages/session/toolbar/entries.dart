// The rows of the toolbar menus as data, like upstream's `TTextMenu`, `TToggleMenu` and
// `TRadioMenu` (`flutter/lib/common/widgets/toolbar.dart:155-255`): the menus draw them, and the
// session's shortcuts run the same rows, so a shortcut does what the enabled row does and
// nothing while the row is greyed out or missing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/keyboard_shortcuts/display.dart';
import 'package:flutter_hbb/models/shortcut_model.dart';

import '../../../widgets/lg_menu.dart';
import '../../../widgets/lg_menu_items.dart';
import '../../../widgets/lg_tooltip.dart';

sealed class TbEntry {
  const TbEntry();
}

/// A group title. [note] is a short remark at its end.
class TbGroup extends TbEntry {
  const TbGroup(this.title, {this.note});

  final String title;
  final String? note;
}

class TbDivider extends TbEntry {
  const TbDivider();
}

/// A row. [onPressed] null greys it out; [disabledReason] is then said on hover (01 P2 block B).
/// [checked] marks the current choice of a group, or with [switchRow] is the state of the switch
/// at the row's end (A-P2 draws on/off settings as switches, choices with a check mark).
/// [actionId] binds it to a session shortcut, whose keys show at the right.
class TbItem extends TbEntry {
  const TbItem({
    required this.label,
    required this.onPressed,
    this.checked,
    this.actionId,
    this.disabledReason,
    this.indent = false,
    this.hint,
    this.trailing,
    this.switchRow = false,
    this.keepOpen = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool? checked;
  final String? actionId;
  final String? disabledReason;

  /// Drawn as a switch; the menu stays open after it is turned.
  final bool switchRow;

  /// The menu stays open after the row is used (a choice that shows more rows under it).
  final bool keepOpen;

  /// Drawn one level in, as an option of the row above ("显示本机光标" under "仅查看模式").
  final bool indent;

  /// Text at the right end when there is no shortcut (a range, the current value).
  final String? hint;

  /// A second control on the row ("输入系统登录密码" and its edit button).
  final Widget? trailing;
}

/// A slider inside the menu. [onChanged] gets the value once the drag pauses or ends.
class TbSlider extends TbEntry {
  const TbSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.toPosition,
    this.fromPosition,
    this.disabledReason,
    this.startLabel,
  });

  /// The slider's name for a screen reader ("自定义缩放").
  final String label;
  final int value;
  final int min;
  final int max;
  final String Function(int value) format;
  final ValueChanged<int>? onChanged;

  /// A track that is not linear (custom scale: 100% at a third of the track).
  final double Function(int value)? toPosition;
  final int Function(double position)? fromPosition;
  final String? disabledReason;

  /// A short word before the track ("画质", "帧率").
  final String? startLabel;
}

/// "− count +" (the Amyuni virtual display driver): [onChanged] gets the count asked for.
class TbStepper extends TbEntry {
  const TbStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.decreaseLabel,
    required this.increaseLabel,
  });

  /// The count's name for a screen reader.
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;
  final String decreaseLabel;
  final String increaseLabel;
}

/// A second-level menu. [value] is what is chosen inside, shown before the arrow.
class TbSubmenu extends TbEntry {
  const TbSubmenu({
    required this.label,
    required this.items,
    this.disabledReason,
    this.value,
  });

  final String label;
  final List<TbEntry> items;
  final String? disabledReason;
  final String? value;
}

/// The bound keys of [actionId] ("Ctrl+Alt+Shift+P"), null when unbound or shortcuts are off.
String? shortcutHint(String? actionId) =>
    actionId == null ? null : ShortcutDisplay.formatFor(actionId);

/// Every row with an action ID in [entries], submenus included.
Iterable<TbItem> _actionItems(List<TbEntry> entries) sync* {
  for (final e in entries) {
    if (e is TbItem && e.actionId != null) yield e;
    if (e is TbSubmenu) yield* _actionItems(e.items);
  }
}

/// Upstream `_registerToggleMenuShortcuts` (`toolbar.dart:212-232`): the IDs of [owned] that the
/// rows do not enable run nothing.
void registerEntryShortcuts(
  ShortcutModel model,
  List<String> owned,
  List<TbEntry> entries,
) {
  for (final id in owned) {
    model.unregister(id);
  }
  for (final item in _actionItems(entries)) {
    final onPressed = item.onPressed;
    if (onPressed == null) {
      model.unregister(item.actionId!);
    } else {
      model.register(item.actionId!, onPressed);
    }
  }
}

/// Upstream `registerToolbarShortcuts` (`toolbar.dart:1426-1459`): a shortcut of [owned] builds
/// its menu again before it runs, so it sees the permissions and state of that moment. The
/// first press builds it too, so nothing is built up front (upstream also ran each menu once
/// at the start, from before it had the refreshers).
void registerMenuShortcuts(
  ShortcutModel model,
  List<String> owned,
  Future<List<TbEntry>> Function() build,
) {
  model.registerRefresher(
    owned,
    () async => registerEntryShortcuts(model, owned, await build()),
  );
}

/// The menu widgets of [entries].
List<Widget> buildEntries(List<TbEntry> entries) => [
  for (final e in entries) _buildEntry(e),
];

Widget _buildEntry(TbEntry e) => switch (e) {
  TbGroup() => LgMenuGroup(e.title, note: e.note),
  TbDivider() => const LgMenuDivider(),
  TbItem() => _buildItem(e),
  // Keyed by its label, so a slider's state never passes to another when rows come and go.
  TbSlider() => _SliderRow(e, key: ValueKey('slider:${e.label}')),
  TbStepper() => LgMenuStepperItem(
    value: e.value,
    min: e.min,
    max: e.max,
    onChanged: e.onChanged,
    decreaseLabel: e.decreaseLabel,
    increaseLabel: e.increaseLabel,
    valueLabel: e.label,
  ),
  TbSubmenu() => LgSubmenu(
    label: e.label,
    value: e.value,
    disabledNote: e.disabledReason,
    items: e.disabledReason == null ? buildEntries(e.items) : const [],
  ),
};

Widget _buildItem(TbItem e) {
  final onPressed = e.onPressed;
  final note = onPressed == null ? e.disabledReason : null;
  if (e.switchRow) {
    return LgMenuSwitchItem(
      label: e.label,
      value: e.checked ?? false,
      onChanged: onPressed == null ? null : (_) => onPressed(),
      shortcut: shortcutHint(e.actionId),
      indent: e.indent,
      disabledNote: note,
    );
  }
  return LgMenuItem(
    label: e.label,
    onPressed: onPressed,
    checked: e.checked,
    hint: e.hint,
    shortcut: shortcutHint(e.actionId),
    trailing: e.trailing,
    indent: e.indent,
    keepOpen: e.keepOpen,
    disabledNote: note,
  );
}

/// [LgMenuSliderItem] with upstream's 300 ms wait before a value is applied; the slider has
/// no note of its own, so a greyed one says why with a tooltip.
class _SliderRow extends StatefulWidget {
  const _SliderRow(this.entry, {super.key});

  final TbSlider entry;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  late int _value = widget.entry.value;
  Timer? _apply;

  TbSlider get _e => widget.entry;

  @override
  void didUpdateWidget(_SliderRow old) {
    super.didUpdateWidget(old);
    if (_apply == null) _value = _e.value;
  }

  /// The menu closing within the 300 ms still sends the last value.
  @override
  void dispose() {
    if (_apply != null) {
      _apply!.cancel();
      _e.onChanged?.call(_value);
    }
    super.dispose();
  }

  double get _position =>
      _e.toPosition?.call(_value) ?? (_value - _e.min) / (_e.max - _e.min);

  int _valueAt(double p) =>
      _e.fromPosition?.call(p) ?? (_e.min + p * (_e.max - _e.min)).round();

  // Upstream applies a custom scale 300 ms after the slider stops (`kDebounceCustomScaleDuration`).
  void _changed(double p) {
    setState(() => _value = _valueAt(p));
    _apply?.cancel();
    _apply = Timer(const Duration(milliseconds: 300), () {
      _apply = null;
      _e.onChanged?.call(_value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final slider = LgMenuSliderItem(
      value: _position.clamp(0.0, 1.0),
      format: (p) => _e.format(_valueAt(p)),
      semanticLabel: _e.label,
      startLabel: _e.startLabel,
      onChanged: _e.onChanged == null ? null : _changed,
    );
    final reason = _e.disabledReason;
    if (_e.onChanged != null || reason == null) return slider;
    return LgTooltip(
      message: reason,
      child: Semantics(hint: reason, child: slider),
    );
  }
}

/// A menu's rows, built when it opens and again after a change ([refresh]), since several of
/// them come from Rust asynchronously.
class TbMenuContent extends StatefulWidget {
  const TbMenuContent({super.key, required this.build, required this.refresh});

  final Future<List<TbEntry>> Function() build;

  /// Fires when the rows should be built again (after an action, or a model change).
  final Listenable refresh;

  @override
  State<TbMenuContent> createState() => _TbMenuContentState();
}

class _TbMenuContentState extends State<TbMenuContent> {
  List<TbEntry> _entries = const [];
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final serial = ++_serial;
    final entries = await widget.build();
    if (mounted && serial == _serial) setState(() => _entries = entries);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: buildEntries(_entries),
  );
}
