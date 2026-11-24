import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/constants.dart';
import '../core/relay_directory_service.dart';
import '../core/theme.dart';
import '../chat/chat_message.dart';
import '../chat/widgets/flash_hologram_overlay.dart';
import '../ghost_touch/ghost_touch_theme.dart';
import '../ghost_touch/models/hologram_models.dart';
import '../ghost_touch/stickers/ghost_sticker_catalog.dart';
import '../ghost_touch/stickers/ghost_sticker_painter.dart';
import '../security/auto_lock_service.dart';
import '../security/keystore_service.dart';
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

  // Global 24/7 Personal Inbox Socket & Fallback Overlay State (works on Game/Contacts/Web screens)
  WebSocketChannel? _inboxChannel;
  Timer? _inboxPingTimer;
  Timer? _inboxReconnectTimer;
  Timer? _heartbeatHideTimer;
  Timer? _stealthPillHideTimer;
  String? _myDeviceId;
  bool _disposed = false;
  int _inboxGen = 0;
  final Set<String> _seenInboxEventIds = {};

  GhostReactionMeta? _globalReactionMeta;
  String? _globalStealthBannerText;
  EphemeralChatMessage? _globalFlashMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoLockService.startObserving();
    _autoLockService.addLockListener(_handleGlobalLock);
    unawaited(GhostTouchPreferencesService.instance.load());
    _initGlobalStandbyAndInbox();
  }

  Future<void> _initGlobalStandbyAndInbox() async {
    try {
      final devId = await KeystoreService().getOrCreateDeviceId();
      if (_disposed || devId.isEmpty) return;
      _myDeviceId = devId;
      if (!kIsWeb) {
        await _autoLockService.configureNativeStandbyEngine(deviceId: devId);
      }
      _connectInboxWebSocket();
    } catch (_) {}
  }

  void _connectInboxWebSocket() {
    if (_disposed || _myDeviceId == null || _myDeviceId!.isEmpty) return;
    _inboxPingTimer?.cancel();
    _inboxReconnectTimer?.cancel();
    try {
      _inboxChannel?.sink.close();
    } catch (_) {}

    final gen = ++_inboxGen;
    try {
      final wsBase = AppConstants.cloudflareHttpBase.replaceFirst('https://', 'wss://');
      final uri = Uri.parse('$wsBase/inbox-ws?deviceId=${Uri.encodeComponent(_myDeviceId!)}');
      final channel = WebSocketChannel.connect(uri);
      _inboxChannel = channel;

      channel.stream.listen(
        (data) {
          if (_disposed || gen != _inboxGen) return;
          _handleInboxRaw(data.toString());
        },
        onError: (_) {
          if (_disposed || gen != _inboxGen) return;
          _scheduleInboxReconnect();
        },
        onDone: () {
          if (_disposed || gen != _inboxGen) return;
          _scheduleInboxReconnect();
        },
      );

      _inboxPingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (_disposed || gen != _inboxGen) return;
        try {
          channel.sink.add(jsonEncode({
            'type': 'ping',
            'version': 1,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }));
        } catch (_) {}
      });
    } catch (_) {
      _scheduleInboxReconnect();
    }
  }

  void _scheduleInboxReconnect() {
    if (_disposed) return;
    _inboxPingTimer?.cancel();
    _inboxReconnectTimer?.cancel();
    _inboxReconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_disposed) _connectInboxWebSocket();
    });
  }

  Future<void> _handleInboxRaw(String raw) async {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['type'] != 'inbox_event') return;
      final eventId = map['eventId'] as String? ?? '';
      if (eventId.isNotEmpty) {
        if (_seenInboxEventIds.contains(eventId)) return;
        if (_seenInboxEventIds.length > 100) {
          _seenInboxEventIds.remove(_seenInboxEventIds.first);
        }
        _seenInboxEventIds.add(eventId);
      }

      final eventType = map['eventType'] as String? ?? '';
      // If Android Native System Overlay is active, it already renders on top of all screens!
      bool nativeOverlayHandlesIt = false;
      if (!kIsWeb) {
        final status = await _autoLockService.checkOverlayAndBatteryStatus();
        nativeOverlayHandlesIt = status['canDrawOverlays'] == true;
      }

      final prefs = GhostTouchPreferencesService.instance.current;

      if (eventType == 'heartbeat_pulse' || eventType == 'reaction_burst') {
        if (nativeOverlayHandlesIt || !mounted) return;
        final meta = eventType == 'reaction_burst'
            ? GhostReactionMeta.of(map['reactionType'] as String?)
            : GhostReactionMeta.megaHeart;
        if (prefs.vibrateEnabled) {
          _autoLockService.triggerHeartbeatVibration();
        }
        if (prefs.soundEnabled) {
          unawaited(_autoLockService.playGhostTouchChime(style: meta.key));
        }
        _heartbeatHideTimer?.cancel();
        setState(() => _globalReactionMeta = meta);
        _heartbeatHideTimer = Timer(const Duration(milliseconds: 2200), () {
          if (mounted) setState(() => _globalReactionMeta = null);
        });
      } else if (eventType == 'stealth_ping') {
        if (nativeOverlayHandlesIt || !mounted) return;
        if (prefs.vibrateEnabled) {
          _autoLockService.triggerHeartbeatVibration();
        }
        _stealthPillHideTimer?.cancel();
        setState(() => _globalStealthBannerText = '🎮 Cyber Circuit • جایزه الماس روزانه آماده است! 💎');
        _stealthPillHideTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _globalStealthBannerText = null);
        });
      } else if (eventType == 'flash_hologram') {
        if (nativeOverlayHandlesIt || !mounted) return;
        if (prefs.vibrateEnabled) {
          _autoLockService.triggerHeartbeatVibration();
        }
        if (prefs.soundEnabled) {
          unawaited(_autoLockService.playGhostTouchChime(style: 'entrance'));
        }
        final media = map['mediaBase64'] as String?;
        final body = map['body'] as String? ?? map['title'] as String? ?? '';
        final emoji = map['emoji'] as String? ?? '';
        final stickerId = map['stickerId'] as String?;
        final holoStr = map['hologramStyle'] as String?;
        final cardDataJson = map['cardDataJson'] as String?;
        final flashSec = (map['flashSeconds'] as int?) ??
            GhostTouchPreferencesService.instance.current.displayDurationSec;
        final cType = (cardDataJson != null && cardDataJson.isNotEmpty)
            ? ChatContentType.flashCard
            : ((stickerId != null && stickerId.isNotEmpty)
                ? ChatContentType.sticker
                : ((media != null && media.isNotEmpty)
                    ? ChatContentType.drawing
                    : ChatContentType.text));
        final msg = EphemeralChatMessage(
          id: eventId.isNotEmpty ? eventId : null,
          senderDeviceId: map['senderDeviceId'] as String? ?? 'peer',
          text: emoji.isNotEmpty && stickerId == null ? '$emoji  $body'.trim() : body,
          contentType: cType,
          mediaBase64: (media != null && media.isNotEmpty) ? media : null,
          stickerId: (stickerId != null && stickerId.isNotEmpty) ? stickerId : null,
          hologramStyle: (holoStr != null && holoStr.isNotEmpty) ? holoStr : null,
          cardDataJson: (cardDataJson != null && cardDataJson.isNotEmpty)
              ? cardDataJson
              : null,
          displayDurationSec: flashSec,
          isFlashScreen: true,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isMe: false,
        );
        setState(() => _globalFlashMessage = msg);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _inboxPingTimer?.cancel();
    _inboxReconnectTimer?.cancel();
    _heartbeatHideTimer?.cancel();
    _stealthPillHideTimer?.cancel();
    try {
      _inboxChannel?.sink.close();
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    _autoLockService.removeLockListener(_handleGlobalLock);
    _autoLockService.stopObserving();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Clear transient overlay suppression once user returns from Android system permission settings
      _autoLockService.setTransientOverlayActive(false);
      // Sockets are often silently dead after the phone was in background: verify immediately.
      try {
        ref.read(wsClientProvider).probeConnection();
      } catch (_) {}
      if (_myDeviceId != null && !kIsWeb) {
        _autoLockService.configureNativeStandbyEngine(deviceId: _myDeviceId!);
      }
      _connectInboxWebSocket();
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
            if (_globalStealthBannerText != null && !_obscureScreen)
              Positioned(
                top: 48,
                left: 20,
                right: 20,
                child: IgnorePointer(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111626).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF00FFA3), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00FFA3).withOpacity(0.28),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.diamond_rounded, color: Color(0xFF00FFA3), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _globalStealthBannerText!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_globalReactionMeta != null && !_obscureScreen)
              Positioned.fill(
                child: IgnorePointer(
                  child: Material(
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _globalReactionMeta!.color.withOpacity(0.55),
                              GhostPalette.neonPurple.withOpacity(0.16),
                              Colors.transparent,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _globalReactionMeta!.color.withOpacity(0.45),
                              blurRadius: 48,
                              spreadRadius: 12,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GhostStickerArtwork(
                              sticker: GhostStickerCatalog.findById(
                                  _globalReactionMeta!.stickerId),
                              size: 112,
                              reducedMotion: GhostTouchPreferencesService
                                  .instance.current.reducedMotion,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _globalReactionMeta!.titleFa,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_globalFlashMessage != null && !_obscureScreen)
              Positioned.fill(
                child: FlashHologramOverlay(
                  message: _globalFlashMessage!,
                  isFa: true,
                  hologramStyle: _globalFlashMessage!.hologramStyle != null
                      ? HologramStyleExt.parse(_globalFlashMessage!.hologramStyle)
                      : null,
                  cardData: _globalFlashMessage!.cardDataJson != null
                      ? FlashCardData.fromJsonString(_globalFlashMessage!.cardDataJson)
                      : null,
                  autoVanishSeconds: _globalFlashMessage!.displayDurationSec ??
                      GhostTouchPreferencesService.instance.current.displayDurationSec,
                  onQuickReaction: (reactionKey) {
                    final target = _globalFlashMessage?.senderDeviceId;
                    if (target == null ||
                        target.isEmpty ||
                        target == 'peer' ||
                        _myDeviceId == null) {
                      return;
                    }
                    final meta = GhostReactionMeta.of(reactionKey);
                    unawaited(RelayDirectoryService.pushInboxEvent(
                      recipientDeviceId: target,
                      senderDeviceId: _myDeviceId!,
                      eventType: 'reaction_burst',
                      reactionType: meta.key,
                      title: meta.titleFa,
                      body: meta.titleFa,
                      colorHex: GhostPalette.toHex(meta.color),
                      stickerId: meta.stickerId,
                    ));
                  },
                  onQuickStickerReply: (stId) {
                    final target = _globalFlashMessage?.senderDeviceId;
                    final st = GhostStickerCatalog.findById(stId);
                    if (target != null &&
                        target.isNotEmpty &&
                        target != 'peer' &&
                        _myDeviceId != null) {
                      unawaited(() async {
                        final pngB64 = await GhostStickerArtwork
                            .renderStickerToPngBase64(st);
                        await RelayDirectoryService.pushInboxEvent(
                          recipientDeviceId: target,
                          senderDeviceId: _myDeviceId!,
                          eventType: 'flash_hologram',
                          emoji: st.fallbackGlyph,
                          title: st.titleFa,
                          body: st.titleFa,
                          colorHex: GhostPalette.toHex(st.primaryColor),
                          mediaBase64: pngB64,
                          flashSeconds: GhostTouchPreferencesService
                              .instance.current.displayDurationSec,
                          hologramStyle: HologramStyle.floatingSticker.name,
                          stickerId: st.id,
                        );
                      }());
                    }
                    if (mounted) setState(() => _globalFlashMessage = null);
                  },
                  onDismiss: () {
                    if (mounted) setState(() => _globalFlashMessage = null);
                  },
                ),
              ),
          ],
        );
      },
      home: const GameHomeScreen(),
    );
  }
}
