import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../security/auto_lock_service.dart';
import 'password_auth_screen.dart';
import '../../contacts/screens/contacts_screen.dart';

class BiometricAuthScreen extends StatefulWidget {
  const BiometricAuthScreen({super.key});

  @override
  State<BiometricAuthScreen> createState() => _BiometricAuthScreenState();
}

class _BiometricAuthScreenState extends State<BiometricAuthScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  Future<void> _authenticate() async {
    AutoLockService().setAuthenticatingBiometrics(true);
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'برای ورود به گفتگوی خصوصی اثر انگشت خود را لمس کنید',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      AutoLockService().setAuthenticatingBiometrics(false);

      if (authenticated) {
        AutoLockService().unlock();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ContactsScreen()),
        );
      } else {
        setState(() => _statusMessage = 'تایید اثر انگشت لغو شد.');
      }
    } catch (e) {
      AutoLockService().setAuthenticatingBiometrics(false);
      setState(() => _statusMessage = 'امکان استفاده از اثر انگشت نیست. از پین ۴ رقمی استفاده کنید.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.fingerprint, color: Color(0xFF64D2FF), size: 72),
              const SizedBox(height: 24),
              const Text(
                'ورود با اثر انگشت',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'حسگر اثر انگشت را لمس کنید یا با پین ۴ رقمی وارد شوید.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 20),
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFF9500), fontSize: 13),
                ),
              ],
              const SizedBox(height: 36),
              ElevatedButton.icon(
                icon: const Icon(Icons.fingerprint),
                label: const Text('تلاش مجدد با اثر انگشت'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF64D2FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _authenticate,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.pin, color: Colors.white70),
                label: const Text('ورود با پین ۴ رقمی', style: TextStyle(color: Colors.white70)),
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const PasswordAuthScreen(isFirstTimeSetup: false),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
