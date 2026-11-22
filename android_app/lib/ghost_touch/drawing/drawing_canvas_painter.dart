import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ghost_touch_theme.dart';
import '../stickers/ghost_sticker_catalog.dart';
import '../stickers/ghost_sticker_painter.dart';
import 'drawing_models.dart';

class DrawingCanvasPainter extends CustomPainter {
  final List<CanvasElement> elements;
  final DrawingStroke? activeStroke;
  final CanvasBackgroundKind background;
  final String? selectedId;
  final bool isExport;

  const DrawingCanvasPainter({
    required this.elements,
    required this.background,
    this.activeStroke,
    this.selectedId,
    this.isExport = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _paintBackground(canvas, size, rect);

    // Layer so eraser (BlendMode.clear) clears artwork without punching through background.
    canvas.saveLayer(rect, Paint());
    for (final el in elements) {
      _paintElement(canvas, size, el);
    }
    if (activeStroke != null) {
      _paintStroke(canvas, activeStroke!);
    }
    canvas.restore();

    if (!isExport && selectedId != null) {
      _paintSelectionOverlay(canvas, size, selectedId!);
    }
  }

  void _paintBackground(Canvas canvas, Size size, Rect rect) {
    switch (background) {
      case CanvasBackgroundKind.transparentGlass:
        if (!isExport) {
          const cell = 18.0;
          final p1 = Paint()..color = const Color(0xFF141828);
          final p2 = Paint()..color = const Color(0xFF1B2034);
          canvas.drawRect(rect, p1);
          for (double y = 0; y < size.height; y += cell) {
            for (double x = 0; x < size.width; x += cell) {
              if (((x ~/ cell) + (y ~/ cell)) % 2 == 0) {
                canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), p2);
              }
            }
          }
        }
        break;

      case CanvasBackgroundKind.deepSpace:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(0, -0.15),
              radius: 1.05,
              colors: [
                Color(0xFF171330),
                GhostPalette.deepSpace,
              ],
            ).createShader(rect),
        );
        break;

      case CanvasBackgroundKind.cyberGrid:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF090C1C), Color(0xFF111A33)],
            ).createShader(rect),
        );
        final gridPaint = Paint()
          ..color = GhostPalette.electricCyan.withOpacity(0.11)
          ..strokeWidth = 1.0;
        const step = 28.0;
        for (double x = 0; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
        }
        for (double y = 0; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
        }
        break;

      case CanvasBackgroundKind.violetNebula:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(0.25, -0.35),
              radius: 1.15,
              colors: [
                Color(0xFF331454),
                Color(0xFF180E2B),
                GhostPalette.deepSpace,
              ],
            ).createShader(rect),
        );
        final bokeh = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
        bokeh.color = GhostPalette.neonPink.withOpacity(0.16);
        canvas.drawCircle(
            Offset(size.width * 0.25, size.height * 0.3), size.width * 0.28, bokeh);
        bokeh.color = GhostPalette.electricBlue.withOpacity(0.16);
        canvas.drawCircle(
            Offset(size.width * 0.78, size.height * 0.7), size.width * 0.30, bokeh);
        break;

      case CanvasBackgroundKind.auroraDark:
        canvas.drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF07191A), Color(0xFF0D142C), GhostPalette.deepSpace],
            ).createShader(rect),
        );
        final aurora = Paint()
          ..shader = LinearGradient(
            colors: [
              GhostPalette.neonGreen.withOpacity(0.18),
              GhostPalette.electricCyan.withOpacity(0.20),
              GhostPalette.neonPurple.withOpacity(0.14),
            ],
          ).createShader(rect)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
        final path = Path()
          ..moveTo(0, size.height * 0.25)
          ..quadraticBezierTo(size.width * 0.45, size.height * 0.08,
              size.width, size.height * 0.35)
          ..lineTo(size.width, size.height * 0.55)
          ..quadraticBezierTo(size.width * 0.45, size.height * 0.28,
              0, size.height * 0.44)
          ..close();
        canvas.drawPath(path, aurora);
        break;

      case CanvasBackgroundKind.starfield:
        canvas.drawRect(rect, Paint()..color = const Color(0xFF070812));
        final rng = math.Random(42);
        for (int i = 0; i < 65; i++) {
          final sx = rng.nextDouble() * size.width;
          final sy = rng.nextDouble() * size.height;
          final sr = 0.7 + rng.nextDouble() * 1.4;
          final alpha = 0.25 + rng.nextDouble() * 0.6;
          canvas.drawCircle(
            Offset(sx, sy),
            sr,
            Paint()..color = Colors.white.withOpacity(alpha),
          );
        }
        break;
    }
  }

  void _paintElement(Canvas canvas, Size size, CanvasElement el) {
    switch (el.kind) {
      case CanvasElementKind.stroke:
        if (el.stroke != null) _paintStroke(canvas, el.stroke!);
        break;
      case CanvasElementKind.shape:
        final s = el.shape!;
        canvas.save();
        canvas.translate(s.center.dx, s.center.dy);
        canvas.rotate(s.rotation);
        paintVectorShape(
          canvas,
          Offset.zero,
          s.size * 0.5,
          s.kind,
          s.color,
          secondary: s.secondaryColor,
          filled: s.filled,
          strokeWidth: s.strokeWidth,
        );
        canvas.restore();
        break;
      case CanvasElementKind.sticker:
        final st = el.stickerItem!;
        final def = GhostStickerCatalog.findById(st.stickerId);
        canvas.save();
        canvas.translate(st.center.dx, st.center.dy);
        canvas.rotate(st.rotation);
        canvas.translate(-st.size / 2, -st.size / 2);
        GhostStickerPainter(
          sticker: def,
          progress: 0.25,
          intensity: 1.0,
          reducedMotion: false,
        ).paint(canvas, Size(st.size, st.size));
        canvas.restore();
        break;
      case CanvasElementKind.text:
        final t = el.textItem!;
        _paintTextItem(canvas, t);
        break;
    }
  }

  void _paintTextItem(Canvas canvas, CanvasTextItem t) {
    final isRtl = RegExp(r'[\u0600-\u06FF]').hasMatch(t.text);
    final style = TextStyle(
      color: t.color,
      fontSize: t.fontSize,
      fontWeight: FontWeight.w800,
      fontFamily: t.fontFamily == 'mono'
          ? 'monospace'
          : (t.fontFamily == 'serif' ? 'serif' : null),
      letterSpacing: t.fontFamily == 'display' ? 1.2 : 0.2,
      shadows: t.neonGlow
          ? [
              Shadow(color: t.color.withOpacity(0.92), blurRadius: 12),
              Shadow(color: t.color.withOpacity(0.55), blurRadius: 24),
            ]
          : const [
              Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
            ],
    );
    final tp = TextPainter(
      text: TextSpan(text: t.text, style: style),
      textAlign: TextAlign.center,
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout(maxWidth: 340);

    canvas.save();
    canvas.translate(t.center.dx, t.center.dy);
    canvas.rotate(t.rotation);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  void _paintSelectionOverlay(Canvas canvas, Size size, String id) {
    Rect? targetRect;
    double rotation = 0;
    for (final el in elements) {
      if (el.id != id) continue;
      if (el.kind == CanvasElementKind.shape) {
        targetRect = el.shape!.hitRect;
        rotation = el.shape!.rotation;
      } else if (el.kind == CanvasElementKind.sticker) {
        targetRect = el.stickerItem!.hitRect;
        rotation = el.stickerItem!.rotation;
      } else if (el.kind == CanvasElementKind.text) {
        targetRect = el.textItem!.hitRectFor(size);
        rotation = el.textItem!.rotation;
      }
      break;
    }
    if (targetRect == null) return;

    canvas.save();
    canvas.translate(targetRect.center.dx, targetRect.center.dy);
    canvas.rotate(rotation);
    final localRect = Rect.fromCenter(
      center: Offset.zero,
      width: targetRect.width,
      height: targetRect.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(localRect, const Radius.circular(10)),
      Paint()
        ..color = GhostPalette.electricCyan.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final handlePaint = Paint()..color = GhostPalette.neonPink;
    for (final pt in [
      localRect.topLeft,
      localRect.topRight,
      localRect.bottomLeft,
      localRect.bottomRight,
    ]) {
      canvas.drawCircle(pt, 4.5, handlePaint);
      canvas.drawCircle(pt, 2.2, Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  Path _buildSmoothPath(List<DrawingPoint> pts) {
    final path = Path();
    path.moveTo(pts.first.offset.dx, pts.first.offset.dy);
    if (pts.length == 1) {
      path.lineTo(pts.first.offset.dx + 0.1, pts.first.offset.dy + 0.1);
      return path;
    }
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i].offset;
      final p1 = pts[i + 1].offset;
      final mid = Offset((p0.dx + p1.dx) * 0.5, (p0.dy + p1.dy) * 0.5);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.offset.dx, pts.last.offset.dy);
    return path;
  }

  Shader? _buildStrokeShader(DrawingStroke s, Rect bounds) {
    if (s.brush == BrushKind.rainbow) {
      return const LinearGradient(
        colors: [
          GhostPalette.neonPink,
          GhostPalette.amberGold,
          GhostPalette.neonGreen,
          GhostPalette.electricCyan,
          GhostPalette.neonPurple,
          GhostPalette.neonPink,
        ],
      ).createShader(bounds.inflate(8));
    }
    if (s.gradientColor != null && s.gradientColor != s.color) {
      return LinearGradient(
        colors: [s.color, s.gradientColor!],
      ).createShader(bounds.inflate(6));
    }
    return null;
  }

  void _paintStroke(Canvas canvas, DrawingStroke s) {
    if (s.points.isEmpty) return;

    final path = _buildSmoothPath(s.points);
    final bounds = path.getBounds();
    final avgPressure = s.points.fold<double>(0, (a, p) => a + p.pressure) /
        s.points.length;
    final w = (s.strokeWidth * (0.75 + 0.4 * avgPressure)).clamp(1.5, 42.0);
    final baseColor = s.color.withOpacity(s.opacity);
    final shader = _buildStrokeShader(s, bounds);

    switch (s.brush) {
      case BrushKind.eraser:
        canvas.drawPath(
          path,
          Paint()
            ..blendMode = BlendMode.clear
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = w * 1.4,
        );
        break;

      case BrushKind.neon:
        final glow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = w * 2.5
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.9);
        if (shader != null) {
          glow.shader = shader;
        } else {
          glow.color = baseColor.withOpacity(0.55 * s.opacity);
        }
        canvas.drawPath(path, glow);

        final core = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = w * 0.72
          ..color = Color.lerp(baseColor, Colors.white, 0.72)!;
        canvas.drawPath(path, core);
        break;

      case BrushKind.softAirbrush:
        final mist = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = w * 2.9
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 1.35);
        if (shader != null) {
          mist.shader = shader;
        } else {
          mist.color = baseColor.withOpacity(0.45 * s.opacity);
        }
        canvas.drawPath(path, mist);
        break;

      case BrushKind.sparkleTrail:
        final beam = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = w * 0.9
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.35);
        if (shader != null) {
          beam.shader = shader;
        } else {
          beam.color = baseColor.withOpacity(0.75 * s.opacity);
        }
        canvas.drawPath(path, beam);

        final starPaint = Paint()..color = Colors.white.withOpacity(s.opacity);
        final accentPaint = Paint()..color = baseColor;
        for (int i = 0; i < s.points.length; i += 4) {
          final p = s.points[i].offset;
          final starR = w * (0.65 + (i % 3) * 0.25);
          _draw4Star(canvas, p + Offset((i % 2 == 0 ? 1 : -1) * w * 0.45, -w * 0.35),
              starR * 0.55, accentPaint);
          _draw4Star(canvas, p, starR * 0.45, starPaint);
        }
        break;

      case BrushKind.marker:
        final markerPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.bevel
          ..strokeWidth = w * 1.55;
        if (shader != null) {
          markerPaint.shader = shader;
        } else {
          markerPaint.color = s.color.withOpacity(0.72 * s.opacity);
        }
        canvas.drawPath(path, markerPaint);
        break;

      case BrushKind.calligraphy:
        for (int i = 0; i < s.points.length - 1; i++) {
          final p0 = s.points[i];
          final p1 = s.points[i + 1];
          final delta = p1.offset - p0.offset;
          final angle = math.atan2(delta.dy, delta.dx);
          final nibFactor = 0.45 + 0.85 * math.sin(angle - 0.65).abs();
          final segW = (s.strokeWidth * nibFactor * p1.pressure).clamp(1.5, 36.0);
          canvas.drawLine(
            p0.offset,
            p1.offset,
            Paint()
              ..color = baseColor
              ..strokeCap = StrokeCap.round
              ..strokeWidth = segW,
          );
        }
        if (s.points.length == 1) {
          canvas.drawCircle(
            s.points.first.offset,
            w * 0.5,
            Paint()..color = baseColor,
          );
        }
        break;

      case BrushKind.rainbow:
        canvas.drawPath(
          path,
          Paint()
            ..shader = shader
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = w * 1.8
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.55),
        );
        canvas.drawPath(
          path,
          Paint()
            ..shader = shader
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = w * 0.85,
        );
        break;

      case BrushKind.dottedBeam:
        final spacing = (w * 1.9).clamp(6.0, 28.0);
        double accum = spacing;
        for (int i = 0; i < s.points.length; i++) {
          final p = s.points[i].offset;
          if (i == 0 || (p - s.points[i - 1].offset).distance >= accum * 0.45) {
            accum = 0;
            canvas.drawCircle(
              p,
              w * 0.72,
              Paint()
                ..color = baseColor.withOpacity(0.45 * s.opacity)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.5),
            );
            canvas.drawCircle(
              p,
              w * 0.42,
              Paint()..color = Color.lerp(baseColor, Colors.white, 0.5)!,
            );
          } else {
            accum += (p - s.points[i - 1].offset).distance;
          }
        }
        break;

      case BrushKind.hologramRibbon:
        final pCyan = Path();
        final pMag = Path();
        final shift = Offset(w * 0.55, -w * 0.45);
        for (int i = 0; i < s.points.length; i++) {
          final pt = s.points[i].offset;
          if (i == 0) {
            pCyan.moveTo(pt.dx - shift.dx, pt.dy - shift.dy);
            pMag.moveTo(pt.dx + shift.dx, pt.dy + shift.dy);
          } else {
            pCyan.lineTo(pt.dx - shift.dx, pt.dy - shift.dy);
            pMag.lineTo(pt.dx + shift.dx, pt.dy + shift.dy);
          }
        }
        canvas.drawPath(
          pCyan,
          Paint()
            ..color = GhostPalette.electricCyan.withOpacity(0.55 * s.opacity)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = w * 0.65
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.35),
        );
        canvas.drawPath(
          pMag,
          Paint()
            ..color = GhostPalette.neonPink.withOpacity(0.55 * s.opacity)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = w * 0.65
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.35),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white.withOpacity(0.92 * s.opacity)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = w * 0.45,
        );
        break;
    }
  }

  static void _draw4Star(Canvas canvas, Offset c, double r, Paint paint) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, paint);
  }

  static Path _heartPath(Offset c, double r) {
    final p = Path();
    p.moveTo(c.dx, c.dy + r * 0.78);
    p.cubicTo(c.dx - r * 1.15, c.dy + r * 0.15, c.dx - r * 0.95,
        c.dy - r * 0.85, c.dx, c.dy - r * 0.25);
    p.cubicTo(c.dx + r * 0.95, c.dy - r * 0.85, c.dx + r * 1.15,
        c.dy + r * 0.15, c.dx, c.dy + r * 0.78);
    p.close();
    return p;
  }

  /// Shared vector shape renderer used on both live canvas and palette thumbnails.
  static void paintVectorShape(
    Canvas canvas,
    Offset center,
    double r,
    VectorShapeKind kind,
    Color primary, {
    Color? secondary,
    bool filled = false,
    double strokeWidth = 3.0,
  }) {
    final sec = secondary ?? GhostPalette.electricCyan;
    final rect = Rect.fromCircle(center: center, radius: r);
    final shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [primary, sec]);

    final strokePaint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth;

    final glowPaint = Paint()
      ..color = primary.withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth * 2.2
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth * 1.3);

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [primary.withOpacity(0.32), sec.withOpacity(0.20)],
      )
      ..style = PaintingStyle.fill;

    void drawShapePath(Path p) {
      if (filled) canvas.drawPath(p, fillPaint);
      canvas.drawPath(p, glowPaint);
      canvas.drawPath(p, strokePaint);
    }

    switch (kind) {
      case VectorShapeKind.heart:
        drawShapePath(_heartPath(center, r * 0.92));
        break;

      case VectorShapeKind.doubleHeart:
        drawShapePath(_heartPath(center + Offset(-r * 0.22, -r * 0.1), r * 0.65));
        drawShapePath(_heartPath(center + Offset(r * 0.24, r * 0.18), r * 0.56));
        break;

      case VectorShapeKind.star5:
        final p = Path();
        for (int i = 0; i < 10; i++) {
          final rad = i.isEven ? r * 0.95 : r * 0.42;
          final a = -math.pi / 2 + i * math.pi / 5;
          final pt = center + Offset(math.cos(a) * rad, math.sin(a) * rad);
          if (i == 0) {
            p.moveTo(pt.dx, pt.dy);
          } else {
            p.lineTo(pt.dx, pt.dy);
          }
        }
        p.close();
        drawShapePath(p);
        break;

      case VectorShapeKind.star4Sparkle:
        final p = Path()
          ..moveTo(center.dx, center.dy - r)
          ..quadraticBezierTo(center.dx, center.dy, center.dx + r, center.dy)
          ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy + r)
          ..quadraticBezierTo(center.dx, center.dy, center.dx - r, center.dy)
          ..quadraticBezierTo(center.dx, center.dy, center.dx, center.dy - r)
          ..close();
        drawShapePath(p);
        break;

      case VectorShapeKind.infinity:
        final p = Path();
        for (int i = 0; i <= 72; i++) {
          final t = (i / 72) * math.pi * 2;
          final denom = 1 + math.sin(t) * math.sin(t);
          final x = center.dx + (r * 0.95 * math.cos(t)) / denom;
          final y = center.dy + (r * 0.85 * math.sin(t) * math.cos(t)) / denom;
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        p.close();
        drawShapePath(p);
        break;

      case VectorShapeKind.crown:
        final p = Path()
          ..moveTo(center.dx - r * 0.82, center.dy + r * 0.52)
          ..lineTo(center.dx - r * 0.9, center.dy - r * 0.35)
          ..lineTo(center.dx - r * 0.38, center.dy + r * 0.08)
          ..lineTo(center.dx, center.dy - r * 0.62)
          ..lineTo(center.dx + r * 0.38, center.dy + r * 0.08)
          ..lineTo(center.dx + r * 0.9, center.dy - r * 0.35)
          ..lineTo(center.dx + r * 0.82, center.dy + r * 0.52)
          ..close();
        drawShapePath(p);
        break;

      case VectorShapeKind.lightning:
        final p = Path()
          ..moveTo(center.dx + r * 0.15, center.dy - r * 0.95)
          ..lineTo(center.dx - r * 0.55, center.dy + r * 0.06)
          ..lineTo(center.dx + r * 0.05, center.dy + r * 0.06)
          ..lineTo(center.dx - r * 0.22, center.dy + r * 0.95)
          ..lineTo(center.dx + r * 0.58, center.dy - r * 0.12)
          ..lineTo(center.dx - r * 0.05, center.dy - r * 0.12)
          ..close();
        drawShapePath(p);
        break;

      case VectorShapeKind.crescentMoon:
        final p = Path()
          ..addArc(Rect.fromCircle(center: center, radius: r * 0.82),
              math.pi * 0.22, math.pi * 1.56)
          ..quadraticBezierTo(center.dx - r * 0.15, center.dy,
              center.dx + math.cos(math.pi * 0.22) * r * 0.82,
              center.dy + math.sin(math.pi * 0.22) * r * 0.82);
        drawShapePath(p);
        break;

      case VectorShapeKind.ringedPlanet:
        if (filled) canvas.drawCircle(center, r * 0.48, fillPaint);
        canvas.drawCircle(center, r * 0.48, glowPaint);
        canvas.drawCircle(center, r * 0.48, strokePaint);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(-0.32);
        final ringRect = Rect.fromCenter(
            center: Offset.zero, width: r * 1.9, height: r * 0.52);
        canvas.drawOval(ringRect, glowPaint);
        canvas.drawOval(ringRect, strokePaint);
        canvas.restore();
        break;

      case VectorShapeKind.butterfly:
        final p = Path()
          ..moveTo(center.dx, center.dy - r * 0.15)
          ..cubicTo(center.dx - r * 0.95, center.dy - r * 0.95,
              center.dx - r * 1.05, center.dy + r * 0.12, center.dx, center.dy + r * 0.22)
          ..cubicTo(center.dx - r * 0.82, center.dy + r * 0.35,
              center.dx - r * 0.65, center.dy + r * 0.88, center.dx, center.dy + r * 0.36)
          ..cubicTo(center.dx + r * 0.65, center.dy + r * 0.88,
              center.dx + r * 0.82, center.dy + r * 0.35, center.dx, center.dy + r * 0.22)
          ..cubicTo(center.dx + r * 1.05, center.dy + r * 0.12,
              center.dx + r * 0.95, center.dy - r * 0.95, center.dx, center.dy - r * 0.15);
        drawShapePath(p);
        break;

      case VectorShapeKind.crystalDiamond:
        final p = Path()
          ..moveTo(center.dx, center.dy - r * 0.95)
          ..lineTo(center.dx + r * 0.72, center.dy - r * 0.2)
          ..lineTo(center.dx, center.dy + r * 0.95)
          ..lineTo(center.dx - r * 0.72, center.dy - r * 0.2)
          ..close();
        drawShapePath(p);
        canvas.drawLine(Offset(center.dx - r * 0.72, center.dy - r * 0.2),
            Offset(center.dx + r * 0.72, center.dy - r * 0.2), strokePaint);
        break;

      case VectorShapeKind.flowerPetal:
        for (int i = 0; i < 6; i++) {
          canvas.save();
          canvas.translate(center.dx, center.dy);
          canvas.rotate(i * math.pi / 3);
          final petal = Rect.fromCenter(
              center: Offset(0, -r * 0.45), width: r * 0.46, height: r * 0.78);
          if (filled) canvas.drawOval(petal, fillPaint);
          canvas.drawOval(petal, glowPaint);
          canvas.drawOval(petal, strokePaint);
          canvas.restore();
        }
        canvas.drawCircle(center, r * 0.18, Paint()..color = Colors.white);
        break;

      case VectorShapeKind.neonArrow:
        final p = Path()
          ..moveTo(center.dx - r * 0.85, center.dy)
          ..lineTo(center.dx + r * 0.35, center.dy)
          ..moveTo(center.dx + r * 0.08, center.dy - r * 0.42)
          ..lineTo(center.dx + r * 0.75, center.dy)
          ..lineTo(center.dx + r * 0.08, center.dy + r * 0.42);
        canvas.drawPath(p, glowPaint);
        canvas.drawPath(p, strokePaint);
        break;

      case VectorShapeKind.speechBubble:
        final p = Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: center + Offset(0, -r * 0.1),
                width: r * 1.65,
                height: r * 1.15),
            Radius.circular(r * 0.35),
          ))
          ..moveTo(center.dx - r * 0.28, center.dy + r * 0.46)
          ..lineTo(center.dx - r * 0.55, center.dy + r * 0.86)
          ..lineTo(center.dx + r * 0.04, center.dy + r * 0.46);
        drawShapePath(p);
        break;

      case VectorShapeKind.hexagon:
        final p = Path();
        for (int i = 0; i < 6; i++) {
          final a = -math.pi / 6 + i * math.pi / 3;
          final pt = center + Offset(math.cos(a) * r * 0.9, math.sin(a) * r * 0.9);
          if (i == 0) {
            p.moveTo(pt.dx, pt.dy);
          } else {
            p.lineTo(pt.dx, pt.dy);
          }
        }
        p.close();
        drawShapePath(p);
        break;

      case VectorShapeKind.musicNote:
        final p = Path()
          ..moveTo(center.dx - r * 0.18, center.dy + r * 0.55)
          ..lineTo(center.dx - r * 0.18, center.dy - r * 0.68)
          ..lineTo(center.dx + r * 0.58, center.dy - r * 0.82)
          ..lineTo(center.dx + r * 0.58, center.dy + r * 0.32);
        canvas.drawPath(p, glowPaint);
        canvas.drawPath(p, strokePaint);
        canvas.drawCircle(
            center + Offset(-r * 0.36, r * 0.55), r * 0.22, strokePaint);
        canvas.drawCircle(
            center + Offset(r * 0.38, r * 0.34), r * 0.22, strokePaint);
        break;

      case VectorShapeKind.spiralVortex:
        final p = Path();
        for (int i = 0; i <= 90; i++) {
          final t = i / 90;
          final a = t * math.pi * 6;
          final rad = t * r * 0.92;
          final pt = center + Offset(math.cos(a) * rad, math.sin(a) * rad);
          if (i == 0) {
            p.moveTo(pt.dx, pt.dy);
          } else {
            p.lineTo(pt.dx, pt.dy);
          }
        }
        canvas.drawPath(p, glowPaint);
        canvas.drawPath(p, strokePaint);
        break;

      case VectorShapeKind.sunburst:
        canvas.drawCircle(center, r * 0.38, glowPaint);
        canvas.drawCircle(center, r * 0.38, strokePaint);
        for (int i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          canvas.drawLine(
            center + Offset(math.cos(a) * r * 0.55, math.sin(a) * r * 0.55),
            center + Offset(math.cos(a) * r * 0.92, math.sin(a) * r * 0.92),
            strokePaint,
          );
        }
        break;

      case VectorShapeKind.shieldBadge:
        final p = Path()
          ..moveTo(center.dx, center.dy - r * 0.9)
          ..lineTo(center.dx + r * 0.76, center.dy - r * 0.55)
          ..quadraticBezierTo(center.dx + r * 0.74, center.dy + r * 0.36,
              center.dx, center.dy + r * 0.92)
          ..quadraticBezierTo(center.dx - r * 0.74, center.dy + r * 0.36,
              center.dx - r * 0.76, center.dy - r * 0.55)
          ..close();
        drawShapePath(p);
        break;

      case VectorShapeKind.wingPair:
        final left = Path()
          ..moveTo(center.dx - r * 0.1, center.dy + r * 0.15)
          ..cubicTo(center.dx - r * 0.95, center.dy - r * 0.85,
              center.dx - r * 1.05, center.dy + r * 0.25, center.dx - r * 0.18, center.dy + r * 0.48);
        final right = Path()
          ..moveTo(center.dx + r * 0.1, center.dy + r * 0.15)
          ..cubicTo(center.dx + r * 0.95, center.dy - r * 0.85,
              center.dx + r * 1.05, center.dy + r * 0.25, center.dx + r * 0.18, center.dy + r * 0.48);
        canvas.drawPath(left, glowPaint);
        canvas.drawPath(left, strokePaint);
        canvas.drawPath(right, glowPaint);
        canvas.drawPath(right, strokePaint);
        break;

      case VectorShapeKind.circleHalo:
        if (filled) canvas.drawCircle(center, r * 0.78, fillPaint);
        canvas.drawCircle(center, r * 0.82, glowPaint);
        canvas.drawCircle(center, r * 0.82, strokePaint);
        canvas.drawCircle(
            center, r * 0.54, strokePaint..strokeWidth = strokeWidth * 0.6);
        break;

      case VectorShapeKind.trianglePrism:
        final p = Path()
          ..moveTo(center.dx, center.dy - r * 0.88)
          ..lineTo(center.dx + r * 0.85, center.dy + r * 0.68)
          ..lineTo(center.dx - r * 0.85, center.dy + r * 0.68)
          ..close();
        drawShapePath(p);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant DrawingCanvasPainter oldDelegate) {
    return oldDelegate.elements != elements ||
        oldDelegate.activeStroke != activeStroke ||
        oldDelegate.background != background ||
        oldDelegate.selectedId != selectedId ||
        oldDelegate.isExport != isExport;
  }
}
