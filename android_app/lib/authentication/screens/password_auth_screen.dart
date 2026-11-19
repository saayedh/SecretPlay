import 'dart:async';
import 'package:flutter/material.dart';
import '../../cryptography/crypto_service.dart';
import '../../security/keystore_service.dart';
import '../../security/auto_lock_service.dart';
import '../../contacts/screens/contacts_screen.dart';

class PasswordAuthScreen extends StatefulWidget {
  final bool isFirstTimeSetup;

  const PasswordAuthScreen({super.key, this.isFirstTimeSetup = false});

  @override
  State<PasswordAuthScreen> createState() => _PasswordAuthScreenState();
}

class _PasswordAuthScreenState extends State<PasswordAuthScreen> {
  final KeystoreService _keystore = KeystoreService();
  final CryptoService _crypto = CryptoService();

  String _enteredPin = '';
  int _failedAttempts = 0;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;
  String? _errorMessage;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    AutoLockService().addLockListener(_onAutoLock);
  }

  @override
  void dispose() {
    AutoLockService().removeLockListener(_onAutoLock);
    _enteredPin = '';
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _onAutoLock(String reason) {
    if (mounted) {
      setState(() => _enteredPin = '');
    }
  }

  void _startLockout(int seconds) {
    setState(() {
      _lockoutSeconds = seconds;
      _errorMessage = 'تلاش ناموفق بیش از حد. لطفاً $seconds ثانیه صبر کنید.';
    });
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lockoutSeconds <= 1) {
        timer.cancel();
        setState(() {
          _lockoutSeconds = 0;
          _failedAttempts = 0;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _lockoutSeconds--;
          _errorMessage = 'تلاش ناموفق بیش از حد. لطفاً $_lockoutSeconds ثانیه صبر کنید.';
        });
      }
    });
  }

  void _onDigitPressed(String digit) {
    if (_lockoutSeconds > 0 || _isBusy) return;
    if (_enteredPin.length >= 4) return;

    setState(() {
      _enteredPin += digit;
      _errorMessage = null;
    });

    // When 4 digits are entered in unlock mode, verify immediately!
    if (_enteredPin.length == 4 && !widget.isFirstTimeSetup) {
      _submit();
    }
  }

  void _onBackspace() {
    if (_lockoutSeconds > 0 || _isBusy || _enteredPin.isEmpty) return;
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    if (_lockoutSeconds > 0 || _isBusy) return;

    if (_enteredPin.length < 4) {
      setState(() => _errorMessage = 'لطفاً یک پین ۴ رقمی وارد کنید.');
      return;
    }

    final pin = _enteredPin;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      if (widget.isFirstTimeSetup) {
        final saltedHash = await _crypto.hashPassphrase(pin);
        await _keystore.savePassphraseHash(saltedHash);
        _enteredPin = '';
        await _proceedToApp();
      } else {
        final storedHash = await _keystore.getPassphraseHash();
        final duressHash = await _keystore.getDuressPinHash();

        final isRealPin = storedHash != null &&
            (storedHash == pin || await _crypto.verifyPassphrase(pin, storedHash));
        final isDuressPin = !isRealPin &&
            duressHash != null &&
            duressHash.isNotEmpty &&
            (duressHash == pin || await _crypto.verifyPassphrase(pin, duressHash));

        setState(() => _enteredPin = '');

        if (isRealPin) {
          await _proceedToApp(decoyMode: false);
        } else if (isDuressPin) {
          // Unlock silently in Decoy / Duress mode (wipes active RAM session & shows harmless decoy contacts)
          await _proceedToApp(decoyMode: true);
        } else {
          _failedAttempts++;
          if (_failedAttempts >= 5) {
            _startLockout(15);
          } else {
            setState(() {
              _errorMessage = 'پین اشتباه است ($_failedAttempts/5)';
            });
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _proceedToApp({bool decoyMode = false}) async {
    AutoLockService().unlock(decoyMode: decoyMode);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ContactsScreen()),
    );
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
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person_rounded, color: Color(0xFF64D2FF), size: 52),
              const SizedBox(height: 16),
              Text(
                widget.isFirstTimeSetup ? 'انتخاب پین ۴ رقمی ورود' : 'ورود به بخش خصوصی',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isFirstTimeSetup
                    ? 'یک کد ۴ رقمی ساده برای باز کردن سریع گفتگو انتخاب کنید'
                    : 'پین ۴ رقمی خود را وارد کنید',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 28),

              // 4-Dot Visual PIN Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final isFilled = index < _enteredPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? const Color(0xFF00FFA3) : Colors.transparent,
                      border: Border.all(
                        color: isFilled ? const Color(0xFF00FFA3) : const Color(0xFF64D2FF),
                        width: 2,
                      ),
                      boxShadow: isFilled
                          ? [
                              BoxShadow(
                                color: const Color(0xFF00FFA3).withOpacity(0.5),
                                blurRadius: 8,
                              )
                            ]
                          : null,
                    ),
                  );
                }),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFF453A), fontSize: 13),
                ),
              ] else
                const SizedBox(height: 32),

              // Numeric PIN Pad
              SizedBox(
                width: 270,
                child: Column(
                  children: [
                    _buildKeyRow(['1', '2', '3']),
                    const SizedBox(height: 14),
                    _buildKeyRow(['4', '5', '6']),
                    const SizedBox(height: 14),
                    _buildKeyRow(['7', '8', '9']),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        const SizedBox(width: 72, height: 64),
                        _buildDigitButton('0'),
                        SizedBox(
                          width: 72,
                          height: 64,
                          child: IconButton(
                            icon: const Icon(Icons.backspace_outlined, color: Colors.white70),
                            onPressed: _onBackspace,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (widget.isFirstTimeSetup) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: 250,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FFA3),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: (_enteredPin.length == 4 && !_isBusy) ? _submit : null,
                    child: const Text(
                      'ثبت پین و ورود',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map(_buildDigitButton).toList(),
    );
  }

  Widget _buildDigitButton(String digit) {
    return SizedBox(
      width: 72,
      height: 64,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFF1C1C1E),
          side: BorderSide(color: Colors.white.withOpacity(0.12)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: () => _onDigitPressed(digit),
        child: Text(
          digit,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
