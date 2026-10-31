// The monitors of the remote device on the toolbar (01 P2 block B "显示器"): a menu, or with
// "在工具栏上平铺显示器按钮" one button per monitor; "下一个显示器（n/总数）" next to it, and on
// the folded bar too when "工具栏收起时也显示" is on (02 §1.4.4). Upstream:
// `flutter/lib/desktop/widgets/remote_toolbar.dart` (`_MonitorCycle` :978-1005,
// `_MainMonitorSwitchButton` :1007-1058, `_MonitorMenu` :1060-1300,
// `_MinimizedMonitorSwitchButton` :3753-3821) and the display shortcuts of
// `flutter/lib/models/shortcut_model.dart:338-403`. "全部显示器" shows them merged in this tab
// (`kAllDisplayValue`); upstream's "open each in its own window" is gone (01 §8 Q11).

import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_menu.dart';
import '../../../widgets/lg_session_toolbar.dart';
import 'toolbar_env.dart';

void openMonitor(FFI ffi, int i, {bool updateCursorPos = true}) {
  if (ffi.ffiModel.pi.currentDisplay == i) return;
  openMonitorInTheSameTab(
    i,
    ffi,
    ffi.ffiModel.pi,
    updateCursorPos: updateCursorPos,
  );
}

/// The next or previous monitor; from the merged view, the first or the last
/// (`shortcut_model.dart:354-371`).
void switchMonitorBy(FFI ffi, int delta, {required bool updateCursorPos}) {
  final pi = ffi.ffiModel.pi;
  if (!displaySwitchAllowed(ffi)) return;
  final count = pi.displays.length;
  if (count <= 1) return;
  final current = pi.currentDisplay;
  final next = current == kAllDisplayValue
      ? (delta > 0 ? 0 : count - 1)
      : ((current + delta) % count + count) % count;
  openMonitor(ffi, next, updateCursorPos: updateCursorPos);
}

/// Whether the monitor buttons show at all (`remote_toolbar.dart:822-835`).
bool monitorsShown(FFI ffi) =>
    displaySwitchAllowed(ffi) && ffi.ffiModel.pi.displaysCount.value > 1;

bool get _flat =>
    bind.mainGetUserDefaultOption(key: kKeyShowMonitorsToolbar) == 'Y';

bool get _nextButton =>
    appCore.options.local.getBool(kOptionAllowMonitorSwitchMainToolbar);

/// "全部显示器" needs a peer that sends several displays in one stream.
bool _allShown(FFI ffi) =>
    ffi.ffiModel.pi.isSupportMultiDisplay &&
    ffi.ffiModel.pi.displays.length > 1;

String _nextLabel(FFI ffi, AppLocalizations l10n) {
  final pi = ffi.ffiModel.pi;
  final current = pi.currentDisplay;
  final inRange = current >= 0 && current < pi.displays.length;
  // "*" for the merged view, as upstream.
  return l10n.toolbarNextMonitor(
    inRange ? '${current + 1}' : '*',
    pi.displays.length,
  );
}

Widget _nextMonitorButton(FFI ffi, AppLocalizations l10n) => LgToolbarButton(
  icon: LgIcons.displays,
  label: _nextLabel(ffi, l10n),
  onPressed: () => switchMonitorBy(ffi, 1, updateCursorPos: false),
);

/// The monitor buttons of the open toolbar, left to right.
List<Widget> monitorToolbarItems(ToolbarEnv env) {
  final ffi = env.ffi;
  final l10n = env.l10n;
  if (!monitorsShown(ffi)) return const [];
  final pi = ffi.ffiModel.pi;
  final current = pi.currentDisplay;
  final monitors = [
    for (var i = 0; i < pi.displays.length; i++)
      (i, l10n.toolbarMonitorN(i + 1)),
    if (_allShown(ffi)) (kAllDisplayValue, l10n.toolbarAllMonitors),
  ];
  return [
    if (_nextButton) _nextMonitorButton(ffi, l10n),
    if (_flat)
      for (final (i, label) in monitors)
        _MonitorButton(
          label: label,
          short: i == kAllDisplayValue ? null : '${i + 1}',
          selected: current == i,
          onPressed: () => openMonitor(ffi, i, updateCursorPos: false),
        )
    else
      LgToolbarMenuButton(
        label: l10n.toolbarMonitor,
        icon: LgIcons.displays,
        items: [
          for (final (i, label) in monitors)
            LgMenuItem(
              label: label,
              checked: current == i,
              onPressed: () => openMonitor(ffi, i),
            ),
        ],
      ),
  ];
}

/// "下一个显示器" on the folded bar (`remote_toolbar.dart:3753-3821`).
Widget? collapsedMonitorSwitch(ToolbarEnv env) {
  final ffi = env.ffi;
  if (!_nextButton ||
      !appCore.options.local.getBool(kOptionAllowMonitorSwitchMinToolbar) ||
      ffi.ffiModel.pi.displays.length < 2 ||
      !displaySwitchAllowed(ffi)) {
    return null;
  }
  return _nextMonitorButton(ffi, env.l10n);
}

/// A monitor button on the toolbar: its number, the monitor's name for screen readers.
/// Placeholder for the designer's flat monitor button.
class _MonitorButton extends StatelessWidget {
  const _MonitorButton({
    required this.label,
    required this.short,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String? short;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    selected: selected,
    button: true,
    onTap: onPressed,
    child: ExcludeSemantics(
      child: LgToolbarButton(
        icon: short == null ? LgIcons.displays : LgIcons.monitor,
        label: short ?? label,
        showText: short != null,
        toggled: selected,
        onPressed: onPressed,
      ),
    ),
  );
}
