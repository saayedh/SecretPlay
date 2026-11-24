import 'package:flutter/material.dart';
import '../ghost_touch_theme.dart';

/// 11 expressive brushes for the Ultimate Drawing Studio.
enum BrushKind {
  neon,
  softAirbrush,
  sparkleTrail,
  pencil,
  marker,
  highlighter,
  calligraphy,
  rainbow,
  dottedBeam,
  hologramRibbon,
  eraser,
}

extension BrushKindExt on BrushKind {
  String label(bool isFa) {
    switch (this) {
      case BrushKind.neon:
        return isFa ? 'نئون لیزری' : 'Laser Neon';
      case BrushKind.softAirbrush:
        return isFa ? 'اسپری محو' : 'Soft Airbrush';
      case BrushKind.sparkleTrail:
        return isFa ? 'دنباله ستاره‌ای' : 'Sparkle Trail';
      case BrushKind.pencil:
        return isFa ? 'مداد گرافیتی' : 'Pencil';
      case BrushKind.marker:
        return isFa ? 'ماژیک روان' : 'Marker';
      case BrushKind.highlighter:
        return isFa ? 'هایلایتر نئونی' : 'Highlighter';
      case BrushKind.calligraphy:
        return isFa ? 'خوشنویسی' : 'Calligraphy';
      case BrushKind.rainbow:
        return isFa ? 'منشور رنگین‌کمان' : 'Rainbow Prism';
      case BrushKind.dottedBeam:
        return isFa ? 'نور نقطه‌ای' : 'Dotted Beam';
      case BrushKind.hologramRibbon:
        return isFa ? 'روبان هولوگرام' : 'Holo Ribbon';
      case BrushKind.eraser:
        return isFa ? 'پاک‌کن' : 'Eraser';
    }
  }

  IconData get icon {
    switch (this) {
      case BrushKind.neon:
        return Icons.flare_rounded;
      case BrushKind.softAirbrush:
        return Icons.blur_on_rounded;
      case BrushKind.sparkleTrail:
        return Icons.auto_awesome_rounded;
      case BrushKind.pencil:
        return Icons.create_rounded;
      case BrushKind.marker:
        return Icons.brush_rounded;
      case BrushKind.highlighter:
        return Icons.border_color_rounded;
      case BrushKind.calligraphy:
        return Icons.edit_rounded;
      case BrushKind.rainbow:
        return Icons.palette_rounded;
      case BrushKind.dottedBeam:
        return Icons.grain_rounded;
      case BrushKind.hologramRibbon:
        return Icons.waves_rounded;
      case BrushKind.eraser:
        return Icons.cleaning_services_rounded;
    }
  }
}

/// 28 glowing vector shape stamps & geometric primitives.
enum VectorShapeKind {
  heart,
  doubleHeart,
  star5,
  star6,
  star4Sparkle,
  infinity,
  crown,
  lightning,
  crescentMoon,
  ringedPlanet,
  butterfly,
  crystalDiamond,
  flowerPetal,
  rose,
  cloud,
  square,
  roundedSquare,
  ellipse,
  neonArrow,
  speechBubble,
  hexagon,
  musicNote,
  spiralVortex,
  sunburst,
  shieldBadge,
  wingPair,
  circleHalo,
  trianglePrism,
}

extension VectorShapeKindExt on VectorShapeKind {
  String label(bool isFa) {
    switch (this) {
      case VectorShapeKind.heart:
        return isFa ? 'قلب نئونی' : 'Heart';
      case VectorShapeKind.doubleHeart:
        return isFa ? 'دو قلب' : 'Double Heart';
      case VectorShapeKind.star5:
        return isFa ? 'ستاره ۵ پر' : 'Star';
      case VectorShapeKind.star6:
        return isFa ? 'ستاره ۶ پر' : '6-Star';
      case VectorShapeKind.star4Sparkle:
        return isFa ? 'درخشش ۴ پر' : 'Sparkle';
      case VectorShapeKind.infinity:
        return isFa ? 'بی‌نهایت' : 'Infinity';
      case VectorShapeKind.crown:
        return isFa ? 'تاج' : 'Crown';
      case VectorShapeKind.lightning:
        return isFa ? 'آذرخش' : 'Lightning';
      case VectorShapeKind.crescentMoon:
        return isFa ? 'هلال ماه' : 'Moon';
      case VectorShapeKind.ringedPlanet:
        return isFa ? 'سیاره حلقه‌دار' : 'Planet';
      case VectorShapeKind.butterfly:
        return isFa ? 'پروانه' : 'Butterfly';
      case VectorShapeKind.crystalDiamond:
        return isFa ? 'الماس کریستال' : 'Crystal';
      case VectorShapeKind.flowerPetal:
        return isFa ? 'گل نئونی' : 'Blossom';
      case VectorShapeKind.rose:
        return isFa ? 'گل رز' : 'Rose';
      case VectorShapeKind.cloud:
        return isFa ? 'ابر' : 'Cloud';
      case VectorShapeKind.square:
        return isFa ? 'مربع' : 'Square';
      case VectorShapeKind.roundedSquare:
        return isFa ? 'مربع گرد' : 'Rounded Box';
      case VectorShapeKind.ellipse:
        return isFa ? 'بیضی' : 'Ellipse';
      case VectorShapeKind.neonArrow:
        return isFa ? 'پیکان' : 'Arrow';
      case VectorShapeKind.speechBubble:
        return isFa ? 'حباب متن' : 'Bubble';
      case VectorShapeKind.hexagon:
        return isFa ? 'شش‌ضلعی سایبری' : 'Hexagon';
      case VectorShapeKind.musicNote:
        return isFa ? 'نت موسیقی' : 'Music';
      case VectorShapeKind.spiralVortex:
        return isFa ? 'مارپیچ انرژی' : 'Vortex';
      case VectorShapeKind.sunburst:
        return isFa ? 'پرتو خورشید' : 'Sunburst';
      case VectorShapeKind.shieldBadge:
        return isFa ? 'سپر محافظ' : 'Shield';
      case VectorShapeKind.wingPair:
        return isFa ? 'بال فرشته' : 'Wings';
      case VectorShapeKind.circleHalo:
        return isFa ? 'هاله مدور' : 'Halo';
      case VectorShapeKind.trianglePrism:
        return isFa ? 'منشور مثلث' : 'Prism';
    }
  }
}

/// 6 curated canvas background styles.
enum CanvasBackgroundKind {
  deepSpace,
  cyberGrid,
  violetNebula,
  auroraDark,
  starfield,
  transparentGlass,
}

extension CanvasBackgroundKindExt on CanvasBackgroundKind {
  String label(bool isFa) {
    switch (this) {
      case CanvasBackgroundKind.deepSpace:
        return isFa ? 'فضای عمیق' : 'Deep Space';
      case CanvasBackgroundKind.cyberGrid:
        return isFa ? 'شبکه سایبری' : 'Cyber Grid';
      case CanvasBackgroundKind.violetNebula:
        return isFa ? 'سحابی بنفش' : 'Violet Nebula';
      case CanvasBackgroundKind.auroraDark:
        return isFa ? 'شفق قطبی' : 'Aurora Glow';
      case CanvasBackgroundKind.starfield:
        return isFa ? 'کهکشان ستاره' : 'Starfield';
      case CanvasBackgroundKind.transparentGlass:
        return isFa ? 'پس‌زمینه شفاف' : 'Transparent';
    }
  }

  Color get swatchColor {
    switch (this) {
      case CanvasBackgroundKind.deepSpace:
        return GhostPalette.deepSpace;
      case CanvasBackgroundKind.cyberGrid:
        return const Color(0xFF0A1424);
      case CanvasBackgroundKind.violetNebula:
        return const Color(0xFF1F1035);
      case CanvasBackgroundKind.auroraDark:
        return const Color(0xFF0A2422);
      case CanvasBackgroundKind.starfield:
        return const Color(0xFF0E1022);
      case CanvasBackgroundKind.transparentGlass:
        return const Color(0xFF23263A);
    }
  }
}

enum StudioInteractionMode {
  draw,
  panZoom,
  select,
}

class DrawingPoint {
  final Offset offset;
  final double pressure;

  const DrawingPoint({
    required this.offset,
    this.pressure = 1.0,
  });

  DrawingPoint translate(Offset delta) =>
      DrawingPoint(offset: offset + delta, pressure: pressure);
}

class DrawingStroke {
  final String id;
  final List<DrawingPoint> points;
  final Color color;
  final Color? gradientColor;
  final double strokeWidth;
  final double opacity;
  final BrushKind brush;

  const DrawingStroke({
    required this.id,
    required this.points,
    required this.color,
    this.gradientColor,
    required this.strokeWidth,
    this.opacity = 1.0,
    required this.brush,
  });

  DrawingStroke copyWith({
    List<DrawingPoint>? points,
    Color? color,
    Color? gradientColor,
    double? strokeWidth,
    double? opacity,
    BrushKind? brush,
  }) {
    return DrawingStroke(
      id: id,
      points: points ?? this.points,
      color: color ?? this.color,
      gradientColor: gradientColor ?? this.gradientColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      opacity: opacity ?? this.opacity,
      brush: brush ?? this.brush,
    );
  }
}

class CanvasShapeItem {
  final String id;
  final VectorShapeKind kind;
  final Offset center;
  final double size;
  final double rotation;
  final Color color;
  final Color? secondaryColor;
  final bool filled;
  final double strokeWidth;

  const CanvasShapeItem({
    required this.id,
    required this.kind,
    required this.center,
    this.size = 86,
    this.rotation = 0,
    required this.color,
    this.secondaryColor,
    this.filled = false,
    this.strokeWidth = 3.2,
  });

  CanvasShapeItem copyWith({
    Offset? center,
    double? size,
    double? rotation,
    Color? color,
    Color? secondaryColor,
    bool? filled,
    double? strokeWidth,
  }) {
    return CanvasShapeItem(
      id: id,
      kind: kind,
      center: center ?? this.center,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      color: color ?? this.color,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      filled: filled ?? this.filled,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }

  Rect get hitRect =>
      Rect.fromCenter(center: center, width: size * 1.12, height: size * 1.12);
}

class CanvasTextItem {
  final String id;
  final String text;
  final Offset center;
  final double fontSize;
  final double rotation;
  final Color color;
  final bool neonGlow;
  final String fontFamily;

  const CanvasTextItem({
    required this.id,
    required this.text,
    required this.center,
    this.fontSize = 26,
    this.rotation = 0,
    this.color = Colors.white,
    this.neonGlow = true,
    this.fontFamily = 'sans',
  });

  CanvasTextItem copyWith({
    String? text,
    Offset? center,
    double? fontSize,
    double? rotation,
    Color? color,
    bool? neonGlow,
    String? fontFamily,
  }) {
    return CanvasTextItem(
      id: id,
      text: text ?? this.text,
      center: center ?? this.center,
      fontSize: fontSize ?? this.fontSize,
      rotation: rotation ?? this.rotation,
      color: color ?? this.color,
      neonGlow: neonGlow ?? this.neonGlow,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }

  Rect hitRectFor(Size canvasSize) {
    final w = (text.length * fontSize * 0.62).clamp(64.0, canvasSize.width * 0.9);
    final h = (fontSize * 1.8).clamp(44.0, 220.0);
    return Rect.fromCenter(center: center, width: w, height: h);
  }
}

class CanvasStickerItem {
  final String id;
  final String stickerId;
  final Offset center;
  final double size;
  final double rotation;

  const CanvasStickerItem({
    required this.id,
    required this.stickerId,
    required this.center,
    this.size = 84,
    this.rotation = 0,
  });

  CanvasStickerItem copyWith({
    Offset? center,
    double? size,
    double? rotation,
  }) {
    return CanvasStickerItem(
      id: id,
      stickerId: stickerId,
      center: center ?? this.center,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
    );
  }

  Rect get hitRect =>
      Rect.fromCenter(center: center, width: size * 1.1, height: size * 1.1);
}

enum CanvasElementKind { stroke, shape, text, sticker }

class CanvasElement {
  final CanvasElementKind kind;
  final DrawingStroke? stroke;
  final CanvasShapeItem? shape;
  final CanvasTextItem? textItem;
  final CanvasStickerItem? stickerItem;
  final bool visible;

  const CanvasElement._({
    required this.kind,
    this.stroke,
    this.shape,
    this.textItem,
    this.stickerItem,
    this.visible = true,
  });

  factory CanvasElement.fromStroke(DrawingStroke s, {bool visible = true}) =>
      CanvasElement._(kind: CanvasElementKind.stroke, stroke: s, visible: visible);

  factory CanvasElement.fromShape(CanvasShapeItem s, {bool visible = true}) =>
      CanvasElement._(kind: CanvasElementKind.shape, shape: s, visible: visible);

  factory CanvasElement.fromText(CanvasTextItem t, {bool visible = true}) =>
      CanvasElement._(kind: CanvasElementKind.text, textItem: t, visible: visible);

  factory CanvasElement.fromSticker(CanvasStickerItem st, {bool visible = true}) =>
      CanvasElement._(
        kind: CanvasElementKind.sticker,
        stickerItem: st,
        visible: visible,
      );

  CanvasElement copyWith({
    bool? visible,
    DrawingStroke? stroke,
    CanvasShapeItem? shape,
    CanvasTextItem? textItem,
    CanvasStickerItem? stickerItem,
  }) {
    return CanvasElement._(
      kind: kind,
      stroke: stroke ?? this.stroke,
      shape: shape ?? this.shape,
      textItem: textItem ?? this.textItem,
      stickerItem: stickerItem ?? this.stickerItem,
      visible: visible ?? this.visible,
    );
  }

  String layerTitle(bool isFa) {
    switch (kind) {
      case CanvasElementKind.stroke:
        return stroke?.brush.label(isFa) ?? (isFa ? 'خط قلم' : 'Stroke');
      case CanvasElementKind.shape:
        return shape?.kind.label(isFa) ?? (isFa ? 'شکل' : 'Shape');
      case CanvasElementKind.text:
        final txt = textItem?.text ?? '';
        if (txt.isEmpty) return isFa ? 'متن' : 'Text';
        return txt.length > 16 ? '${txt.substring(0, 16)}…' : txt;
      case CanvasElementKind.sticker:
        return isFa ? 'استیکر وکتور' : 'Sticker';
    }
  }

  String get id {
    switch (kind) {
      case CanvasElementKind.stroke:
        return stroke!.id;
      case CanvasElementKind.shape:
        return shape!.id;
      case CanvasElementKind.text:
        return textItem!.id;
      case CanvasElementKind.sticker:
        return stickerItem!.id;
    }
  }
}

class CanvasSnapshot {
  final List<CanvasElement> elements;
  final CanvasBackgroundKind background;

  const CanvasSnapshot({
    this.elements = const [],
    this.background = CanvasBackgroundKind.deepSpace,
  });
}
