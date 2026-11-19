import 'package:flutter/material.dart';

class AppThemes {
  // Playful Arcade / Game Mode Theme
  static final ThemeData gameTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF00FFA3), // Neon mint
      secondary: Color(0xFFFF007A), // Cyberpunk pink
      tertiary: Color(0xFF7928CA), // Electric purple
      surface: Color(0xFF13111C),
      onPrimary: Colors.black,
      onSecondary: Colors.white,
      onSurface: Color(0xFFE4E4EB),
    ),
    scaffoldBackgroundColor: const Color(0xFF0A090F),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF13111C),
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'sans-serif',
        fontWeight: FontWeight.bold,
        fontSize: 20,
        color: Color(0xFF00FFA3),
      ),
    ),
    cardTheme: CardTheme(
      color: const Color(0xFF1A1726),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00FFA3),
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    ),
  );

  // Private Secure Communication Theme
  static final ThemeData privateTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF64D2FF), // Titanium ice blue
      secondary: Color(0xFF5E5CE6), // Deep indigo
      surface: Color(0xFF1C1C1E),
      onPrimary: Colors.black,
      onSurface: Color(0xFFE5E5EA),
    ),
    scaffoldBackgroundColor: const Color(0xFF000000),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1C1C1E),
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 18,
        color: Color(0xFFE5E5EA),
      ),
    ),
    cardTheme: CardTheme(
      color: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
