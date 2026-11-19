// The monitors of the remote device on the toolbar (01 P2 block B "显示器"): a menu, or with
// "在工具栏上平铺显示器按钮" one button per monitor; "下一个显示器（n/总数）" next to it, and on
// the folded bar too when "工具栏收起时也显示" is on (02 §1.4.4). Upstream:
// `flutter/lib/desktop/widgets/remote_toolbar.dart` (`_MonitorCycle` :978-1005,
// `_MainMonitorSwitchButton` :1007-1058, `_MonitorMenu` :1060-1300,
// `_MinimizedMonitorSwitchButton` :3753-3821) and the display shortcuts of
// `flutter/lib/models/shortcut_model.dart:338-403`. "全部显示器" shows them merged in this tab
// (`kAllDisplayValue`); upstream's "open each in its own window" is gone (01 §8 Q11). In a camera
// view the monitors are the cameras (13 §3.2 block B): the button names the one shown and opens a
// list with their names instead of the arrangement.

import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/camera_names.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../../icons/lg_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/lg_menu.dart';
import '../../../widgets/lg_menu_items.dart';
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
    appCore.options.userDefault.get(kKeyShowMonitorsToolbar) == 'Y';

bool get _nextButton =>
    appCore.options.local.getBool(kOptionAllowMonitorSwitchMainToolbar);

/// "全部显示器" needs a peer that sends several displays in one stream.
bool _allShown(FFI ffi) =>
    ffi.ffiModel.pi.isSupportMultiDisplay &&
    ffi.ffiModel.pi.displays.length > 1;

bool _camera(FFI ffi) => ffi.connType == ConnType.viewCamera;

String _nextLabel(FFI ffi, AppLocalizations l10n) {
  final pi = ffi.ffiModel.pi;
  final current = pi.currentDisplay;
  final inRange = current >= 0 && current < pi.displays.length;
  // "*" for the merged view, as upstream.
  final n = inRange ? '${current + 1}' : '*';
  return _camera(ffi)
      ? l10n.camNext(n, pi.displays.length)
      : l10n.toolbarNextMonitor(n, pi.displays.length);
}

/// "摄像头 ‹n›", with its name when the remote device gave one ("摄像头 1，Integrated Camera").
String _cameraLabel(AppLocalizations l10n, List<String> names, int i) =>
    names[i].isEmpty ? l10n.camN(i + 1) : l10n.camNamed(i + 1, names[i]);

/// The camera switch (13 §3.2 block B): the button says the camera shown, the list has a row
/// per camera with its name at the end of the row (`.mr .cn`), the one shown checked, then
/// "全部摄像头".
Widget _cameraMenu(FFI ffi, AppLocalizations l10n, {required bool all}) {
  final pi = ffi.ffiModel.pi;
  final current = pi.currentDisplay;
  final names = cameraNames(ffi);
  final merged = current == kAllDisplayValue;
  return LgToolbarMenuButton(
    label: merged ? l10n.camAll : l10n.camN(current + 1),
    icon: LgIcons.camera,
    semanticLabel:
        merged ? l10n.camSwitchAllLabel : l10n.camSwitchLabel(current + 1),
    items: [
      for (var i = 0; i < names.length; i++)
        LgMenuItem(
          label: l10n.camN(i + 1),
          trailing: names[i].isEmpty ? null : LgMenuRowNote(names[i]),
          semanticLabel: _cameraLabel(l10n, names, i),
          checked: current == i,
          onPressed: () => openMonitor(ffi, i),
        ),
      if (all) ...[
        const LgMenuDivider(),
        LgMenuSwitchItem(
          label: l10n.camAll,
          value: merged,
          onChanged: (on) => openMonitor(ffi, on ? kAllDisplayValue : 0),
        ),
      ],
    ],
  );
}

/// "2/3", named in full for a screen reader ("下一个显示器（2/3）").
Widget _nextMonitorButton(FFI ffi, AppLocalizations l10n) {
  final pi = ffi.ffiModel.pi;
  final current = pi.currentDisplay;
  final inRange = current >= 0 && current < pi.displays.length;
  return LgToolbarButton(
    icon: _camera(ffi) ? LgIcons.camera : LgIcons.displays,
    label: '${inRange ? current + 1 : '*'}/${pi.displays.length}',
    semanticLabel: _nextLabel(ffi, l10n),
    showText: true,
    onPressed: () => switchMonitorBy(ffi, 1, updateCursorPos: false),
  );
}

/// The monitor buttons of the open toolbar, left to right.
List<Widget> monitorToolbarItems(ToolbarEnv env) {
  final ffi = env.ffi;
  final l10n = env.l10n;
  if (!monitorsShown(ffi)) return const [];
  final pi = ffi.ffiModel.pi;
  final current = pi.currentDisplay;
  final all = _allShown(ffi);
  final camera = _camera(ffi);
  final names = camera ? cameraNames(ffi) : const <String>[];
  return [
    if (_nextButton) _nextMonitorButton(ffi, l10n),
    if (_flat) ...[
      for (var i = 0; i < pi.displays.length; i++)
        LgToolbarTextButton(
          label: '${i + 1}',
          semanticLabel: camera
              ? _cameraLabel(l10n, names, i)
              : l10n.toolbarMonitorN(i + 1),
          // A camera's hover is its number over its name (`p10-cam-tiles`).
          tooltip: camera ? l10n.camN(i + 1) : null,
          tooltipNote: camera && names[i].isNotEmpty ? names[i] : null,
          selected: current == i,
          onPressed: () => openMonitor(ffi, i, updateCursorPos: false),
        ),
      if (all)
        LgToolbarButton(
          icon: camera ? LgIcons.cameras : LgIcons.displays,
          label: camera ? l10n.camAll : l10n.toolbarAllMonitors,
          toggled: current == kAllDisplayValue,
          onPressed: () =>
              openMonitor(ffi, kAllDisplayValue, updateCursorPos: false),
        ),
    ] else if (camera)
      _cameraMenu(ffi, l10n, all: all)
    else
      LgToolbarMenuButton(
        label: l10n.toolbarMonitor,
        icon: LgIcons.displays,
        items: [
          // The remote arrangement, the one shown tinted (A-P2 `m-display`).
          LgDisplayMap(
            tiles: [
              for (final (i, d) in pi.displays.indexed)
                LgDisplayTile(
                  rect: Rect.fromLTWH(
                    d.x,
                    d.y,
                    d.width.toDouble(),
                    d.height.toDouble(),
                  ),
                  label: '${i + 1}',
                  semanticLabel: l10n.toolbarMonitorN(i + 1),
                ),
            ],
            current: current == kAllDisplayValue ? null : current,
            onSelect: (i) => openMonitor(ffi, i),
          ),
          if (all) ...[
            const LgMenuDivider(),
            LgMenuSwitchItem(
              label: l10n.toolbarAllMonitors,
              value: current == kAllDisplayValue,
              // Off shows the first display; the map above picks any other.
              onChanged: (on) => openMonitor(ffi, on ? kAllDisplayValue : 0),
            ),
          ],
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
