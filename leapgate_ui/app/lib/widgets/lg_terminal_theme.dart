// What the terminal area looks like (13 §2.2.1, R3-Q14; `.tm` of `A-P9-终端.html`): xterm's theme
// and style built from the tokens `--lg-term-*` (`LgTokens.term`), the scroll bar of the area, and
// the dark ground that holds it. The area is dark in the light theme too: a terminal is full of
// programs that choose their colours for a dark ground.
//
// The terminal itself (`TerminalView`) is the caller's; this only dresses it. Typical use:
//
//     LgTerminalSurface(
//       child: LgTerminalScrollbar(
//         controller: scroll,
//         child: TerminalView(terminal, scrollController: scroll,
//             theme: lgTerminalTheme(), textStyle: lgTerminalStyle(),
//             padding: const EdgeInsets.only(top: 3)),
//       ),
//     )

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../theme/lg_tokens.dart';

/// How much of the selection colour is laid over the text. xterm paints the selection after the
/// text, over it, and has no colour for the text of a selection (the mockup's `--lg-term-sel` ground
/// with `--lg-term-sel-fg` white text cannot be had). An opaque selection would hide the text, and
/// a dark translucent one (the mockup's `--lg-term-sel`) pulls every colour towards itself and
/// takes the contrast away; a light one, in the cursor's teal, lifts the ground and leaves the
/// text brighter than it. So the selection is the cursor colour at this strength: the text under
/// it keeps 4.5:1 or better (checked in the tests), the selected ground is a clear teal tint.
const double kLgTermSelectionAlpha = .2;

/// The theme of the terminal: the 16 colours, the foreground and background, the cursor and the
/// selection from [LgTermColors.standard]; the selection is the cursor colour, translucent, see
/// [kLgTermSelectionAlpha].
TerminalTheme lgTerminalTheme([
  LgTermColors term = LgTermColors.standard,
]) => TerminalTheme(
  cursor: term.cursor,
  selection: term.cursor.withValues(alpha: kLgTermSelectionAlpha),
  foreground: term.fg,
  background: term.bg,
  black: term.black,
  red: term.red,
  green: term.green,
  yellow: term.yellow,
  blue: term.blue,
  magenta: term.magenta,
  cyan: term.cyan,
  white: term.white,
  brightBlack: term.brightBlack,
  brightRed: term.brightRed,
  brightGreen: term.brightGreen,
  brightYellow: term.brightYellow,
  brightBlue: term.brightBlue,
  brightMagenta: term.brightMagenta,
  brightCyan: term.brightCyan,
  brightWhite: term.brightWhite,
  // Not in the mockup: the yellow and the green of the palette, the ground's colour on them.
  searchHitBackground: term.yellow,
  searchHitBackgroundCurrent: term.green,
  searchHitForeground: term.bg,
);

/// The face of the terminal (`.tm .tx`): Cascadia Mono, then Consolas, then the Chinese UI faces
/// for what the Latin ones lack, 13 px with a line 1.2 times as high, in both interface modes.
TerminalStyle lgTerminalStyle({double fontSize = 13}) => TerminalStyle(
  fontSize: fontSize,
  height: 1.2,
  fontFamily: 'Cascadia Mono',
  fontFamilyFallback: const [
    'Consolas',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Courier New',
    'monospace',
  ],
);

/// The dark ground of the terminal area (`.tm`): 5 px at each side, `--lg-term-bg`. [dimmed] puts
/// the scrim of a dialog over what is shown (the connection is down and the panel stands over the
/// last screen, `.tm.dim`). Fills the space it is given.
class LgTerminalSurface extends StatelessWidget {
  const LgTerminalSurface({
    super.key,
    required this.child,
    this.dimmed = false,
  });

  final Widget child;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final t = LgTokens.of(context);
    return ColoredBox(
      color: t.term.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: child,
          ),
          if (dimmed) IgnorePointer(child: ColoredBox(color: t.colors.scrim)),
        ],
      ),
    );
  }
}

/// The scroll bar on the right of the terminal (`.tm .sbr`): a 10 px track with a rounded thumb,
/// both in the light-on-dark colours of the area, 2 px from the edges. Always there, as the
/// mockup draws it. [controller] is the one given to `TerminalView.scrollController`.
class LgTerminalScrollbar extends StatelessWidget {
  const LgTerminalScrollbar({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final term = LgTokens.of(context).term;
    return RawScrollbar(
      controller: controller,
      thumbVisibility: true,
      trackVisibility: true,
      thickness: 10,
      radius: const Radius.circular(5),
      trackRadius: const Radius.circular(5),
      thumbColor: term.thumb,
      trackColor: term.track,
      trackBorderColor: Colors.transparent,
      crossAxisMargin: 2,
      mainAxisMargin: 2,
      child: child,
    );
  }
}

/// [text] as a note written into the terminal: in `--lg-term-fg2`, then back to the normal colour
/// (`ESC [ 38;2;r;g;b m … ESC [ 0 m`). For the lines the application itself writes ("无法打开终端…",
/// "已重新连接…"); the program's own output keeps the palette.
String lgTerminalNote(
  String text, [
  LgTermColors term = LgTermColors.standard,
]) => '${term.noteStart}$text${LgTermColors.reset}';
