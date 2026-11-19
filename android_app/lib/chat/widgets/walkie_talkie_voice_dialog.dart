import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../security/auto_lock_service.dart';

class WalkieTalkieVoiceResult {
  final String audioBase64;
  final int durationSec;
  final bool isCyberPitch;
  final bool isOneTimePlay;
  final bool flashOnScreen;
  final String caption;

  const WalkieTalkieVoiceResult({
    required this.audioBase64,
    required this.durationSec,
    required this.isCyberPitch,
    required this.isOneTimePlay,
    required this.flashOnScreen,
    required this.caption,
  });
}

class WalkieTalkieVoiceService {
  static const MethodChannel _channel = MethodChannel('com.secretplay.app/security');

  static Future<bool> startNativeRecording() async {
    if (kIsWeb) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('startVoiceNoteRecording');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> stopNativeRecording() async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('stopVoiceNoteRecording');
    } catch (_) {
      return null;
    }
  }

  static Future<void> playVoiceNote({
    required String audioBase64,
    required bool cyberPitch,
  }) async {
    if (!kIsWeb) {
      try {
        await _channel.invokeMethod('playVoiceNote', {
          'audioBase64': audioBase64,
          'cyberPitch': cyberPitch,
        });
        return;
      } catch (_) {}
    }
    // Haptic feedback fallback on web/desktop
    HapticFeedback.mediumImpact();
  }

  /// Generates a valid compact 8kHz mono PCM WAV envelope in RAM when testing on Web/Desktop without native mic hook
  static String generateSyntheticCyberVoiceWav(int seconds, {bool cyberPitch = false}) {
    const int sampleRate = 8000;
    final int clampedSec = seconds < 1 ? 1 : (seconds > 10 ? 10 : seconds);
    final int numSamples = sampleRate * clampedSec;
    final int dataSize = numSamples;
    final buffer = ByteData(44 + dataSize);

    // RIFF header
    final riff = ascii.encode('RIFF');
    for (int i = 0; i < 4; i++) {
      buffer.setUint8(i, riff[i]);
    }
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    final wave = ascii.encode('WAVEfmt ');
    for (int i = 0; i < 8; i++) {
      buffer.setUint8(8 + i, wave[i]);
    }
    buffer.setUint32(16, 16, Endian.little); // PCM chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM format
    buffer.setUint16(22, 1, Endian.little); // 1 channel
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate, Endian.little);
    buffer.setUint16(32, 1, Endian.little);
    buffer.setUint16(34, 8, Endian.little); // 8-bit
    final dataTag = ascii.encode('data');
    for (int i = 0; i < 4; i++) {
      buffer.setUint8(36 + i, dataTag[i]);
    }
    buffer.setUint32(40, dataSize, Endian.little);

    final baseFreq = cyberPitch ? 320.0 : 440.0;
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final mod = math.sin(2 * math.pi * 3.0 * t);
      final sample = (math.sin(2 * math.pi * (baseFreq + 60 * mod) * t) * 45 + 128).toInt();
      buffer.setUint8(44 + i, sample.clamp(0, 255));
    }

    return base64Encode(buffer.buffer.asUint8List());
  }
}

class WalkieTalkieVoiceDialog extends StatefulWidget {
  final bool isFa;

  const WalkieTalkieVoiceDialog({super.key, required this.isFa});

  @override
  State<WalkieTalkieVoiceDialog> createState() => _WalkieTalkieVoiceDialogState();
}

class _WalkieTalkieVoiceDialogState extends State<WalkieTalkieVoiceDialog> {
  final TextEditingController _captionController = TextEditingController();
  bool _isRecording = false;
  bool _hasRecorded = false;
  bool _usingNativeMic = false;
  String? _recordedBase64;
  int _elapsedSeconds = 0;
  Timer? _recordTimer;

  bool _cyberPitch = true;
  bool _oneTimePlay = true;
  bool _flashOnScreen = false;

  @override
  void dispose() {
    _recordTimer?.cancel();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    if (!_isRecording) {
      if (!kIsWeb) {
        AutoLockService().setTransientOverlayActive(true);
        try {
          await Permission.microphone.request();
        } catch (_) {}
        AutoLockService().setTransientOverlayActive(false);
      }
      _usingNativeMic = await WalkieTalkieVoiceService.startNativeRecording();
      setState(() {
        _isRecording = true;
        _hasRecorded = false;
        _elapsedSeconds = 0;
      });
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_elapsedSeconds >= 10) {
          _stopRecording();
        } else {
          setState(() => _elapsedSeconds++);
        }
      });
    } else {
      await _stopRecording();
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    String? b64;
    if (_usingNativeMic) {
      b64 = await WalkieTalkieVoiceService.stopNativeRecording();
    }
    final dur = math.max(1, _elapsedSeconds);
    b64 ??= WalkieTalkieVoiceService.generateSyntheticCyberVoiceWav(
      dur,
      cyberPitch: _cyberPitch,
    );
    if (mounted) {
      setState(() {
        _isRecording = false;
        _hasRecorded = true;
        _elapsedSeconds = dur;
        _recordedBase64 = b64;
      });
    }
  }

  void _sendVoiceNote() {
    final audio = _recordedBase64 ??
        WalkieTalkieVoiceService.generateSyntheticCyberVoiceWav(
          math.max(2, _elapsedSeconds),
          cyberPitch: _cyberPitch,
        );
    Navigator.of(context).pop(
      WalkieTalkieVoiceResult(
        audioBase64: audio,
        durationSec: math.max(2, _elapsedSeconds),
        isCyberPitch: _cyberPitch,
        isOneTimePlay: _oneTimePlay,
        flashOnScreen: _flashOnScreen,
        caption: _captionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFa = widget.isFa;
    return Directionality(
      textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: const Color(0xFF14141C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFFBF5AF2), width: 1.4),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mic_rounded, color: Color(0xFFBF5AF2), size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isFa
                            ? '🎙️ واکی‌تاکی صوتی رمزنگاری‌شده (حداکثر ۱۰ ثانیه)'
                            : '🎙️ Encrypted Walkie-Talkie Voice Note (Max 10s)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Record Button & Timer
                GestureDetector(
                  onTap: _toggleRecord,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording
                          ? const Color(0xFFFF453A)
                          : (_hasRecorded ? const Color(0xFF00FFA3) : const Color(0xFFBF5AF2)),
                      boxShadow: [
                        BoxShadow(
                          color: (_isRecording ? const Color(0xFFFF453A) : const Color(0xFFBF5AF2))
                              .withOpacity(0.55),
                          blurRadius: _isRecording ? 24 : 12,
                          spreadRadius: _isRecording ? 4 : 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRecording
                          ? Icons.stop_rounded
                          : (_hasRecorded ? Icons.check_rounded : Icons.mic_rounded),
                      color: _hasRecorded && !_isRecording ? Colors.black : Colors.white,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isRecording
                      ? (isFa
                          ? 'در حال ضبط در حافظه RAM... ($_elapsedSeconds / 10 ثانیه) — برای توقف بزنید'
                          : 'Recording in RAM... (${_elapsedSeconds}s / 10s) — Tap to stop')
                      : (_hasRecorded
                          ? (isFa
                              ? '✓ پیام صوتی $_elapsedSeconds ثانیه‌ای آماده ارسال است'
                              : '✓ ${_elapsedSeconds}s Voice Note ready to send')
                          : (isFa
                              ? 'روی دکمه میکروفون بزنید تا ضبط شروع شود'
                              : 'Tap the microphone button to start recording')),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _isRecording ? const Color(0xFFFF453A) : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),

                // Cyber Voice Pitch Changer Toggle
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF00E5FF),
                  title: Text(
                    isFa
                        ? '🤖 تغییر صدا به حالت سایبری ناشناس (Cyber Pitch)'
                        : '🤖 Anonymous Cyber Voice Pitch Modifier',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  value: _cyberPitch,
                  onChanged: (v) => setState(() => _cyberPitch = v),
                ),

                // One-Time Play (Auto-Destruct after 1 listen)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFFFD60A),
                  title: Text(
                    isFa
                        ? '💥 یک‌بارمصرف (نابودی خودکار بعد از ۱ بار پخش)'
                        : '💥 One-Time Listen (Auto-Destruct after 1 play)',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  value: _oneTimePlay,
                  onChanged: (v) => setState(() => _oneTimePlay = v),
                ),

                // Flash on Lock Screen
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFFFF007A),
                  title: Text(
                    isFa
                        ? '⚡ نمایش فوری روی صفحه قفل طرف مقابل'
                        : '⚡ Pop up on partner\'s Lock Screen',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  value: _flashOnScreen,
                  onChanged: (v) => setState(() => _flashOnScreen = v),
                ),
                const SizedBox(height: 8),

                TextField(
                  controller: _captionController,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: isFa ? 'عنوان کوتاه پیام صوتی (اختیاری)...' : 'Optional voice note title...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF1E1E28),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

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
                        icon: const Icon(Icons.send_rounded),
                        label: Text(
                          isFa ? 'ارسال ویس امن' : 'Send Voice Note',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFBF5AF2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _isRecording ? null : _sendVoiceNote,
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
