import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class _StrokePoint {
  final Offset offset;
  final Color color;
  final double strokeWidth;

  const _StrokePoint({
    required this.offset,
    required this.color,
    required this.strokeWidth,
  });
}

class NeonSketchResult {
  final String pngBase64;
  final String caption;
  final bool flashOnLockScreen;

  const NeonSketchResult({
    required this.pngBase64,
    required this.caption,
    required this.flashOnLockScreen,
  });
}

class NeonSketchDialog extends StatefulWidget {
  final bool isFa;
  final bool initialFlash;

  const NeonSketchDialog({
    super.key,
    required this.isFa,
    this.initialFlash = true,
  });

  @override
  State<NeonSketchDialog> createState() => _NeonSketchDialogState();
}

class _NeonSketchDialogState extends State<NeonSketchDialog> {
  final GlobalKey _repaintKey = GlobalKey();
  final TextEditingController _captionController = TextEditingController();
  final List<List<_StrokePoint>> _strokes = [];
  List<_StrokePoint> _activeStroke = [];

  Color _selectedColor = const Color(0xFF00FFA3);
  double _strokeWidth = 4.5;
  late bool _flashToScreen;
  bool _isExporting = false;

  static const List<Color> _neonPalette = [
    Color(0xFF00FFA3), // Neon Green
    Color(0xFF00E5FF), // Cyber Cyan
    Color(0xFFFF007A), // Neon Pink
    Color(0xFFFFD60A), // Electric Yellow
    Color(0xFFBF5AF2), // Neon Purple
    Color(0xFFFF453A), // Laser Red
    Colors.white,
  ];

  @override
  void initState() {
    super.initState();
    _flashToScreen = widget.initialFlash;
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() => _strokes.removeLast());
    }
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _activeStroke.clear();
    });
  }

  Future<void> _exportAndSend() async {
    if (_isExporting) return;
    if (_strokes.isEmpty && _captionController.text.trim().isEmpty) return;

    setState(() => _isExporting = true);
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 1.5);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final b64 = base64Encode(pngBytes);

      if (!mounted) return;
      Navigator.of(context).pop(
        NeonSketchResult(
          pngBase64: b64,
          caption: _captionController.text.trim(),
          flashOnLockScreen: _flashToScreen,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFa = widget.isFa;
    return Directionality(
      textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: const Color(0xFF141418),
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF64D2FF), width: 1.2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.brush_rounded, color: Color(0xFF00FFA3), size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isFa ? 'بوم نقاشی و پیام نئونی زنده' : 'Live Neon Sketch & Flash Note',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.undo_rounded, color: Colors.white70, size: 20),
                      tooltip: isFa ? 'برگشت' : 'Undo',
                      onPressed: _undo,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFFF453A), size: 20),
                      tooltip: isFa ? 'پاک کردن' : 'Clear',
                      onPressed: _clear,
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Drawing Canvas
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 250,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF09090D),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: RepaintBoundary(
                      key: _repaintKey,
                      child: Container(
                        color: const Color(0xFF09090D),
                        child: GestureDetector(
                          onPanStart: (details) {
                            setState(() {
                              _activeStroke = [
                                _StrokePoint(
                                  offset: details.localPosition,
                                  color: _selectedColor,
                                  strokeWidth: _strokeWidth,
                                ),
                              ];
                              _strokes.add(_activeStroke);
                            });
                          },
                          onPanUpdate: (details) {
                            setState(() {
                              _activeStroke.add(
                                _StrokePoint(
                                  offset: details.localPosition,
                                  color: _selectedColor,
                                  strokeWidth: _strokeWidth,
                                ),
                              );
                            });
                          },
                          onPanEnd: (_) {
                            _activeStroke = [];
                          },
                          child: CustomPaint(
                            painter: _NeonSketchPainter(strokes: _strokes),
                            size: const Size(double.infinity, 250),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Color Palette & Brush Size
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: _neonPalette.map((color) {
                        final isSelected = _selectedColor == color;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedColor = color),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: isSelected ? 28 : 22,
                            height: isSelected ? 28 : 22,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: 2.2,
                              ),
                              boxShadow: isSelected
                                  ? [BoxShadow(color: color.withOpacity(0.7), blurRadius: 8)]
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    // Stroke width toggle
                    IconButton(
                      icon: Icon(
                        Icons.circle,
                        color: _selectedColor,
                        size: _strokeWidth * 2.5,
                      ),
                      tooltip: isFa ? 'ضخامت قلم' : 'Brush Size',
                      onPressed: () {
                        setState(() {
                          if (_strokeWidth < 4) {
                            _strokeWidth = 5.5;
                          } else if (_strokeWidth < 7) {
                            _strokeWidth = 9.0;
                          } else {
                            _strokeWidth = 2.8;
                          }
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Optional short message caption
                TextField(
                  controller: _captionController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: isFa
                        ? 'متن دلخواه زیر نقاشی (مثلاً: کجایی؟ بیدار شو ❤️)...'
                        : 'Optional caption below sketch...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF1C1C22),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Flash on Peer Lock-Screen Switch
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _flashToScreen
                        ? const Color(0xFFFF007A).withOpacity(0.15)
                        : const Color(0xFF1C1C22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _flashToScreen ? const Color(0xFFFF007A) : Colors.white12,
                    ),
                  ),
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: const Color(0xFFFF007A),
                    title: Text(
                      isFa
                          ? '⚡ نمایش فوری روی صفحه قفل طرف مقابل (Flash Screen)'
                          : '⚡ Pop up on partner\'s Lock Screen (Live Flash)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    value: _flashToScreen,
                    onChanged: (v) => setState(() => _flashToScreen = v),
                  ),
                ),
                const SizedBox(height: 12),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(isFa ? 'انصراف' : 'Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: Icon(_flashToScreen ? Icons.bolt_rounded : Icons.send_rounded),
                        label: Text(
                          _flashToScreen
                              ? (isFa ? 'ارسال فلش روی صفحه!' : 'Flash to Screen!')
                              : (isFa ? 'ارسال در چت' : 'Send Sketch'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _flashToScreen ? const Color(0xFFFF007A) : const Color(0xFF00FFA3),
                          foregroundColor: _flashToScreen ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _exportAndSend,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NeonSketchPainter extends CustomPainter {
  final List<List<_StrokePoint>> strokes;

  _NeonSketchPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final color = stroke.first.color;
      final width = stroke.first.strokeWidth;

      final glowPaint = Paint()
        ..color = color.withOpacity(0.35)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width * 2.4
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      final corePaint = Paint()
        ..color = color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;

      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first.offset, width / 2, glowPaint..style = PaintingStyle.fill);
        canvas.drawCircle(stroke.first.offset, width / 2, corePaint..style = PaintingStyle.fill);
      } else {
        final path = Path()..moveTo(stroke.first.offset.dx, stroke.first.offset.dy);
        for (int i = 1; i < stroke.length; i++) {
          path.lineTo(stroke[i].offset.dx, stroke[i].offset.dy);
        }
        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, corePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NeonSketchPainter oldDelegate) => true;
}
