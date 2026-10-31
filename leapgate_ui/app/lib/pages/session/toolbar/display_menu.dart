// The "画面" menu (01 P2 block B): scale, scrolling, image quality, codec, true color,
// resolution, virtual displays and the cursor. Conditions and actions are upstream's
// `flutter/lib/common/widgets/toolbar.dart` (`toolbarViewStyle` :800-831, `toolbarImageQuality`
// :833-871, `toolbarCodec` :873-931, `toolbarCursor` :933-1050, true color :1184-1200,
// `getVirtualDisplayMenuChildren` :1474-1562) and `flutter/lib/desktop/widgets/remote_toolbar.dart`
// (`_DisplayMenu` :1713-2044, `_ResolutionsMenu` :2218-2545), rewritten into 01's groups. The
// custom quality is set with two sliders in the menu instead of upstream's dialog
// (`dialog.dart:1828-1900`); "Adjust window" and the window adjustment 3 s after a resolution
// change are gone (01 §3.2). The quality monitor switch is in the connection details (B).

import 'dart:convert';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/utils/scale.dart';

import 'dialogs.dart';
import 'entries.dart';
import 'toolbar_env.dart';

const kDisplayMenuActions = [
  kShortcutActionViewModeOriginal,
  kShortcutActionViewModeAdaptive,
  kShortcutActionViewModeCustom,
  kShortcutActionImageQualityBest,
  kShortcutActionImageQualityBalanced,
  kShortcutActionImageQualityLow,
  kShortcutActionCodecAuto,
  kShortcutActionCodecVp8,
  kShortcutActionCodecVp9,
  kShortcutActionCodecAv1,
  kShortcutActionCodecH264,
  kShortcutActionCodecH265,
  kShortcutActionToggleTrueColor,
  kShortcutActionPlugOutAllVirtualDisplays,
  kShortcutActionToggleShowRemoteCursor,
  kShortcutActionToggleFollowRemoteCursor,
  kShortcutActionToggleFollowRemoteWindow,
  kShortcutActionToggleZoomCursor,
];

const _kCustomResolution = 'custom';

// Custom scale: 5% to 1000%, with 100% at a third of the track
// (`common/widgets/custom_scale_base.dart:38-75`).
int _scaleAt(double p) {
  if (p <= 0.0) return kScaleCustomMinPercent;
  if (p >= 1.0) return kScaleCustomMaxPercent;
  if ((p - kScaleCustomPivotPos).abs() <= kScaleCustomDetentEpsilon) {
    return kScaleCustomPivotPercent;
  }
  final v = p <= kScaleCustomPivotPos
      ? kScaleCustomMinPercent +
            p /
                kScaleCustomPivotPos *
                (kScaleCustomPivotPercent - kScaleCustomMinPercent)
      : kScaleCustomPivotPercent +
            (p - kScaleCustomPivotPos) /
                (1.0 - kScaleCustomPivotPos) *
                (kScaleCustomMaxPercent - kScaleCustomPivotPercent);
  return clampCustomScalePercent(v.round());
}

double _scalePosition(int percent) {
  final p = clampCustomScalePercent(percent);
  if (p <= kScaleCustomPivotPercent) {
    return (p - kScaleCustomMinPercent) /
        (kScaleCustomPivotPercent - kScaleCustomMinPercent) *
        kScaleCustomPivotPos;
  }
  return kScaleCustomPivotPos +
      (p - kScaleCustomPivotPercent) /
          (kScaleCustomMaxPercent - kScaleCustomPivotPercent) *
          (1.0 - kScaleCustomPivotPos);
}

Future<List<TbEntry>> displayMenuEntries(ToolbarEnv env) async {
  final l10n = env.l10n;
  final ffi = env.ffi;
  final sid = env.sessionId;
  final pi = env.pi;
  final viewStyle = await bind.sessionGetViewStyle(sessionId: sid) ?? '';
  final scrollStyle = await bind.sessionGetScrollStyle(sessionId: sid) ?? '';
  final quality = await bind.sessionGetImageQuality(sessionId: sid) ?? '';
  final codecs = await _codecs(env);
  final entries = <TbEntry>[];

  // Scale.
  Future<void> setViewStyle(String style) async {
    await bind.sessionSetViewStyle(sessionId: sid, value: style);
    await ffi.canvasModel.updateViewStyle();
    env.notifyChanged();
  }

  entries.add(TbGroup(l10n.toolbarScale));
  for (final (style, label, action) in [
    (
      kRemoteViewStyleOriginal,
      l10n.toolbarScaleOriginal,
      kShortcutActionViewModeOriginal,
    ),
    (
      kRemoteViewStyleAdaptive,
      l10n.toolbarScaleAdaptive,
      kShortcutActionViewModeAdaptive,
    ),
    (kRemoteViewStyleCustom, l10n.menuCustom, kShortcutActionViewModeCustom),
  ]) {
    entries.add(
      TbItem(
        label: label,
        checked: viewStyle == style,
        actionId: action,
        hint: style == kRemoteViewStyleCustom ? l10n.menuScaleRange : null,
        onPressed: () => setViewStyle(style),
      ),
    );
  }
  if (viewStyle == kRemoteViewStyleCustom) {
    entries.add(
      TbSlider(
        label: l10n.menuCustomScale,
        value: await getSessionCustomScalePercent(sid),
        min: kScaleCustomMinPercent,
        max: kScaleCustomMaxPercent,
        toPosition: _scalePosition,
        fromPosition: _scaleAt,
        format: (v) => '$v%',
        onChanged: (v) async {
          await bind.sessionSetFlutterOption(
            sessionId: sid,
            k: kCustomScalePercentKey,
            v: '$v',
          );
          await ffi.canvasModel.updateViewStyle();
        },
      ),
    );
  }

  // Scrolling: with the original or a custom scale; only when the image overflows.
  if (viewStyle == kRemoteViewStyleOriginal ||
      viewStyle == kRemoteViewStyleCustom) {
    final overflow = ffi.canvasModel.imageOverflow.value;
    Future<void> setScrollStyle(String style) async {
      await bind.sessionSetScrollStyle(sessionId: sid, value: style);
      await ffi.canvasModel.updateScrollStyle();
      env.notifyChanged();
    }

    entries.add(TbGroup(l10n.menuScrollStyle));
    for (final (style, label) in [
      (kRemoteScrollStyleAuto, l10n.menuScrollAuto),
      (kRemoteScrollStyleBar, l10n.menuScrollBar),
      (kRemoteScrollStyleEdge, l10n.menuScrollEdge),
    ]) {
      entries.add(
        TbItem(
          label: label,
          checked: scrollStyle == style,
          onPressed: overflow ? () => setScrollStyle(style) : null,
        ),
      );
    }
    if (scrollStyle == kRemoteScrollStyleEdge) {
      entries.add(
        TbSlider(
          label: l10n.menuEdgeWidth,
          // The canvas starts from 100 too (`CanvasModel._edgeScrollEdgeThickness`).
          value:
              await bind.sessionGetEdgeScrollEdgeThickness(sessionId: sid) ??
              100,
          min: 20,
          max: 150,
          format: (v) => '$v px',
          onChanged: overflow
              ? (v) async {
                  await bind.sessionSetEdgeScrollEdgeThickness(
                    sessionId: sid,
                    value: v,
                  );
                  ffi.canvasModel.updateEdgeScrollEdgeThickness(v);
                }
              : null,
        ),
      );
    }
  }

  // Image quality.
  Future<void> setQuality(String value) async {
    await bind.sessionSetImageQuality(sessionId: sid, value: value);
    // Custom: the remote device gets the values the sliders start from, as upstream's dialog
    // sends them when it closes (`dialog.dart:1845-1866`).
    if (value == kRemoteImageQualityCustom) {
      final custom = await _readCustomQuality(env);
      await bind.sessionSetCustomImageQuality(
        sessionId: sid,
        value: custom.quality,
      );
      if (!custom.hideFps) {
        await bind.sessionSetCustomFps(sessionId: sid, fps: custom.fps);
      }
    }
    env.notifyChanged();
  }

  entries.add(TbGroup(l10n.toolbarQuality));
  for (final (value, label, action) in [
    (
      kRemoteImageQualityBest,
      l10n.toolbarQualityBest,
      kShortcutActionImageQualityBest,
    ),
    (
      kRemoteImageQualityBalanced,
      l10n.toolbarQualityBalanced,
      kShortcutActionImageQualityBalanced,
    ),
    (
      kRemoteImageQualityLow,
      l10n.toolbarQualityLow,
      kShortcutActionImageQualityLow,
    ),
    (kRemoteImageQualityCustom, l10n.menuCustom, null),
  ]) {
    entries.add(
      TbItem(
        label: label,
        checked: quality == value,
        actionId: action,
        onPressed: () => setQuality(value),
      ),
    );
  }
  if (quality == kRemoteImageQualityCustom) {
    entries.addAll(await _customQuality(env));
  }

  // Codec.
  if (codecs != null) {
    final preference = await ffi.options.get(kOptionCodecPreference) ?? '';
    Future<void> setCodec(String value) async {
      await ffi.options.set(kOptionCodecPreference, value);
      bind.sessionChangePreferCodec(sessionId: sid);
      env.notifyChanged();
    }

    final format = ffi.qualityMonitorModel.data.codecFormat;
    entries.add(TbGroup(l10n.menuCodec));
    for (final (value, label, action, shown) in [
      (
        'auto',
        preference == 'auto' && format != null
            ? l10n.menuCodecAutoWith(format)
            : l10n.menuCodecAuto,
        kShortcutActionCodecAuto,
        true,
      ),
      ('vp8', 'VP8', kShortcutActionCodecVp8, codecs.vp8),
      ('vp9', 'VP9', kShortcutActionCodecVp9, true),
      ('av1', 'AV1', kShortcutActionCodecAv1, codecs.av1),
      ('h264', 'H264', kShortcutActionCodecH264, codecs.h264),
      ('h265', 'H265', kShortcutActionCodecH265, codecs.h265),
    ]) {
      if (!shown) continue;
      entries.add(
        TbItem(
          label: label,
          checked: preference == value,
          actionId: action,
          onPressed: () => setCodec(value),
        ),
      );
    }
  }

  // True color: AV1 and VP9 only.
  final format = ffi.qualityMonitorModel.data.codecFormat;
  if (versionCmp(pi.version, '1.2.4') >= 0 &&
      (format == 'AV1' || format == 'VP9')) {
    entries.add(
      TbItem(
        label: l10n.menuTrueColor,
        checked: ffi.options.getToggle('i444'),
        actionId: kShortcutActionToggleTrueColor,
        onPressed: () async {
          await ffi.options.toggle('i444');
          bind.sessionChangePreferCodec(sessionId: sid);
          env.notifyChanged();
        },
      ),
    );
  }

  if (env.isDefaultConn) {
    final resolutions = _resolutionMenu(env);
    if (resolutions != null) entries.add(resolutions);
  }
  if (env.isDefaultConn && showVirtualDisplayMenu(ffi)) {
    entries.add(
      TbSubmenu(label: l10n.menuVirtualDisplay, items: _virtualDisplays(env)),
    );
  }

  // Cursor.
  if (env.isDefaultConn) {
    final cursor = await _cursorEntries(env, viewStyle);
    if (cursor.isNotEmpty) {
      entries.add(TbGroup(l10n.menuCursor));
      entries.addAll(cursor);
    }
  }
  return entries;
}

typedef _Codecs = ({bool vp8, bool av1, bool h264, bool h265});

/// The codecs both ends can use besides VP9; null when there are none to choose
/// (`toolbar.dart:876-900`).
Future<_Codecs?> _codecs(ToolbarEnv env) async {
  try {
    final Map json = jsonDecode(
      await bind.sessionAlternativeCodecs(sessionId: env.sessionId),
    );
    final c = (
      vp8: json['vp8'] == true,
      av1: json['av1'] == true,
      h264: json['h264'] == true,
      h265: json['h265'] == true,
    );
    return c.vp8 || c.av1 || c.h264 || c.h265 ? c : null;
  } catch (e) {
    return null;
  }
}

/// The saved custom quality and frame rate, or upstream's defaults (`dialog.dart:1828-1891`).
/// The frame rate is hidden on a public server without a direct connection and for peers
/// before 1.2.0.
Future<({int quality, int fps, bool hideFps})> _readCustomQuality(
  ToolbarEnv env,
) async {
  final sid = env.sessionId;
  final public = await bind.mainIsUsingPublicServer();
  final direct = env.ffi.connection.direct == true;
  final hideFps =
      (public && !direct) || versionCmp(env.pi.version, '1.2.0') < 0;
  final q = await bind.sessionGetCustomImageQuality(sessionId: sid);
  var quality = q != null && q.isNotEmpty ? q[0] : kDefaultQuality.toInt();
  if (quality < kMinQuality || quality > kMaxQuality) {
    quality = kDefaultQuality.toInt();
  }
  final fpsOption = await env.ffi.options.get('custom-fps');
  var fps = (double.tryParse(fpsOption ?? '') ?? kDefaultFps).toInt();
  if (fps < kMinFps || fps > kMaxFps) fps = kDefaultFps.toInt();
  return (quality: quality, fps: fps, hideFps: hideFps);
}

/// The two sliders of the custom quality.
Future<List<TbEntry>> _customQuality(ToolbarEnv env) async {
  final l10n = env.l10n;
  final sid = env.sessionId;
  final (:quality, :fps, :hideFps) = await _readCustomQuality(env);
  return [
    TbSlider(
      label: l10n.toolbarQuality,
      value: quality,
      min: kMinQuality.toInt(),
      max: kMaxQuality.toInt(),
      format: (v) => '$v',
      onChanged: (v) =>
          bind.sessionSetCustomImageQuality(sessionId: sid, value: v),
    ),
    if (!hideFps)
      TbSlider(
        label: l10n.menuFps,
        value: fps,
        min: kMinFps.toInt(),
        max: kMaxFps.toInt(),
        format: (v) => '$v',
        onChanged: (v) => bind.sessionSetCustomFps(sessionId: sid, fps: v),
      ),
  ];
}

/// This device's main display, for "与本机相同" (`remote_toolbar.dart:2339-2360`).
Resolution? _localResolution() {
  try {
    final d = json.decode(bind.mainGetMainDisplay());
    if (d['w'] != null && d['h'] != null) return Resolution(d['w'], d['h']);
  } catch (e) {
    return null;
  }
  return null;
}

TbSubmenu? _resolutionMenu(ToolbarEnv env) {
  final l10n = env.l10n;
  final ffi = env.ffi;
  final model = env.model;
  final pi = env.pi;
  final resolutions = pi.resolutions;
  final isVirtual = model.isVirtualDisplayResolution;
  if (!(isVirtual || resolutions.length > 1) ||
      pi.currentDisplay == kAllDisplayValue) {
    return null;
  }
  if (!model.keyboard) {
    return TbSubmenu(
      label: l10n.menuResolution,
      items: const [],
      disabledReason: l10n.menuNoKeyboard,
    );
  }
  final scale = pi.scaleOfDisplay(pi.currentDisplay);
  final rect = model.rect;
  final width = rect == null ? 0 : (rect.width / scale).toInt();
  final height = rect == null ? 0 : (rect.height / scale).toInt();
  final display = pi.currentDisplay;
  final last = stateGlobal.getLastResolutionGroupValue(ffi.id, display);
  final groupValue = last == _kCustomResolution
      ? _kCustomResolution
      : '${width}x$height';

  Future<void> change(int w, int h) async {
    if (pi.currentDisplay == kAllDisplayValue) return;
    await bind.sessionChangeResolution(
      sessionId: env.sessionId,
      display: display,
      width: w,
      height: h,
    );
    env.notifyChanged();
  }

  void choose(String value, int w, int h) {
    stateGlobal.setLastResolutionGroupValue(ffi.id, display, value);
    if (w != width || h != height) change(w, h);
  }

  final local = _localResolution();
  Resolution? fit;
  if (local != null) {
    fit = isVirtual
        ? local
        : resolutions
              .where((r) => r.width == local.width && r.height == local.height)
              .firstOrNull;
  }
  final current = pi.tryGetDisplayIfNotAllDisplay();
  final items = <TbEntry>[
    if (current != null &&
        model.isOriginalResolutionSet &&
        !model.isOriginalResolution &&
        resolutions.any(
          (r) =>
              r.width == current.originalWidth &&
              r.height == current.originalHeight,
        ))
      TbItem(
        label: l10n.menuResolutionOriginal,
        hint: '${current.originalWidth}×${current.originalHeight}',
        onPressed: () => change(current.originalWidth, current.originalHeight),
      ),
    if (fit != null && (fit.width != width || fit.height != height))
      TbItem(
        label: l10n.menuResolutionLocal,
        hint: '${local!.width}×${local.height}',
        onPressed: () => change(fit!.width, fit.height),
      ),
    if (resolutions.isNotEmpty) TbGroup(l10n.menuResolutionSupported),
    for (final r in resolutions)
      TbItem(
        label: '${r.width}×${r.height}',
        checked: groupValue == '${r.width}x${r.height}',
        onPressed: () => choose('${r.width}x${r.height}', r.width, r.height),
      ),
    if (isVirtual)
      TbItem(
        label: l10n.menuResolutionCustom,
        checked: groupValue == _kCustomResolution,
        onPressed: () async {
          final size = await showCustomResolutionDialog(
            env.overlays,
            ffi,
            l10n,
            width: width,
            height: height,
          );
          if (size != null) choose(_kCustomResolution, size.$1, size.$2);
        },
      ),
  ];
  return TbSubmenu(label: l10n.menuResolution, items: items);
}

/// One switch per virtual display (RustDesk's driver) or a count (Amyuni's), and "全部移除";
/// all disabled while privacy mode is on.
List<TbEntry> _virtualDisplays(ToolbarEnv env) {
  final l10n = env.l10n;
  final ffi = env.ffi;
  final pi = env.pi;
  final privacy = ffi.privacyMode.value.isNotEmpty;
  void toggle(int index, bool on) {
    bind.sessionToggleVirtualDisplay(
      sessionId: env.sessionId,
      index: index,
      on: on,
    );
    env.notifyChanged();
  }

  if (pi.isRustDeskIdd) {
    final plugged = pi.RustDeskVirtualDisplays;
    return [
      for (var i = 0; i < kMaxVirtualDisplayCount; i++)
        TbItem(
          label: l10n.menuVirtualDisplayN(i + 1),
          checked: plugged.contains(i + 1),
          onPressed: privacy
              ? null
              : () => toggle(i + 1, !plugged.contains(i + 1)),
        ),
      const TbDivider(),
      TbItem(
        label: l10n.menuRemoveAll,
        actionId: kShortcutActionPlugOutAllVirtualDisplays,
        onPressed: privacy ? null : () => toggle(kAllVirtualDisplay, false),
      ),
    ];
  }
  final count = pi.amyuniVirtualDisplayCount;
  return [
    TbStepper(
      label: l10n.menuVirtualDisplayCount,
      value: count,
      decreaseLabel: l10n.menuDecrease,
      increaseLabel: l10n.menuIncrease,
      onDecrease: privacy || count == 0 ? null : () => toggle(0, false),
      onIncrease: privacy || count == 4 ? null : () => toggle(0, true),
    ),
    const TbDivider(),
    TbItem(
      label: l10n.menuRemoveAll,
      actionId: kShortcutActionPlugOutAllVirtualDisplays,
      onPressed: privacy || count == 0
          ? null
          : () => toggle(kAllVirtualDisplay, false),
    ),
  ];
}

/// `toolbar.dart:933-1050`. Following the remote cursor keeps "显示远程光标" on and locked.
Future<List<TbEntry>> _cursorEntries(ToolbarEnv env, String viewStyle) async {
  final l10n = env.l10n;
  final ffi = env.ffi;
  final pi = env.pi;
  final model = env.model;
  final sid = env.sessionId;
  final multiUi = bind.sessionIsMultiUiSession(sessionId: sid);
  final cursorShown =
      pi.platform != kPeerPlatformAndroid &&
      !ffi.canvasModel.cursorEmbedded &&
      !pi.isWayland;
  final followShown =
      cursorShown &&
      versionCmp(pi.version, '1.2.4') >= 0 &&
      pi.displays.length > 1 &&
      pi.currentDisplay != kAllDisplayValue &&
      !multiUi;
  const showOption = 'show-remote-cursor';
  const followOption = 'follow-remote-cursor';
  final following = followShown && ffi.options.getToggle(followOption);

  Future<void> syncShowCursor() async {
    ffi.showRemoteCursor.value = ffi.options.getToggle(showOption);
  }

  // Following turns the remote cursor on (`toolbar.dart:983-988`).
  if (following && !ffi.options.getToggle(showOption)) {
    await ffi.options.toggle(showOption);
    await syncShowCursor();
  }
  return [
    if (cursorShown)
      TbItem(
        label: l10n.menuShowRemoteCursor,
        checked: ffi.showRemoteCursor.value,
        actionId: kShortcutActionToggleShowRemoteCursor,
        disabledReason: model.viewOnly
            ? l10n.menuViewOnlyUnavailable
            : (following ? l10n.menuFollowingCursor : null),
        onPressed: model.viewOnly || following
            ? null
            : () async {
                await ffi.options.toggle(showOption);
                await syncShowCursor();
                env.notifyChanged();
              },
      ),
    if (followShown)
      TbItem(
        label: l10n.menuFollowRemoteCursor,
        checked: following,
        actionId: kShortcutActionToggleFollowRemoteCursor,
        onPressed: () async {
          await ffi.options.toggle(followOption);
          if (!ffi.options.getToggle(showOption)) {
            await ffi.options.toggle(showOption);
            await syncShowCursor();
          }
          env.notifyChanged();
        },
      ),
    if (followShown)
      TbItem(
        label: l10n.menuFollowRemoteWindow,
        checked: ffi.options.getToggle('follow-remote-window'),
        actionId: kShortcutActionToggleFollowRemoteWindow,
        onPressed: () async {
          await ffi.options.toggle('follow-remote-window');
          env.notifyChanged();
        },
      ),
    if (pi.platform != kPeerPlatformAndroid &&
        viewStyle != kRemoteViewStyleOriginal)
      TbItem(
        label: l10n.menuZoomCursor,
        checked: ffi.options.getToggle(kOptionZoomCursor),
        actionId: kShortcutActionToggleZoomCursor,
        onPressed: () async {
          await ffi.options.toggle(kOptionZoomCursor);
          env.notifyChanged();
        },
      ),
  ];
}
