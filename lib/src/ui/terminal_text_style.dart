import 'package:flutter/widgets.dart';

const _kDefaultFontSize = 13.0;

const _kDefaultHeight = 1.2;

const _kDefaultFontFamily = 'monospace';

const _kDefaultFontFamilyFallback = [
  'Menlo',
  'Monaco',
  'Consolas',
  'Liberation Mono',
  'Courier New',
  'Noto Sans Mono CJK SC',
  'Noto Sans Mono CJK TC',
  'Noto Sans Mono CJK KR',
  'Noto Sans Mono CJK JP',
  'Noto Sans Mono CJK HK',
  'Noto Color Emoji',
  'Symbols Nerd Font Mono',
  'Symbols Nerd Font',
  'Noto Sans Symbols 2',
  'Noto Sans Symbols',
  'monospace',
  'sans-serif',
];

const _kTerminalFontFeatures = [
  FontFeature.disable('calt'),
  FontFeature.disable('clig'),
  FontFeature.disable('kern'),
  FontFeature.disable('liga'),
];

class TerminalStyle {
  const TerminalStyle({
    this.fontSize = _kDefaultFontSize,
    this.height = _kDefaultHeight,
    this.fontFamily = _kDefaultFontFamily,
    this.fontFamilyFallback = _kDefaultFontFamilyFallback,
    this.drawBoldTextWithBrightColors = true,
  });

  factory TerminalStyle.fromTextStyle(TextStyle textStyle) {
    return TerminalStyle(
      fontSize: textStyle.fontSize ?? _kDefaultFontSize,
      height: textStyle.height ?? _kDefaultHeight,
      fontFamily: textStyle.fontFamily ??
          textStyle.fontFamilyFallback?.first ??
          _kDefaultFontFamily,
      fontFamilyFallback:
          textStyle.fontFamilyFallback ?? _kDefaultFontFamilyFallback,
      drawBoldTextWithBrightColors: true,
    );
  }

  final double fontSize;

  final double height;

  final String fontFamily;

  final List<String> fontFamilyFallback;

  final bool drawBoldTextWithBrightColors;

  TextStyle toTextStyle({
    Color? color,
    Color? backgroundColor,
    Color? decorationColor,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool doubleUnderline = false,
    TextDecorationStyle decorationStyle = TextDecorationStyle.solid,
    bool strikethrough = false,
    bool overline = false,
  }) {
    final decorations = [
      if (underline || doubleUnderline) TextDecoration.underline,
      if (strikethrough) TextDecoration.lineThrough,
      if (overline) TextDecoration.overline,
    ];
    final decoration = switch (decorations.isEmpty) {
      true => TextDecoration.none,
      false => TextDecoration.combine(decorations),
    };
    final effectiveDecorationStyle = switch (doubleUnderline) {
      true => TextDecorationStyle.double,
      false => decorationStyle,
    };

    return TextStyle(
      fontSize: fontSize,
      height: height,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      color: color,
      backgroundColor: backgroundColor,
      fontWeight: switch (bold) {
        true => FontWeight.bold,
        false => FontWeight.normal,
      },
      fontStyle: switch (italic) {
        true => FontStyle.italic,
        false => FontStyle.normal,
      },
      decoration: decoration,
      decorationStyle: effectiveDecorationStyle,
      decorationColor: decorationColor,
      fontFeatures: _kTerminalFontFeatures,
    );
  }

  TerminalStyle copyWith({
    double? fontSize,
    double? height,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    bool? drawBoldTextWithBrightColors,
  }) {
    return TerminalStyle(
      fontSize: fontSize ?? this.fontSize,
      height: height ?? this.height,
      fontFamily: fontFamily ?? this.fontFamily,
      fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
      drawBoldTextWithBrightColors:
          drawBoldTextWithBrightColors ?? this.drawBoldTextWithBrightColors,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TerminalStyle) return false;
    if (fontSize != other.fontSize ||
        height != other.height ||
        fontFamily != other.fontFamily ||
        drawBoldTextWithBrightColors != other.drawBoldTextWithBrightColors ||
        fontFamilyFallback.length != other.fontFamilyFallback.length) {
      return false;
    }
    for (var index = 0; index < fontFamilyFallback.length; index++) {
      if (fontFamilyFallback[index] != other.fontFamilyFallback[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        fontSize,
        height,
        fontFamily,
        drawBoldTextWithBrightColors,
        Object.hashAll(fontFamilyFallback),
      );
}
