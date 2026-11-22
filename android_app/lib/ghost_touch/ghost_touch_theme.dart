import 'dart:ui';
import 'package:flutter/material.dart';

/// Design tokens for SecretPlay Ghost Touch holographic universe.
class GhostPalette {
  static const Color neonPink = Color(0xFFFF3D9A);
  static const Color electricCyan = Color(0xFF00E5FF);
  static const Color neonPurple = Color(0xFFB45CFF);
  static const Color electricBlue = Color(0xFF477BFF);
  static const Color neonGreen = Color(0xFF00FFA3);
  static const Color deepSpace = Color(0xFF080912);
  static const Color darkViolet = Color(0xFF151124);
  static const Color amberGold = Color(0xFFFFC857);
  static const Color surfaceGlass = Color(0xFF121526);
  static const Color borderSpecular = Color(0x28FFFFFF);

  static const List<Color> presets = [
    neonPink,
    electricCyan,
    neonPurple,
    electricBlue,
    neonGreen,
    amberGold,
    Colors.white,
  ];

  static String toHex(Color color) {
    final rgb = color.value & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  static Color fromHex(String? hex, {Color fallback = neonPink}) {
    if (hex == null || hex.isEmpty) return fallback;
    try {
      final clean = hex.replaceFirst('#', '').trim();
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }
      if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {}
    return fallback;
  }
}

/// Consistent motion choreography timings & curves across Ghost Touch.
class GhostMotion {
  static const Duration microTap = Duration(milliseconds: 160);
  static const Duration cardEntrance = Duration(milliseconds: 420);
  static const Duration hologramReveal = Duration(milliseconds: 650);
  static const Duration heartbeatCycle = Duration(milliseconds: 1150);
  static const Duration gentleFloat = Duration(milliseconds: 2600);
  static const Duration smoothFadeOut = Duration(milliseconds: 340);

  static const Curve entranceCurve = Curves.easeOutCubic;
  static const Curve springCurve = Curves.elasticOut;
  static const Curve pulseCurve = Curves.easeInOutSine;
}

/// Reusable frosted glassmorphic card with optional blur & soft category glow.
class GhostGlassCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool reducedMotion;
  final double glowOpacity;
  final double? blurSigma;
  final List<Color>? gradientColors;

  const GhostGlassCard({
    super.key,
    required this.child,
    this.accentColor = GhostPalette.electricCyan,
    this.borderRadius = 22,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.reducedMotion = false,
    this.glowOpacity = 0.22,
    this.blurSigma = 14,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ??
        [
          accentColor.withOpacity(0.14),
          GhostPalette.darkViolet.withOpacity(0.86),
          GhostPalette.deepSpace.withOpacity(0.92),
        ];

    final core = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: accentColor.withOpacity(0.42),
          width: 1.25,
        ),
      ),
      child: child,
    );

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(glowOpacity.clamp(0.0, 0.7)),
            blurRadius: reducedMotion ? 10 : 22,
            spreadRadius: reducedMotion ? 0 : 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: (!reducedMotion && (blurSigma ?? 0) > 0)
            ? BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: blurSigma!,
                  sigmaY: blurSigma!,
                ),
                child: core,
              )
            : core,
      ),
    );
  }
}
