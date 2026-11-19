import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../security/keystore_service.dart';
import '../../cryptography/crypto_service.dart';
import '../../networking/network_mode.dart';
import '../../chat/screens/private_chat_screen.dart';
import '../../networking/screens/network_mode_screen.dart';
import '../../networking/screens/qr_scanner_screen.dart';

class DeviceVerificationScreen extends ConsumerStatefulWidget {
  const DeviceVerificationScreen({super.key});

  @override
  ConsumerState<DeviceVerificationScreen> createState() => _DeviceVerificationScreenState();
}

class _DeviceVerificationScreenState extends ConsumerState<DeviceVerificationScreen> {
  final KeystoreService _keystore = KeystoreService();
  final CryptoService _crypto = CryptoService();
  final TextEditingController _tokenController = TextEditingController();

  String _currentToken = '';
  String? _statusMessage;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initIdentityAndToken();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  String _generateShortToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final part1 = List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
    final part2 = List.generate(2, (_) => chars[rng.nextInt(chars.length)]).join();
    return 'SP-$part1-$part2';
  }

  Future<void> _initIdentityAndToken() async {
    await _keystore.getOrCreateDeviceId();
    var privKey = await _keystore.getIdentityPrivateKey();
    var pubKey = await _keystore.getIdentityPublicKey();

    if (privKey == null || pubKey == null) {
      final keyPair = await _crypto.generateIdentityKeyPair();
      privKey = await _crypto.exportPrivateKey(keyPair);
      pubKey = await _crypto.exportPublicKey(keyPair);
      await _keystore.saveIdentityKeyPair(
        privateKeyBase64: privKey,
        publicKeyBase64: pubKey,
      );
    }

    var savedToken = await _keystore.getPairToken();
    if (savedToken == null || savedToken.trim().isEmpty) {
      savedToken = _generateShortToken();
    }

    if (mounted) {
      setState(() {
        _currentToken = savedToken!;
        _tokenController.text = savedToken;
        _isReady = true;
      });
    }
  }

  void _onGenerateNewToken() {
    final fresh = _generateShortToken();
    setState(() {
      _currentToken = fresh;
      _tokenController.text = fresh;
      _statusMessage = 'توکن جدید ساخته شد. آن را برای نفر دوم بفرستید.';
    });
  }

  Future<void> _copyToken() async {
    final token = _tokenController.text.trim().toUpperCase();
    if (token.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('توکن "$token" کپی شد! برای نفر دوم بفرستید.'),
          backgroundColor: const Color(0xFF1C1C1E),
        ),
      );
    }
  }

  Future<void> _scanPartnerQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (scanned == null || scanned.trim().isEmpty) return;

    String extractedToken = scanned.trim();
    if (extractedToken.startsWith('{')) {
      try {
        final data = jsonDecode(extractedToken) as Map<String, dynamic>;
        if (data['pairToken'] is String) {
          extractedToken = data['pairToken'] as String;
        } else if (data['invitationCode'] is String) {
          extractedToken = data['invitationCode'] as String;
        }
        if (data['wsUrl'] is String) {
          final scannedUrl = data['wsUrl'] as String;
          if (scannedUrl.startsWith('wss://')) {
            ref.read(networkConfigProvider.notifier).setMode(NetworkMode.cloud);
            ref.read(networkConfigProvider.notifier).setCloudflareUrl(scannedUrl.split('?').first);
          } else if (scannedUrl.startsWith('ws://')) {
            ref.read(networkConfigProvider.notifier).setMode(NetworkMode.local);
            ref.read(networkConfigProvider.notifier).setLocalUrl(scannedUrl.split('?').first);
          }
        }
      } catch (_) {
        // Use raw scanned string as token
      }
    }

    setState(() {
      _currentToken = extractedToken.trim().toUpperCase();
      _tokenController.text = _currentToken;
    });

    await _connectWithToken();
  }

  Future<void> _connectWithToken() async {
    final token = _tokenController.text.trim().toUpperCase();
    if (token.length < 3) {
      setState(() => _statusMessage = 'توکن باید حداقل ۳ کاراکتر باشد.');
      return;
    }

    // If token changed, clear old peer key so server auto-pins the peer in this token room
    final oldToken = await _keystore.getPairToken();
    if (oldToken != null && oldToken != token) {
      await _keystore.revokePairing();
    }

    await _keystore.savePairToken(token);
    ref.read(networkConfigProvider.notifier).setPairToken(token);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PrivateChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final netConfig = ref.watch(networkConfigProvider);
    final qrPayload = jsonEncode({
      'pairToken': _currentToken,
      'wsUrl': netConfig.mode == NetworkMode.cloud
          ? netConfig.cloudflareUrl
          : netConfig.localServerUrl,
    });

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('اتصال دو نفره با توکن مشترک'),
        actions: [
          IconButton(
            icon: const Icon(Icons.router_rounded, color: Color(0xFF64D2FF)),
            tooltip: 'تنظیمات شبکه (کلودفلر / لوکال)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NetworkModeScreen()),
              );
            },
          ),
        ],
      ),
      body: !_isReady
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'توکن اتاق دو نفره شما',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'کافیست هر دو نفر یک توکن یکسان وارد کنید (یا QR زیر را اسکن کنید) تا کلیدهای رمزنگاری به‌طور خودکار تبادل شوند.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 20),

                    // Editable Token Box
                    TextField(
                      controller: _tokenController,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF00FFA3),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                      ),
                      onChanged: (val) {
                        setState(() => _currentToken = val.trim().toUpperCase());
                      },
                      decoration: InputDecoration(
                        labelText: 'کد توکن مشترک (قابل ویرایش)',
                        labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
                        hintText: 'مثلاً SP-4829-K7 یا رمز دلخواه',
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFF1C1C1E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.copy_rounded, color: Color(0xFF64D2FF)),
                          tooltip: 'کپی توکن',
                          onPressed: _copyToken,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Quick Action Buttons Row (Copy / New Random / Scan QR)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy, size: 18, color: Color(0xFF64D2FF)),
                            label: const Text('کپی کد', style: TextStyle(color: Colors.white)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF64D2FF)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _copyToken,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 18, color: Color(0xFF00FFA3)),
                            label: const Text('کد جدید', style: TextStyle(color: Colors.white)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF00FFA3)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _onGenerateNewToken,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.qr_code_scanner, size: 18, color: Colors.amber),
                            label: const Text('اسکن QR', style: TextStyle(color: Colors.white)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.amber),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _scanPartnerQr,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Primary Connect Button
                    ElevatedButton.icon(
                      icon: const Icon(Icons.login_rounded),
                      label: const Text(
                        'اتصال با این توکن و ورود به چت',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FFA3),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _connectWithToken,
                    ),

                    if (_statusMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _statusMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF64D2FF), fontSize: 13),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Optional QR Display for in-person 1-second scan
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: qrPayload,
                          version: QrVersions.auto,
                          size: 170.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'اگر کنار هم هستید، نفر دوم می‌تواند این QR را اسکن کند',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
