import 'package:flutter/material.dart';

class AppThemes {
  static const Color bgObsidian = Color(0xFF07080D);
  static const Color bgSurface = Color(0xFF11131C);
  static const Color bgCard = Color(0xFF171A26);
  static const Color neonCyan = Color(0xFF00E5FF);
  static const Color neonGreen = Color(0xFF00FFA3);
  static const Color neonPink = Color(0xFFFF007A);
  static const Color neonPurple = Color(0xFF9D4EDD);
  static const Color neonAmber = Color(0xFFFFB800);

  static final ThemeData gameTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgObsidian,
    colorScheme: const ColorScheme.dark(
      primary: neonGreen,
      secondary: neonPink,
      tertiary: neonCyan,
      surface: bgSurface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    ),
    cardTheme: CardTheme(
      color: bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: neonGreen,
        foregroundColor: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
  );

  static final ThemeData privateTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgObsidian,
    colorScheme: const ColorScheme.dark(
      primary: neonCyan,
      secondary: neonGreen,
      surface: bgSurface,
      error: Color(0xFFFF453A),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0D0F18),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
