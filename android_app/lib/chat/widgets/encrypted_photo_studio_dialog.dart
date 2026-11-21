import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../security/auto_lock_service.dart';

class SnapPhotoResult {
  final String pngBase64;
  final String caption;
  final bool flashOnScreen;

  const SnapPhotoResult({
    required this.pngBase64,
    required this.caption,
    required this.flashOnScreen,
  });
}

/// Built-in Encrypted Camera Snap & Polaroid Card Studio
/// Works 100% offline/online using already-installed packages!
class EncryptedPhotoStudioDialog extends StatefulWidget {
  final bool isFa;

  const EncryptedPhotoStudioDialog({super.key, required this.isFa});

  @override
  State<EncryptedPhotoStudioDialog> createState() => _EncryptedPhotoStudioDialogState();
}

class _EncryptedPhotoStudioDialogState extends State<EncryptedPhotoStudioDialog> {
  final GlobalKey _captureKey = GlobalKey();
  final TextEditingController _captionController = TextEditingController();
  MobileScannerController? _cameraController;

  bool _useCameraPreview = true;
  bool _flashOnScreen = false;
  bool _isCapturing = false;
  int _selectedThemeIndex = 0;

  @override
  void initState() {
    super.initState();
    AutoLockService().setTransientOverlayActive(true);
    try {
      _cameraController = MobileScannerController(
        facing: CameraFacing.back,
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    } catch (_) {
      _useCameraPreview = false;
    }
  }

  @override
  void dispose() {
    AutoLockService().setTransientOverlayActive(false);
    _cameraController?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _captureAndSend() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image img = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final Uint8List bytes = byteData.buffer.asUint8List();

      if (!mounted) return;
      Navigator.of(context).pop(
        SnapPhotoResult(
          pngBase64: base64Encode(bytes),
          caption: _captionController.text.trim(),
          flashOnScreen: _flashOnScreen,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFa = widget.isFa;
    final gradient = [
      const [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF00FFA3)],
      const [Color(0xFF2A0845), Color(0xFF6441A5), Color(0xFFFF007A)],
      const [Color(0xFF000428), Color(0xFF004E92), Color(0xFF00E5FF)],
    ][_selectedThemeIndex % 3];

    return Directionality(
      textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: const Color(0xFF14141A),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFF00FFA3), width: 1.2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.camera_alt_rounded, color: Color(0xFF00FFA3)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isFa ? '📸 ثبت و ارسال عکس / کارت تصویری رمزنگاری‌شده' : '📸 Encrypted Camera Snap & Photo Card',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_useCameraPreview && _cameraController != null)
                      IconButton(
                        icon: const Icon(Icons.flip_camera_ios_rounded, color: Color(0xFF64D2FF)),
                        tooltip: isFa ? 'چرخش دوربین' : 'Switch Camera',
                        onPressed: () => _cameraController?.switchCamera(),
                      ),
                    IconButton(
                      icon: Icon(
                        _useCameraPreview ? Icons.palette_rounded : Icons.videocam_rounded,
                        color: Colors.amber,
                      ),
                      tooltip: isFa ? 'تغییر حالت دوربین / کارت نئونی' : 'Toggle Camera / Neon Card',
                      onPressed: () {
                        setState(() {
                          _useCameraPreview = !_useCameraPreview;
                          _selectedThemeIndex++;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Capture Viewport
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: RepaintBoundary(
                    key: _captureKey,
                    child: Container(
                      height: 250,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_useCameraPreview && _cameraController != null)
                            MobileScanner(
                              controller: _cameraController!,
                              onDetect: (_) {},
                              errorBuilder: (ctx, err, child) {
                                return _buildNeonPhotoCardPreview(isFa);
                              },
                            )
                          else
                            _buildNeonPhotoCardPreview(isFa),

                          // Caption overlay at bottom of photo
                          if (_captionController.text.trim().isNotEmpty)
                            Positioned(
                              bottom: 12,
                              left: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.68),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF00FFA3).withOpacity(0.6)),
                                ),
                                child: Text(
                                  _captionController.text,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Caption Input
                TextField(
                  controller: _captionController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: isFa ? 'متن روی عکس یا توضیح تصویر...' : 'Text overlay on photo...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF1C1C22),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Flash on Lock Screen toggle
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFFF007A),
                  title: Text(
                    isFa
                        ? '⚡ نمایش فوری این تصویر روی صفحه قفل طرف مقابل'
                        : '⚡ Pop up this photo on partner\'s Lock Screen',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  value: _flashOnScreen,
                  onChanged: (v) => setState(() => _flashOnScreen = v),
                ),
                const SizedBox(height: 10),

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
                        icon: const Icon(Icons.camera_rounded),
                        label: Text(
                          isFa ? 'ثبت و ارسال تصویر' : 'Snap & Send Photo',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FFA3),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _captureAndSend,
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

  Widget _buildNeonPhotoCardPreview(bool isFa) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFF00FFA3), size: 54),
            const SizedBox(height: 12),
            Text(
              _captionController.text.trim().isNotEmpty
                  ? _captionController.text
                  : (isFa ? 'کارت تصویری رمزنگاری‌شده SecretPlay' : 'SecretPlay Encrypted Visual Card'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
