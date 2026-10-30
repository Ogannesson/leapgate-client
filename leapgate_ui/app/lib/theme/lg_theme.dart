import 'package:flutter/material.dart';

import 'lg_tokens.dart';

/// Builds the app theme from the tokens. Pages use the components in
/// `lib/widgets/`; the Material colour scheme only covers Material widgets we
/// have not replaced (03 §4.1).
ThemeData buildLgTheme({required Brightness brightness, required LgMode mode}) {
  final c = brightness == Brightness.dark ? LgColors.dark : LgColors.light;
  final tokens = LgTokens(colors: c, mode: mode);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: c.nav,
    onPrimaryContainer: c.navFg,
    secondary: c.accent,
    onSecondary: c.onAccent,
    secondaryContainer: c.cat,
    onSecondaryContainer: c.catFg,
    error: c.error,
    onError: c.onAccent,
    errorContainer: c.errorBg,
    onErrorContainer: c.text,
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.text2,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.bg,
    surfaceContainer: c.bg,
    surfaceContainerHigh: c.float,
    surfaceContainerHighest: c.surface2,
    outline: c.borderStrong,
    outlineVariant: c.border,
    scrim: c.scrim,
    shadow: c.text,
  );
  final base = brightness == Brightness.dark
      ? Typography.material2021().white
      : Typography.material2021().black;
  // bodyMedium is Material's default text style; make it the body token.
  final textTheme = _withLgText(
    base,
    c.text,
  ).copyWith(bodyMedium: tokens.text.copyWith(color: c.text));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    cardColor: c.surface,
    dividerColor: c.border,
    disabledColor: c.text2,
    hoverColor: c.hover,
    focusColor: c.active,
    highlightColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.standard,
    fontFamily: LgFixed.fontFamily,
    fontFamilyFallback: LgFixed.fontFamilyFallback,
    textTheme: textTheme,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.active,
      selectionHandleColor: c.accent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.thumb),
      thickness: const WidgetStatePropertyAll(4),
      radius: const Radius.circular(2),
    ),
    extensions: [tokens],
  );
}

TextTheme _withLgText(TextTheme t, Color color) {
  TextStyle? f(TextStyle? s) => s?.copyWith(
    fontFamily: LgFixed.fontFamily,
    fontFamilyFallback: LgFixed.fontFamilyFallback,
    color: color,
    leadingDistribution: TextLeadingDistribution.even,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  return TextTheme(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}
