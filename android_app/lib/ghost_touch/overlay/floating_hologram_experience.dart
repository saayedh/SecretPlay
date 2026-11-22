import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_message.dart';
import '../cards/holographic_card_renderer.dart';
import '../ghost_touch_theme.dart';
import '../models/hologram_models.dart';
import '../stickers/ghost_sticker_catalog.dart';
import '../stickers/ghost_sticker_painter.dart';

/// Advanced Holographic Floating Notification & Interactive Experience (Phase 5).
///
/// Supports:
/// - All 8 [HologramStyle] reveals & ambient effects
/// - [FlashCardData], animated vector stickers, neon drawings, and photos
/// - Single tap -> local particle burst
/// - Double tap -> Mega Heartbeat Shockwave + reaction callback
/// - Quick particle reactions + Quick sticker replies + Quick Sketch action
/// - Position/Intensity/Reduced-Motion customization via [GhostTouchPreferencesService]
class FloatingHologramExperience extends StatefulWidget {
  final EphemeralChatMessage message;
  final bool isFa;
  final VoidCallback onDismiss;
  final VoidCallback? onQuickReplySketch;
  final ValueChanged<String>? onQuickReaction;
  final ValueChanged<String>? onQuickStickerReply;
  final int autoVanishSeconds;
  final HologramStyle? hologramStyle;
  final FlashCardData? cardData;

  const FloatingHologramExperience({
    super.key,
    required this.message,
    required this.isFa,
    required this.onDismiss,
    this.onQuickReplySketch,
    this.onQuickReaction,
    this.onQuickStickerReply,
    this.autoVanishSeconds = 7,
    this.hologramStyle,
    this.cardData,
  });

  @override
  State<FloatingHologramExperience> createState() =>
      _FloatingHologramExperienceState();
}

class _FloatingHologramExperienceState extends State<FloatingHologramExperience>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final AnimationController _ambientCtrl;
  late final AnimationController _burstCtrl;
  late final AnimationController _shockwaveCtrl;

  Timer? _vanishTimer;
  late int _remainingSec;
  bool _timerPaused = false;
  Uint8List? _decodedMedia;
  Offset _lastTapFrac = const Offset(0.5, 0.5);
  Color _burstColor = GhostPalette.neonPink;

  static const List<String> _quickReplyStickerIds = [
    'love_glowing_heart',
    'presence_miss_you',
    'presence_virtual_hug',
    'presence_right_now',
    'love_double_hearts',
  ];

  @override
  void initState() {
    super.initState();
    _remainingSec = (widget.cardData?.durationSec ?? widget.autoVanishSeconds)
        .clamp(3, 30);
    _decodeMediaOnce();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: GhostMotion.hologramReveal,
    )..forward();

    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );
    if (!GhostTouchPreferencesService.instance.current.reducedMotion) {
      _ambientCtrl.repeat();
    }

    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _shockwaveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    _startCountdown();
  }

  @override
  void didUpdateWidget(covariant FloatingHologramExperience oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.mediaBase64 != widget.message.mediaBase64 ||
        oldWidget.message.id != widget.message.id) {
      _decodeMediaOnce();
    }
  }

  void _decodeMediaOnce() {
    final b64 = widget.message.mediaBase64;
    if (b64 == null || b64.isEmpty) {
      _decodedMedia = null;
      return;
    }
    try {
      _decodedMedia = base64Decode(b64);
    } catch (_) {
      _decodedMedia = null;
    }
  }

  void _startCountdown() {
    _vanishTimer?.cancel();
    _vanishTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_timerPaused) return;
      if (_remainingSec <= 1) {
        t.cancel();
        widget.onDismiss();
      } else {
        setState(() => _remainingSec--);
      }
    });
  }

  @override
  void dispose() {
    _vanishTimer?.cancel();
    _entranceCtrl.dispose();
    _ambientCtrl.dispose();
    _burstCtrl.dispose();
    _shockwaveCtrl.dispose();
    super.dispose();
  }

  void _triggerTapBurst(Color color, [Offset localFrac = const Offset(0.5, 0.5)]) {
    HapticFeedback.lightImpact();
    setState(() {
      _lastTapFrac = localFrac;
      _burstColor = color;
    });
    _burstCtrl.forward(from: 0);
  }

  void _triggerMegaHeartbeat() {
    HapticFeedback.heavyImpact();
    setState(() {
      _burstColor = GhostPalette.neonPink;
      _timerPaused = true;
    });
    _shockwaveCtrl.forward(from: 0);
    _burstCtrl.forward(from: 0);
    widget.onQuickReaction?.call('mega_heart');
  }

  HologramStyle _resolveStyle(GhostTouchPreferences prefs) {
    if (widget.hologramStyle != null) return widget.hologramStyle!;
    if (widget.cardData != null) return widget.cardData!.hologramStyle;
    if (widget.message.contentType == ChatContentType.drawing) {
      return HologramStyle.neonDrawingReveal;
    }
    if (widget.message.contentType == ChatContentType.sticker) {
      return HologramStyle.floatingSticker;
    }
    return prefs.defaultStyle;
  }

  Color _resolveAccent(HologramStyle style) {
    if (widget.cardData != null) {
      return GhostPalette.fromHex(
        widget.cardData!.accentColorHex,
        fallback: widget.cardData!.template.accentColor,
      );
    }
    if (widget.message.stickerId != null) {
      return GhostStickerCatalog.findById(widget.message.stickerId).primaryColor;
    }
    switch (style) {
      case HologramStyle.floatingHeart:
        return GhostPalette.neonPink;
      case HologramStyle.holographicCard:
        return GhostPalette.electricCyan;
      case HologramStyle.cosmicPortal:
        return GhostPalette.neonPurple;
      case HologramStyle.particleAssembly:
        return GhostPalette.electricBlue;
      case HologramStyle.neonDrawingReveal:
        return GhostPalette.neonPink;
      case HologramStyle.floatingSticker:
        return GhostPalette.neonGreen;
      case HologramStyle.digitalWave:
        return GhostPalette.electricCyan;
      case HologramStyle.surpriseBurst:
        return GhostPalette.amberGold;
    }
  }

  Alignment _resolveAlignment(OverlayPosition pos) {
    switch (pos) {
      case OverlayPosition.top:
        return Alignment.topCenter;
      case OverlayPosition.center:
        return Alignment.center;
      case OverlayPosition.bottom:
        return Alignment.bottomCenter;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFa = widget.isFa;
    return ValueListenableBuilder<GhostTouchPreferences>(
      valueListenable: GhostTouchPreferencesService.instance.notifier,
      builder: (context, prefs, _) {
        if (prefs.reducedMotion && _ambientCtrl.isAnimating) {
          _ambientCtrl.stop();
        } else if (!prefs.reducedMotion && !_ambientCtrl.isAnimating) {
          _ambientCtrl.repeat();
        }

        final style = _resolveStyle(prefs);
        final accent = _resolveAccent(style);

        return Directionality(
          textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
          child: Material(
            color: Colors.black.withOpacity(0.58),
            child: SafeArea(
              child: Stack(
                children: [
                  // Tap outside to dismiss
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onDismiss,
                    ),
                  ),

                  // Ambient 8-Style Hologram Visualizer Layer
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([
                          _ambientCtrl,
                          _burstCtrl,
                          _shockwaveCtrl,
                        ]),
                        builder: (_, __) => CustomPaint(
                          painter: _HologramBackdropPainter(
                            style: style,
                            accent: accent,
                            ambientProgress:
                                prefs.reducedMotion ? 0.25 : _ambientCtrl.value,
                            burstProgress: _burstCtrl.value,
                            burstCenterFrac: _lastTapFrac,
                            burstColor: _burstColor,
                            shockwaveProgress: _shockwaveCtrl.value,
                            intensity: prefs.effectIntensity,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Main Holographic Floating Card
                  Align(
                    alignment: _resolveAlignment(prefs.position),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                      child: ScaleTransition(
                        scale: CurvedAnimation(
                          parent: _entranceCtrl,
                          curve: GhostMotion.springCurve,
                        ),
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                            parent: _entranceCtrl,
                            curve: Curves.easeOut,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: GhostGlassCard(
                              accentColor: accent,
                              borderRadius: 28,
                              reducedMotion: prefs.reducedMotion,
                              glowOpacity: 0.34 * prefs.effectIntensity,
                              padding: const EdgeInsets.all(16),
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildHeaderRow(isFa, style, accent),
                                    const SizedBox(height: 12),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (d) {
                                        final box = context.findRenderObject()
                                            as RenderBox?;
                                        final sz =
                                            box?.size ?? const Size(360, 480);
                                        _triggerTapBurst(
                                          accent,
                                          Offset(
                                            (d.globalPosition.dx / sz.width)
                                                .clamp(0.1, 0.9),
                                            (d.globalPosition.dy / sz.height)
                                                .clamp(0.1, 0.9),
                                          ),
                                        );
                                      },
                                      onDoubleTap: _triggerMegaHeartbeat,
                                      child: _buildBody(isFa, accent, prefs),
                                    ),
                                    const SizedBox(height: 12),
                                    _buildInteractiveFooter(isFa, accent),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow(bool isFa, HologramStyle style, Color accent) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(style.icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                style.label(isFa),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Pause / Countdown pill
        InkWell(
          onTap: () => setState(() => _timerPaused = !_timerPaused),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _timerPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 14,
                  color: GhostPalette.electricCyan,
                ),
                const SizedBox(width: 3),
                Text(
                  '${_remainingSec}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        InkWell(
          onTap: widget.onDismiss,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
      bool isFa, Color accent, GhostTouchPreferences prefs) {
    if (widget.cardData != null) {
      return HolographicCardRenderer(
        data: widget.cardData!,
        isFa: isFa,
        compact: false,
        reducedMotion: prefs.reducedMotion,
        sharedAnimation: _ambientCtrl,
      );
    }

    if (widget.message.contentType == ChatContentType.sticker) {
      final def = GhostStickerCatalog.findById(widget.message.stickerId);
      return Column(
        children: [
          AnimatedBuilder(
            animation: _ambientCtrl,
            builder: (_, child) {
              final bob = prefs.reducedMotion
                  ? 0.0
                  : math.sin(_ambientCtrl.value * math.pi * 2) * 5.0;
              return Transform.translate(
                offset: Offset(0, bob),
                child: child,
              );
            },
            child: GhostStickerArtwork(
              sticker: def,
              size: 118,
              sharedAnimation: _ambientCtrl,
              reducedMotion: prefs.reducedMotion,
              intensity: prefs.effectIntensity,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isFa ? def.titleFa : def.titleEn,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }

    if (_decodedMedia != null) {
      return Column(
        children: [
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withOpacity(0.5)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: Image.memory(
                _decodedMedia!,
                fit: BoxFit.contain,
              ),
            ),
          ),
          if (widget.message.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.message.text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Text(
        widget.message.text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildInteractiveFooter(bool isFa, Color accent) {
    return Column(
      children: [
        Text(
          isFa
              ? 'ضربه برای افکت • دابل‌تپ برای شوک قلب!'
              : 'Tap for sparkles • Double-tap for heartbeat shockwave',
          style: TextStyle(
            color: Colors.white.withOpacity(0.45),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 8),

        // Quick Particle Reactions + Sketch Reply
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _reactionPill('heart', Icons.favorite_rounded, GhostPalette.neonPink),
            const SizedBox(width: 8),
            _reactionPill('spark', Icons.auto_awesome_rounded, GhostPalette.amberGold),
            const SizedBox(width: 8),
            _reactionPill('bolt', Icons.bolt_rounded, GhostPalette.electricCyan),
            const SizedBox(width: 8),
            _reactionPill('hug', Icons.volunteer_activism_rounded, GhostPalette.neonGreen),
            if (widget.onQuickReplySketch != null) ...[
              const SizedBox(width: 10),
              InkWell(
                onTap: widget.onQuickReplySketch,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accent, GhostPalette.neonPurple],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.brush_rounded,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        isFa ? 'پاسخ' : 'Reply',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),

        if (widget.onQuickStickerReply != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              shrinkWrap: true,
              scrollDirection: Axis.horizontal,
              itemCount: _quickReplyStickerIds.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final def =
                    GhostStickerCatalog.findById(_quickReplyStickerIds[i]);
                return InkWell(
                  onTap: () {
                    _triggerTapBurst(def.primaryColor);
                    widget.onQuickStickerReply!(def.id);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 40,
                    height: 40,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: def.primaryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: def.primaryColor.withOpacity(0.4)),
                    ),
                    child: GhostStickerArtwork(
                      sticker: def,
                      size: 30,
                      sharedAnimation: _ambientCtrl,
                      reducedMotion: true,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _reactionPill(String reactionKey, IconData icon, Color color) {
    return InkWell(
      onTap: () {
        _triggerTapBurst(color);
        widget.onQuickReaction?.call(reactionKey);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}

class _HologramBackdropPainter extends CustomPainter {
  final HologramStyle style;
  final Color accent;
  final double ambientProgress;
  final double burstProgress;
  final Offset burstCenterFrac;
  final Color burstColor;
  final double shockwaveProgress;
  final double intensity;

  const _HologramBackdropPainter({
    required this.style,
    required this.accent,
    required this.ambientProgress,
    required this.burstProgress,
    required this.burstCenterFrac,
    required this.burstColor,
    required this.shockwaveProgress,
    required this.intensity,
  });

  double get _phase => ambientProgress * math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final minDim = math.min(size.width, size.height);
    final k = intensity.clamp(0.2, 1.0);

    // Style-specific ambient hologram backdrops
    switch (style) {
      case HologramStyle.floatingHeart:
        for (int i = 0; i < 3; i++) {
          final r = minDim * (0.25 + i * 0.1 + 0.03 * math.sin(_phase + i));
          final c = center;
          final heart = Path()
            ..moveTo(c.dx, c.dy + r * 0.72)
            ..cubicTo(c.dx - r * 1.15, c.dy + r * 0.1, c.dx - r * 0.9,
                c.dy - r * 0.85, c.dx, c.dy - r * 0.25)
            ..cubicTo(c.dx + r * 0.9, c.dy - r * 0.85, c.dx + r * 1.15,
                c.dy + r * 0.1, c.dx, c.dy + r * 0.72);
          canvas.drawPath(
            heart,
            Paint()
              ..color = accent.withOpacity((0.20 - i * 0.05) * k)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0,
          );
        }
        break;

      case HologramStyle.cosmicPortal:
        for (int i = 0; i < 4; i++) {
          canvas.save();
          canvas.translate(center.dx, center.dy);
          canvas.rotate(_phase * (i.isEven ? 1 : -1) + i * 0.6);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: minDim * (0.65 + i * 0.12),
              height: minDim * (0.38 + i * 0.08),
            ),
            Paint()
              ..color = (i.isEven ? accent : GhostPalette.electricCyan)
                  .withOpacity(0.20 * k)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6,
          );
          canvas.restore();
        }
        break;

      case HologramStyle.particleAssembly:
      case HologramStyle.surpriseBurst:
        for (int i = 0; i < 20; i++) {
          final a = (i / 20) * math.pi * 2 + _phase * 0.5;
          final dist = minDim *
              (style == HologramStyle.particleAssembly
                  ? (0.48 - 0.12 * ((ambientProgress + i * 0.07) % 1.0))
                  : (0.28 + 0.22 * ((ambientProgress + i * 0.09) % 1.0)));
          final pt = center + Offset(math.cos(a) * dist, math.sin(a) * dist);
          canvas.drawCircle(
            pt,
            2.2 + (i % 3),
            Paint()..color = accent.withOpacity(0.45 * k),
          );
        }
        break;

      case HologramStyle.neonDrawingReveal:
        final scanY = ambientProgress * size.height;
        canvas.drawLine(
          Offset(0, scanY),
          Offset(size.width, scanY),
          Paint()
            ..color = GhostPalette.electricCyan.withOpacity(0.28 * k)
            ..strokeWidth = 2.2,
        );
        break;

      case HologramStyle.digitalWave:
        for (int wIdx = 0; wIdx < 2; wIdx++) {
          final path = Path()..moveTo(0, size.height * 0.5);
          for (double x = 0; x <= size.width; x += 12) {
            final y = size.height * 0.5 +
                math.sin(x * 0.02 + _phase * (wIdx + 1)) * (40 + wIdx * 18);
            path.lineTo(x, y);
          }
          canvas.drawPath(
            path,
            Paint()
              ..color = (wIdx == 0 ? accent : GhostPalette.neonGreen)
                  .withOpacity(0.24 * k)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0,
          );
        }
        break;

      case HologramStyle.holographicCard:
      case HologramStyle.floatingSticker:
        final pulseR = minDim * (0.36 + 0.05 * math.sin(_phase));
        canvas.drawCircle(
          center,
          pulseR,
          Paint()
            ..color = accent.withOpacity(0.18 * k)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
        break;
    }

    // Tap Particle Burst
    if (burstProgress > 0 && burstProgress < 1.0) {
      final origin = Offset(
        burstCenterFrac.dx * size.width,
        burstCenterFrac.dy * size.height,
      );
      final fade = 1.0 - burstProgress;
      for (int i = 0; i < 14; i++) {
        final a = (i / 14) * math.pi * 2;
        final d = burstProgress * minDim * 0.28;
        canvas.drawCircle(
          origin + Offset(math.cos(a) * d, math.sin(a) * d),
          3.2 * fade,
          Paint()..color = burstColor.withOpacity(fade * 0.9),
        );
      }
    }

    // Double-tap Mega Heartbeat Shockwave
    if (shockwaveProgress > 0 && shockwaveProgress < 1.0) {
      final fade = 1.0 - shockwaveProgress;
      final rad = shockwaveProgress * minDim * 0.65;
      canvas.drawCircle(
        center,
        rad,
        Paint()
          ..color = GhostPalette.neonPink.withOpacity(fade * 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5 * fade,
      );
      canvas.drawCircle(
        center,
        rad * 0.72,
        Paint()
          ..color = GhostPalette.electricCyan.withOpacity(fade * 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8 * fade,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HologramBackdropPainter old) => true;
}
