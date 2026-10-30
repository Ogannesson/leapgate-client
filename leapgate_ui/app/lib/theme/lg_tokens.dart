// Design tokens, transcribed by hand from docs/新界面/样稿/A-基础.html
// (.lg-light / .lg-dark :44-83, shared sizes :31-42, .lg-detail :85-91).
// From here on this file is the source of truth; the mockup is only a reference
// (docs/新界面/03-实施方案.md §4.1). Mockup px are Flutter logical pixels.

import 'package:flutter/material.dart';

/// Interface mode (01 §2.3). Detail only changes sizes and font sizes, plus the
/// connection-method marker, which the marker widget reads from [LgTokens.mode].
enum LgMode { compact, detail }

/// One identity colour group (`--lg-kN-s/-t/-i`). Text never uses these for
/// contrast (01 §2.4).
@immutable
class LgIdentityColor {
  const LgIdentityColor(this.solid, this.tint, this.ink);

  final Color solid;
  final Color tint;
  final Color ink;

  static LgIdentityColor lerp(LgIdentityColor a, LgIdentityColor b, double t) =>
      LgIdentityColor(
        Color.lerp(a.solid, b.solid, t)!,
        Color.lerp(a.tint, b.tint, t)!,
        Color.lerp(a.ink, b.ink, t)!,
      );
}

@immutable
class LgColors {
  const LgColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.text2,
    required this.accent,
    required this.onAccent,
    required this.online,
    required this.offline,
    required this.connecting,
    required this.warning,
    required this.error,
    required this.direct,
    required this.relay,
    required this.unencrypted,
    required this.warningBg,
    required this.errorBg,
    required this.canvas,
    required this.float,
    required this.shadow,
    required this.hover,
    required this.track,
    required this.thumb,
    required this.active,
    required this.disabled,
    required this.nav,
    required this.navFg,
    required this.cat,
    required this.catFg,
    required this.bar,
    required this.cmBand,
    required this.tagMix,
    required this.winClose,
    required this.onWinClose,
    required this.onIdentity,
    required this.scrim,
    required this.identity,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color text2;
  final Color accent;
  final Color onAccent;

  final Color online;
  final Color offline;
  final Color connecting;
  final Color warning;
  final Color error;
  final Color direct;
  final Color relay;
  final Color unencrypted;

  final Color warningBg;
  final Color errorBg;

  /// Neutral ground around the remote picture.
  final Color canvas;

  /// Floating layers: menus, popovers, tooltips, dialogs.
  final Color float;
  final List<BoxShadow> shadow;

  final Color hover;

  /// Scrollbar / slider track and thumb.
  final Color track;
  final Color thumb;

  /// Selected toolbar item, selected table row.
  final Color active;
  final Color disabled;

  /// Navigation item selected background and text.
  final Color nav;
  final Color navFg;

  /// Category item selected background and text.
  final Color cat;
  final Color catFg;

  /// The bar under each group of the local ID.
  final Color bar;

  /// Connection manager info header background.
  final Color cmBand;

  /// Share of a user-picked tag colour mixed into the ground (`--lg-tag-mix`).
  final double tagMix;

  /// Windows caption close button on hover.
  final Color winClose;
  final Color onWinClose;

  /// Text on an identity solid colour (visitor avatar letter).
  final Color onIdentity;

  final Color scrim;

  /// k1..k7; index with `identityGroup()` from `package:flutter_hbb/leapgate/identity_color.dart`.
  final List<LgIdentityColor> identity;

  /// Tag chip background: the tag colour mixed into the ground at [tagMix].
  Color tagTint(Color tag) => tag.withValues(alpha: tag.a * tagMix);

  static const light = LgColors(
    bg: Color(0xFFEAF1F1),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFDCE8E9),
    border: Color(0xFFC8D3D1),
    borderStrong: Color(0xFF6B7F7D),
    text: Color(0xFF14282B),
    text2: Color(0xFF475B5D),
    accent: Color(0xFF0B6577),
    onAccent: Color(0xFFFFFFFF),
    online: Color(0xFF03743C),
    offline: Color(0xFF576765),
    connecting: Color(0xFF0B6577),
    warning: Color(0xFF935501),
    error: Color(0xFFBE2B21),
    direct: Color(0xFF03743C),
    relay: Color(0xFF4F59C4),
    unencrypted: Color(0xFF935501),
    warningBg: Color(0xFFFBE9C6),
    errorBg: Color(0xFFFBE3E0),
    canvas: Color(0xFFD3D7D8),
    float: Color(0xFFFFFFFF),
    shadow: [
      BoxShadow(
        color: Color.fromRGBO(20, 40, 42, .08),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
      BoxShadow(
        color: Color.fromRGBO(20, 40, 42, .16),
        offset: Offset(0, 8),
        blurRadius: 24,
      ),
    ],
    hover: Color.fromRGBO(20, 40, 42, .08),
    track: Color.fromRGBO(20, 40, 42, .16),
    thumb: Color.fromRGBO(20, 40, 42, .40),
    active: Color.fromRGBO(11, 101, 119, .16),
    disabled: Color.fromRGBO(20, 40, 42, .14),
    nav: Color(0xFFD9ECEF),
    navFg: Color(0xFF0B6577),
    cat: Color(0xFFD2E7EC),
    catFg: Color(0xFF0B6577),
    bar: Color(0xFF0B6577),
    cmBand: Color(0xFFD6ECF0),
    tagMix: .12,
    winClose: Color(0xFFC42B1C),
    onWinClose: Color(0xFFFFFFFF),
    onIdentity: Color(0xFFFFFFFF),
    scrim: Color.fromRGBO(10, 20, 22, .5),
    identity: [
      LgIdentityColor(Color(0xFFA65B80), Color(0xFFEAC3D4), Color(0xFF59213E)),
      LgIdentityColor(Color(0xFFBD6E53), Color(0xFFECC4B6), Color(0xFF5D240E)),
      LgIdentityColor(Color(0xFFA07E2A), Color(0xFFDECEAB), Color(0xFF483500)),
      LgIdentityColor(Color(0xFF65873E), Color(0xFFC6D8B6), Color(0xFF284002)),
      LgIdentityColor(Color(0xFF009184), Color(0xFFADDCD4), Color(0xFF00423B)),
      LgIdentityColor(Color(0xFF2F7FB0), Color(0xFFB2D4ED), Color(0xFF003C5D)),
      LgIdentityColor(Color(0xFF836FB6), Color(0xFFD0C8EC), Color(0xFF3D2C61)),
    ],
  );

  static const dark = LgColors(
    bg: Color(0xFF142529),
    surface: Color(0xFF203033),
    surface2: Color(0xFF2C4247),
    border: Color(0xFF35494D),
    borderStrong: Color(0xFF7D969A),
    text: Color(0xFFE6EFEF),
    text2: Color(0xFFA8BBBD),
    accent: Color(0xFF86C9D4),
    onAccent: Color(0xFF05272E),
    online: Color(0xFF59D68A),
    offline: Color(0xFFA0B1B3),
    connecting: Color(0xFF86C9D4),
    warning: Color(0xFFF3B44A),
    error: Color(0xFFFEA9A0),
    direct: Color(0xFF59D68A),
    relay: Color(0xFFB1BBFF),
    unencrypted: Color(0xFFF3B44A),
    warningBg: Color(0xFF3A2F17),
    errorBg: Color(0xFF432322),
    canvas: Color(0xFF0C1213),
    float: Color(0xFF2A3D41),
    // `0 0 0 1px #35494D`: a 1 px ring instead of a shadow.
    shadow: [BoxShadow(color: Color(0xFF35494D), spreadRadius: 1)],
    hover: Color.fromRGBO(230, 239, 239, .08),
    track: Color.fromRGBO(230, 239, 239, .22),
    thumb: Color.fromRGBO(230, 239, 239, .42),
    active: Color.fromRGBO(134, 201, 212, .14),
    disabled: Color.fromRGBO(230, 239, 239, .10),
    nav: Color(0xFF26494F),
    navFg: Color(0xFF86C9D4),
    cat: Color(0xFF294A52),
    catFg: Color(0xFF86C9D4),
    bar: Color(0xFF86C9D4),
    cmBand: Color(0xFF1C424B),
    tagMix: .16,
    winClose: Color(0xFFC42B1C),
    onWinClose: Color(0xFFFFFFFF),
    onIdentity: Color(0xFF0B1A1D),
    scrim: Color.fromRGBO(10, 20, 22, .5),
    identity: [
      LgIdentityColor(Color(0xFFC97DA1), Color(0xFF6B4959), Color(0xFFFEDEEC)),
      LgIdentityColor(Color(0xFFC17657), Color(0xFF6E4B3D), Color(0xFFFDDDD0)),
      LgIdentityColor(Color(0xFFB99B4B), Color(0xFF605332), Color(0xFFFDE6AA)),
      LgIdentityColor(Color(0xFF71934C), Color(0xFF4B5B3C), Color(0xFFD4F5B5)),
      LgIdentityColor(Color(0xFF2EA799), Color(0xFF365D57), Color(0xFF9DF9EB)),
      LgIdentityColor(Color(0xFF5A9FD4), Color(0xFF3B5870), Color(0xFFD7EBFB)),
      LgIdentityColor(Color(0xFF927EC5), Color(0xFF574F6F), Color(0xFFE9E4FA)),
    ],
  );

  static LgColors lerp(LgColors a, LgColors b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return LgColors(
      bg: c(a.bg, b.bg),
      surface: c(a.surface, b.surface),
      surface2: c(a.surface2, b.surface2),
      border: c(a.border, b.border),
      borderStrong: c(a.borderStrong, b.borderStrong),
      text: c(a.text, b.text),
      text2: c(a.text2, b.text2),
      accent: c(a.accent, b.accent),
      onAccent: c(a.onAccent, b.onAccent),
      online: c(a.online, b.online),
      offline: c(a.offline, b.offline),
      connecting: c(a.connecting, b.connecting),
      warning: c(a.warning, b.warning),
      error: c(a.error, b.error),
      direct: c(a.direct, b.direct),
      relay: c(a.relay, b.relay),
      unencrypted: c(a.unencrypted, b.unencrypted),
      warningBg: c(a.warningBg, b.warningBg),
      errorBg: c(a.errorBg, b.errorBg),
      canvas: c(a.canvas, b.canvas),
      float: c(a.float, b.float),
      shadow: t < .5 ? a.shadow : b.shadow,
      hover: c(a.hover, b.hover),
      track: c(a.track, b.track),
      thumb: c(a.thumb, b.thumb),
      active: c(a.active, b.active),
      disabled: c(a.disabled, b.disabled),
      nav: c(a.nav, b.nav),
      navFg: c(a.navFg, b.navFg),
      cat: c(a.cat, b.cat),
      catFg: c(a.catFg, b.catFg),
      bar: c(a.bar, b.bar),
      cmBand: c(a.cmBand, b.cmBand),
      tagMix: a.tagMix + (b.tagMix - a.tagMix) * t,
      winClose: c(a.winClose, b.winClose),
      onWinClose: c(a.onWinClose, b.onWinClose),
      onIdentity: c(a.onIdentity, b.onIdentity),
      scrim: c(a.scrim, b.scrim),
      identity: [
        for (var i = 0; i < a.identity.length; i++)
          LgIdentityColor.lerp(a.identity[i], b.identity[i], t),
      ],
    );
  }
}

/// Control heights, font sizes and line heights that change with [LgMode].
///
/// Phone frames keep the compact sizes in both modes (A-基础.html:84), so the
/// phone UI will use [LgSizes.compact] whatever the mode is.
@immutable
class LgSizes {
  const LgSizes({
    required this.button,
    required this.nav,
    required this.row,
    required this.main,
    required this.tool,
    required this.bar,
    required this.tableRow,
    required this.permission,
    required this.menuGroup,
    required this.menuSlider,
    required this.fs,
    required this.lh,
    required this.fsM,
    required this.lhM,
    required this.fsS,
    required this.lhS,
    required this.fsN,
    required this.lhN,
    required this.toolGap,
    required this.toolPad,
    required this.cmHead,
    required this.cmAvatar,
    required this.fsCmName,
    required this.lhCmName,
    required this.cmHeadGap,
  });

  /// `--lg-h-btn`: buttons, icon buttons, segmented control.
  final double button;

  /// `--lg-h-nav`: navigation and category items.
  final double nav;

  /// `--lg-h-row`: menu rows, list rows.
  final double row;

  /// `--lg-h-main`: connect box, input fields, large buttons.
  final double main;

  /// `--lg-h-tool`: toolbar items.
  final double tool;

  /// `--lg-h-bar`: floating toolbar.
  final double bar;

  /// `--lg-h-trow`: table (list view) rows.
  final double tableRow;

  /// `--lg-h-perm`: connection manager permission rows.
  final double permission;

  /// `--lg-h-mg`: menu group titles.
  final double menuGroup;

  /// `--lg-h-ms`: slider rows inside menus.
  final double menuSlider;

  /// Body text (`--lg-fs` / `--lg-lh`).
  final double fs;
  final double lh;

  /// Medium text (`--lg-fs-m`).
  final double fsM;
  final double lhM;

  /// Small text (`--lg-fs-s`).
  final double fsS;
  final double lhS;

  /// Names and emphasised numbers (`--lg-fs-n`).
  final double fsN;
  final double lhN;

  /// Toolbar item icon/text gap and side padding (`--lg-gap-ti`, `--lg-pad-ti`).
  final double toolGap;
  final double toolPad;

  /// Connection manager info header (`--lg-h-cmhead` and friends).
  final double cmHead;
  final double cmAvatar;
  final double fsCmName;
  final double lhCmName;
  final double cmHeadGap;

  static const compact = LgSizes(
    button: 36,
    nav: 40,
    row: 44,
    main: 48,
    tool: 44,
    bar: 52,
    tableRow: 44,
    permission: 40,
    menuGroup: 32,
    menuSlider: 52,
    fs: 15,
    lh: 22,
    fsM: 14,
    lhM: 20,
    fsS: 13,
    lhS: 18,
    fsN: 17,
    lhN: 24,
    toolGap: 4,
    toolPad: 12,
    cmHead: 112,
    cmAvatar: 52,
    fsCmName: 20,
    lhCmName: 28,
    cmHeadGap: 16,
  );

  static const detail = LgSizes(
    button: 32,
    nav: 32,
    row: 28,
    main: 32,
    tool: 28,
    bar: 36,
    tableRow: 32,
    permission: 28,
    menuGroup: 28,
    menuSlider: 36,
    fs: 13,
    lh: 18,
    fsM: 13,
    lhM: 18,
    fsS: 12,
    lhS: 18,
    fsN: 14,
    lhN: 20,
    toolGap: 6,
    toolPad: 8,
    cmHead: 84,
    cmAvatar: 40,
    fsCmName: 14,
    lhCmName: 20,
    cmHeadGap: 12,
  );
}

/// Spacing scale `--lg-sp-1`..`--lg-sp-8`.
abstract final class LgSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 32;
  static const double s8 = 48;
}

/// Corner radii `--lg-r-*`.
abstract final class LgRadius {
  static const double r6 = 6;
  static const double r10 = 10;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r28 = 28;
}

/// Values that do not change with theme or mode.
abstract final class LgFixed {
  /// Identity / selection strip on top of tabs (`--lg-strip`).
  static const double strip = 3;

  /// Avatar letter in the connection manager header, both modes (`--lg-fs-cmav`).
  static const double fsCmAvatar = 20;

  static const String fontFamily = 'Atkinson Hyperlegible Next';
  static const List<String> fontFamilyFallback = [
    'Microsoft YaHei UI',
    'Microsoft YaHei',
  ];
}

class LgTokens extends ThemeExtension<LgTokens> {
  const LgTokens({required this.colors, required this.mode});

  final LgColors colors;
  final LgMode mode;

  LgSizes get sizes => mode == LgMode.detail ? LgSizes.detail : LgSizes.compact;
  bool get detail => mode == LgMode.detail;

  static LgTokens of(BuildContext context) =>
      Theme.of(context).extension<LgTokens>()!;

  /// Text styles. Colour is left to the caller; family, tabular figures and
  /// CSS-like even leading are set here.
  TextStyle get text => style(sizes.fs, sizes.lh);
  TextStyle get textM => style(sizes.fsM, sizes.lhM);
  TextStyle get textS => style(sizes.fsS, sizes.lhS);
  TextStyle get textN => style(sizes.fsN, sizes.lhN);

  static TextStyle style(
    double size,
    double lineHeight, [
    FontWeight weight = FontWeight.w400,
  ]) => TextStyle(
    fontFamily: LgFixed.fontFamily,
    fontFamilyFallback: LgFixed.fontFamilyFallback,
    fontSize: size,
    height: lineHeight / size,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: weight,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  LgTokens copyWith({LgColors? colors, LgMode? mode}) =>
      LgTokens(colors: colors ?? this.colors, mode: mode ?? this.mode);

  @override
  LgTokens lerp(LgTokens? other, double t) {
    if (other == null) return this;
    return LgTokens(
      colors: LgColors.lerp(colors, other.colors, t),
      mode: t < .5 ? mode : other.mode,
    );
  }
}
