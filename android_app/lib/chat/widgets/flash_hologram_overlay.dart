import 'dart:convert';
import 'package:flutter/material.dart';
import '../chat_message.dart';
import 'cyber_sticker_sheet.dart';

class FlashHologramOverlay extends StatefulWidget {
  final EphemeralChatMessage message;
  final bool isFa;
  final VoidCallback onDismiss;
  final VoidCallback? onQuickReplySketch;

  const FlashHologramOverlay({
    super.key,
    required this.message,
    required this.isFa,
    required this.onDismiss,
    this.onQuickReplySketch,
  });

  @override
  State<FlashHologramOverlay> createState() => _FlashHologramOverlayState();
}

class _FlashHologramOverlayState extends State<FlashHologramOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isFa = widget.isFa;
    final sticker = msg.contentType == ChatContentType.sticker
        ? CyberStickerCatalog.findById(msg.stickerId)
        : null;
    final accentColor = sticker?.neonColor ?? const Color(0xFFFF007A);

    return Directionality(
      textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        color: Colors.black.withOpacity(0.88),
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final glow = 12.0 + (_pulseController.value * 18.0);
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(22),
                  constraints: const BoxConstraints(maxWidth: 380),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101018),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: accentColor, width: 2.2),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.55),
                        blurRadius: glow,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: accentColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, color: accentColor, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          isFa
                              ? 'پیام هولوگرافیک زنده روی صفحه!'
                              : 'LIVE HOLOGRAM FLASH RECEIVED!',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Rich Visual Content (Sticker / Drawing / Photo / Text)
                  if (msg.contentType == ChatContentType.sticker && sticker != null) ...[
                    Text(
                      sticker.emoji,
                      style: const TextStyle(fontSize: 72),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isFa ? sticker.titleFa : sticker.titleEn,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: sticker.neonColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ] else if ((msg.contentType == ChatContentType.drawing ||
                          msg.contentType == ChatContentType.image) &&
                      msg.mediaBase64 != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: BoxDecoration(
                          color: const Color(0xFF09090D),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Image.memory(
                          base64Decode(msg.mediaBase64!),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white38,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ],

                  if (msg.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      msg.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),

                  // Dismiss & Quick Sketch Reply Buttons
                  Row(
                    children: [
                      if (widget.onQuickReplySketch != null) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.brush_rounded, size: 18, color: Color(0xFF00FFA3)),
                            label: Text(
                              isFa ? 'پاسخ با نقاشی' : 'Reply Sketch',
                              style: const TextStyle(color: Colors.white),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF00FFA3)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              widget.onDismiss();
                              widget.onQuickReplySketch!();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(
                            isFa ? 'دیدم / بستن' : 'Got It!',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: widget.onDismiss,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
