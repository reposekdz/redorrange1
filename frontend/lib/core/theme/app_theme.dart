import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Brand palette
  static const orange      = Color(0xFFFF6B35);
  static const orangeDark  = Color(0xFFE85520);
  static const orangeLight = Color(0xFFFF8C61);
  static const orangeAccent= Color(0xFFFFAB76);
  static const orangeSurf  = Color(0xFFFFF3EE);

  // ── Light
  static const lBg    = Color(0xFFF8F8F8);
  static const lSurf  = Color(0xFFFFFFFF);
  static const lCard  = Color(0xFFFFFFFF);
  static const lDiv   = Color(0xFFEEEEEE);
  static const lText  = Color(0xFF0F0F0F);
  static const lSub   = Color(0xFF777777);
  static const lInput = Color(0xFFF2F2F2);

  // ── Dark
  static const dBg    = Color(0xFF0A0A0A);
  static const dSurf  = Color(0xFF161616);
  static const dCard  = Color(0xFF1E1E1E);
  static const dDiv   = Color(0xFF2A2A2A);
  static const dText  = Color(0xFFF0F0F0);
  static const dSub   = Color(0xFF888888);
  static const dInput = Color(0xFF222222);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark  => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg     = isDark ? dBg    : lBg;
    final surf   = isDark ? dSurf  : lSurf;
    final card   = isDark ? dCard  : lCard;
    final div    = isDark ? dDiv   : lDiv;
    final text   = isDark ? dText  : lText;
    final sub    = isDark ? dSub   : lSub;
    final input  = isDark ? dInput : lInput;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: orange, onPrimary: Colors.white,
        primaryContainer: isDark ? const Color(0xFF3D2010) : orangeSurf,
        onPrimaryContainer: isDark ? orangeLight : orangeDark,
        secondary: orangeDark, onSecondary: Colors.white,
        secondaryContainer: isDark ? const Color(0xFF2A1508) : const Color(0xFFFFE4D8),
        onSecondaryContainer: isDark ? orangeLight : orangeDark,
        surface: surf, onSurface: text,
        surfaceContainerHighest: card,
        outline: div,
        error: const Color(0xFFE53935), onError: Colors.white,
      ),
      scaffoldBackgroundColor: bg,
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge:  TextStyle(color: text, fontWeight: FontWeight.w800),
        displayMedium: TextStyle(color: text, fontWeight: FontWeight.w800),
        headlineLarge: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 28, letterSpacing: -0.5),
        headlineMedium:TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 24),
        headlineSmall: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 20),
        titleLarge:    TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -0.2),
        titleMedium:   TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 16),
        titleSmall:    TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 14),
        bodyLarge:     TextStyle(color: text, fontWeight: FontWeight.w400, fontSize: 16, height: 1.5),
        bodyMedium:    TextStyle(color: text, fontWeight: FontWeight.w400, fontSize: 14, height: 1.4),
        bodySmall:     TextStyle(color: sub,  fontWeight: FontWeight.w400, fontSize: 12),
        labelLarge:    TextStyle(color: text, fontWeight: FontWeight.w600, fontSize: 14),
        labelMedium:   TextStyle(color: sub,  fontWeight: FontWeight.w500, fontSize: 12),
        labelSmall:    TextStyle(color: sub,  fontWeight: FontWeight.w500, fontSize: 11),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surf, foregroundColor: text, elevation: 0, scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        iconTheme: IconThemeData(color: text),
      ),
      cardTheme: CardThemeData(
        color: card, elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: div, thickness: 0.5),
      iconTheme: IconThemeData(color: isDark ? const Color(0xFFCCCCCC) : const Color(0xFF444444), size: 24),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: input,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: orange, width: 1.5)),
        errorBorder:   OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5)),
        hintStyle: TextStyle(color: sub, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        backgroundColor: orange, foregroundColor: Colors.white, elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: orange, side: const BorderSide(color: orange),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      )),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: orange)),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF2A1508) : orangeSurf,
        selectedColor: orange, labelStyle: const TextStyle(fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surf, selectedItemColor: orange,
        unselectedItemColor: sub, type: BottomNavigationBarType.fixed, elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFF1A1A1A),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: orange),
      extensions: [RedOrrangeColors(isDark: isDark)],
    );
  }
}

class RedOrrangeColors extends ThemeExtension<RedOrrangeColors> {
  final Color msgOwn, msgOther, msgOwnText, msgOtherText, storyRing, online, unread;

  RedOrrangeColors({required bool isDark})
    : msgOwn      = AppTheme.orange,
      msgOther    = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
      msgOwnText  = Colors.white,
      msgOtherText= isDark ? const Color(0xFFF0F0F0) : const Color(0xFF0F0F0F),
      storyRing   = AppTheme.orange,
      online      = const Color(0xFF4CAF50),
      unread      = AppTheme.orange;

  @override
  RedOrrangeColors copyWith({Color? msgOwn, Color? msgOther, Color? msgOwnText, Color? msgOtherText, Color? storyRing, Color? online, Color? unread}) =>
    RedOrrangeColors(isDark: false);

  @override
  RedOrrangeColors lerp(ThemeExtension<RedOrrangeColors>? other, double t) => this;
}
