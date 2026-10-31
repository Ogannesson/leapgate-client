// The rows of the toolbar menus as data, like upstream's `TTextMenu`, `TToggleMenu` and
// `TRadioMenu` (`flutter/lib/common/widgets/toolbar.dart:155-255`): the menus draw them, and the
// session's shortcuts run the same rows, so a shortcut does what the enabled row does and
// nothing while the row is greyed out or missing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/keyboard_shortcuts/display.dart';
import 'package:flutter_hbb/models/shortcut_model.dart';

import '../../../widgets/lg_menu.dart';
import '../../../widgets/lg_tooltip.dart';

sealed class TbEntry {
  const TbEntry();
}

/// A group title.
class TbGroup extends TbEntry {
  const TbGroup(this.title);

  final String title;
}

class TbDivider extends TbEntry {
  const TbDivider();
}

/// A row. [onPressed] null greys it out; [disabledReason] is then said on hover (01 P2 block B).
/// [checked] marks the current choice of a group or the state of a switch. [actionId] binds it
/// to a session shortcut, whose keys show at the right.
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
  });

  final String label;
  final VoidCallback? onPressed;
  final bool? checked;
  final String? actionId;
  final String? disabledReason;

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
  });

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
}

/// "− count +" (the Amyuni virtual display driver).
class TbStepper extends TbEntry {
  const TbStepper({
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    required this.decreaseLabel,
    required this.increaseLabel,
  });

  final String label;
  final int value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final String decreaseLabel;
  final String increaseLabel;
}

class TbSubmenu extends TbEntry {
  const TbSubmenu({
    required this.label,
    required this.items,
    this.disabledReason,
  });

  final String label;
  final List<TbEntry> items;
  final String? disabledReason;
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

Widget _withReason(String? reason, Widget child) =>
    reason == null ? child : LgTooltip(message: reason, child: child);

Widget _buildEntry(TbEntry e) => switch (e) {
  TbGroup() => LgMenuGroup(e.title),
  TbDivider() => const Divider(height: 9, indent: 16, endIndent: 16),
  TbItem() => _buildItem(e),
  TbSlider() => _withReason(e.disabledReason, _SliderRow(e)),
  TbStepper() => _StepperRow(e),
  TbSubmenu() => _withReason(
    e.disabledReason,
    LgSubmenu(
      label: e.label,
      items: e.disabledReason == null ? buildEntries(e.items) : const [],
    ),
  ),
};

Widget _buildItem(TbItem e) {
  Widget row = LgMenuItem(
    label: e.label,
    onPressed: e.onPressed,
    checked: e.checked,
    hint: shortcutHint(e.actionId) ?? e.hint,
  );
  if (e.trailing != null) {
    row = Row(
      children: [
        Expanded(child: row),
        e.trailing!,
      ],
    );
  }
  if (e.indent) {
    row = Padding(padding: const EdgeInsets.only(left: 24), child: row);
  }
  return _withReason(e.onPressed == null ? e.disabledReason : null, row);
}

// Placeholders for the designer's slider and stepper rows (`LEAPGATE.md` §10.9): plain
// Material controls, labelled for the tests and screen readers.

class _SliderRow extends StatefulWidget {
  const _SliderRow(this.entry);

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

  @override
  void dispose() {
    _apply?.cancel();
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
  Widget build(BuildContext context) => Semantics(
    label: _e.label,
    value: _e.format(_value),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(_e.label),
          Expanded(
            child: ExcludeSemantics(
              child: Slider(
                value: _position.clamp(0.0, 1.0),
                onChanged: _e.onChanged == null ? null : _changed,
              ),
            ),
          ),
          Text(_e.format(_value)),
        ],
      ),
    ),
  );
}

class _StepperRow extends StatelessWidget {
  const _StepperRow(this.entry);

  final TbStepper entry;

  @override
  Widget build(BuildContext context) => Semantics(
    label: entry.label,
    value: '${entry.value}',
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Text(entry.label)),
          IconButton(
            tooltip: entry.decreaseLabel,
            onPressed: entry.onDecrease,
            icon: const Icon(Icons.remove),
          ),
          Text('${entry.value}'),
          IconButton(
            tooltip: entry.increaseLabel,
            onPressed: entry.onIncrease,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    ),
  );
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
