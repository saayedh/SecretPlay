import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ghost_touch_theme.dart';
import '../models/hologram_models.dart';
import '../stickers/ghost_sticker_catalog.dart';
import '../stickers/ghost_sticker_painter.dart';

/// Animated renderer for any [FlashCardData] across all 12 curated templates
/// and 4 border effects. Used in chat bubbles, card designer preview, and
/// full holographic overlays.
class HolographicCardRenderer extends StatefulWidget {
  final FlashCardData data;
  final bool isFa;
  final bool compact;
  final bool reducedMotion;
  final Animation<double>? sharedAnimation;

  const HolographicCardRenderer({
    super.key,
    required this.data,
    required this.isFa,
    this.compact = false,
    this.reducedMotion = false,
    this.sharedAnimation,
  });

  @override
  State<HolographicCardRenderer> createState() =>
      _HolographicCardRendererState();
}

class _HolographicCardRendererState extends State<HolographicCardRenderer>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant HolographicCardRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sharedAnimation != widget.sharedAnimation ||
        oldWidget.reducedMotion != widget.reducedMotion) {
      _syncController();
    }
  }

  void _syncController() {
    if (widget.sharedAnimation != null || widget.reducedMotion) {
      _ctrl?.dispose();
      _ctrl = null;
      return;
    }
    _ctrl ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  TextStyle _resolveTextStyle(Color textColor, Color accentColor) {
    final baseSize = widget.compact ? 14.5 : 19.0;
    final hasGlow = widget.data.borderEffect != CardBorderEffect.minimal;
    final shadows = hasGlow
        ? [
            Shadow(color: accentColor.withOpacity(0.55), blurRadius: 10),
          ]
        : null;

    switch (widget.data.fontStyle) {
      case CardFontStyle.modern:
        return TextStyle(
          color: textColor,
          fontSize: baseSize,
          fontWeight: FontWeight.w700,
          height: 1.4,
          shadows: shadows,
        );
      case CardFontStyle.serif:
        return TextStyle(
          color: textColor,
          fontSize: baseSize + 1,
          fontFamily: 'serif',
          fontWeight: FontWeight.w600,
          height: 1.45,
          shadows: shadows,
        );
      case CardFontStyle.mono:
        return TextStyle(
          color: textColor,
          fontSize: baseSize - 1,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          height: 1.45,
          shadows: shadows,
        );
      case CardFontStyle.display:
        return TextStyle(
          color: textColor,
          fontSize: baseSize + 2,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.9,
          height: 1.35,
          shadows: shadows,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final accent = GhostPalette.fromHex(
      d.accentColorHex,
      fallback: d.template.accentColor,
    );
    final textColor = GhostPalette.fromHex(d.textColorHex, fallback: Colors.white);
    final grad = d.template.gradientColors;
    final hasSticker = d.stickerId != null && d.stickerId!.isNotEmpty;
    final sticker = hasSticker ? GhostStickerCatalog.findById(d.stickerId) : null;
    final anim = widget.sharedAnimation ?? _ctrl;
    final radius = widget.compact ? 20.0 : 26.0;
    final hasPersian = RegExp(r'[\u0600-\u06FF]').hasMatch(d.text);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: grad,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(
                  d.borderEffect == CardBorderEffect.minimal ? 0.14 : 0.30,
                ),
                blurRadius: widget.compact ? 14 : 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: anim == null
                    ? CustomPaint(
                        painter: _FlashCardArtPainter(
                          template: d.template,
                          accent: accent,
                          borderEffect: d.borderEffect,
                          radius: radius,
                          progress: 0.25,
                        ),
                      )
                    : AnimatedBuilder(
                        animation: anim,
                        builder: (_, __) => CustomPaint(
                          painter: _FlashCardArtPainter(
                            template: d.template,
                            accent: accent,
                            borderEffect: d.borderEffect,
                            radius: radius,
                            progress: anim.value,
                          ),
                        ),
                      ),
              ),
              Padding(
                padding: EdgeInsets.all(widget.compact ? 14 : 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Subtle header label
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: accent.withOpacity(0.8), blurRadius: 6),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          d.template.label(widget.isFa),
                          style: TextStyle(
                            color: accent.withOpacity(0.9),
                            fontSize: widget.compact ? 10 : 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: widget.compact ? 8 : 12),
                    if (sticker != null) ...[
                      GhostStickerArtwork(
                        sticker: sticker,
                        size: widget.compact ? 54 : 74,
                        sharedAnimation: anim,
                        reducedMotion: widget.reducedMotion,
                      ),
                      SizedBox(height: widget.compact ? 8 : 12),
                    ],
                    Directionality(
                      textDirection:
                          (hasPersian || widget.isFa) ? TextDirection.rtl : TextDirection.ltr,
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          d.text.isEmpty
                              ? (widget.isFa
                                  ? 'پیام هولوگرافیک برای تو'
                                  : 'A Holographic Card For You')
                              : d.text,
                          textAlign: d.textAlign,
                          style: _resolveTextStyle(textColor, accent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlashCardArtPainter extends CustomPainter {
  final FlashCardTemplate template;
  final Color accent;
  final CardBorderEffect borderEffect;
  final double radius;
  final double progress;

  const _FlashCardArtPainter({
    required this.template,
    required this.accent,
    required this.borderEffect,
    required this.radius,
    required this.progress,
  });

  double get _phase => progress * math.pi * 2;
  double get _pulse => 0.5 + 0.5 * math.sin(_phase);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _paintTemplateArt(canvas, size, rect);
    _paintBorderEffect(canvas, size, rect);
  }

  void _paintTemplateArt(Canvas canvas, Size size, Rect rect) {
    final w = size.width;
    final h = size.height;
    switch (template) {
      case FlashCardTemplate.romanticNeonHeart:
        final c = Offset(w * 0.84, h * 0.25);
        for (int i = 0; i < 2; i++) {
          final r = 24.0 + i * 16 + _pulse * 5;
          final p = Path()
            ..moveTo(c.dx, c.dy + r * 0.72)
            ..cubicTo(c.dx - r * 1.1, c.dy + r * 0.1, c.dx - r * 0.9,
                c.dy - r * 0.8, c.dx, c.dy - r * 0.22)
            ..cubicTo(c.dx + r * 0.9, c.dy - r * 0.8, c.dx + r * 1.1,
                c.dy + r * 0.1, c.dx, c.dy + r * 0.72);
          canvas.drawPath(
            p,
            Paint()
              ..color = accent.withOpacity(0.16 - i * 0.06)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6,
          );
        }
        break;

      case FlashCardTemplate.cosmicMessage:
        final c = Offset(w * 0.5, h * 0.55);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-0.22 + _phase * 0.08);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: w * 1.1, height: h * 0.36),
          Paint()
            ..color = accent.withOpacity(0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        canvas.restore();
        break;

      case FlashCardTemplate.pinkCrystal:
        for (int i = 0; i < 4; i++) {
          final fx = w * (0.15 + i * 0.24);
          final fy = h * (i.isEven ? 0.22 : 0.78);
          final d = 14.0 + _pulse * 4;
          final poly = Path()
            ..moveTo(fx, fy - d)
            ..lineTo(fx + d * 0.7, fy)
            ..lineTo(fx, fy + d)
            ..lineTo(fx - d * 0.7, fy)
            ..close();
          canvas.drawPath(
            poly,
            Paint()
              ..color = accent.withOpacity(0.16)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
        break;

      case FlashCardTemplate.purpleGalaxy:
        final c = Offset(w * 0.5, h * 0.5);
        for (int i = 0; i < 16; i++) {
          final t = i / 16.0;
          final ang = t * math.pi * 4 + _phase;
          final rad = t * math.min(w, h) * 0.48;
          canvas.drawCircle(
            c + Offset(math.cos(ang) * rad, math.sin(ang) * rad * 0.6),
            1.2 + (1 - t) * 1.8,
            Paint()..color = accent.withOpacity(0.35),
          );
        }
        break;

      case FlashCardTemplate.cyberpunkEnergy:
        final scanY = ((progress * 1.4) % 1.0) * h;
        canvas.drawLine(
          Offset(0, scanY),
          Offset(w, scanY),
          Paint()
            ..color = accent.withOpacity(0.35)
            ..strokeWidth = 1.8,
        );
        final corner = Paint()
          ..color = accent.withOpacity(0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        const cl = 14.0;
        canvas.drawPath(
            Path()
              ..moveTo(10, 10 + cl)
              ..lineTo(10, 10)
              ..lineTo(10 + cl, 10),
            corner);
        canvas.drawPath(
            Path()
              ..moveTo(w - 10 - cl, h - 10)
              ..lineTo(w - 10, h - 10)
              ..lineTo(w - 10, h - 10 - cl),
            corner);
        break;

      case FlashCardTemplate.minimalElegant:
        final sheenX = -w * 0.3 + progress * w * 1.6;
        canvas.drawLine(
          Offset(sheenX, 0),
          Offset(sheenX - 40, h),
          Paint()
            ..color = Colors.white.withOpacity(0.06)
            ..strokeWidth = 18,
        );
        break;

      case FlashCardTemplate.auroraCard:
        final p = Path()..moveTo(0, h * 0.25);
        for (double x = 0; x <= w; x += 10) {
          final y = h * 0.22 +
              math.sin(x * 0.03 + _phase) * 10 +
              math.cos(x * 0.015 - _phase) * 6;
          p.lineTo(x, y);
        }
        p.lineTo(w, 0);
        p.lineTo(0, 0);
        p.close();
        canvas.drawPath(
          p,
          Paint()
            ..shader = LinearGradient(
              colors: [
                GhostPalette.neonGreen.withOpacity(0.18),
                GhostPalette.electricCyan.withOpacity(0.20),
                GhostPalette.neonPurple.withOpacity(0.14),
              ],
            ).createShader(rect)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
        );
        break;

      case FlashCardTemplate.glassmorphismCard:
        canvas.drawLine(
          Offset(w * 0.1, 0),
          Offset(w * 0.45, h),
          Paint()
            ..color = Colors.white.withOpacity(0.05 + _pulse * 0.03)
            ..strokeWidth = 26,
        );
        break;

      case FlashCardTemplate.floatingFlower:
        for (int i = 0; i < 6; i++) {
          final px = w * ((i * 0.18 + progress * 0.12) % 1.0);
          final py = h * (1.0 - ((progress + i * 0.17) % 1.0));
          canvas.save();
          canvas.translate(px, py);
          canvas.rotate(_phase + i);
          canvas.drawOval(
            const Rect.fromLTWH(-4, -7, 8, 14),
            Paint()..color = accent.withOpacity(0.24),
          );
          canvas.restore();
        }
        break;

      case FlashCardTemplate.animatedStarField:
        final rng = math.Random(19);
        for (int i = 0; i < 24; i++) {
          final sx = rng.nextDouble() * w;
          final sy = rng.nextDouble() * h;
          final tw = 0.2 + 0.7 * (0.5 + 0.5 * math.sin(_phase * 2 + i));
          canvas.drawCircle(
            Offset(sx, sy),
            0.9 + (i % 2) * 0.8,
            Paint()..color = accent.withOpacity(tw * 0.55),
          );
        }
        break;

      case FlashCardTemplate.liquidNeon:
        final p = Path()..moveTo(0, h);
        for (double x = 0; x <= w; x += 8) {
          final y = h * 0.78 + math.sin(x * 0.04 + _phase) * 9;
          p.lineTo(x, y);
        }
        p.lineTo(w, h);
        p.close();
        canvas.drawPath(
          p,
          Paint()..color = accent.withOpacity(0.18),
        );
        break;

      case FlashCardTemplate.digitalHeartbeat:
        final baseY = h * 0.84;
        final ecg = Path()..moveTo(0, baseY);
        for (double x = 0; x <= w; x += 4) {
          final local = ((x / w + progress) % 1.0);
          double dy = 0;
          if (local > 0.35 && local < 0.42) dy = -18 * math.sin((local - 0.35) / 0.07 * math.pi);
          if (local >= 0.42 && local < 0.46) dy = 10 * math.sin((local - 0.42) / 0.04 * math.pi);
          ecg.lineTo(x, baseY + dy);
        }
        canvas.drawPath(
          ecg,
          Paint()
            ..color = accent.withOpacity(0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
        break;
    }
  }

  void _paintBorderEffect(Canvas canvas, Size size, Rect rect) {
    final rr = RRect.fromRectAndRadius(rect.deflate(1), Radius.circular(radius));
    switch (borderEffect) {
      case CardBorderEffect.minimal:
        canvas.drawRRect(
          rr,
          Paint()
            ..color = Colors.white.withOpacity(0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
        break;

      case CardBorderEffect.glow:
        canvas.drawRRect(
          rr,
          Paint()
            ..color = accent.withOpacity(0.55 + _pulse * 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
        break;

      case CardBorderEffect.doublePrism:
        canvas.drawRRect(
          rr,
          Paint()
            ..color = accent.withOpacity(0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(4.5), Radius.circular(radius - 3)),
          Paint()
            ..color = GhostPalette.electricCyan.withOpacity(0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
        break;

      case CardBorderEffect.pulse:
        canvas.drawRRect(
          rr,
          Paint()
            ..color = accent.withOpacity(0.28)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        final path = Path()..addRRect(rr);
        final metrics = path.computeMetrics().toList();
        if (metrics.isNotEmpty) {
          final m = metrics.first;
          final len = m.length;
          final start = (progress * len) % len;
          final end = math.min(start + len * 0.22, len);
          final seg = m.extractPath(start, end);
          canvas.drawPath(
            seg,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 2.4,
          );
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _FlashCardArtPainter old) =>
      old.template != template ||
      old.accent != accent ||
      old.borderEffect != borderEffect ||
      old.progress != progress;
}
