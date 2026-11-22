import 'package:flutter/material.dart';

import '../../ghost_touch/models/hologram_models.dart';
import '../../ghost_touch/overlay/floating_hologram_experience.dart';
import '../chat_message.dart';

class FlashHologramOverlay extends StatelessWidget {
  final EphemeralChatMessage message;
  final bool isFa;
  final VoidCallback onDismiss;
  final VoidCallback? onQuickReplySketch;
  final ValueChanged<String>? onQuickReaction;
  final ValueChanged<String>? onQuickStickerReply;
  final int autoVanishSeconds;
  final HologramStyle? hologramStyle;
  final FlashCardData? cardData;

  const FlashHologramOverlay({
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
  Widget build(BuildContext context) {
    return FloatingHologramExperience(
      message: message,
      isFa: isFa,
      onDismiss: onDismiss,
      onQuickReplySketch: onQuickReplySketch,
      onQuickReaction: onQuickReaction,
      onQuickStickerReply: onQuickStickerReply,
      autoVanishSeconds: autoVanishSeconds,
      hologramStyle: hologramStyle,
      cardData: cardData,
    );
  }
}
