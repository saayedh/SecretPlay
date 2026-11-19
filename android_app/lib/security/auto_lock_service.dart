import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef LockCallback = void Function(String reason);

class AutoLockService with WidgetsBindingObserver {
  static const MethodChannel _securityChannel = MethodChannel('com.secretplay.app/security');

  static final AutoLockService _instance = AutoLockService._internal();
  factory AutoLockService() => _instance;

  AutoLockService._internal() {
    _initPlatformListener();
  }

  bool _isLocked = true;
  bool get isLocked => _isLocked;

  bool _isAuthenticatingBiometrics = false;
  void setAuthenticatingBiometrics(bool value) {
    _isAuthenticatingBiometrics = value;
  }

  final List<LockCallback> _lockListeners = [];

  void addLockListener(LockCallback callback) {
    _lockListeners.add(callback);
  }

  void removeLockListener(LockCallback callback) {
    _lockListeners.remove(callback);
  }

  void startObserving() {
    WidgetsBinding.instance.addObserver(this);
  }

  void stopObserving() {
    WidgetsBinding.instance.removeObserver(this);
  }

  void _initPlatformListener() {
    try {
      _securityChannel.setMethodCallHandler((call) async {
        if (call.method == 'onAppBackgrounded') {
          if (!_isAuthenticatingBiometrics) {
            triggerLock('platform_background_gesture');
          }
        }
      });
    } catch (_) {
      // Ignore in non-platform unit tests
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // If biometric or system permission prompt is showing, Android enters paused/inactive state temporarily
    if (_isAuthenticatingBiometrics) {
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      triggerLock('lifecycle_${state.name}');
    }
  }

  void unlock() {
    _isLocked = false;
  }

  void triggerLock(String reason) {
    if (_isLocked) return;
    _isLocked = true;
    debugPrint('[AutoLock] Triggering immediate lock! Reason: $reason');

    for (final listener in List.of(_lockListeners)) {
      try {
        listener(reason);
      } catch (e) {
        debugPrint('[AutoLock] Error in lock listener: $e');
      }
    }
  }
}
