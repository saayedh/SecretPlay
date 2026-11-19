import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      _errorMessage = 'تلاش ناموفق بیش از حد. $seconds ثانیه صبر کنید.';
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
          _errorMessage = 'تلاش ناموفق بیش از حد. $_lockoutSeconds ثانیه صبر کنید.';
        });
      }
    });
  }

  void _onDigitPressed(String digit) {
    if (_lockoutSeconds > 0 || _isBusy) return;
    if (_enteredPin.length >= 4) return;
    HapticFeedback.lightImpact();

    setState(() {
      _enteredPin += digit;
      _errorMessage = null;
    });

    if (_enteredPin.length == 4 && !widget.isFirstTimeSetup) {
      _submit();
    }
  }

  void _onBackspace() {
    if (_lockoutSeconds > 0 || _isBusy || _enteredPin.isEmpty) return;
    HapticFeedback.selectionClick();
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
        await _proceedToApp(decoyMode: false);
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
          await _proceedToApp(decoyMode: true);
        } else {
          HapticFeedback.heavyImpact();
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
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, animation, __) => const ContactsScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.5),
            radius: 1.1,
            colors: [Color(0xFF14182E), Color(0xFF07080D)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white60),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00FFA3), Color(0xFF00E5FF)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E5FF).withOpacity(0.35),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.lock_open_rounded, color: Colors.black, size: 32),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          widget.isFirstTimeSetup ? 'انتخاب پین ۴ رقمی ورود' : 'گاوصندوق SecretPlay',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.isFirstTimeSetup
                              ? 'یک کد ۴ رقمی ساده برای باز کردن سریع گفتگو انتخاب کنید'
                              : 'پین ۴ رقمی خود را وارد کنید',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                        const SizedBox(height: 28),

                        // Glowing 4-Dot Indicator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (index) {
                            final isFilled = index < _enteredPin.length;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                              width: isFilled ? 20 : 16,
                              height: isFilled ? 20 : 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isFilled
                                    ? const Color(0xFF00FFA3)
                                    : Colors.white.withOpacity(0.08),
                                border: Border.all(
                                  color: isFilled
                                      ? const Color(0xFF00FFA3)
                                      : const Color(0xFF00E5FF).withOpacity(0.45),
                                  width: 2,
                                ),
                                boxShadow: isFilled
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF00FFA3).withOpacity(0.6),
                                          blurRadius: 12,
                                        ),
                                      ]
                                    : null,
                              ),
                            );
                          }),
                        ),

                        SizedBox(
                          height: 36,
                          child: Center(
                            child: _errorMessage != null
                                ? Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFFFF453A),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),

                        // Circular Frosted-Glass Numeric Keypad
                        SizedBox(
                          width: 264,
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
                                  const SizedBox(width: 72, height: 72),
                                  _buildDigitButton('0'),
                                  SizedBox(
                                    width: 72,
                                    height: 72,
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.backspace_outlined,
                                        color: Colors.white70,
                                        size: 24,
                                      ),
                                      onPressed: _onBackspace,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        if (widget.isFirstTimeSetup) ...[
                          const SizedBox(height: 22),
                          SizedBox(
                            width: 240,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00FFA3),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: (_enteredPin.length == 4 && !_isBusy) ? _submit : null,
                              child: const Text(
                                'ثبت پین و ورود',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(36),
        onTap: () => _onDigitPressed(digit),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.06),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Center(
            child: Text(
              digit,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
