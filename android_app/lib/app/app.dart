import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../security/auto_lock_service.dart';
import '../game/screens/game_home_screen.dart';
import '../chat/screens/private_chat_screen.dart' show wsClientProvider;

class SecretPlayApp extends ConsumerStatefulWidget {
  const SecretPlayApp({super.key});

  @override
  ConsumerState<SecretPlayApp> createState() => _SecretPlayAppState();
}

class _SecretPlayAppState extends ConsumerState<SecretPlayApp> with WidgetsBindingObserver {
  final AutoLockService _autoLockService = AutoLockService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _obscureScreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoLockService.startObserving();
    _autoLockService.addLockListener(_handleGlobalLock);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoLockService.removeLockListener(_handleGlobalLock);
    _autoLockService.stopObserving();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Sockets are often silently dead after the phone was in background: verify immediately.
      try {
        ref.read(wsClientProvider).probeConnection();
      } catch (_) {}
    }
    final shouldObscure = AutoLockService().strictBackgroundAutoLock &&
        (state == AppLifecycleState.paused || state == AppLifecycleState.hidden);
    if (_obscureScreen != shouldObscure && mounted) {
      setState(() => _obscureScreen = shouldObscure);
    }
  }

  void _handleGlobalLock(String reason) {
    final nav = _navigatorKey.currentState;
    if (nav != null) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GameHomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecretPlay',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppThemes.gameTheme,
      darkTheme: AppThemes.gameTheme,
      themeMode: ThemeMode.dark,
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            if (_obscureScreen)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: Icon(
                      Icons.shield_rounded,
                      color: Color(0xFF00FFA3),
                      size: 64,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      home: const GameHomeScreen(),
    );
  }
}
