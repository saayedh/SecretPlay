import 'package:flutter/material.dart';

import '../../ghost_touch/drawing/ultimate_drawing_studio.dart';
import '../../ghost_touch/models/hologram_models.dart';

class NeonSketchResult {
  final String pngBase64;
  final String caption;
  final bool flashOnLockScreen;
  final HologramStyle hologramStyle;
  final int durationSec;

  const NeonSketchResult({
    required this.pngBase64,
    required this.caption,
    required this.flashOnLockScreen,
    this.hologramStyle = HologramStyle.neonDrawingReveal,
    this.durationSec = 7,
  });
}

class NeonSketchDialog extends StatelessWidget {
  final bool isFa;
  final bool initialFlash;
  final bool signatureMode;

  const NeonSketchDialog({
    super.key,
    required this.isFa,
    this.initialFlash = false,
    this.signatureMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return UltimateDrawingStudio(
      isFa: isFa,
      initialFlash: initialFlash,
      signatureMode: signatureMode,
    );
  }
}
