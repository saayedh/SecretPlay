import 'package:flutter/material.dart';

import '../../ghost_touch/models/hologram_models.dart';
import '../../ghost_touch/stickers/ghost_sticker_catalog.dart';
import '../../ghost_touch/stickers/ghost_sticker_studio.dart';

/// Backward-compatible wrapper around [GhostStickerDef] for callers expecting [CyberSticker].
class CyberSticker {
  final String id;
  final String emoji;
  final String titleFa;
  final String titleEn;
  final String category;
  final Color neonColor;

  const CyberSticker({
    required this.id,
    required this.emoji,
    required this.titleFa,
    required this.titleEn,
    required this.category,
    required this.neonColor,
  });

  factory CyberSticker.fromGhostDef(GhostStickerDef def) {
    return CyberSticker(
      id: def.id,
      emoji: def.fallbackGlyph,
      titleFa: def.titleFa,
      titleEn: def.titleEn,
      category: def.category.name,
      neonColor: def.primaryColor,
    );
  }

  GhostStickerDef get ghostDef => GhostStickerCatalog.findById(id);
}

class CyberStickerCatalog {
  static List<CyberSticker> get all =>
      GhostStickerCatalog.all.map(CyberSticker.fromGhostDef).toList();

  static CyberSticker findById(String? id) {
    return CyberSticker.fromGhostDef(GhostStickerCatalog.findById(id));
  }
}

class CyberStickerSelection {
  final CyberSticker sticker;
  final bool flashOnScreen;
  final HologramStyle hologramStyle;
  final int durationSec;
  final String? signaturePngBase64;
  final String? signatureName;

  const CyberStickerSelection({
    required this.sticker,
    required this.flashOnScreen,
    this.hologramStyle = HologramStyle.floatingSticker,
    this.durationSec = 7,
    this.signaturePngBase64,
    this.signatureName,
  });
}

class CyberStickerSheet extends StatelessWidget {
  final bool isFa;
  final bool initialFlashOnScreen;
  final Future<SignatureSticker?> Function(BuildContext context)?
      onCreateSignature;

  const CyberStickerSheet({
    super.key,
    required this.isFa,
    this.initialFlashOnScreen = false,
    this.onCreateSignature,
  });

  @override
  Widget build(BuildContext context) {
    return GhostStickerStudio(
      isFa: isFa,
      initialFlashOnScreen: initialFlashOnScreen,
      onCreateSignature: onCreateSignature,
    );
  }
}
