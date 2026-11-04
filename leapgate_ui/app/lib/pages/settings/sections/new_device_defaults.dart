import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/options.dart';
import 'package:flutter_hbb/leapgate/settings/outgoing.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/lg_tokens.dart';
import '../../../widgets/lg_panel_inputs.dart';
import '../../../widgets/lg_selection.dart';
import '../../../widgets/lg_settings_rows.dart';
import '../../../widgets/lg_slider.dart';
import '../settings_flow.dart';
import '../settings_registry.dart';

/// Item ids of this section: the UserDefaultConfig keys, and the custom quality's row.
const kDefaultsItemCustomQuality = kOptionCustomImageQuality;

/// The codecs by their names, as the toolbar's codec menu writes them.
const _codecNames = {
  'vp8': 'VP8',
  'vp9': 'VP9',
  'av1': 'AV1',
  'h264': 'H264',
  'h265': 'H265',
};

/// The on / off options of the section in display order, by their subtitle.
List<(String, String)> _screenToggles(AppLocalizations l10n) => [
      (kOptionI444, l10n.menuTrueColor),
      (kOptionShowRemoteCursor, l10n.menuShowRemoteCursor),
      (kOptionFollowRemoteCursor, l10n.menuFollowRemoteCursor),
      (kOptionFollowRemoteWindow, l10n.menuFollowRemoteWindow),
      (kOptionZoomCursor, l10n.menuZoomCursor),
      (kOptionCollapseToolbar, l10n.settingsDefaultsCollapseToolbar),
    ];

List<(String, String)> _inputToggles(AppLocalizations l10n) => [
      (kOptionViewOnly, l10n.menuViewOnly),
      (kKeyReverseMouseWheel, l10n.menuReverseWheel),
      (kOptionSwapLeftRightMouse, l10n.menuSwapMouseButtons),
    ];

/// "同步剪贴板" is upstream's "禁用剪贴板" the other way round; the key stays
/// `disable_clipboard` (02 §1.4.2).
List<(String, String)> _sessionToggles(AppLocalizations l10n) => [
      (kOptionDisableAudio, l10n.menuMute),
      (kOptionDisableClipboard, l10n.menuSyncClipboard),
      (kOptionEnableFileCopyPaste, l10n.menuFileCopyPaste),
      (kOptionLockAfterSessionEnd, l10n.menuLockAfterEnd),
      (kOptionPrivacyMode, l10n.settingsDefaultsPrivacy),
    ];

bool _on(OptionScope defaults, String key) => key == kOptionDisableClipboard
    ? defaults.get(key) != 'Y'
    : defaultOn(defaults, key);

/// Rust keeps file copy and paste on unless it is 'N' (`config.rs` `UserDefaultConfig::get`).
Future<bool> _setOn(OptionScope defaults, String key, bool on) =>
    key == kOptionDisableClipboard
        ? setDefaultOn(defaults, key, !on)
        : setDefaultOn(defaults, key, on);

/// 传出连接 › 新设备的默认设置 (02 §1.4.2). Coder D. Every item is a UserDefaultConfig option:
/// a device's file copies them the first time it is connected to (02 §4.3 item 1).
SettingsSection newDeviceDefaultsSection(AppLocalizations l10n) =>
    SettingsSection(
      id: SettingsSectionId.newDeviceDefaults,
      title: l10n.settingsSectionNewDeviceDefaults,
      lede: l10n.settingsDefaultsLede,
      items: () {
        final defaults = appCore.options.userDefault;
        return [
          SettingsItem(kOptionViewStyle, l10n.settingsDefaultsViewStyle,
              options: [l10n.toolbarScaleOriginal, l10n.toolbarScaleAdaptive]),
          SettingsItem(kOptionScrollStyle, l10n.menuScrollStyle,
              description: l10n.settingsDefaultsScrollNote,
              options: [
                l10n.menuScrollAuto,
                l10n.menuScrollBar,
                l10n.menuScrollEdge,
              ]),
          if (defaults.get(kOptionScrollStyle) == kRemoteScrollStyleEdge)
            SettingsItem(
                kOptionEdgeScrollEdgeThickness, l10n.settingsDefaultsEdgeWidth),
          SettingsItem(kOptionImageQuality, l10n.toolbarQuality, options: [
            l10n.toolbarQualityBest,
            l10n.toolbarQualityBalanced,
            l10n.toolbarQualityLow,
            l10n.menuCustom,
          ]),
          if (defaults.get(kOptionImageQuality) == kRemoteImageQualityCustom)
            SettingsItem(
                kDefaultsItemCustomQuality, l10n.settingsDefaultsCustomQuality),
          SettingsItem(kOptionCodecPreference, l10n.menuCodec),
          for (final (key, name) in [
            ..._screenToggles(l10n),
            ..._inputToggles(l10n),
          ])
            SettingsItem(key, name),
          SettingsItem(kKeyTrackpadSpeed, l10n.menuTrackpadSpeed,
              description: l10n.settingsDefaultsTrackpadNote),
          for (final (key, name) in _sessionToggles(l10n))
            SettingsItem(key, name),
          SettingsItem(kOptionTerminalPersistent,
              l10n.settingsDefaultsTerminalPersistent),
        ];
      },
      build: (context, ctx) => _defaults(context, ctx),
    );

Widget _defaults(BuildContext context, SettingsSectionContext ctx) {
  final l10n = AppLocalizations.of(context)!;
  final defaults = appCore.options.userDefault;

  void save(String item, String value) =>
      ctx.save(item, () => defaults.set(item, value));

  LgSettingsRow segmented(String item, String name, List<LgSegment<String>> segments,
          {String? description}) =>
      LgSettingsRow(
        key: ctx.keyOf(item),
        name: name,
        description: description,
        wide: true,
        marked: ctx.isMarked(item),
        error: ctx.errorOf(item),
        control: LgSegmented<String>(
          segments: segments,
          selected: defaults.get(item),
          onChanged: (v) {
            if (v != defaults.get(item)) save(item, v);
          },
        ),
      );

  List<Widget> toggles(List<(String, String)> list) => [
        for (final (key, name) in list)
          LgSettingsRow.toggle(
            key: ctx.keyOf(key),
            name: name,
            value: _on(defaults, key),
            onChanged: (v) => ctx.save(key, () => _setOn(defaults, key, v)),
            marked: ctx.isMarked(key),
            error: ctx.errorOf(key),
          ),
      ];

  final scroll = defaults.get(kOptionScrollStyle);
  final quality = defaults.get(kOptionImageQuality);
  final codecs = defaultCodecChoices();
  final codec = defaults.get(kOptionCodecPreference);
  final trackpadError = ctx.errorOf(kKeyTrackpadSpeed);

  return SettingsFlow([
    LgSettingsSubtitle(l10n.toolbarDisplay),
    LgSettingsBlock(children: [
      segmented(kOptionViewStyle, l10n.settingsDefaultsViewStyle, [
        LgSegment(kRemoteViewStyleOriginal, l10n.toolbarScaleOriginal),
        LgSegment(kRemoteViewStyleAdaptive, l10n.toolbarScaleAdaptive),
      ]),
      segmented(kOptionScrollStyle, l10n.menuScrollStyle, [
        LgSegment(kRemoteScrollStyleAuto, l10n.menuScrollAuto),
        LgSegment(kRemoteScrollStyleBar, l10n.menuScrollBar),
        LgSegment(kRemoteScrollStyleEdge, l10n.menuScrollEdge),
      ], description: l10n.settingsDefaultsScrollNote),
      if (scroll == kRemoteScrollStyleEdge)
        LgSettingsRow(
          key: ctx.keyOf(kOptionEdgeScrollEdgeThickness),
          name: l10n.settingsDefaultsEdgeWidth,
          indented: true,
          wide: true,
          marked: ctx.isMarked(kOptionEdgeScrollEdgeThickness),
          error: ctx.errorOf(kOptionEdgeScrollEdgeThickness),
          control: _DebouncedSlider(
            value: _number(defaults, kOptionEdgeScrollEdgeThickness, 100),
            min: 20,
            max: 150,
            step: 1,
            semanticLabel: l10n.settingsDefaultsEdgeWidth,
            format: (v) => l10n.settingsDefaultsPixels(v.round()),
            onSave: (v) =>
                save(kOptionEdgeScrollEdgeThickness, '${v.round()}'),
          ),
        ),
      segmented(kOptionImageQuality, l10n.toolbarQuality, [
        LgSegment(kRemoteImageQualityBest, l10n.toolbarQualityBest),
        LgSegment(kRemoteImageQualityBalanced, l10n.toolbarQualityBalanced),
        LgSegment(kRemoteImageQualityLow, l10n.toolbarQualityLow),
        LgSegment(kRemoteImageQualityCustom, l10n.menuCustom),
      ]),
      if (quality == kRemoteImageQualityCustom)
        LgSettingsRow(
          key: ctx.keyOf(kDefaultsItemCustomQuality),
          name: l10n.settingsDefaultsCustomQuality,
          indented: true,
          marked: ctx.isMarked(kDefaultsItemCustomQuality),
          error: ctx.errorOf(kDefaultsItemCustomQuality),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _SliderLine(
                label: l10n.toolbarQuality,
                slider: _DebouncedSlider(
                  // The old "更多" (up to 2000 %) is gone (R2-Q12).
                  value: _number(defaults, kOptionCustomImageQuality,
                          kDefaultQuality)
                      .clamp(kMinQuality, kMaxQuality),
                  min: kMinQuality,
                  max: kMaxQuality,
                  step: 5,
                  semanticLabel: l10n.toolbarQuality,
                  format: (v) => '${v.round()}%',
                  onSave: (v) =>
                      save(kOptionCustomImageQuality, '${v.round()}'),
                ),
              ),
              _SliderLine(
                label: l10n.menuFps,
                slider: _DebouncedSlider(
                  value: _number(defaults, kOptionCustomFps, kDefaultFps)
                      .clamp(kMinFps, kMaxFps),
                  min: kMinFps,
                  max: kMaxFps,
                  step: 5,
                  semanticLabel: l10n.menuFps,
                  format: (v) => '${v.round()}',
                  onSave: (v) => save(kOptionCustomFps, '${v.round()}'),
                ),
              ),
            ],
          ),
        ),
      LgSettingsRow(
        key: ctx.keyOf(kOptionCodecPreference),
        name: l10n.menuCodec,
        wide: true,
        marked: ctx.isMarked(kOptionCodecPreference),
        error: ctx.errorOf(kOptionCodecPreference),
        control: SizedBox(
          width: 200,
          child: LgSelectField<String>(
            dense: true,
            semanticLabel: l10n.menuCodec,
            items: [
              for (final c in codecs)
                LgSelectItem(c, _codecNames[c] ?? l10n.menuCodecAuto),
            ],
            // A hardware codec this device no longer decodes shows as "自动".
            value: codecs.contains(codec) ? codec : 'auto',
            onChanged: (v) {
              if (v != codec) save(kOptionCodecPreference, v);
            },
          ),
        ),
      ),
      ...toggles(_screenToggles(l10n)),
    ]),
    LgSettingsSubtitle(l10n.toolbarInput),
    LgSettingsBlock(children: [
      ...toggles(_inputToggles(l10n)),
      LgSettingsRow(
        key: ctx.keyOf(kKeyTrackpadSpeed),
        name: l10n.menuTrackpadSpeed,
        description: l10n.settingsDefaultsTrackpadNote,
        wide: true,
        marked: ctx.isMarked(kKeyTrackpadSpeed),
        error: trackpadError,
        errorAtEnd: true,
        control: _TrackpadSpeed(
          value: _number(defaults, kKeyTrackpadSpeed,
                  kDefaultTrackpadSpeed.toDouble())
              .round(),
          label: l10n.menuTrackpadSpeed,
          errorText: trackpadError,
          onSave: (v) => save(kKeyTrackpadSpeed, '$v'),
          onInvalid: () =>
              ctx.setError(kKeyTrackpadSpeed, l10n.settingsDefaultsTrackpadInvalid),
          onReverted: () => ctx.setError(kKeyTrackpadSpeed, null),
        ),
      ),
    ]),
    LgSettingsSubtitle(l10n.toolbarSession),
    LgSettingsBlock(children: toggles(_sessionToggles(l10n))),
    LgSettingsSubtitle(l10n.settingsDefaultsTerminal),
    LgSettingsBlock(
        children: toggles([
      (kOptionTerminalPersistent, l10n.settingsDefaultsTerminalPersistent),
    ])),
  ]);
}

/// A number option; Rust answers the default for one that is unset or out of range.
double _number(OptionScope defaults, String key, double fallback) =>
    double.tryParse(defaults.get(key)) ?? fallback;

/// A slider's name, the slider and its value on one line.
class _SliderLine extends StatelessWidget {
  const _SliderLine({required this.label, required this.slider});

  final String label;
  final Widget slider;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 64, child: Text(label)),
          Flexible(child: slider),
        ],
      );
}

/// A slider that saves 1 second after it stops moving, as upstream's (02 §1.4.2: no writing
/// while it is dragged), with its value written after it. A move still waiting is saved when
/// the slider goes away.
class _DebouncedSlider extends StatefulWidget {
  const _DebouncedSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.semanticLabel,
    required this.format,
    required this.onSave,
    this.width = 200,
    this.trailing,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final String semanticLabel;
  final String Function(double value) format;
  final ValueChanged<double> onSave;
  final double width;

  /// What follows the slider, given the value it shows now (while moving too); the value
  /// written out when null.
  final Widget Function(double value)? trailing;

  @override
  State<_DebouncedSlider> createState() => _DebouncedSliderState();
}

class _DebouncedSliderState extends State<_DebouncedSlider> {
  double? _moved;
  Timer? _timer;

  void _save() {
    final v = _moved;
    if (v != null) widget.onSave(v);
  }

  /// The section reads the values again after a save: from then on the slider shows what was
  /// saved (or, when saving failed, what is still stored).
  @override
  void didUpdateWidget(_DebouncedSlider old) {
    super.didUpdateWidget(old);
    if (!(_timer?.isActive ?? false)) _moved = null;
  }

  @override
  void dispose() {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
      _save();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = (_moved ?? widget.value).clamp(widget.min, widget.max);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.width,
          child: LgSlider(
            value: value,
            min: widget.min,
            max: widget.max,
            step: widget.step,
            semanticLabel: widget.semanticLabel,
            format: widget.format,
            onChanged: (v) {
              setState(() => _moved = v);
              _timer?.cancel();
              _timer = Timer(const Duration(seconds: 1), _save);
            },
          ),
        ),
        const SizedBox(width: LgSpace.s3),
        widget.trailing?.call(value) ??
            SizedBox(width: 72, child: Text(widget.format(value))),
      ],
    );
  }
}

/// "触控板速度": the slider, and a box for the exact percentage (10~1000) that follows the slider
/// while it moves (upstream `TrackpadSpeedWidget.updateValue`).
class _TrackpadSpeed extends StatelessWidget {
  const _TrackpadSpeed({
    required this.value,
    required this.label,
    required this.errorText,
    required this.onSave,
    required this.onInvalid,
    required this.onReverted,
  });

  final int value;
  final String label;
  final String? errorText;
  final ValueChanged<int> onSave;
  final VoidCallback onInvalid;
  final VoidCallback onReverted;

  @override
  Widget build(BuildContext context) => _DebouncedSlider(
        value: value.toDouble(),
        min: kMinTrackpadSpeed.toDouble(),
        max: kMaxTrackpadSpeed.toDouble(),
        step: 10,
        semanticLabel: label,
        format: (v) => '${v.round()}%',
        onSave: (v) => onSave(v.round()),
        width: 160,
        trailing: (shown) => LgSettingsNumberField(
            text: '${shown.round()}',
            unit: '%',
            width: 72,
            semanticLabel: label,
            errorText: errorText,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (typed) {
              final v = int.tryParse(typed.trim());
              if (v == null ||
                  v < kMinTrackpadSpeed ||
                  v > kMaxTrackpadSpeed) {
                onInvalid();
              } else {
                onSave(v);
              }
            },
            onReverted: onReverted,
          ),
      );
}
