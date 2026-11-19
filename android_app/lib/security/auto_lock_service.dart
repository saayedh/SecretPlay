import 'dart:async';
import 'package:flutter/foundation.dart';
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

  /// True when unlocked via the secondary Duress / Decoy PIN (shows harmless decoy contacts & empty vault)
  bool _isDecoyMode = false;
  bool get isDecoyMode => _isDecoyMode;

  /// Shake-to-Lock / Panic Escape toggle (enabled by default)
  bool _shakeToLockEnabled = true;
  bool get shakeToLockEnabled => _shakeToLockEnabled;
  void setShakeToLockEnabled(bool value) {
    _shakeToLockEnabled = value;
  }

  bool _isAuthenticatingBiometrics = false;
  void setAuthenticatingBiometrics(bool value) {
    _isAuthenticatingBiometrics = value;
  }

  /// Temporary suspension while user opens QR camera, photo picker, or system dialogs
  bool _isTransientOverlayActive = false;
  void setTransientOverlayActive(bool value) {
    _isTransientOverlayActive = value;
  }

  /// Standby mode keeps WebSocket alive in background so Lock-Screen Flash Holograms can wake the screen!
  /// Strict auto-lock on backgrounding can be toggled in Security Settings.
  bool _strictBackgroundAutoLock = false;
  bool get strictBackgroundAutoLock => _strictBackgroundAutoLock;
  void setStrictBackgroundAutoLock(bool value) {
    _strictBackgroundAutoLock = value;
  }

  final List<LockCallback> _lockListeners = [];
  final StreamController<int> _updateProgressController = StreamController<int>.broadcast();
  Stream<int> get onUpdateProgress => _updateProgressController.stream;

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
          if (!_isAuthenticatingBiometrics &&
              !_isTransientOverlayActive &&
              _strictBackgroundAutoLock) {
            triggerLock('platform_background_gesture');
          }
        } else if (call.method == 'onShakeDetected') {
          if (_shakeToLockEnabled && !_isLocked) {
            triggerLock('shake_to_lock_panic');
          }
        } else if (call.method == 'onUpdateProgress') {
          final pct = call.arguments as int? ?? 0;
          _updateProgressController.add(pct);
        }
      });
    } catch (_) {
      // Ignore in non-platform unit tests
    }
  }

  Future<void> wakeScreenForFlashMessage({
    required String title,
    required String subtitle,
  }) async {
    if (kIsWeb) return;
    try {
      await _securityChannel.invokeMethod('wakeAndShowFlashAlert', {
        'title': title,
        'subtitle': subtitle,
      });
    } catch (_) {}
  }

  Future<void> setStandbyServiceEnabled(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _securityChannel.invokeMethod(
        enabled ? 'startStandbyService' : 'stopStandbyService',
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (kIsWeb || _isAuthenticatingBiometrics || _isTransientOverlayActive) {
      return;
    }

    // Never lock on 'inactive' (triggered by keyboard language selector, notification shade, or permission popups)
    if (state == AppLifecycleState.inactive) {
      return;
    }

    // Only auto-lock on background if user explicitly enabled Strict Background Auto-Lock
    // (When disabled, the user can receive Live Lock-Screen Flash Notes & Drawings even while their phone is locked!)
    if (_strictBackgroundAutoLock &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached ||
            state == AppLifecycleState.hidden)) {
      triggerLock('lifecycle_${state.name}');
    }
  }

  void unlock({bool decoyMode = false}) {
    _isLocked = false;
    _isDecoyMode = decoyMode;
  }

  void triggerLock(String reason) {
    if (_isLocked) return;
    _isLocked = true;
    _isDecoyMode = false;
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
