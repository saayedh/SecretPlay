import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../../security/keystore_service.dart';
import 'password_auth_screen.dart';
import 'biometric_auth_screen.dart';

class PrivateAccessScreen extends StatefulWidget {
  const PrivateAccessScreen({super.key});

  @override
  State<PrivateAccessScreen> createState() => _PrivateAccessScreenState();
}

class _PrivateAccessScreenState extends State<PrivateAccessScreen> {
  final KeystoreService _keystore = KeystoreService();
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _checkAuthMethods();
  }

  Future<void> _checkAuthMethods() async {
    final hasPassphrase = await _keystore.isPassphraseConfigured();
    final canCheckBiometrics = await _localAuth.canCheckBiometrics;
    final isDeviceSupported = await _localAuth.isDeviceSupported();

    if (!mounted) return;

    if (!hasPassphrase) {
      // First-time setup: prompt to create passphrase
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PasswordAuthScreen(isFirstTimeSetup: true)),
      );
    } else if (canCheckBiometrics && isDeviceSupported) {
      // Prompt biometrics by default with fallback to passphrase
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const BiometricAuthScreen()),
      );
    } else {
      // Fallback directly to password authentication
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PasswordAuthScreen(isFirstTimeSetup: false)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF64D2FF)),
      ),
    );
  }
}
