import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../core/app_localizations.dart';
import '../../core/relay_directory_service.dart';
import '../../core/theme.dart';
import '../../contacts/contact_model.dart';
import '../../security/auto_lock_service.dart';
import '../../security/keystore_service.dart';
import '../../cryptography/crypto_service.dart';
import '../../networking/websocket_client.dart';
import '../chat_message.dart';
import '../chat_session.dart';
import '../widgets/neon_sketch_dialog.dart';
import '../widgets/cyber_sticker_sheet.dart';
import '../widgets/encrypted_photo_studio_dialog.dart';
import '../widgets/flash_hologram_overlay.dart';
import '../widgets/walkie_talkie_voice_dialog.dart';
import '../../authentication/screens/device_verification_screen.dart';
import '../../voice/screens/voice_call_screen.dart';
import '../../networking/screens/connection_status_screen.dart';
import '../../networking/screens/network_mode_screen.dart';
import '../../security/screens/security_settings_screen.dart';
import '../../game/screens/game_home_screen.dart';

// Riverpod Providers
final keystoreProvider = Provider<KeystoreService>((ref) => KeystoreService());
final cryptoServiceProvider = Provider<CryptoService>((ref) => CryptoService());
final wsClientProvider = Provider<SecretPlayWebSocketClient>((ref) => SecretPlayWebSocketClient());
final autoLockProvider = Provider<AutoLockService>((ref) => AutoLockService());

final chatSessionProvider =
    StateNotifierProvider<ChatSessionNotifier, List<EphemeralChatMessage>>((ref) {
  return ChatSessionNotifier(
    cryptoService: ref.watch(cryptoServiceProvider),
    wsClient: ref.watch(wsClientProvider),
    autoLockService: ref.watch(autoLockProvider),
  );
});

class PrivateChatScreen extends ConsumerStatefulWidget {
  final SecretContact? activeContact;

  const PrivateChatScreen({super.key, this.activeContact});

  @override
  ConsumerState<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends ConsumerState<PrivateChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  String _activeToken = '';
  String? _myDeviceId;
  String? _peerDeviceId;
  SimpleKeyPair? _myKeyPair;
  bool _sendNextTextAsFlash = false;
  int? _burnTimerSeconds; // null = Off, or 5, 10, 30 seconds
  EphemeralChatMessage? _activeFlashHologram;
  Timer? _uiCountdownTick;
  final Set<String> _playingVoiceIds = {};
  bool _isPeerTyping = false;
  Timer? _peerTypingResetTimer;
  Timer? _myTypingThrottleTimer;
  bool _sentTypingStart = false;

  StreamSubscription? _statusSub;
  StreamSubscription? _signalSub;
  StreamSubscription? _peerIdSub;
  StreamSubscription? _flashSub;
  bool _isShowingIncomingCall = false;

  @override
  void initState() {
    super.initState();
    AutoLockService().addLockListener(_onAutoLock);
    AutoLockService().setStandbyServiceEnabled(true);
    _uiCountdownTick = Timer.periodic(const Duration(seconds: 1), (_) {
      final messages = ref.read(chatSessionProvider);
      if (mounted && messages.any((m) => m.expiresAtMs != null)) {
        setState(() {});
      }
    });
    _setupConnection();
  }

  @override
  void dispose() {
    AutoLockService().removeLockListener(_onAutoLock);
    _uiCountdownTick?.cancel();
    _peerTypingResetTimer?.cancel();
    _myTypingThrottleTimer?.cancel();
    _statusSub?.cancel();
    _signalSub?.cancel();
    _peerIdSub?.cancel();
    _flashSub?.cancel();
    _textController.clear();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onAutoLock(String reason) {
    _textController.clear();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GameHomeScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _setupConnection() async {
    final keystore = ref.read(keystoreProvider);
    final wsClient = ref.read(wsClientProvider);
    final crypto = ref.read(cryptoServiceProvider);

    final deviceId = await keystore.getOrCreateDeviceId();
    var myPriv = await keystore.getIdentityPrivateKey();
    var myPub = await keystore.getIdentityPublicKey();

    if (myPriv == null || myPub == null) {
      final generated = await crypto.generateIdentityKeyPair();
      myPriv = await crypto.exportPrivateKey(generated);
      myPub = await crypto.exportPublicKey(generated);
      await keystore.saveIdentityKeyPair(
        privateKeyBase64: myPriv,
        publicKeyBase64: myPub,
      );
    }

    final keyPair = await crypto.reconstructIdentityKeyPair(myPriv);
    _myDeviceId = deviceId;
    _myKeyPair = keyPair;

    final savedToken =
        widget.activeContact?.roomToken ?? (await keystore.getPairToken()) ?? '';
    if (savedToken.isNotEmpty) {
      await keystore.savePairToken(savedToken);
      ref.read(networkConfigProvider.notifier).setPairToken(savedToken);
    }
    if (mounted) {
      setState(() => _activeToken = savedToken);
    }

    String? peerId = widget.activeContact != null
        ? widget.activeContact!.peerDeviceId
        : await keystore.getPeerDeviceId();
    String? peerPub = widget.activeContact != null
        ? widget.activeContact!.peerPublicKey
        : await keystore.getPeerPublicKey();

    if ((peerPub == null || peerPub.isEmpty) && widget.activeContact != null) {
      final lookedUp = await RelayDirectoryService.lookupBySecretNumber(
        widget.activeContact!.contactId,
      );
      if (lookedUp != null) {
        peerId = lookedUp['deviceId'];
        peerPub = lookedUp['publicKey'];
      }
    }
    _peerDeviceId = peerId;

    final sessionNotifier = ref.read(chatSessionProvider.notifier);
    if (peerId != null && peerPub != null && peerPub.isNotEmpty) {
      sessionNotifier.initializeSession(
        myDeviceId: deviceId,
        peerDeviceId: peerId,
        peerPublicKeyBase64: peerPub,
        myIdentityKeyPair: keyPair,
      );
    }

    _flashSub?.cancel();
    _flashSub = sessionNotifier.onFlashMessage.listen((flashMsg) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() => _activeFlashHologram = flashMsg);
      }
    });

    _peerIdSub?.cancel();
    _peerIdSub = wsClient.onPeerIdentity.listen((peerInfo) async {
      final pId = peerInfo['peerDeviceId'];
      final pKey = peerInfo['peerPublicKey'];
      if (pId != null && pKey != null && _myDeviceId != null && _myKeyPair != null) {
        _peerDeviceId = pId;
        await keystore.savePairedPeer(
          peerDeviceId: pId,
          peerPublicKeyBase64: pKey,
        );
        // Also persist peer key inside Contacts list if activeContact is set
        final rawList = await keystore.getContactsJson();
        if (rawList != null && rawList.isNotEmpty) {
          try {
            final decoded = (jsonDecode(rawList) as List<dynamic>)
                .map((e) => SecretContact.fromJson(e as Map<String, dynamic>))
                .toList();
            bool updated = false;
            for (int i = 0; i < decoded.length; i++) {
              if (decoded[i].roomToken == _activeToken ||
                  decoded[i].contactId == widget.activeContact?.contactId) {
                decoded[i] = decoded[i].copyWith(
                  peerDeviceId: pId,
                  peerPublicKey: pKey,
                  lastActiveAt: DateTime.now().millisecondsSinceEpoch,
                );
                updated = true;
              }
            }
            if (updated) {
              await keystore.saveContactsJson(
                jsonEncode(decoded.map((c) => c.toJson()).toList()),
              );
            }
          } catch (_) {}
        }

        ref.read(chatSessionProvider.notifier).initializeSession(
              myDeviceId: _myDeviceId!,
              peerDeviceId: pId,
              peerPublicKeyBase64: pKey,
              myIdentityKeyPair: _myKeyPair!,
            );
      }
    });

    _statusSub?.cancel();
    _statusSub = wsClient.onStatusChange.listen((status) {
      if (mounted) {
        setState(() => _connectionStatus = status);
      }
    });

    _signalSub?.cancel();
    _signalSub = wsClient.onSignal.listen((payload) {
      if (!mounted) return;
      final signalType = payload['signalType'] as String?;
      final senderId = payload['senderDeviceId'] as String?;
      if (senderId != null && senderId.isNotEmpty) {
        _peerDeviceId = senderId;
      }

      if (signalType == 'typing_start') {
        _peerTypingResetTimer?.cancel();
        if (!_isPeerTyping) {
          setState(() => _isPeerTyping = true);
        }
        _peerTypingResetTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _isPeerTyping = false);
        });
        return;
      } else if (signalType == 'typing_stop') {
        _peerTypingResetTimer?.cancel();
        if (_isPeerTyping) {
          setState(() => _isPeerTyping = false);
        }
        return;
      }

      if (signalType == 'call_request' && !_isShowingIncomingCall) {
        _isShowingIncomingCall = true;
        bool incomingVideo = false;
        final rawEnc = payload['encryptedPayload'] as String? ?? '';
        if (rawEnc.isNotEmpty) {
          try {
            final decoded = utf8.decode(base64Decode(rawEnc));
            if (decoded.contains('"video":true')) {
              incomingVideo = true;
            }
          } catch (_) {}
        }
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => VoiceCallScreen(
                  isIncoming: true,
                  isVideoCall: incomingVideo,
                  initialPeerDeviceId: senderId ?? _peerDeviceId,
                  peerDisplayName: widget.activeContact?.alias,
                ),
              ),
            )
            .whenComplete(() {
          _isShowingIncomingCall = false;
        });
      }
    });

    final netConfig = ref.read(networkConfigProvider);
    await wsClient.connect(
      config: netConfig,
      deviceId: deviceId,
      pairToken: savedToken,
      publicKey: myPub,
      signChallenge: (nonce, ts) async {
        return await crypto.signAuthChallenge(
          identityKeyPair: keyPair,
          deviceId: deviceId,
          nonce: nonce,
          timestamp: ts,
        );
      },
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String val) {
    final wsClient = ref.read(wsClientProvider);
    if (_myDeviceId == null) return;
    final trimmed = val.trim();

    if (trimmed.isEmpty) {
      if (_sentTypingStart) {
        _sentTypingStart = false;
        _myTypingThrottleTimer?.cancel();
        wsClient.sendRaw({
          'type': 'signal',
          'version': 1,
          'signalType': 'typing_stop',
          'senderDeviceId': _myDeviceId,
          'recipientDeviceId': _peerDeviceId ?? 'peer',
          'sessionEpoch': wsClient.sessionEpoch ?? 'offline-room',
          'encryptedPayload': '',
          'iv': '',
          'authTag': '',
          'seq': 0,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
      return;
    }

    if (!_sentTypingStart) {
      _sentTypingStart = true;
      wsClient.sendRaw({
        'type': 'signal',
        'version': 1,
        'signalType': 'typing_start',
        'senderDeviceId': _myDeviceId,
        'recipientDeviceId': _peerDeviceId ?? 'peer',
        'sessionEpoch': wsClient.sessionEpoch ?? 'offline-room',
        'encryptedPayload': '',
        'iv': '',
        'authTag': '',
        'seq': 0,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    _myTypingThrottleTimer?.cancel();
    _myTypingThrottleTimer = Timer(const Duration(seconds: 2), () {
      _sentTypingStart = false;
      wsClient.sendRaw({
        'type': 'signal',
        'version': 1,
        'signalType': 'typing_stop',
        'senderDeviceId': _myDeviceId,
        'recipientDeviceId': _peerDeviceId ?? 'peer',
        'sessionEpoch': wsClient.sessionEpoch ?? 'offline-room',
        'encryptedPayload': '',
        'iv': '',
        'authTag': '',
        'seq': 0,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _myTypingThrottleTimer?.cancel();
    if (_sentTypingStart && _myDeviceId != null) {
      _sentTypingStart = false;
      final wsClient = ref.read(wsClientProvider);
      wsClient.sendRaw({
        'type': 'signal',
        'version': 1,
        'signalType': 'typing_stop',
        'senderDeviceId': _myDeviceId,
        'recipientDeviceId': _peerDeviceId ?? 'peer',
        'sessionEpoch': wsClient.sessionEpoch ?? 'offline-room',
        'encryptedPayload': '',
        'iv': '',
        'authTag': '',
        'seq': 0,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
    var sent = await ref.read(chatSessionProvider.notifier).sendMessage(
          text,
          contentType: ChatContentType.text,
          isFlashScreen: _sendNextTextAsFlash,
          burnAfterSeconds: _burnTimerSeconds,
        );
    if (!sent && widget.activeContact != null && _myDeviceId != null && _myKeyPair != null) {
      // Retry directory lookup in case partner just came online or registered!
      final lookedUp = await RelayDirectoryService.lookupBySecretNumber(
        widget.activeContact!.contactId,
      );
      if (lookedUp != null) {
        _peerDeviceId = lookedUp['deviceId'];
        ref.read(chatSessionProvider.notifier).initializeSession(
              myDeviceId: _myDeviceId!,
              peerDeviceId: lookedUp['deviceId']!,
              peerPublicKeyBase64: lookedUp['publicKey']!,
              myIdentityKeyPair: _myKeyPair!,
            );
        sent = await ref.read(chatSessionProvider.notifier).sendMessage(
              text,
              contentType: ChatContentType.text,
              isFlashScreen: _sendNextTextAsFlash,
              burnAfterSeconds: _burnTimerSeconds,
            );
      }
    }
    if (!sent) {
      if (mounted) {
        final s = S(ref.read(appLocaleProvider));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              s.tr(
                'مخاطب هنوز کلید رمزنگاری خود را ثبت نکرده است. به محض اینکه یک بار وارد برنامه شود، کلیدش خودکار دریافت می‌شود!',
                'Partner has not registered their E2EE key yet. Once they open the app once, messaging will work even offline!',
              ),
            ),
          ),
        );
      }
      return;
    }
    _textController.clear();
    if (_sendNextTextAsFlash) {
      setState(() => _sendNextTextAsFlash = false);
    }
    _scrollToBottom();
  }

  void _cycleBurnTimer() {
    setState(() {
      if (_burnTimerSeconds == null) {
        _burnTimerSeconds = 10;
      } else if (_burnTimerSeconds == 10) {
        _burnTimerSeconds = 30;
      } else if (_burnTimerSeconds == 30) {
        _burnTimerSeconds = 5;
      } else {
        _burnTimerSeconds = null;
      }
    });
  }

  Future<void> _openVoiceRecorder() async {
    final isFa = ref.read(appLocaleProvider) == AppLang.fa;
    final res = await showDialog<WalkieTalkieVoiceResult>(
      context: context,
      builder: (_) => WalkieTalkieVoiceDialog(isFa: isFa),
    );
    if (res == null) return;
    await ref.read(chatSessionProvider.notifier).sendMessage(
          res.caption.isNotEmpty
              ? res.caption
              : (isFa ? 'پیام صوتی (${res.durationSec} ثانیه)' : 'Voice Note (${res.durationSec}s)'),
          contentType: ChatContentType.voice,
          mediaBase64: res.audioBase64,
          isFlashScreen: res.flashOnScreen,
          burnAfterSeconds: _burnTimerSeconds,
          isOneTimeVoice: res.isOneTimePlay,
          isCyberPitch: res.isCyberPitch,
          voiceDurationSec: res.durationSec,
        );
    _scrollToBottom();
  }

  Future<void> _playVoiceMessage(EphemeralChatMessage msg) async {
    if (msg.mediaBase64 == null || _playingVoiceIds.contains(msg.id)) return;
    setState(() => _playingVoiceIds.add(msg.id));
    await WalkieTalkieVoiceService.playVoiceNote(
      audioBase64: msg.mediaBase64!,
      cyberPitch: msg.isCyberPitch,
    );
    final waitSec = (msg.voiceDurationSec ?? 3).clamp(1, 10);
    await Future.delayed(Duration(seconds: waitSec));
    if (!mounted) return;
    setState(() => _playingVoiceIds.remove(msg.id));
    if (msg.isOneTimeVoice) {
      ref.read(chatSessionProvider.notifier).removeMessageById(msg.id);
    }
  }

  Future<void> _openSketchPad({bool initialFlash = true}) async {
    final isFa = ref.read(appLocaleProvider) == AppLang.fa;
    final res = await showDialog<NeonSketchResult>(
      context: context,
      builder: (_) => NeonSketchDialog(isFa: isFa, initialFlash: initialFlash),
    );
    if (res == null) return;
    await ref.read(chatSessionProvider.notifier).sendMessage(
          res.caption,
          contentType: ChatContentType.drawing,
          mediaBase64: res.pngBase64,
          isFlashScreen: res.flashOnLockScreen,
        );
    _scrollToBottom();
  }

  Future<void> _openPhotoStudio() async {
    final isFa = ref.read(appLocaleProvider) == AppLang.fa;
    final res = await showDialog<SnapPhotoResult>(
      context: context,
      builder: (_) => EncryptedPhotoStudioDialog(isFa: isFa),
    );
    if (res == null) return;
    await ref.read(chatSessionProvider.notifier).sendMessage(
          res.caption,
          contentType: ChatContentType.image,
          mediaBase64: res.pngBase64,
          isFlashScreen: res.flashOnScreen,
        );
    _scrollToBottom();
  }

  Future<void> _openStickerSheet() async {
    final isFa = ref.read(appLocaleProvider) == AppLang.fa;
    final res = await showModalBottomSheet<CyberStickerSelection>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => CyberStickerSheet(isFa: isFa),
    );
    if (res == null) return;
    await ref.read(chatSessionProvider.notifier).sendMessage(
          isFa ? res.sticker.titleFa : res.sticker.titleEn,
          contentType: ChatContentType.sticker,
          stickerId: res.sticker.id,
          isFlashScreen: res.flashOnScreen,
        );
    _scrollToBottom();
  }

  void _manualLockAndExit() {
    _textController.clear();
    AutoLockService().setStandbyServiceEnabled(false);
    ref.read(autoLockProvider).triggerLock('manual_exit');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const GameHomeScreen()),
      (route) => false,
    );
  }

  void _startVoiceCall({bool video = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceCallScreen(
          isIncoming: false,
          isVideoCall: video,
          initialPeerDeviceId: _peerDeviceId,
          peerDisplayName: widget.activeContact?.alias,
        ),
      ),
    );
  }

  void _openTokenSettings() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DeviceVerificationScreen()),
    );
  }

  void _openConnectionStatus() {
    final wsClient = ref.read(wsClientProvider);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ConnectionStatusScreen(wsClient: wsClient)),
    );
  }

  Color _getStatusColor() {
    switch (_connectionStatus) {
      case ConnectionStatus.peerOnline:
        return const Color(0xFF00FFA3);
      case ConnectionStatus.authenticated:
      case ConnectionStatus.connected:
        return const Color(0xFFFF9500);
      case ConnectionStatus.connecting:
        return const Color(0xFF64D2FF);
      case ConnectionStatus.disconnected:
        return const Color(0xFFFF453A);
    }
  }

  String _getStatusText(S s) {
    switch (_connectionStatus) {
      case ConnectionStatus.peerOnline:
        return s.tr('متصل • رمزنگاری دوطرفه فعال', 'Connected • E2EE Active');
      case ConnectionStatus.authenticated:
        return s.tr('آنلاین • منتظر نفر دوم با همین توکن', 'Online • Waiting for Partner');
      case ConnectionStatus.connected:
        return s.tr('در حال احراز هویت...', 'Authenticating...');
      case ConnectionStatus.connecting:
        return s.tr('در حال اتصال...', 'Connecting...');
      case ConnectionStatus.disconnected:
        return s.tr('آفلاین / قطع شده', 'Offline / Disconnected');
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatSessionProvider);
    final wsClient = ref.watch(wsClientProvider);
    final lang = ref.watch(appLocaleProvider);
    final s = S(lang);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _manualLockAndExit,
      },
      child: Focus(
        autofocus: true,
        child: Directionality(
          textDirection: s.dir,
          child: Theme(
            data: AppThemes.privateTheme,
            child: Stack(
              children: [
                Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                leading: IconButton(
                  icon: Icon(
                    Navigator.of(context).canPop() ? Icons.arrow_back_rounded : Icons.lock_rounded,
                    color: Navigator.of(context).canPop()
                        ? const Color(0xFF64D2FF)
                        : const Color(0xFFFF453A),
                  ),
                  tooltip: Navigator.of(context).canPop()
                      ? s.tr('بازگشت به مخاطبین', 'Back to Contacts')
                      : s.tr('قفل فوری و پاکسازی حافظه', 'Instant Lock & Wipe'),
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      _manualLockAndExit();
                    }
                  },
                ),
                title: GestureDetector(
                  onTap: _openConnectionStatus,
                  child: Column(
                    children: [
                      Text(
                        widget.activeContact != null
                            ? '${widget.activeContact!.alias} (${widget.activeContact!.contactId})'
                            : (_activeToken.isNotEmpty
                                ? s.tr('اتاق: $_activeToken', 'Room: $_activeToken')
                                : 'SECRETPLAY E2EE'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _getStatusColor(),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _isPeerTyping
                                ? s.tr('✍️ در حال نوشتن پیام...', '✍️ Typing a message...')
                                : _getStatusText(s),
                            style: TextStyle(
                              color: _isPeerTyping ? const Color(0xFF00E5FF) : _getStatusColor(),
                              fontSize: 10,
                              fontWeight: _isPeerTyping ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.call_rounded, color: Color(0xFF00FFA3)),
                    tooltip: s.tr('تماس صوتی رمزنگاری‌شده', 'Encrypted Voice Call'),
                    onPressed: _connectionStatus == ConnectionStatus.peerOnline
                        ? () => _startVoiceCall(video: false)
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.videocam_rounded, color: Color(0xFF00E5FF)),
                    tooltip: s.tr('تماس تصویری رمزنگاری‌شده', 'Encrypted Video Call'),
                    onPressed: _connectionStatus == ConnectionStatus.peerOnline
                        ? () => _startVoiceCall(video: true)
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.key_rounded, color: Color(0xFF64D2FF)),
                    tooltip: s.tr('تغییر توکن اتاق', 'Change Room Token'),
                    onPressed: _openTokenSettings,
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(38, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: () => ref.read(appLocaleProvider.notifier).toggleLanguage(),
                    child: Text(
                      s.isFa ? 'EN' : 'فا',
                      style: const TextStyle(
                        color: Color(0xFFFFD60A),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white70),
                    color: const Color(0xFF1C1C22),
                    onSelected: (val) {
                      if (val == 'network') {
                        Navigator.of(context)
                            .push(
                              MaterialPageRoute(
                                builder: (_) => NetworkModeScreen(wsClient: wsClient),
                              ),
                            )
                            .then((_) => _setupConnection());
                      } else if (val == 'security') {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
                        );
                      } else if (val == 'reconnect') {
                        _setupConnection();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'reconnect',
                        child: Text(
                          s.tr('🔄 اتصال مجدد به سرور', '🔄 Reconnect to Relay'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'network',
                        child: Text(
                          s.tr('🌐 حالت شبکه (کلودفلر / لوکال)', '🌐 Network Mode (Cloud / Local)'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'security',
                        child: Text(
                          s.tr('🛡️ تنظیمات امنیتی و کلیدها', '🛡️ Security & Keys'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              body: Column(
                children: [
                  // Shared Token & Flash Mode Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    color: const Color(0xFF1C1C1E),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _activeToken.isNotEmpty
                                ? s.tr(
                                    'توکن: $_activeToken • ارسال عکس، نقاشی و فلش روی صفحه قفل فعال است',
                                    'Token: $_activeToken • E2EE Photo, Sketch & Lock-Screen Flash Active',
                                  )
                                : s.tr('بدون ذخیره تاریخچه چت (Session-Only)', 'Zero-Disk Session-Only'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ),
                        if (_activeToken.isNotEmpty)
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: _activeToken));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    s.tr('توکن $_activeToken کپی شد!', 'Token $_activeToken copied!'),
                                  ),
                                ),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(Icons.copy, size: 15, color: Color(0xFF64D2FF)),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Messages View
                  Expanded(
                    child: messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    color: const Color(0xFFFF007A).withOpacity(0.35),
                                    size: 64,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _connectionStatus == ConnectionStatus.peerOnline
                                        ? s.tr(
                                            'اتصال دوطرفه برقرار شد!\nمی‌توانید پیام، عکس، استیکر یا نقاشی نئونی بفرستید تا مستقیم روی صفحه گوشی طرف مقابل ظاهر شود.',
                                            'Mutual E2EE Session Active!\nSend text, photos, stickers, or a Live Neon Sketch to pop up directly on your partner\'s screen.',
                                          )
                                        : s.tr(
                                            'منتظر ورود نفر دوم با توکن $_activeToken...',
                                            'Waiting for partner to join with token $_activeToken...',
                                          ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final msg = messages[index];
                              return _buildMessageBubble(msg, s);
                            },
                          ),
                  ),

                  // Animated Peer Typing Indicator Banner above input bar
                  if (_isPeerTyping)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      color: const Color(0xFF161824),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note_rounded, color: Color(0xFF00E5FF), size: 18),
                          const SizedBox(width: 6),
                          Text(
                            s.tr(
                              '${widget.activeContact?.alias ?? "مخاطب"} در حال نوشتن پیام است...',
                              '${widget.activeContact?.alias ?? "Partner"} is typing...',
                            ),
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Rich Media & Flash Action Toolbar + Text Input
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    color: const Color(0xFF121216),
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Quick Rich Media Bar (Photo / Neon Sketch / Stickers / Flash Screen Toggle)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildToolbarChip(
                                  icon: Icons.mic_rounded,
                                  label: s.tr('🎙️ ویس واکی‌تاکی', '🎙️ Voice Note'),
                                  color: const Color(0xFFBF5AF2),
                                  onTap: _openVoiceRecorder,
                                ),
                                const SizedBox(width: 8),
                                _buildToolbarChip(
                                  icon: Icons.timer_outlined,
                                  label: _burnTimerSeconds != null
                                      ? s.tr('⏱️ خودنابودگر: ${_burnTimerSeconds}s', '⏱️ Burn: ${_burnTimerSeconds}s')
                                      : s.tr('⏱️ خودنابودگر: خاموش', '⏱️ Burn: OFF'),
                                  color: const Color(0xFFFF9F0A),
                                  isActive: _burnTimerSeconds != null,
                                  onTap: _cycleBurnTimer,
                                ),
                                const SizedBox(width: 8),
                                _buildToolbarChip(
                                  icon: Icons.camera_alt_rounded,
                                  label: s.tr('📸 عکس', '📸 Photo'),
                                  color: const Color(0xFF00FFA3),
                                  onTap: _openPhotoStudio,
                                ),
                                const SizedBox(width: 8),
                                _buildToolbarChip(
                                  icon: Icons.brush_rounded,
                                  label: s.tr('🎨 نقاشی روی صفحه', '🎨 Neon Sketch'),
                                  color: const Color(0xFF00E5FF),
                                  onTap: () => _openSketchPad(initialFlash: true),
                                ),
                                const SizedBox(width: 8),
                                _buildToolbarChip(
                                  icon: Icons.auto_awesome_rounded,
                                  label: s.tr('✨ استیکر نئونی', '✨ Stickers'),
                                  color: const Color(0xFFFFD60A),
                                  onTap: _openStickerSheet,
                                ),
                                const SizedBox(width: 8),
                                _buildToolbarChip(
                                  icon: Icons.bolt_rounded,
                                  label: _sendNextTextAsFlash
                                      ? s.tr('⚡ فلش روی صفحه: روشن', '⚡ Screen Flash: ON')
                                      : s.tr('⚡ فلش روی صفحه قفل', '⚡ Flash Lock Screen'),
                                  color: const Color(0xFFFF007A),
                                  isActive: _sendNextTextAsFlash,
                                  onTap: () {
                                    setState(() => _sendNextTextAsFlash = !_sendNextTextAsFlash);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _textController,
                                  onChanged: _onTextChanged,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: _sendNextTextAsFlash
                                        ? s.tr(
                                            '⚡ پیام فوری برای نمایش روی صفحه قفل طرف مقابل...',
                                            '⚡ Flash message to pop up on partner\'s screen...',
                                          )
                                        : s.tr(
                                            'پیام رمزنگاری‌شده بنویسید...',
                                            'Write an encrypted message...',
                                          ),
                                    hintStyle: TextStyle(
                                      color: _sendNextTextAsFlash
                                          ? const Color(0xFFFF007A)
                                          : Colors.white30,
                                      fontSize: 13,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF1C1C22),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 11,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: _sendNextTextAsFlash
                                          ? const BorderSide(color: Color(0xFFFF007A), width: 1.5)
                                          : BorderSide.none,
                                    ),
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: _sendNextTextAsFlash
                                      ? const Color(0xFFFF007A)
                                      : const Color(0xFF007AFF),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    _sendNextTextAsFlash ? Icons.bolt_rounded : Icons.send_rounded,
                                    color: Colors.white,
                                  ),
                                  onPressed: _sendMessage,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Live Full-Screen Hologram Overlay when partner sends a Flash message/sketch/sticker!
            if (_activeFlashHologram != null)
              Positioned.fill(
                child: FlashHologramOverlay(
                  message: _activeFlashHologram!,
                  isFa: s.isFa,
                  onDismiss: () => setState(() => _activeFlashHologram = null),
                  onQuickReplySketch: () => _openSketchPad(initialFlash: true),
                ),
              ),
          ],
        ),
      ),
    ),
      ),
    );
  }

  Widget _buildToolbarChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color : color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.65)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isActive ? Colors.white : color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(EphemeralChatMessage msg, S s) {
    final timeStr = DateFormat('HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
    );
    final sticker = msg.contentType == ChatContentType.sticker
        ? CyberStickerCatalog.findById(msg.stickerId)
        : null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final remainingBurnSec = msg.expiresAtMs != null
        ? ((msg.expiresAtMs! - nowMs) / 1000).ceil().clamp(0, 999)
        : null;
    final isPlayingVoice = _playingVoiceIds.contains(msg.id);

    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isMe ? const Color(0xFF007AFF) : const Color(0xFF23232B),
          borderRadius: BorderRadius.circular(18),
          border: msg.isFlashScreen
              ? Border.all(color: const Color(0xFFFF007A), width: 1.5)
              : (remainingBurnSec != null
                  ? Border.all(color: const Color(0xFFFF9F0A), width: 1.4)
                  : null),
        ),
        child: Column(
          crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (msg.isFlashScreen || remainingBurnSec != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (msg.isFlashScreen)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt_rounded, color: Color(0xFFFFD60A), size: 14),
                          const SizedBox(width: 3),
                          Text(
                            s.tr('فلش هولوگرافیک', 'Screen Flash'),
                            style: const TextStyle(
                              color: Color(0xFFFFD60A),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    if (remainingBurnSec != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF9F0A), size: 14),
                          const SizedBox(width: 2),
                          Text(
                            s.tr('نابودی در ${remainingBurnSec}s', 'Burns in ${remainingBurnSec}s'),
                            style: const TextStyle(
                              color: Color(0xFFFF9F0A),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

            if (msg.contentType == ChatContentType.voice) ...[
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _playVoiceMessage(msg),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBF5AF2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPlayingVoice ? Icons.graphic_eq_rounded : Icons.play_circle_fill_rounded,
                        color: const Color(0xFF00FFA3),
                        size: 32,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg.text,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${msg.isCyberPitch ? s.tr("🤖 صدای سایبری • ", "🤖 Cyber Pitch • ") : ""}${msg.isOneTimeVoice ? s.tr("💥 یک‌بارمصرف", "💥 One-Time Listen") : s.tr("برای پخش بزنید", "Tap to play")}',
                              style: const TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (msg.contentType == ChatContentType.sticker && sticker != null) ...[
              Center(
                child: Column(
                  children: [
                    Text(sticker.emoji, style: const TextStyle(fontSize: 52)),
                    const SizedBox(height: 4),
                    Text(
                      s.isFa ? sticker.titleFa : sticker.titleEn,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if ((msg.contentType == ChatContentType.drawing ||
                    msg.contentType == ChatContentType.image) &&
                msg.mediaBase64 != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: const Color(0xFF09090D),
                  constraints: const BoxConstraints(maxHeight: 230),
                  child: Image.memory(
                    base64Decode(msg.mediaBase64!),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
              if (msg.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  msg.text,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ] else ...[
              Text(
                msg.text,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ],

            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
                if (msg.isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg.status == MessageDeliveryStatus.relayed
                        ? Icons.done_all
                        : Icons.done,
                    color: Colors.white70,
                    size: 13,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
