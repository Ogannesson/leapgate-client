// The list of trusted devices in the 2FA section (02 §1.3.3, A-P6-设置.html
// ".td-*"): the title with "全部删除", and one row per device that need not type
// a code any more: a pick box, the platform on the device's identity colour, the
// name, the ID, the days left. Rows are picked for deleting; picked rows show
// "已选择 N 台" and a "删除" button in the header. It lives in the section, not
// in a dialog, and shows a line instead of rows when there are none.
//
// It only draws. The page keeps which are picked, asks before it deletes, and
// writes every text.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_button.dart';
import 'lg_device.dart';
import 'lg_pressable.dart';
import 'lg_settings_rows.dart';

/// One trusted device.
class LgTrustedDevice {
  const LgTrustedDevice({
    required this.id,
    required this.name,
    required this.formattedId,
    required this.platform,
    required this.remaining,
  });

  /// The ID as stored; the identity colour comes from it.
  final String id;
  final String name;

  /// "912 345 678".
  final String formattedId;
  final LgPlatform platform;

  /// "剩余 23 天", "今天到期".
  final String remaining;
}

class LgTrustedDevices extends StatelessWidget {
  const LgTrustedDevices({
    super.key,
    required this.title,
    required this.devices,
    required this.picked,
    required this.onToggle,
    required this.deleteAllLabel,
    required this.onDeleteAll,
    required this.emptyText,
    this.pickedCountLabel,
    this.deleteLabel,
    this.onDeleteSelected,
  }) : assert(picked.length == 0 || deleteLabel != null);

  /// "受信设备".
  final String title;
  final List<LgTrustedDevice> devices;

  /// The IDs of the picked rows.
  final Set<String> picked;

  /// A row was clicked or Space/Enter was pressed on it.
  final ValueChanged<String> onToggle;

  /// "全部删除"; not shown when there is no device.
  final String deleteAllLabel;
  final VoidCallback? onDeleteAll;

  /// "暂无受信设备".
  final String emptyText;

  /// "已选择 2 台"; shown while something is picked.
  final String? pickedCountLabel;

  /// "删除" (the picked ones).
  final String? deleteLabel;
  final VoidCallback? onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LgSettingsListHeader(
          title: title,
          trailing: [
            if (picked.isNotEmpty && pickedCountLabel != null)
              Text(pickedCountLabel!, style: t.textM.copyWith(color: c.text2)),
            if (picked.isNotEmpty && deleteLabel != null)
              LgButton(
                label: deleteLabel!,
                kind: LgButtonKind.danger,
                horizontalPadding: LgSpace.s3,
                onPressed: onDeleteSelected,
              ),
            if (devices.isNotEmpty)
              LgButton(
                label: deleteAllLabel,
                kind: LgButtonKind.text,
                onPressed: onDeleteAll,
              ),
          ],
        ),
        if (devices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: LgSpace.s3),
            child: Text(emptyText, style: t.textM.copyWith(color: c.text2)),
          )
        else
          for (final (i, d) in devices.indexed)
            _TrustedRow(
              device: d,
              picked: picked.contains(d.id),
              ruleAbove:
                  i > 0 &&
                  !picked.contains(d.id) &&
                  !picked.contains(devices[i - 1].id),
              onPressed: () => onToggle(d.id),
            ),
      ],
    );
  }
}

class _TrustedRow extends StatelessWidget {
  const _TrustedRow({
    required this.device,
    required this.picked,
    required this.ruleAbove,
    required this.onPressed,
  });

  final LgTrustedDevice device;
  final bool picked;
  final bool ruleAbove;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    return LgPressable(
      onPressed: onPressed,
      selected: picked,
      semanticLabel:
          '${device.name}, ${device.formattedId}, ${device.remaining}',
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        return LgFocusRing(
          show: states.contains(WidgetState.focused),
          radius: radius,
          child: CustomPaint(
            foregroundPainter: _RulePainter(color: c.border, show: ruleAbove),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The picked row is tinted 8 beyond the column on both sides.
                Positioned(
                  left: -LgSpace.s2,
                  right: -LgSpace.s2,
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: picked
                          ? Color.alphaBlend(
                              overlay ?? Colors.transparent,
                              c.active,
                            )
                          : overlay,
                      borderRadius: radius,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: t.sizes.row),
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        _PickBox(picked: picked),
                        const SizedBox(width: LgSpace.s3),
                        LgDeviceAvatar(
                          id: device.id,
                          platform: device.platform,
                          size: 32,
                        ),
                        const SizedBox(width: LgSpace.s3),
                        Expanded(
                          child: Text(
                            device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textM.copyWith(
                              color: c.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: LgSpace.s3),
                        SizedBox(
                          width: 112,
                          child: Text(
                            device.formattedId,
                            maxLines: 1,
                            style: t.textM.copyWith(color: c.text2),
                          ),
                        ),
                        const SizedBox(width: LgSpace.s3),
                        SizedBox(
                          // "Expires today" and "23 days left" are about 80 wide.
                          width: 96,
                          child: Text(
                            device.remaining,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: t.textM.copyWith(color: c.text2),
                          ),
                        ),
                      ],
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

/// The 20 px box in front of a row (`.s-ck`).
class _PickBox extends StatelessWidget {
  const _PickBox({required this.picked});

  final bool picked;

  @override
  Widget build(BuildContext context) {
    final c = LgTokens.of(context).colors;
    const radius = BorderRadius.all(Radius.circular(LgRadius.r6));
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: picked ? c.accent : null,
        borderRadius: radius,
      ),
      foregroundDecoration: picked
          ? null
          : BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: c.borderStrong, width: 1.5),
            ),
      child: picked ? LgIcon(LgIcons.check, size: 16, color: c.onAccent) : null,
    );
  }
}

class _RulePainter extends CustomPainter {
  _RulePainter({required this.color, required this.show});

  final Color color;
  final bool show;

  @override
  void paint(Canvas canvas, Size size) {
    if (!show) return;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 1), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RulePainter old) =>
      old.color != color || old.show != show;
}
