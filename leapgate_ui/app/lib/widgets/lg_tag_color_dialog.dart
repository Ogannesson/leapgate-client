// The dialog that changes the colour of a tag (02 §3.6; `p1-tagcolor-*` in
// A-P1.html): a preview of the tag as it is drawn on a device, a row of ready
// colours, and under "自定义" a wheel, a lightness bar and a field for `#RRGGBB`.
// The tag keeps its colour as a number (ARGB), as upstream stores it.
//
// What the dialog keeps to itself is the colour being tried. It tells the
// caller only when "保存" is pressed ([onSave], the number), and "保存" is
// grey while the colour is the old one or the text of the field is not a
// colour. A request in flight ([busy]) and a refusal ([error]) are the
// caller's.

import 'package:flutter/material.dart';

import '../icons/lg_icon.dart';
import '../theme/lg_tokens.dart';
import 'lg_banner.dart';
import 'lg_button.dart';
import 'lg_color_wheel.dart';
import 'lg_device_parts.dart';
import 'lg_feedback.dart';
import 'lg_form_dialog.dart';
import 'lg_pressable.dart';
import 'lg_text_field.dart';

/// The ready colours, in the order of the row: the seven identity colours of the
/// light theme and a slate grey. They are fixed numbers, not the theme's: a tag
/// is saved with its colour, and the same tag must be the same colour whichever
/// theme the next person looks at it in.
final List<Color> lgTagPresetColors = [
  for (final k in LgColors.light.identity) k.solid,
  LgColors.light.text2,
];

/// The words of the dialog, localised by the caller.
class LgTagColorDialogLabels {
  const LgTagColorDialogLabels({
    required this.title,
    required this.colorLabel,
    required this.customLabel,
    required this.valueLabel,
    required this.hexPlaceholder,
    required this.hexError,
    required this.brightnessLabel,
    required this.wheelLabel,
    required this.cancel,
    required this.save,
    required this.busySave,
  });

  /// "修改标签颜色".
  final String title;

  /// "颜色", over the ready colours.
  final String colorLabel;

  /// "自定义", the button that opens the wheel.
  final String customLabel;

  /// "颜色值", over the field.
  final String valueLabel;

  /// What the empty field shows ("#RRGGBB").
  final String hexPlaceholder;

  /// "颜色值格式不正确", under the field when its text is not a colour.
  final String hexError;

  /// "明度", over the lightness bar.
  final String brightnessLabel;

  /// Name of the wheel for a screen reader ("色轮").
  final String wheelLabel;
  final String cancel;

  /// "保存"; while [LgTagColorDialog.busy] the button says [busySave]
  /// ("正在保存…").
  final String save;
  final String busySave;
}

class LgTagColorDialog extends StatefulWidget {
  const LgTagColorDialog({
    super.key,
    required this.labels,
    required this.tagName,
    required this.initialColor,
    required this.onSave,
    required this.onCancel,
    this.previewName,
    this.busy = false,
    this.error,
    this.startCustom = false,
    this.width = 440,
  });

  final LgTagColorDialogLabels labels;

  /// The tag in the preview.
  final String tagName;

  /// What the preview shows to the left of the tag: a device name, as it would
  /// stand on a card. Null leaves it out.
  final String? previewName;

  /// The colour the tag has now; "保存" stays grey until another one is picked.
  final Color initialColor;

  /// "保存" was pressed: the colour as a number, `0xFFRRGGBB`.
  final ValueChanged<int> onSave;
  final VoidCallback onCancel;

  /// The request is on its way: the colour cannot be changed, "保存" turns.
  final bool busy;

  /// Why saving failed ("无法修改标签颜色。\n服务器返回：…。"), in a banner under the
  /// title.
  final String? error;

  /// Opens with the wheel out.
  final bool startCustom;
  final double width;

  @override
  State<LgTagColorDialog> createState() => _LgTagColorDialogState();
}

class _LgTagColorDialogState extends State<LgTagColorDialog> {
  late HSVColor _hsv;
  late final TextEditingController _hex;
  late bool _custom;
  bool _hexBad = false;

  static final _hexPattern = RegExp(r'^#?([0-9a-fA-F]{6})$');

  static String _hexOf(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Color get _color => _hsv.toColor();

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hex = TextEditingController(text: _hexOf(widget.initialColor));
    _custom = widget.startCustom;
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setHsv(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _hexBad = false;
      _hex.text = _hexOf(hsv.toColor());
    });
  }

  void _setColor(Color color) => _setHsv(HSVColor.fromColor(color));

  void _hexChanged(String text) {
    final m = _hexPattern.firstMatch(text.trim());
    setState(() {
      if (m == null) {
        _hexBad = true;
        return;
      }
      _hexBad = false;
      final parsed = Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
      // Typing the hex of the colour already on the wheel leaves the wheel
      // where it is (the hue of a grey is not in its hex).
      if (parsed.toARGB32() != _color.toARGB32()) {
        _hsv = HSVColor.fromColor(parsed);
      }
    });
  }

  bool get _changed => _color.toARGB32() != widget.initialColor.toARGB32();

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final l = widget.labels;
    final on = !widget.busy;
    final color = _color;
    final canSave = on && !_hexBad && _changed;
    return LgFormDialog(
      title: l.title,
      icon: LgIcons.tag,
      width: widget.width,
      banner: widget.error == null
          ? null
          : LgBanner(tone: LgTone.error, slim: true, text: widget.error),
      actions: [
        LgDialogAction(label: l.cancel, onPressed: widget.onCancel),
        LgDialogAction(
          label: widget.busy ? l.busySave : l.save,
          kind: LgButtonKind.primary,
          isDefault: true,
          busy: widget.busy,
          onPressed: canSave ? () => widget.onSave(color.toARGB32()) : null,
        ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.only(top: LgSpace.s5),
          child: _Preview(
            previewName: widget.previewName,
            tag: LgDeviceTag(widget.tagName, color),
          ),
        ),
        LgFormField(
          label: l.colorLabel,
          child: Padding(
            padding: const EdgeInsets.only(top: LgSpace.s1, bottom: LgSpace.s1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final preset in lgTagPresetColors)
                  _Swatch(
                    color: preset,
                    on: preset.toARGB32() == color.toARGB32(),
                    onPressed: on ? () => _setColor(preset) : null,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: LgSpace.s2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _CustomToggle(
              label: l.customLabel,
              open: _custom,
              onPressed: () => setState(() => _custom = !_custom),
            ),
          ),
        ),
        if (_custom)
          Padding(
            padding: const EdgeInsets.only(top: LgSpace.s2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LgColorWheel(
                  hue: _hsv.hue,
                  saturation: _hsv.saturation,
                  value: _hsv.value,
                  enabled: on,
                  semanticLabel: l.wheelLabel,
                  semanticValue: _hexOf(color),
                  onChanged: (h, s) =>
                      _setHsv(HSVColor.fromAHSV(1, h, s, _hsv.value)),
                ),
                const SizedBox(width: LgSpace.s5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          l.valueLabel,
                          style: t.textS.copyWith(
                            color: c.text2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: LgSpace.s1),
                      LgTextField(
                        controller: _hex,
                        placeholder: l.hexPlaceholder,
                        semanticLabel: l.valueLabel,
                        errorText: _hexBad ? l.hexError : null,
                        enabled: on,
                        maxLength: 7,
                        onChanged: _hexChanged,
                      ),
                      const SizedBox(height: LgSpace.s4),
                      ExcludeSemantics(
                        child: Text(
                          l.brightnessLabel,
                          style: t.textS.copyWith(
                            color: c.text2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: LgSpace.s2),
                      LgValueBar(
                        hue: _hsv.hue,
                        saturation: _hsv.saturation,
                        value: _hsv.value,
                        enabled: on,
                        semanticLabel: l.brightnessLabel,
                        onChanged: (v) => _setHsv(
                          HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, v),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The tag as a card would show it (`.tcprev`): on the ground of the page, a
/// row of the surface with the device's name and, at its end, the tag.
class _Preview extends StatelessWidget {
  const _Preview({required this.previewName, required this.tag});

  final String? previewName;
  final LgDeviceTag tag;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(LgSpace.s3),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(LgRadius.r12),
        ),
        child: Container(
          height: t.sizes.row,
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s4),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(LgRadius.r10),
          ),
          child: Row(
            children: [
              if (previewName != null)
                Expanded(
                  child: Text(
                    previewName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.copyWith(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: LgSpace.s3),
              LgTagChip(tag),
            ],
          ),
        ),
      ),
    );
  }
}

/// One ready colour (`.tcs`): a 36 px square of it; the one in use has a check
/// mark and a ring in the accent colour 2 px off it.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.on,
    required this.onPressed,
  });

  final Color color;
  final bool on;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    final hex = _LgTagColorDialogState._hexOf(color);
    return LgPressable(
      onPressed: onPressed,
      semanticLabel: hex,
      selected: on,
      builder: (context, states) {
        final overlay = lgStateOverlay(c, states);
        return Opacity(
          opacity: states.contains(WidgetState.disabled) ? .6 : 1,
          child: LgFocusRing(
            show: states.contains(WidgetState.focused),
            radius: radius,
            child: SizedBox(
              width: t.sizes.button,
              height: t.sizes.button,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (on)
                    Positioned(
                      left: -4,
                      top: -4,
                      right: -4,
                      bottom: -4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(LgRadius.r10 + 4),
                          border: Border.all(color: c.accent, width: 2),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: overlay == null
                            ? color
                            : Color.alphaBlend(overlay, color),
                        borderRadius: radius,
                      ),
                      // The ready colours are fixed, so is the check on them.
                      child: on
                          ? const LgIcon(
                              LgIcons.check,
                              size: 20,
                              color: Color(0xFFFFFFFF),
                            )
                          : null,
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

/// "自定义" with a chevron (`.tccu`): a text button in the accent colour that
/// opens and closes the wheel.
class _CustomToggle extends StatelessWidget {
  const _CustomToggle({
    required this.label,
    required this.open,
    required this.onPressed,
  });

  final String label;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    final c = t.colors;
    final radius = BorderRadius.circular(LgRadius.r10);
    return LgPressable(
      onPressed: onPressed,
      semanticLabel: label,
      toggled: open,
      builder: (context, states) => LgFocusRing(
        show: states.contains(WidgetState.focused),
        radius: radius,
        child: Container(
          height: t.sizes.button,
          padding: const EdgeInsets.symmetric(horizontal: LgSpace.s2),
          decoration: BoxDecoration(
            color: lgStateOverlay(c, states),
            borderRadius: radius,
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: t.text.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: LgSpace.s2),
                LgIcon(
                  open ? LgIcons.chevU : LgIcons.chevD,
                  size: 20,
                  color: c.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
