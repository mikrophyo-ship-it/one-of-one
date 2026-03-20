import 'package:flutter/material.dart';

class OneOfOneTheme {
  static const Color black = Color(0xFF0A0A0A);
  static const Color gold = Color(0xFFC7A54B);
  static const Color ivory = Color(0xFFF6F1E7);
  static const Color muted = Color(0xFFB9AEA0);

  static ThemeData customerTheme() {
    const ColorScheme scheme = ColorScheme.dark(
      primary: gold,
      secondary: ivory,
      surface: Color(0xFF111111),
      error: Color(0xFFC95D63),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: black,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: ivory,
          letterSpacing: 1.1,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: ivory,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: ivory),
        bodyMedium: TextStyle(fontSize: 14, color: muted),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: black,
        ),
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF181818),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: const EdgeInsets.symmetric(vertical: 10),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: black,
        foregroundColor: ivory,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF151515),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: gold),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFF2C2C2C)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: black,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
    );
  }

  static ThemeData adminTheme() {
    final ThemeData base = customerTheme();
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardTheme: base.cardTheme.copyWith(
        color: const Color(0xFF1A1A1A),
        margin: const EdgeInsets.all(8),
      ),
    );
  }
}

