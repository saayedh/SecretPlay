import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'ghost_sticker_catalog.dart';

/// Animated original vector artwork widget for any [GhostStickerDef].
/// Pass [sharedAnimation] when rendering inside a dense grid so all tiles share one Ticker.
class GhostStickerArtwork extends StatefulWidget {
  final GhostStickerDef sticker;
  final double size;
  final Animation<double>? sharedAnimation;
  final bool reducedMotion;
  final double intensity;

  const GhostStickerArtwork({
    super.key,
    required this.sticker,
    this.size = 72,
    this.sharedAnimation,
    this.reducedMotion = false,
    this.intensity = 1.0,
  });

  @override
  State<GhostStickerArtwork> createState() => _GhostStickerArtworkState();
}

class _GhostStickerArtworkState extends State<GhostStickerArtwork>
    with SingleTickerProviderStateMixin {
  AnimationController? _localController;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant GhostStickerArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sharedAnimation != widget.sharedAnimation ||
        oldWidget.reducedMotion != widget.reducedMotion) {
      _syncController();
    }
  }

  void _syncController() {
    if (widget.sharedAnimation != null || widget.reducedMotion) {
      _localController?.dispose();
      _localController = null;
      return;
    }
    _localController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _localController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = widget.sharedAnimation ?? _localController;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: anim == null
            ? CustomPaint(
                painter: GhostStickerPainter(
                  sticker: widget.sticker,
                  progress: 0.25,
                  intensity: widget.intensity,
                  reducedMotion: true,
                ),
              )
            : AnimatedBuilder(
                animation: anim,
                builder: (_, __) => CustomPaint(
                  painter: GhostStickerPainter(
                    sticker: widget.sticker,
                    progress: anim.value,
                    intensity: widget.intensity,
                    reducedMotion: widget.reducedMotion,
                  ),
                ),
              ),
      ),
    );
  }
}

class GhostStickerPainter extends CustomPainter {
  final GhostStickerDef sticker;
  final double progress;
  final double intensity;
  final bool reducedMotion;

  const GhostStickerPainter({
    required this.sticker,
    required this.progress,
    this.intensity = 1.0,
    this.reducedMotion = false,
  });

  double get _phase => progress * math.pi * 2;
  double get _pulse => 0.5 + 0.5 * math.sin(_phase);
  double get _beat {
    // Classic double lub-dub curve
    final t = progress;
    if (t < 0.16) return math.sin(t / 0.16 * math.pi) * 0.16;
    if (t >= 0.22 && t < 0.40) return math.sin((t - 0.22) / 0.18 * math.pi) * 0.22;
    return 0.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) * 0.42;
    final p1 = sticker.primaryColor;
    final p2 = sticker.secondaryColor;

    // Ambient holographic aura
    if (!reducedMotion && intensity > 0.25) {
      final auraPaint = Paint()
        ..shader = ui.Gradient.radial(
          c,
          r * (1.15 + _pulse * 0.18),
          [p1.withOpacity(0.28 * intensity), p2.withOpacity(0.08 * intensity), Colors.transparent],
          const [0.0, 0.55, 1.0],
        );
      canvas.drawCircle(c, r * 1.25, auraPaint);
    }

    canvas.save();
    _applyRootMotionTransform(canvas, c, r);
    _paintMotif(canvas, size, c, r, p1, p2);
    canvas.restore();
  }

  void _applyRootMotionTransform(Canvas canvas, Offset c, double r) {
    if (reducedMotion) return;
    switch (sticker.animType) {
      case GhostStickerAnimType.heartbeat:
        final sc = 0.96 + _beat * 0.85;
        canvas.translate(c.dx, c.dy);
        canvas.scale(sc, sc);
        canvas.translate(-c.dx, -c.dy);
        break;
      case GhostStickerAnimType.floatDrift:
        canvas.translate(
          math.sin(_phase) * r * 0.04,
          math.cos(_phase) * r * 0.08,
        );
        break;
      case GhostStickerAnimType.cuteBounce:
        final bounce = math.sin(_phase * 2).abs();
        canvas.translate(0, -bounce * r * 0.09);
        canvas.translate(c.dx, c.dy);
        canvas.scale(1.0 + (1 - bounce) * 0.05, 1.0 - (1 - bounce) * 0.04);
        canvas.translate(-c.dx, -c.dy);
        break;
      case GhostStickerAnimType.liquidMorph:
        final sx = 1.0 + math.sin(_phase) * 0.05;
        final sy = 1.0 + math.cos(_phase) * 0.05;
        canvas.translate(c.dx, c.dy);
        canvas.scale(sx, sy);
        canvas.translate(-c.dx, -c.dy);
        break;
      default:
        break;
    }
  }

  void _paintMotif(Canvas canvas, Size size, Offset c, double r, Color p1, Color p2) {
    switch (sticker.motif) {
      // ================== A. LOVE & EMOTION ==================
      case StickerMotif.glowingHeart:
        _drawEnergyRings(canvas, c, r, p1, p2, count: 2);
        _drawGradientHeart(canvas, c, r * 0.78, p1, p2, glow: true);
        _drawSparkles(canvas, c, r * 1.02, p2, 4);
        break;

      case StickerMotif.doubleFloatingHearts:
        _drawGradientHeart(
          canvas,
          c.translate(-r * 0.22, r * 0.08 + math.sin(_phase) * 3),
          r * 0.56,
          p2,
          p1,
          glow: true,
        );
        _drawGradientHeart(
          canvas,
          c.translate(r * 0.24, -r * 0.14 - math.sin(_phase) * 3),
          r * 0.48,
          p1,
          Colors.white,
          glow: true,
        );
        break;

      case StickerMotif.beatingHeart:
        final waveR = r * (0.72 + progress * 0.55);
        canvas.drawPath(
          _heartPath(c, waveR),
          Paint()
            ..color = p1.withOpacity((1.0 - progress).clamp(0.0, 0.7))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2,
        );
        _drawGradientHeart(canvas, c, r * 0.78, p1, p2, glow: true);
        _drawEcgTrace(canvas, c.translate(0, r * 0.04), r * 0.9, Colors.white, progress);
        break;

      case StickerMotif.brokenHeartLight:
        _drawGradientHeart(canvas, c, r * 0.78, p2.withOpacity(0.85), p1.withOpacity(0.4), glow: true);
        // Glowing golden-cyan kintsugi lightning seam
        final seam = Path()
          ..moveTo(c.dx, c.dy - r * 0.28)
          ..lineTo(c.dx - r * 0.12, c.dy - r * 0.04)
          ..lineTo(c.dx + r * 0.12, c.dy + r * 0.10)
          ..lineTo(c.dx - r * 0.02, c.dy + r * 0.42);
        canvas.drawPath(
          seam,
          Paint()
            ..color = p1.withOpacity(0.55 + _pulse * 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.14
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        canvas.drawPath(
          seam,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
        _drawSparkles(canvas, c, r * 0.5, p1, 3);
        break;

      case StickerMotif.starHaloHeart:
        _drawGradientHeart(canvas, c.translate(0, r * 0.04), r * 0.68, p1, p2, glow: true);
        for (int i = 0; i < 6; i++) {
          final a = _phase * 0.5 + i * (math.pi / 3);
          final pos = Offset(c.dx + math.cos(a) * r * 0.88, c.dy + math.sin(a) * r * 0.82);
          _drawStar(canvas, pos, r * (0.11 + 0.04 * math.sin(_phase + i)), 4, p2);
        }
        break;

      case StickerMotif.orbitParticlesHeart:
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-0.35);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r * 2.1, height: r * 0.72),
          Paint()
            ..color = p2.withOpacity(0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
        canvas.restore();
        _drawGradientHeart(canvas, c, r * 0.68, p1, p2, glow: true);
        for (int i = 0; i < 4; i++) {
          final a = _phase + i * (math.pi / 2);
          final px = math.cos(a) * r * 1.02;
          final py = math.sin(a) * r * 0.34;
          const rot = -0.35;
          final ox = px * math.cos(rot) - py * math.sin(rot);
          final oy = px * math.sin(rot) + py * math.cos(rot);
          canvas.drawCircle(c.translate(ox, oy), r * 0.08, Paint()..color = p2);
        }
        break;

      case StickerMotif.infinityHeart:
        final inf = Path();
        for (int i = 0; i <= 48; i++) {
          final a = (i / 48) * math.pi * 2;
          final denom = 1 + math.sin(a) * math.sin(a);
          final x = c.dx + (r * 0.95 * math.cos(a)) / denom;
          final y = c.dy + (r * 0.85 * math.sin(a) * math.cos(a)) / denom;
          if (i == 0) {
            inf.moveTo(x, y);
          } else {
            inf.lineTo(x, y);
          }
        }
        inf.close();
        canvas.drawPath(
          inf,
          Paint()
            ..color = p1.withOpacity(0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.16
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        canvas.drawPath(
          inf,
          Paint()
            ..shader = ui.Gradient.linear(
              c.translate(-r, 0),
              c.translate(r, 0),
              [p1, p2, Colors.white, p1],
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.09,
        );
        _drawGradientHeart(canvas, c.translate(0, -r * 0.06), r * 0.36, p2, Colors.white, glow: true);
        break;

      case StickerMotif.crystalHeart:
        _drawCrystalHeart(canvas, c, r * 0.82, p1, p2);
        _drawSparkles(canvas, c, r * 0.95, Colors.white, 4);
        break;

      case StickerMotif.glassHeart:
        final hp = _heartPath(c, r * 0.80);
        canvas.drawPath(
          hp,
          Paint()
            ..shader = ui.Gradient.linear(
              c.translate(-r, -r),
              c.translate(r, r),
              [p1.withOpacity(0.48), p2.withOpacity(0.22), Colors.white.withOpacity(0.18)],
            ),
        );
        canvas.drawPath(
          hp,
          Paint()
            ..color = Colors.white.withOpacity(0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
        // Glossy crescent reflection
        canvas.drawArc(
          Rect.fromCenter(center: c.translate(-r * 0.25, -r * 0.18), width: r * 0.42, height: r * 0.34),
          math.pi * 1.1,
          math.pi * 0.6,
          false,
          Paint()
            ..color = Colors.white.withOpacity(0.7)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 3.0,
        );
        break;

      case StickerMotif.liquidHeart:
        final wobble = 1.0 + 0.06 * math.sin(_phase * 2);
        canvas.drawPath(
          _heartPath(c.translate(math.sin(_phase) * 3, 0), r * 0.84 * wobble),
          Paint()..color = p2.withOpacity(0.45),
        );
        _drawGradientHeart(canvas, c, r * 0.78, p1, p2, glow: true);
        canvas.drawCircle(
          c.translate(r * 0.56, -r * 0.48 + math.sin(_phase) * 4),
          r * 0.11,
          Paint()..color = p1,
        );
        canvas.drawCircle(
          c.translate(-r * 0.62, r * 0.28 - math.cos(_phase) * 4),
          r * 0.08,
          Paint()..color = p2,
        );
        break;

      case StickerMotif.pinkHoloHeart:
        _drawGradientHeart(canvas, c, r * 0.8, p1, p2, glow: true);
        // Holographic scanlines
        canvas.save();
        canvas.clipPath(_heartPath(c, r * 0.8));
        final linePaint = Paint()
          ..color = Colors.white.withOpacity(0.28)
          ..strokeWidth = 1.5;
        final offset = (progress * 18) % 8;
        for (double y = c.dy - r; y < c.dy + r; y += 8) {
          canvas.drawLine(Offset(c.dx - r, y + offset), Offset(c.dx + r, y + offset), linePaint);
        }
        canvas.restore();
        break;

      case StickerMotif.constellationHeart:
        final pts = [
          c.translate(0, -r * 0.22),
          c.translate(-r * 0.36, -r * 0.52),
          c.translate(-r * 0.72, -r * 0.18),
          c.translate(-r * 0.48, r * 0.26),
          c.translate(0, r * 0.68),
          c.translate(r * 0.48, r * 0.26),
          c.translate(r * 0.72, -r * 0.18),
          c.translate(r * 0.36, -r * 0.52),
        ];
        final lineP = Paint()
          ..color = p1.withOpacity(0.65)
          ..strokeWidth = 1.6;
        for (int i = 0; i < pts.length; i++) {
          canvas.drawLine(pts[i], pts[(i + 1) % pts.length], lineP);
        }
        for (int i = 0; i < pts.length; i++) {
          final tw = 0.7 + 0.5 * math.sin(_phase + i);
          _drawStar(canvas, pts[i], r * 0.11 * tw, 4, i.isEven ? Colors.white : p2);
        }
        break;

      case StickerMotif.wingedHeart:
        final flap = math.sin(_phase * 2) * 0.22;
        for (final side in [-1.0, 1.0]) {
          canvas.save();
          canvas.translate(c.dx + side * r * 0.28, c.dy - r * 0.05);
          canvas.rotate(side * flap);
          final wing = Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(side * r * 0.65, -r * 0.62, side * r * 0.92, -r * 0.22)
            ..quadraticBezierTo(side * r * 0.72, 0, side * r * 0.80, r * 0.12)
            ..quadraticBezierTo(side * r * 0.52, r * 0.18, side * r * 0.62, r * 0.32)
            ..quadraticBezierTo(side * r * 0.26, r * 0.28, 0, r * 0.18)
            ..close();
          canvas.drawPath(
            wing,
            Paint()
              ..shader = ui.Gradient.linear(
                Offset.zero,
                Offset(side * r * 0.8, 0),
                [Colors.white.withOpacity(0.92), p1.withOpacity(0.45)],
              ),
          );
          canvas.restore();
        }
        _drawGradientHeart(canvas, c, r * 0.56, p1, p2, glow: true);
        break;

      case StickerMotif.floatingRose:
        // Stem & leaf
        canvas.drawLine(
          c.translate(0, r * 0.15),
          c.translate(0, r * 0.85),
          Paint()
            ..color = p2
            ..strokeWidth = 3.2
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawOval(
          Rect.fromCenter(center: c.translate(r * 0.22, r * 0.56), width: r * 0.38, height: r * 0.18),
          Paint()..color = p2.withOpacity(0.85),
        );
        // Layered rose petals
        for (int layer = 3; layer >= 1; layer--) {
          final pr = r * (0.20 + layer * 0.13);
          for (int k = 0; k < 5; k++) {
            final a = k * (math.pi * 2 / 5) + layer * 0.4 + _phase * 0.15;
            final center = c.translate(math.cos(a) * pr * 0.35, -r * 0.15 + math.sin(a) * pr * 0.35);
            canvas.drawCircle(
              center,
              pr * 0.52,
              Paint()
                ..color = Color.lerp(p1, Colors.white, (3 - layer) * 0.18)!.withOpacity(0.85),
            );
          }
        }
        canvas.drawCircle(c.translate(0, -r * 0.15), r * 0.16, Paint()..color = p1);
        break;

      case StickerMotif.glowingBlossom:
        for (int i = 0; i < 6; i++) {
          final a = i * (math.pi / 3) + _phase * 0.25;
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(a);
          canvas.drawOval(
            Rect.fromCenter(center: Offset(0, -r * 0.48), width: r * 0.44, height: r * 0.72),
            Paint()
              ..shader = ui.Gradient.linear(
                Offset(0, -r * 0.82),
                Offset.zero,
                [p1, p2.withOpacity(0.75)],
              ),
          );
          canvas.restore();
        }
        canvas.drawCircle(c, r * 0.22, Paint()..color = p2);
        canvas.drawCircle(c, r * 0.11, Paint()..color = Colors.white);
        break;

      case StickerMotif.neonButterflies:
        _drawButterfly(canvas, c.translate(-r * 0.22, -r * 0.12), r * 0.56, p1, p2, _phase * 2);
        _drawButterfly(canvas, c.translate(r * 0.34, r * 0.26), r * 0.36, p2, p1, _phase * 2 + 1.0);
        break;

      case StickerMotif.heartGalaxy:
        _drawGalaxySpiral(canvas, c, r * 0.96, p2, p1);
        _drawGradientHeart(canvas, c, r * 0.50, p1, Colors.white, glow: true);
        break;

      case StickerMotif.coupleHearts:
        final angle = _phase * 0.5;
        final o1 = c.translate(math.cos(angle) * r * 0.30, math.sin(angle) * r * 0.18);
        final o2 = c.translate(math.cos(angle + math.pi) * r * 0.30, math.sin(angle + math.pi) * r * 0.18);
        _drawGradientHeart(canvas, o1, r * 0.48, p1, Colors.white, glow: true);
        _drawGradientHeart(canvas, o2, r * 0.48, p2, Colors.white, glow: true);
        break;

      // ================== B. COSMIC & SPACE ==================
      case StickerMotif.ringedPlanet:
        // Back half ring
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-0.35);
        canvas.drawArc(
          Rect.fromCenter(center: Offset.zero, width: r * 2.15, height: r * 0.64),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = p2.withOpacity(0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.14,
        );
        canvas.restore();
        canvas.drawCircle(
          c,
          r * 0.58,
          Paint()
            ..shader = ui.Gradient.linear(
              c.translate(-r * 0.5, -r * 0.5),
              c.translate(r * 0.5, r * 0.5),
              [p2, p1, const Color(0xFF0A1026)],
            ),
        );
        // Front ring
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-0.35);
        canvas.drawArc(
          Rect.fromCenter(center: Offset.zero, width: r * 2.15, height: r * 0.64),
          0,
          math.pi,
          false,
          Paint()
            ..color = Colors.white.withOpacity(0.88)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.10,
        );
        canvas.restore();
        // Orbiting moonlet
        canvas.drawCircle(
          c.translate(math.cos(_phase) * r * 0.92, math.sin(_phase) * r * 0.32),
          r * 0.10,
          Paint()..color = p2,
        );
        break;

      case StickerMotif.crescentMoon:
        final moonPath = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: c, radius: r * 0.72)),
          Path()..addOval(Rect.fromCircle(center: c.translate(r * 0.32, -r * 0.16), radius: r * 0.58)),
        );
        canvas.drawPath(
          moonPath,
          Paint()
            ..shader = ui.Gradient.linear(c.translate(-r, -r), c.translate(r, r), [p1, Colors.white, p2]),
        );
        _drawSparkles(canvas, c.translate(r * 0.35, -r * 0.25), r * 0.45, p1, 3);
        break;

      case StickerMotif.shootingStar:
        final fly = (progress * 1.2) % 1.0;
        final starPos = Offset(
          c.dx - r * 0.55 + fly * r * 1.1,
          c.dy + r * 0.45 - fly * r * 0.9,
        );
        canvas.drawLine(
          starPos,
          starPos.translate(-r * 0.85, r * 0.65),
          Paint()
            ..shader = ui.Gradient.linear(starPos, starPos.translate(-r * 0.85, r * 0.65), [p2, p1, Colors.transparent])
            ..strokeWidth = r * 0.18
            ..strokeCap = StrokeCap.round,
        );
        _drawStar(canvas, starPos, r * 0.28, 5, p2);
        _drawStar(canvas, starPos, r * 0.14, 5, Colors.white);
        break;

      case StickerMotif.galaxyPortal:
      case StickerMotif.celebrationPortal:
        _drawEnergyRings(canvas, c, r, p1, p2, count: 4);
        _drawGalaxySpiral(canvas, c, r * 0.75, p1, p2);
        canvas.drawCircle(c, r * 0.18, Paint()..color = Colors.white);
        break;

      case StickerMotif.nebulaCloud:
        for (int i = 0; i < 4; i++) {
          final a = i * 1.6 + _phase * 0.3;
          final offset = c.translate(math.cos(a) * r * 0.32, math.sin(a) * r * 0.24);
          canvas.drawCircle(
            offset,
            r * (0.45 + 0.08 * math.sin(_phase + i)),
            Paint()
              ..shader = ui.Gradient.radial(
                offset,
                r * 0.55,
                [(i.isEven ? p1 : p2).withOpacity(0.55), Colors.transparent],
              ),
          );
        }
        _drawSparkles(canvas, c, r * 0.8, Colors.white, 6);
        break;

      case StickerMotif.miniGalaxy:
        _drawGalaxySpiral(canvas, c, r * 0.98, p1, p2);
        _drawSparkles(canvas, c, r * 0.9, Colors.white, 5);
        break;

      case StickerMotif.cosmicStarHeart:
        _drawGradientHeart(canvas, c, r * 0.70, p1, p2, glow: true);
        _drawStar(canvas, c, r * 0.30, 4, Colors.white);
        _drawSparkles(canvas, c, r * 0.95, p2, 4);
        break;

      case StickerMotif.orbitingSatellite:
        canvas.drawCircle(
          c,
          r * 0.85,
          Paint()
            ..color = p1.withOpacity(0.32)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        canvas.drawCircle(c, r * 0.28, Paint()..color = p1.withOpacity(0.45));
        final a = _phase;
        final sat = c.translate(math.cos(a) * r * 0.82, math.sin(a) * r * 0.82);
        canvas.save();
        canvas.translate(sat.dx, sat.dy);
        canvas.rotate(a + math.pi / 4);
        // Solar wings + body
        canvas.drawRect(Rect.fromCenter(center: Offset(-r * 0.22, 0), width: r * 0.24, height: r * 0.14), Paint()..color = p1);
        canvas.drawRect(Rect.fromCenter(center: Offset(r * 0.22, 0), width: r * 0.24, height: r * 0.14), Paint()..color = p1);
        canvas.drawCircle(Offset.zero, r * 0.11, Paint()..color = Colors.white);
        canvas.restore();
        break;

      case StickerMotif.auroraCurtain:
        for (int wave = 0; wave < 3; wave++) {
          final path = Path();
          final yBase = c.dy - r * 0.2 + wave * r * 0.22;
          path.moveTo(c.dx - r * 0.95, yBase);
          for (double x = -0.95; x <= 0.95; x += 0.15) {
            final y = yBase + math.sin(x * 3.5 + _phase + wave) * r * 0.18;
            path.lineTo(c.dx + x * r, y);
          }
          canvas.drawPath(
            path,
            Paint()
              ..color = (wave == 0 ? p1 : (wave == 1 ? p2 : Colors.white)).withOpacity(0.65)
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = r * 0.18
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
        }
        _drawSparkles(canvas, c.translate(0, -r * 0.2), r * 0.9, Colors.white, 4);
        break;

      case StickerMotif.sparklingConstellation:
        final nodes = [
          c.translate(-r * 0.70, r * 0.20),
          c.translate(-r * 0.28, -r * 0.45),
          c.translate(r * 0.15, -r * 0.10),
          c.translate(r * 0.65, -r * 0.55),
          c.translate(r * 0.50, r * 0.42),
        ];
        final lp = Paint()
          ..color = p2.withOpacity(0.5)
          ..strokeWidth = 1.6;
        for (int i = 0; i < nodes.length - 1; i++) {
          canvas.drawLine(nodes[i], nodes[i + 1], lp);
        }
        for (int i = 0; i < nodes.length; i++) {
          _drawStar(canvas, nodes[i], r * (0.14 + 0.04 * math.sin(_phase + i)), 4, i.isEven ? p1 : Colors.white);
        }
        break;

      // ================== C. CYBERPUNK ==================
      case StickerMotif.cyberHoloEmblem:
        _drawPolygon(canvas, c, r * 0.85, 6, _phase * 0.2, p1, strokeWidth: 2.8);
        _drawPolygon(canvas, c, r * 0.58, 6, -_phase * 0.35, p2, strokeWidth: 2.2);
        _drawStar(canvas, c, r * 0.30, 4, Colors.white);
        break;

      case StickerMotif.energyPortal:
        _drawEnergyRings(canvas, c, r, p1, p2, count: 4);
        _drawLightningBolt(canvas, c, r * 0.55, p1, Colors.white);
        break;

      case StickerMotif.digitalCircuitHeart:
        canvas.drawPath(
          _heartPath(c, r * 0.80),
          Paint()
            ..color = p1.withOpacity(0.18)
            ..style = PaintingStyle.fill,
        );
        canvas.drawPath(
          _heartPath(c, r * 0.80),
          Paint()
            ..color = p1
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6,
        );
        // Circuit traces
        canvas.drawLine(c.translate(-r * 0.4, 0), c.translate(-r * 0.12, 0), Paint()..color = p2..strokeWidth = 2);
        canvas.drawLine(c.translate(r * 0.12, 0), c.translate(r * 0.4, 0), Paint()..color = p2..strokeWidth = 2);
        canvas.drawCircle(c, r * 0.14, Paint()..color = Colors.white);
        canvas.drawCircle(c.translate(-r * 0.4, 0), r * 0.06, Paint()..color = p2);
        canvas.drawCircle(c.translate(r * 0.4, 0), r * 0.06, Paint()..color = p2);
        break;

      case StickerMotif.glowingCrystalShard:
        final poly = Path()
          ..moveTo(c.dx, c.dy - r * 0.92)
          ..lineTo(c.dx + r * 0.48, c.dy - r * 0.18)
          ..lineTo(c.dx + r * 0.30, c.dy + r * 0.82)
          ..lineTo(c.dx, c.dy + r * 0.95)
          ..lineTo(c.dx - r * 0.30, c.dy + r * 0.82)
          ..lineTo(c.dx - r * 0.48, c.dy - r * 0.18)
          ..close();
        canvas.drawPath(
          poly,
          Paint()..shader = ui.Gradient.linear(c.translate(-r, -r), c.translate(r, r), [Colors.white, p2, p1]),
        );
        canvas.drawLine(c.translate(0, -r * 0.92), c.translate(0, r * 0.95), Paint()..color = Colors.white.withOpacity(0.65)..strokeWidth = 1.6);
        break;

      case StickerMotif.electricLightning:
        _drawEnergyRings(canvas, c, r * 0.92, p2, p1, count: 2);
        _drawLightningBolt(canvas, c, r * 0.95, p1, p2);
        break;

      case StickerMotif.gyroHoloRings:
        for (int i = 0; i < 3; i++) {
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(_phase * (i.isEven ? 0.5 : -0.4) + i * 1.0);
          canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: r * 1.8, height: r * (0.65 + i * 0.25)),
            Paint()
              ..color = (i.isEven ? p1 : p2)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6,
          );
          canvas.restore();
        }
        canvas.drawCircle(c, r * 0.22 * (0.85 + 0.3 * _pulse), Paint()..color = Colors.white);
        break;

      case StickerMotif.signalBeacon:
        for (int i = 0; i < 3; i++) {
          final rp = ((progress + i * 0.33) % 1.0);
          canvas.drawArc(
            Rect.fromCenter(center: c.translate(0, r * 0.2), width: r * 2.0 * rp, height: r * 2.0 * rp),
            -math.pi * 0.85,
            math.pi * 0.70,
            false,
            Paint()
              ..color = p1.withOpacity((1.0 - rp).clamp(0.0, 0.9))
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.0
              ..strokeCap = StrokeCap.round,
          );
        }
        canvas.drawCircle(c.translate(0, r * 0.2), r * 0.16, Paint()..color = Colors.white);
        canvas.drawLine(
          c.translate(0, r * 0.2),
          c.translate(0, r * 0.72),
          Paint()
            ..color = p2
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round,
        );
        break;

      case StickerMotif.morphingPrism:
        final sides = 3 + ((progress * 4).floor() % 4);
        _drawPolygon(canvas, c, r * 0.82, sides, _phase * 0.4, p1, filled: true, secondary: p2);
        _drawPolygon(canvas, c, r * 0.45, sides, -_phase * 0.4, Colors.white, strokeWidth: 2.0);
        break;

      case StickerMotif.digitalWaveform:
        const bars = 9;
        for (int i = 0; i < bars; i++) {
          final x = c.dx - r * 0.8 + i * (r * 1.6 / (bars - 1));
          final amp = 0.25 + 0.75 * math.sin(_phase + i * 0.85).abs();
          final h = r * 0.85 * amp;
          canvas.drawLine(
            Offset(x, c.dy - h),
            Offset(x, c.dy + h),
            Paint()
              ..color = Color.lerp(p1, p2, i / (bars - 1))!
              ..strokeWidth = r * 0.11
              ..strokeCap = StrokeCap.round,
          );
        }
        break;

      case StickerMotif.energyExplosion:
        _drawBurstRays(canvas, c, r, p1, p2, 12);
        canvas.drawCircle(c, r * 0.25, Paint()..color = Colors.white);
        break;

      // ================== D. CUTE & PLAYFUL ==================
      case StickerMotif.blushSpirit:
        _drawCuteCircleCreature(canvas, c, r * 0.78, p1, blush: true, eyes: 'happy', mouth: 'smile');
        _drawSparkles(canvas, c, r * 1.0, p1, 3);
        break;

      case StickerMotif.happyStarBuddy:
        _drawStar(canvas, c, r * 0.88, 5, p1);
        _drawCuteFace(canvas, c.translate(0, r * 0.05), r * 0.48, blushColor: p2, eyes: 'open', mouth: 'grin');
        break;

      case StickerMotif.sleepyCloud:
        final cloudColor = p1;
        canvas.drawCircle(c.translate(-r * 0.38, r * 0.05), r * 0.34, Paint()..color = cloudColor);
        canvas.drawCircle(c.translate(r * 0.38, r * 0.05), r * 0.34, Paint()..color = cloudColor);
        canvas.drawCircle(c.translate(0, -r * 0.18), r * 0.45, Paint()..color = cloudColor);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c.translate(0, r * 0.18), width: r * 1.15, height: r * 0.42),
            Radius.circular(r * 0.21),
          ),
          Paint()..color = cloudColor,
        );
        _drawCuteFace(canvas, c.translate(0, r * 0.06), r * 0.48, blushColor: p2, eyes: 'closed', mouth: 'tiny');
        break;

      case StickerMotif.winkNeonCat:
        // Cat ears
        final ears = Path()
          ..moveTo(c.dx - r * 0.60, c.dy - r * 0.15)
          ..lineTo(c.dx - r * 0.58, c.dy - r * 0.85)
          ..lineTo(c.dx - r * 0.15, c.dy - r * 0.55)
          ..moveTo(c.dx + r * 0.60, c.dy - r * 0.15)
          ..lineTo(c.dx + r * 0.58, c.dy - r * 0.85)
          ..lineTo(c.dx + r * 0.15, c.dy - r * 0.55);
        canvas.drawPath(ears, Paint()..color = p1..style = PaintingStyle.stroke..strokeWidth = 3.2..strokeJoin = StrokeJoin.round);
        canvas.drawCircle(c, r * 0.68, Paint()..color = const Color(0xFF15192E));
        canvas.drawCircle(c, r * 0.68, Paint()..color = p1..style = PaintingStyle.stroke..strokeWidth = 2.8);
        _drawCuteFace(canvas, c, r * 0.55, blushColor: p2, eyes: 'wink', mouth: 'smile');
        break;

      case StickerMotif.loveBunny:
        for (final side in [-1.0, 1.0]) {
          canvas.save();
          canvas.translate(c.dx + side * r * 0.25, c.dy - r * 0.45);
          canvas.rotate(side * 0.18 + math.sin(_phase) * 0.05);
          canvas.drawOval(
            Rect.fromCenter(center: Offset(0, -r * 0.35), width: r * 0.26, height: r * 0.68),
            Paint()..color = p2,
          );
          canvas.drawOval(
            Rect.fromCenter(center: Offset(0, -r * 0.35), width: r * 0.13, height: r * 0.46),
            Paint()..color = p1,
          );
          canvas.restore();
        }
        canvas.drawCircle(c.translate(0, r * 0.12), r * 0.62, Paint()..color = p2);
        _drawCuteFace(canvas, c.translate(0, r * 0.12), r * 0.50, blushColor: p1, eyes: 'happy', mouth: 'smile');
        break;

      case StickerMotif.shyGhost:
        final g = Path()
          ..moveTo(c.dx - r * 0.58, c.dy + r * 0.62)
          ..lineTo(c.dx - r * 0.58, c.dy - r * 0.12)
          ..arcToPoint(Offset(c.dx + r * 0.58, c.dy - r * 0.12), radius: Radius.circular(r * 0.58))
          ..lineTo(c.dx + r * 0.58, c.dy + r * 0.62)
          ..quadraticBezierTo(c.dx + r * 0.35, c.dy + r * 0.42, c.dx + r * 0.18, c.dy + r * 0.62)
          ..quadraticBezierTo(c.dx, c.dy + r * 0.42, c.dx - r * 0.18, c.dy + r * 0.62)
          ..quadraticBezierTo(c.dx - r * 0.35, c.dy + r * 0.42, c.dx - r * 0.58, c.dy + r * 0.62)
          ..close();
        canvas.drawPath(g, Paint()..shader = ui.Gradient.linear(c.translate(0, -r), c.translate(0, r), [p1, p2]));
        _drawCuteFace(canvas, c.translate(0, -r * 0.05), r * 0.46, blushColor: const Color(0xFFFF6EC7), eyes: 'open', mouth: 'tiny');
        break;

      case StickerMotif.smilingFlower:
        for (int i = 0; i < 6; i++) {
          final a = i * (math.pi / 3) + _phase * 0.15;
          canvas.drawCircle(
            c.translate(math.cos(a) * r * 0.48, math.sin(a) * r * 0.48),
            r * 0.32,
            Paint()..color = p1.withOpacity(0.88),
          );
        }
        canvas.drawCircle(c, r * 0.44, Paint()..color = p2);
        _drawCuteFace(canvas, c, r * 0.38, blushColor: const Color(0xFFFF4D8D), eyes: 'happy', mouth: 'grin');
        break;

      case StickerMotif.heartCharacter:
        _drawGradientHeart(canvas, c, r * 0.85, p1, p2, glow: true);
        _drawCuteFace(canvas, c.translate(0, -r * 0.08), r * 0.46, blushColor: Colors.white, eyes: 'happy', mouth: 'grin');
        break;

      case StickerMotif.laughingSpark:
        _drawBurstRays(canvas, c, r * 0.92, p1, p2, 8);
        canvas.drawCircle(c, r * 0.55, Paint()..color = p1);
        _drawCuteFace(canvas, c, r * 0.48, blushColor: p2, eyes: 'closed', mouth: 'grin');
        break;

      case StickerMotif.partyCreature:
        canvas.drawCircle(c.translate(0, r * 0.1), r * 0.64, Paint()..shader = ui.Gradient.linear(c.translate(-r, -r), c.translate(r, r), [p1, p2]));
        // Party cone hat
        final hat = Path()
          ..moveTo(c.dx - r * 0.25, c.dy - r * 0.48)
          ..lineTo(c.dx + r * 0.05, c.dy - r * 0.98)
          ..lineTo(c.dx + r * 0.32, c.dy - r * 0.48)
          ..close();
        canvas.drawPath(hat, Paint()..color = const Color(0xFFFFC857));
        _drawCuteFace(canvas, c.translate(0, r * 0.1), r * 0.48, blushColor: const Color(0xFFFF3D9A), eyes: 'happy', mouth: 'grin');
        break;

      // ================== E. PRESENCE & SECRET SIGNALS ==================
      case StickerMotif.onlineRadarBeacon:
        for (int i = 0; i < 3; i++) {
          final rp = ((progress + i * 0.33) % 1.0);
          canvas.drawCircle(
            c,
            r * (0.28 + rp * 0.72),
            Paint()
              ..color = p1.withOpacity((1.0 - rp).clamp(0.0, 0.85))
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6,
          );
        }
        canvas.drawCircle(c, r * 0.30, Paint()..color = p1);
        canvas.drawCircle(c, r * 0.14, Paint()..color = Colors.white);
        break;

      case StickerMotif.thinkingOfYouOrb:
        canvas.drawCircle(
          c,
          r * 0.62,
          Paint()
            ..shader = ui.Gradient.radial(c, r * 0.65, [Colors.white.withOpacity(0.55), p1, p2.withOpacity(0.35)]),
        );
        _drawEnergyRings(canvas, c, r, p2, p1, count: 2);
        _drawGradientHeart(canvas, c, r * 0.32, Colors.white, p2, glow: true);
        break;

      case StickerMotif.imHereShield:
        final shield = Path()
          ..moveTo(c.dx, c.dy - r * 0.85)
          ..lineTo(c.dx + r * 0.68, c.dy - r * 0.48)
          ..quadraticBezierTo(c.dx + r * 0.68, c.dy + r * 0.35, c.dx, c.dy + r * 0.88)
          ..quadraticBezierTo(c.dx - r * 0.68, c.dy + r * 0.35, c.dx - r * 0.68, c.dy - r * 0.48)
          ..close();
        canvas.drawPath(shield, Paint()..shader = ui.Gradient.linear(c.translate(0, -r), c.translate(0, r), [p1.withOpacity(0.55), p2.withOpacity(0.25)]));
        canvas.drawPath(shield, Paint()..color = p1..style = PaintingStyle.stroke..strokeWidth = 2.6);
        _drawGradientHeart(canvas, c.translate(0, -r * 0.04), r * 0.34, Colors.white, p2, glow: false);
        break;

      case StickerMotif.missYouHalo:
        _drawEnergyRings(canvas, c, r, p1, p2, count: 3);
        _drawGradientHeart(canvas, c, r * 0.72, p1, p2, glow: true);
        break;

      case StickerMotif.positiveEnergyCoil:
        _drawBurstRays(canvas, c, r * 0.95, p1, p2, 10);
        canvas.drawCircle(c, r * 0.46, Paint()..shader = ui.Gradient.radial(c, r * 0.46, [Colors.white, p1, p2]));
        break;

      case StickerMotif.littleSurpriseBox:
      case StickerMotif.glowingGiftRibbon:
        final boxRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: c.translate(0, r * 0.14), width: r * 1.15, height: r * 0.95),
          Radius.circular(r * 0.14),
        );
        canvas.drawRRect(boxRect, Paint()..shader = ui.Gradient.linear(c.translate(-r, -r), c.translate(r, r), [p1, const Color(0xFF1F1638)]));
        canvas.drawRRect(boxRect, Paint()..color = p2..style = PaintingStyle.stroke..strokeWidth = 2.2);
        // Ribbon cross
        canvas.drawLine(c.translate(0, -r * 0.34), c.translate(0, r * 0.61), Paint()..color = p2..strokeWidth = r * 0.14);
        canvas.drawLine(c.translate(-r * 0.56, r * 0.14), c.translate(r * 0.56, r * 0.14), Paint()..color = p2..strokeWidth = r * 0.14);
        // Popping bow/sparkles
        final lift = math.sin(_phase * 2).abs() * r * 0.12;
        _drawStar(canvas, c.translate(0, -r * 0.52 - lift), r * 0.22, 4, p2);
        _drawSparkles(canvas, c.translate(0, -r * 0.45), r * 0.6, Colors.white, 4);
        break;

      case StickerMotif.thinkingRightNowPulse:
        _drawGalaxySpiral(canvas, c, r * 0.85, p1, p2);
        _drawGradientHeart(canvas, c, r * 0.45, p2, Colors.white, glow: true);
        break;

      case StickerMotif.comeTalkWave:
        final bubble = Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(center: c.translate(0, -r * 0.08), width: r * 1.5, height: r * 1.05),
            Radius.circular(r * 0.35),
          ))
          ..moveTo(c.dx - r * 0.35, c.dy + r * 0.42)
          ..lineTo(c.dx - r * 0.55, c.dy + r * 0.78)
          ..lineTo(c.dx - r * 0.08, c.dy + r * 0.44);
        canvas.drawPath(bubble, Paint()..color = p1.withOpacity(0.24));
        canvas.drawPath(bubble, Paint()..color = p1..style = PaintingStyle.stroke..strokeWidth = 2.5);
        for (int i = 0; i < 3; i++) {
          final dy = math.sin(_phase * 2 + i * 1.0) * r * 0.08;
          canvas.drawCircle(c.translate((i - 1) * r * 0.34, -r * 0.08 + dy), r * 0.09, Paint()..color = i == 1 ? Colors.white : p2);
        }
        break;

      case StickerMotif.heartbeatEcgSync:
        _drawGradientHeart(canvas, c.translate(0, -r * 0.06), r * 0.66, p1.withOpacity(0.35), p2.withOpacity(0.15), glow: true);
        _drawEcgTrace(canvas, c, r * 1.15, p2, progress);
        break;

      case StickerMotif.virtualHugArc:
        canvas.drawArc(
          Rect.fromCenter(center: c, width: r * 1.55, height: r * 1.55),
          0.35 + math.sin(_phase) * 0.1,
          math.pi * 0.85,
          false,
          Paint()..color = p1..style = PaintingStyle.stroke..strokeWidth = r * 0.16..strokeCap = StrokeCap.round,
        );
        canvas.drawArc(
          Rect.fromCenter(center: c, width: r * 1.55, height: r * 1.55),
          math.pi + 0.35 + math.sin(_phase) * 0.1,
          math.pi * 0.85,
          false,
          Paint()..color = p2..style = PaintingStyle.stroke..strokeWidth = r * 0.16..strokeCap = StrokeCap.round,
        );
        _drawGradientHeart(canvas, c, r * 0.44, p2, Colors.white, glow: true);
        break;

      // ================== F. CELEBRATION ==================
      case StickerMotif.fireworksBloom:
        _drawBurstRays(canvas, c, r, p1, p2, 16, bloomProgress: progress);
        _drawSparkles(canvas, c, r * 0.95, Colors.white, 6);
        break;

      case StickerMotif.confettiShower:
        for (int i = 0; i < 14; i++) {
          final angle = i * 2.39996;
          final fall = ((progress + i * 0.17) % 1.0);
          final x = c.dx + math.cos(angle) * r * (0.2 + fall * 0.85);
          final y = c.dy - r * 0.8 + fall * r * 1.65;
          final col = [p1, p2, const Color(0xFF00FFA3), const Color(0xFFFFC857)][i % 4];
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(_phase + i);
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: r * 0.14, height: r * 0.08), Paint()..color = col);
          canvas.restore();
        }
        _drawStar(canvas, c, r * 0.35, 5, p1);
        break;

      case StickerMotif.floatingStarsCluster:
        _drawStar(canvas, c, r * 0.48, 5, p1);
        _drawStar(canvas, c.translate(-r * 0.56, -r * 0.45 + math.sin(_phase) * 4), r * 0.24, 4, p2);
        _drawStar(canvas, c.translate(r * 0.58, r * 0.36 - math.cos(_phase) * 4), r * 0.28, 4, p1);
        break;

      case StickerMotif.animatedBalloons:
        final b1 = c.translate(-r * 0.26, -r * 0.18 + math.sin(_phase) * 4);
        final b2 = c.translate(r * 0.28, -r * 0.28 + math.cos(_phase) * 4);
        canvas.drawLine(b1.translate(0, r * 0.4), c.translate(-r * 0.05, r * 0.85), Paint()..color = Colors.white54..strokeWidth = 1.5);
        canvas.drawLine(b2.translate(0, r * 0.4), c.translate(r * 0.05, r * 0.85), Paint()..color = Colors.white54..strokeWidth = 1.5);
        canvas.drawOval(Rect.fromCenter(center: b1, width: r * 0.68, height: r * 0.84), Paint()..shader = ui.Gradient.radial(b1.translate(-r * 0.12, -r * 0.15), r * 0.5, [Colors.white, p1]));
        canvas.drawOval(Rect.fromCenter(center: b2, width: r * 0.62, height: r * 0.78), Paint()..shader = ui.Gradient.radial(b2.translate(-r * 0.12, -r * 0.15), r * 0.5, [Colors.white, p2]));
        break;

      case StickerMotif.birthdayCakeCandle:
        // Two cake tiers
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate(0, r * 0.42), width: r * 1.4, height: r * 0.48), Radius.circular(r * 0.12)), Paint()..color = p2);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate(0, r * 0.04), width: r * 1.0, height: r * 0.40), Radius.circular(r * 0.12)), Paint()..color = p1);
        // Candle & animated flame
        canvas.drawRect(Rect.fromCenter(center: c.translate(0, -r * 0.34), width: r * 0.14, height: r * 0.38), Paint()..color = Colors.white);
        canvas.drawOval(
          Rect.fromCenter(center: c.translate(math.sin(_phase * 3) * 2, -r * 0.68), width: r * 0.20, height: r * (0.28 + _pulse * 0.08)),
          Paint()..color = const Color(0xFFFFC857),
        );
        break;

      case StickerMotif.sparklingLightBurst:
        _drawBurstRays(canvas, c, r, p1, p2, 10);
        _drawStar(canvas, c, r * 0.56, 4, Colors.white);
        break;
    }
  }

  // ==================== SHARED VECTOR PRIMITIVES ====================

  Path _heartPath(Offset c, double r) {
    final p = Path();
    p.moveTo(c.dx, c.dy + r * 0.75);
    p.cubicTo(
      c.dx - r * 1.25,
      c.dy + r * 0.10,
      c.dx - r * 0.92,
      c.dy - r * 0.95,
      c.dx,
      c.dy - r * 0.30,
    );
    p.cubicTo(
      c.dx + r * 0.92,
      c.dy - r * 0.95,
      c.dx + r * 1.25,
      c.dy + r * 0.10,
      c.dx,
      c.dy + r * 0.75,
    );
    p.close();
    return p;
  }

  void _drawGradientHeart(Canvas canvas, Offset c, double r, Color p1, Color p2, {required bool glow}) {
    final hp = _heartPath(c, r);
    if (glow && !reducedMotion) {
      canvas.drawPath(
        hp,
        Paint()
          ..color = p1.withOpacity(0.45 * intensity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawPath(
      hp,
      Paint()
        ..shader = ui.Gradient.linear(
          c.translate(-r * 0.7, -r * 0.7),
          c.translate(r * 0.7, r * 0.7),
          [p2, p1],
        ),
    );
    canvas.drawPath(
      hp,
      Paint()
        ..color = Colors.white.withOpacity(0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  void _drawCrystalHeart(Canvas canvas, Offset c, double r, Color p1, Color p2) {
    final top = c.translate(0, -r * 0.25);
    final bottom = c.translate(0, r * 0.75);
    final leftPeak = c.translate(-r * 0.45, -r * 0.65);
    final rightPeak = c.translate(r * 0.45, -r * 0.65);
    final leftEdge = c.translate(-r * 0.85, -r * 0.08);
    final rightEdge = c.translate(r * 0.85, -r * 0.08);

    final facets = [
      ([top, leftPeak, leftEdge], p1),
      ([top, leftEdge, bottom], Color.lerp(p1, p2, 0.45)!),
      ([top, bottom, rightEdge], Color.lerp(p2, p1, 0.35)!),
      ([top, rightPeak, rightEdge], p2),
    ];
    for (final (pts, col) in facets) {
      final path = Path()
        ..moveTo(pts[0].dx, pts[0].dy)
        ..lineTo(pts[1].dx, pts[1].dy)
        ..lineTo(pts[2].dx, pts[2].dy)
        ..close();
      canvas.drawPath(path, Paint()..color = col.withOpacity(0.92));
      canvas.drawPath(path, Paint()..color = Colors.white.withOpacity(0.55)..style = PaintingStyle.stroke..strokeWidth = 1.2);
    }
  }

  void _drawEnergyRings(Canvas canvas, Offset c, double r, Color p1, Color p2, {int count = 3}) {
    for (int i = 0; i < count; i++) {
      final sc = 0.72 + i * 0.16 + (_pulse * 0.06);
      canvas.drawCircle(
        c,
        r * sc,
        Paint()
          ..color = (i.isEven ? p1 : p2).withOpacity((0.65 - i * 0.15).clamp(0.15, 0.8))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  void _drawSparkles(Canvas canvas, Offset c, double r, Color color, int count) {
    for (int i = 0; i < count; i++) {
      final a = _phase * 0.4 + i * (math.pi * 2 / count);
      final pos = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      final tw = 0.65 + 0.45 * math.sin(_phase * 2 + i);
      _drawStar(canvas, pos, r * 0.12 * tw, 4, color);
    }
  }

  void _drawStar(Canvas canvas, Offset c, double radius, int points, Color color) {
    final path = Path();
    final inner = radius * 0.42;
    for (int i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : inner;
      final a = (i * math.pi / points) - math.pi / 2;
      final pt = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawButterfly(Canvas canvas, Offset c, double r, Color p1, Color p2, double flapPhase) {
    final wingScaleX = 0.62 + 0.38 * math.cos(flapPhase).abs();
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(wingScaleX, 1.0);
    for (final side in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(side * r * 0.42, -r * 0.22), width: r * 0.72, height: r * 0.56),
        Paint()..color = p1.withOpacity(0.9),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(side * r * 0.32, r * 0.25), width: r * 0.52, height: r * 0.42),
        Paint()..color = p2.withOpacity(0.85),
      );
    }
    canvas.drawLine(Offset(0, -r * 0.36), Offset(0, r * 0.40), Paint()..color = Colors.white..strokeWidth = 2.4..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  void _drawGalaxySpiral(Canvas canvas, Offset c, double r, Color p1, Color p2) {
    for (int arm = 0; arm < 2; arm++) {
      final path = Path();
      final base = arm * math.pi + _phase;
      for (int i = 0; i <= 26; i++) {
        final t = i / 26.0;
        final a = base + t * math.pi * 2.4;
        final rad = t * r * 0.92;
        final pt = c.translate(math.cos(a) * rad, math.sin(a) * rad);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = (arm == 0 ? p1 : p2).withOpacity(0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.14
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  void _drawPolygon(Canvas canvas, Offset c, double r, int sides, double rotation, Color p1,
      {double strokeWidth = 2.4, bool filled = false, Color? secondary}) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final a = rotation + i * (math.pi * 2 / sides);
      final pt = c.translate(math.cos(a) * r, math.sin(a) * r);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    if (filled) {
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(c.translate(-r, -r), c.translate(r, r), [p1, secondary ?? p1]),
      );
    } else {
      canvas.drawPath(
        path,
        Paint()
          ..color = p1
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }
  }

  void _drawLightningBolt(Canvas canvas, Offset c, double r, Color p1, Color p2) {
    final bolt = Path()
      ..moveTo(c.dx + r * 0.15, c.dy - r * 0.82)
      ..lineTo(c.dx - r * 0.36, c.dy + r * 0.05)
      ..lineTo(c.dx + r * 0.06, c.dy + r * 0.05)
      ..lineTo(c.dx - r * 0.18, c.dy + r * 0.85)
      ..lineTo(c.dx + r * 0.42, c.dy - r * 0.12)
      ..lineTo(c.dx - r * 0.04, c.dy - r * 0.12)
      ..close();
    canvas.drawPath(
      bolt,
      Paint()
        ..color = p1.withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawPath(bolt, Paint()..shader = ui.Gradient.linear(c.translate(0, -r), c.translate(0, r), [Colors.white, p1, p2]));
  }

  void _drawBurstRays(Canvas canvas, Offset c, double r, Color p1, Color p2, int count,
      {double bloomProgress = 0.5}) {
    final scale = 0.55 + 0.45 * math.sin(bloomProgress * math.pi);
    for (int i = 0; i < count; i++) {
      final a = _phase * 0.25 + i * (math.pi * 2 / count);
      final pStart = c.translate(math.cos(a) * r * 0.25, math.sin(a) * r * 0.25);
      final pEnd = c.translate(math.cos(a) * r * scale, math.sin(a) * r * scale);
      canvas.drawLine(
        pStart,
        pEnd,
        Paint()
          ..color = (i.isEven ? p1 : p2)
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(pEnd, 2.5, Paint()..color = Colors.white);
    }
  }

  void _drawEcgTrace(Canvas canvas, Offset c, double width, Color color, double phase) {
    final left = c.dx - width / 2;
    final path = Path()
      ..moveTo(left, c.dy)
      ..lineTo(left + width * 0.28, c.dy)
      ..lineTo(left + width * 0.36, c.dy - width * 0.22)
      ..lineTo(left + width * 0.45, c.dy + width * 0.28)
      ..lineTo(left + width * 0.54, c.dy - width * 0.34)
      ..lineTo(left + width * 0.62, c.dy + width * 0.14)
      ..lineTo(left + width * 0.70, c.dy)
      ..lineTo(left + width, c.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawCuteCircleCreature(Canvas canvas, Offset c, double r, Color bodyColor,
      {required bool blush, required String eyes, required String mouth}) {
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = ui.Gradient.linear(c.translate(-r, -r), c.translate(r, r), [bodyColor, bodyColor.withOpacity(0.75)]),
    );
    _drawCuteFace(
      canvas,
      c,
      r * 0.72,
      blushColor: blush ? const Color(0xFFFF2A7A) : Colors.transparent,
      eyes: eyes,
      mouth: mouth,
    );
  }

  void _drawCuteFace(Canvas canvas, Offset c, double r,
      {required Color blushColor, required String eyes, required String mouth}) {
    final eyePaint = Paint()
      ..color = const Color(0xFF0A0D18)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (blushColor != Colors.transparent) {
      canvas.drawOval(
        Rect.fromCenter(center: c.translate(-r * 0.46, r * 0.18), width: r * 0.26, height: r * 0.14),
        Paint()..color = blushColor.withOpacity(0.55),
      );
      canvas.drawOval(
        Rect.fromCenter(center: c.translate(r * 0.46, r * 0.18), width: r * 0.26, height: r * 0.14),
        Paint()..color = blushColor.withOpacity(0.55),
      );
    }

    if (eyes == 'happy') {
      canvas.drawArc(Rect.fromCenter(center: c.translate(-r * 0.30, -r * 0.04), width: r * 0.24, height: r * 0.18), math.pi, math.pi, false, eyePaint);
      canvas.drawArc(Rect.fromCenter(center: c.translate(r * 0.30, -r * 0.04), width: r * 0.24, height: r * 0.18), math.pi, math.pi, false, eyePaint);
    } else if (eyes == 'closed') {
      canvas.drawArc(Rect.fromCenter(center: c.translate(-r * 0.30, -r * 0.04), width: r * 0.22, height: r * 0.14), 0, math.pi, false, eyePaint);
      canvas.drawArc(Rect.fromCenter(center: c.translate(r * 0.30, -r * 0.04), width: r * 0.22, height: r * 0.14), 0, math.pi, false, eyePaint);
    } else if (eyes == 'wink') {
      canvas.drawCircle(c.translate(-r * 0.30, -r * 0.05), r * 0.09, Paint()..color = const Color(0xFF0A0D18));
      canvas.drawArc(Rect.fromCenter(center: c.translate(r * 0.30, -r * 0.04), width: r * 0.24, height: r * 0.18), math.pi, math.pi, false, eyePaint);
    } else {
      canvas.drawCircle(c.translate(-r * 0.30, -r * 0.06), r * 0.09, Paint()..color = const Color(0xFF0A0D18));
      canvas.drawCircle(c.translate(r * 0.30, -r * 0.06), r * 0.09, Paint()..color = const Color(0xFF0A0D18));
    }

    if (mouth == 'grin') {
      canvas.drawArc(Rect.fromCenter(center: c.translate(0, r * 0.18), width: r * 0.36, height: r * 0.28), 0, math.pi, true, Paint()..color = const Color(0xFF0A0D18));
    } else if (mouth == 'tiny') {
      canvas.drawCircle(c.translate(0, r * 0.22), r * 0.07, Paint()..color = const Color(0xFF0A0D18));
    } else {
      canvas.drawArc(Rect.fromCenter(center: c.translate(0, r * 0.18), width: r * 0.30, height: r * 0.20), 0.15, math.pi - 0.3, false, eyePaint);
    }
  }

  @override
  bool shouldRepaint(covariant GhostStickerPainter oldDelegate) {
    return oldDelegate.sticker.id != sticker.id ||
        oldDelegate.progress != progress ||
        oldDelegate.intensity != intensity ||
        oldDelegate.reducedMotion != reducedMotion;
  }
}
