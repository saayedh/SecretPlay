import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:permission_handler/permission_handler.dart';
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
  String? _peerPublicKey;
  SimpleKeyPair? _myKeyPair;
  bool _sendNextTextAsFlash = false;
  bool _showAttachDock = false;
  int? _burnTimerSeconds;
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
  StreamSubscription? _updateSub;
  bool _isShowingIncomingCall = false;
  bool _showHeartbeatWave = false;
  Timer? _heartbeatWaveTimer;

  @override
  void initState() {
    super.initState();
    _connectionStatus = ref.read(wsClientProvider).status;
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
    _heartbeatWaveTimer?.cancel();
    _statusSub?.cancel();
    _signalSub?.cancel();
    _peerIdSub?.cancel();
    _flashSub?.cancel();
    _updateSub?.cancel();
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
    if (!kIsWeb) {
      try {
        final granted = await Permission.notification.isGranted;
        if (!granted) {
          AutoLockService().setTransientOverlayActive(true);
          try {
            await Permission.notification.request();
          } finally {
            AutoLockService().setTransientOverlayActive(false);
          }
        }
      } catch (_) {}
    }
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

    var myNumber = await keystore.getMySecretNumber();
    if (myNumber == null || myNumber.isEmpty) {
      myNumber = SecretContact.deriveMySecretNumber('$deviceId:$myPub');
      await keystore.saveMySecretNumber(myNumber);
    }
    unawaited(RelayDirectoryService.registerIdentity(
      deviceId: deviceId,
      secretNumber: myNumber,
      publicKeyBase64: myPub,
    ));

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

    if ((peerPub == null || peerPub.isEmpty) &&
        wsClient.lastPeerDeviceId != null &&
        wsClient.lastPeerPublicKey != null) {
      peerId = wsClient.lastPeerDeviceId;
      peerPub = wsClient.lastPeerPublicKey;
    }

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
    _peerPublicKey = peerPub;

    final sessionNotifier = ref.read(chatSessionProvider.notifier);
    await sessionNotifier.switchRoom(savedToken);
    if (peerId != null && peerPub != null && peerPub.isNotEmpty) {
      sessionNotifier.initializeSession(
        myDeviceId: deviceId,
        peerDeviceId: peerId,
        peerPublicKeyBase64: peerPub,
        myIdentityKeyPair: keyPair,
      );
    }

    _updateSub?.cancel();
    _updateSub = wsClient.onAppUpdate.listen((updatePayload) {
      if (mounted) {
        final isFa = ref.read(appLocaleProvider) == AppLang.fa;
        RelayDirectoryService.showUpdateDialogFromPush(
          context,
          updatePayload,
          isFa: isFa,
        );
      }
    });

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
        _peerPublicKey = pKey;
        await keystore.savePairedPeer(
          peerDeviceId: pId,
          peerPublicKeyBase64: pKey,
        );
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
      } else if (signalType == 'stealth_ping') {
        AutoLockService().triggerStealthOnlinePing();
        if (mounted) {
          final s = S(ref.read(appLocaleProvider));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                s.tr(
                  '🤫 پینگ مخفی: مخاطب آنلاین شد و منتظر شماست!',
                  '🤫 Stealth ping: Partner is online!',
                ),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      } else if (signalType == 'heartbeat_pulse') {
        AutoLockService().triggerHeartbeatVibration();
        _heartbeatWaveTimer?.cancel();
        if (mounted) {
          setState(() => _showHeartbeatWave = true);
        }
        _heartbeatWaveTimer = Timer(const Duration(milliseconds: 2200), () {
          if (mounted) setState(() => _showHeartbeatWave = false);
        });
        return;
      }

      if (signalType == 'call_request' && !_isShowingIncomingCall) {
        _isShowingIncomingCall = true;
        bool incomingVideo = payload['isVideo'] == true;
        if (!incomingVideo) {
          final rawEnc = payload['encryptedPayload'] as String? ?? '';
          if (rawEnc.isNotEmpty) {
            try {
              final decoded = utf8.decode(base64Decode(rawEnc));
              if (decoded.contains('"video":true')) {
                incomingVideo = true;
              }
            } catch (_) {}
          }
        }
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => VoiceCallScreen(
                  isIncoming: true,
                  isVideoCall: incomingVideo,
                  initialPeerDeviceId: senderId ?? _peerDeviceId,
                  peerPublicKeyBase64: _peerPublicKey,
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
    setState(() {}); // Updates Send/Mic icon toggle
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

  Future<void> _sendWithAutoLookup({
    required String text,
    ChatContentType contentType = ChatContentType.text,
    String? mediaBase64,
    String? stickerId,
    bool isFlashScreen = false,
    int? burnAfterSeconds,
    bool isOneTimeVoice = false,
    bool isCyberPitch = false,
    int? voiceDurationSec,
  }) async {
    final notifier = ref.read(chatSessionProvider.notifier);
    var sent = await notifier.sendMessage(
          text,
          contentType: contentType,
          mediaBase64: mediaBase64,
          stickerId: stickerId,
          isFlashScreen: isFlashScreen,
          burnAfterSeconds: burnAfterSeconds,
          isOneTimeVoice: isOneTimeVoice,
          isCyberPitch: isCyberPitch,
          voiceDurationSec: voiceDurationSec,
        );
    if (!sent &&
        notifier.lastSendError == SendError.noPeerKey &&
        widget.activeContact != null &&
        _myDeviceId != null &&
        _myKeyPair != null) {
      final lookedUp = await RelayDirectoryService.lookupBySecretNumber(
        widget.activeContact!.contactId,
      );
      if (lookedUp != null) {
        _peerDeviceId = lookedUp['deviceId'];
        _peerPublicKey = lookedUp['publicKey'];
        notifier.initializeSession(
              myDeviceId: _myDeviceId!,
              peerDeviceId: lookedUp['deviceId']!,
              peerPublicKeyBase64: lookedUp['publicKey']!,
              myIdentityKeyPair: _myKeyPair!,
            );
        sent = await notifier.sendMessage(
              text,
              contentType: contentType,
              mediaBase64: mediaBase64,
              stickerId: stickerId,
              isFlashScreen: isFlashScreen,
              burnAfterSeconds: burnAfterSeconds,
              isOneTimeVoice: isOneTimeVoice,
              isCyberPitch: isCyberPitch,
              voiceDurationSec: voiceDurationSec,
            );
      }
    }
    if (!sent && mounted) {
      final s = S(ref.read(appLocaleProvider));
      final err = notifier.lastSendError;
      final msgText = err == SendError.tooLarge
          ? s.tr(
              'حجم تصویر یا صدا بیش از حد مجاز است (حداکثر ~900KB).',
              'Media payload exceeds relay frame limit.',
            )
          : s.tr(
              'مخاطب هنوز یک بار وارد برنامه نشده تا کلید رمزنگاری‌اش ثبت شود. به محض ورود اولش، ارسال آفلاین فعال می‌شود!',
              'Partner has not opened the app once yet to register their E2EE key.',
            );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msgText)),
      );
    }
    _scrollToBottom();
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
    _textController.clear();
    final flash = _sendNextTextAsFlash;
    if (_sendNextTextAsFlash) {
      setState(() => _sendNextTextAsFlash = false);
    } else {
      setState(() {});
    }
    await _sendWithAutoLookup(
      text: text,
      contentType: ChatContentType.text,
      isFlashScreen: flash,
      burnAfterSeconds: _burnTimerSeconds,
    );
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
    setState(() => _showAttachDock = false);
    final isFa = ref.read(appLocaleProvider) == AppLang.fa;
    final res = await showDialog<WalkieTalkieVoiceResult>(
      context: context,
      builder: (_) => WalkieTalkieVoiceDialog(isFa: isFa),
    );
    if (res == null) return;
    await _sendWithAutoLookup(
      text: res.caption.isNotEmpty
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
    setState(() => _showAttachDock = false);
    final isFa = ref.read(appLocaleProvider) == AppLang.fa;
    final res = await showDialog<NeonSketchResult>(
      context: context,
      builder: (_) => NeonSketchDialog(isFa: isFa, initialFlash: initialFlash),
    );
    if (res == null) return;
    await _sendWithAutoLookup(
      text: res.caption,
      contentType: ChatContentType.drawing,
      mediaBase64: res.pngBase64,
      isFlashScreen: res.flashOnLockScreen,
      burnAfterSeconds: _burnTimerSeconds,
    );
  }

  void _sendStealthOnlinePing() {
    if (_myDeviceId == null) return;
    final wsClient = ref.read(wsClientProvider);
    final rawEpoch = wsClient.sessionEpoch;
    final epoch = (rawEpoch != null && rawEpoch.isNotEmpty)
        ? rawEpoch
        : 'offline-$_activeToken';
    wsClient.sendRaw({
      'type': 'signal',
      'version': 1,
      'signalType': 'stealth_ping',
      'senderDeviceId': _myDeviceId,
      'recipientDeviceId': _peerDeviceId ?? 'peer',
      'sessionEpoch': epoch,
      'encryptedPayload': '',
      'iv': '',
      'authTag': '',
      'seq': 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    HapticFeedback.lightImpact();
    setState(() => _showAttachDock = false);
    if (mounted) {
      final s = S(ref.read(appLocaleProvider));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.tr(
              '🤫 پینگ مخفی (با پوشش اعلان بازی) برای مخاطب ارسال شد!',
              '🤫 Stealth disguised online ping sent to partner!',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _sendHeartbeatPulse() {
    if (_myDeviceId == null) return;
    final wsClient = ref.read(wsClientProvider);
    final rawEpoch = wsClient.sessionEpoch;
    final epoch = (rawEpoch != null && rawEpoch.isNotEmpty)
        ? rawEpoch
        : 'offline-$_activeToken';
    wsClient.sendRaw({
      'type': 'signal',
      'version': 1,
      'signalType': 'heartbeat_pulse',
      'senderDeviceId': _myDeviceId,
      'recipientDeviceId': _peerDeviceId ?? 'peer',
      'sessionEpoch': epoch,
      'encryptedPayload': '',
      'iv': '',
      'authTag': '',
      'seq': 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    AutoLockService().triggerHeartbeatVibration();
    _heartbeatWaveTimer?.cancel();
    setState(() {
      _showHeartbeatWave = true;
      _showAttachDock = false;
    });
    _heartbeatWaveTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showHeartbeatWave = false);
    });
  }

  Future<void> _openPhotoStudio() async {
    setState(() => _showAttachDock = false);
    final isFa = ref.read(appLocaleProvider) == AppLang.fa;
    final res = await showDialog<SnapPhotoResult>(
      context: context,
      builder: (_) => EncryptedPhotoStudioDialog(isFa: isFa),
    );
    if (res == null) return;
    await _sendWithAutoLookup(
      text: res.caption,
      contentType: ChatContentType.image,
      mediaBase64: res.pngBase64,
      isFlashScreen: res.flashOnScreen,
      burnAfterSeconds: _burnTimerSeconds,
    );
  }

  Future<void> _openStickerSheet() async {
    setState(() => _showAttachDock = false);
    final isFa = ref.read(appLocaleProvider) == AppLang.fa;
    final res = await showModalBottomSheet<CyberStickerSelection>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => CyberStickerSheet(isFa: isFa),
    );
    if (res == null) return;
    await _sendWithAutoLookup(
      text: isFa ? res.sticker.titleFa : res.sticker.titleEn,
      contentType: ChatContentType.sticker,
      stickerId: res.sticker.id,
      isFlashScreen: res.flashOnScreen,
      burnAfterSeconds: _burnTimerSeconds,
    );
  }

  void _openImageLightbox(String mediaBase64) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.memory(base64Decode(mediaBase64), fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
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
          peerPublicKeyBase64: _peerPublicKey,
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
        return const Color(0xFFFFB800);
      case ConnectionStatus.connecting:
        return const Color(0xFF00E5FF);
      case ConnectionStatus.disconnected:
        return const Color(0xFFFF453A);
    }
  }

  String _getStatusText(S s) {
    switch (_connectionStatus) {
      case ConnectionStatus.peerOnline:
        return s.tr('آنلاین • رمزنگاری سرتاسری', 'Online • E2EE Active');
      case ConnectionStatus.authenticated:
        return s.tr('آماده ارسال آفلاین و آنلاین', 'Offline & Online Ready');
      case ConnectionStatus.connected:
        return s.tr('در حال احراز هویت...', 'Authenticating...');
      case ConnectionStatus.connecting:
        return s.tr('در حال اتصال...', 'Connecting...');
      case ConnectionStatus.disconnected:
        return s.tr('آفلاین', 'Offline');
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatSessionProvider);
    final wsClient = ref.watch(wsClientProvider);
    final lang = ref.watch(appLocaleProvider);
    final s = S(lang);
    final titleText = widget.activeContact?.alias ??
        (_activeToken.isNotEmpty ? _activeToken : 'SECRETPLAY');
    final hasText = _textController.text.trim().isNotEmpty;

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
                  backgroundColor: const Color(0xFF07080D),
                  appBar: AppBar(
                    backgroundColor: const Color(0xFF0D0F18),
                    leading: IconButton(
                      icon: Icon(
                        Navigator.of(context).canPop()
                            ? Icons.arrow_back_ios_new_rounded
                            : Icons.lock_rounded,
                        color: Navigator.of(context).canPop()
                            ? const Color(0xFF00E5FF)
                            : const Color(0xFFFF453A),
                        size: 20,
                      ),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          _manualLockAndExit();
                        }
                      },
                    ),
                    titleSpacing: 0,
                    title: GestureDetector(
                      onTap: _openConnectionStatus,
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFF00FFA3), Color(0xFF00B8D4)],
                              ),
                            ),
                            child: Center(
                              child: Text(
                                titleText.characters.first.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titleText,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: _isPeerTyping
                                            ? const Color(0xFF00E5FF)
                                            : _getStatusColor(),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        _isPeerTyping
                                            ? s.tr('در حال نوشتن...', 'typing...')
                                            : _getStatusText(s),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: _isPeerTyping
                                              ? const Color(0xFF00E5FF)
                                              : _getStatusColor(),
                                          fontSize: 11,
                                          fontWeight: _isPeerTyping
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.radar_rounded, color: Color(0xFFFFD60A)),
                        tooltip: s.tr('پینگ مخفی (من آنلاینم)', 'Stealth Ping (I am Online)'),
                        onPressed: _sendStealthOnlinePing,
                      ),
                      IconButton(
                        icon: const Icon(Icons.call_rounded, color: Color(0xFF00FFA3)),
                        tooltip: s.tr('تماس صوتی', 'Voice Call'),
                        onPressed: _connectionStatus == ConnectionStatus.peerOnline
                            ? () => _startVoiceCall(video: false)
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.videocam_rounded, color: Color(0xFF00E5FF)),
                        tooltip: s.tr('تماس تصویری', 'Video Call'),
                        onPressed: _connectionStatus == ConnectionStatus.peerOnline
                            ? () => _startVoiceCall(video: true)
                            : null,
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                        color: const Color(0xFF171A26),
                        onSelected: (val) {
                          if (val == 'clear_chat') {
                            ref.read(chatSessionProvider.notifier).clearCurrentRoomHistoryPermanently();
                          } else if (val == 'lock') {
                            _manualLockAndExit();
                          } else if (val == 'lang') {
                            ref.read(appLocaleProvider.notifier).toggleLanguage();
                          } else if (val == 'token') {
                            _openTokenSettings();
                          } else if (val == 'network') {
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
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'clear_chat',
                            child: Text(
                              s.tr('🗑️ پاک کردن تاریخچه این چت', '🗑️ Clear Chat History'),
                              style: const TextStyle(color: Colors.amber),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'lock',
                            child: Text(
                              s.tr('🔒 قفل فوری و خروج به بازی', '🔒 Panic Lock & Exit'),
                              style: const TextStyle(color: Color(0xFFFF453A)),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'lang',
                            child: Text(
                              s.isFa ? '🌐 Switch to English' : '🌐 تغییر زبان به فارسی',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'token',
                            child: Text(
                              s.tr('🔑 تنظیمات توکن اتاق', '🔑 Room Token'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'network',
                            child: Text(
                              s.tr('📡 حالت شبکه', '📡 Network Mode'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'security',
                            child: Text(
                              s.tr('🛡️ امنیت و پین فریبنده', '🛡️ Security Settings'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  body: Column(
                    children: [
                      // Messages List
                      Expanded(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(0.0, -0.3),
                              radius: 1.3,
                              colors: [Color(0xFF101322), Color(0xFF07080D)],
                            ),
                          ),
                          child: messages.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(28.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(18),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF00FFA3).withOpacity(0.1),
                                            border: Border.all(
                                              color: const Color(0xFF00FFA3).withOpacity(0.35),
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.shield_moon_rounded,
                                            color: Color(0xFF00FFA3),
                                            size: 46,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          s.tr(
                                            'گفتگوی کاملاً رمزنگاری‌شده و بدون تاریخچه',
                                            'End-to-End Encrypted • Zero-Disk Vault',
                                          ),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          s.tr(
                                            'پیام، استیکر، نقاشی نئونی یا ویس بفرستید — حتی اگر مخاطب آفلاین باشد در صف امن تحویل می‌ماند.',
                                            'Send texts, stickers, neon sketches, or voice notes — even if your partner is offline.',
                                          ),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  itemCount: messages.length,
                                  itemBuilder: (context, index) =>
                                      _buildMessageBubble(messages[index], s),
                                ),
                        ),
                      ),

                      // Typing Indicator Strip
                      if (_isPeerTyping)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          color: const Color(0xFF0E111C),
                          child: Row(
                            children: [
                              const Icon(Icons.more_horiz_rounded,
                                  color: Color(0xFF00E5FF), size: 20),
                              const SizedBox(width: 6),
                              Text(
                                s.tr(
                                  '$titleText در حال نوشتن است...',
                                  '$titleText is typing...',
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

                      // Expandable Clean Attachment Dock (+ Menu)
                      if (_showAttachDock)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF11131E),
                            border: Border(top: BorderSide(color: Colors.white10)),
                          ),
                          child: GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 2.1,
                            children: [
                              _buildAttachTile(
                                icon: Icons.camera_alt_rounded,
                                label: s.tr('عکس', 'Photo'),
                                color: const Color(0xFF00FFA3),
                                onTap: _openPhotoStudio,
                              ),
                              _buildAttachTile(
                                icon: Icons.brush_rounded,
                                label: s.tr('نقاشی نئونی', 'Sketch'),
                                color: const Color(0xFF00E5FF),
                                onTap: () => _openSketchPad(initialFlash: true),
                              ),
                              _buildAttachTile(
                                icon: Icons.auto_awesome_rounded,
                                label: s.tr('استیکر', 'Stickers'),
                                color: const Color(0xFFFFD60A),
                                onTap: _openStickerSheet,
                              ),
                              _buildAttachTile(
                                icon: Icons.mic_rounded,
                                label: s.tr('ویس واکی‌تاکی', 'Voice'),
                                color: const Color(0xFFBF5AF2),
                                onTap: _openVoiceRecorder,
                              ),
                              _buildAttachTile(
                                icon: Icons.local_fire_department_rounded,
                                label: _burnTimerSeconds != null
                                    ? s.tr('نابودی ${_burnTimerSeconds}s', 'Burn ${_burnTimerSeconds}s')
                                    : s.tr('تایمر حذف', 'Burn Timer'),
                                color: const Color(0xFFFF9F0A),
                                active: _burnTimerSeconds != null,
                                onTap: _cycleBurnTimer,
                              ),
                              _buildAttachTile(
                                icon: Icons.bolt_rounded,
                                label: s.tr('فلش صفحه قفل', 'Flash Lock'),
                                color: const Color(0xFFFF007A),
                                active: _sendNextTextAsFlash,
                                onTap: () {
                                  setState(() {
                                    _sendNextTextAsFlash = !_sendNextTextAsFlash;
                                    _showAttachDock = false;
                                  });
                                },
                              ),
                              _buildAttachTile(
                                icon: Icons.radar_rounded,
                                label: s.tr('پینگ مخفی', 'Stealth Ping'),
                                color: const Color(0xFFFFD60A),
                                onTap: _sendStealthOnlinePing,
                              ),
                              _buildAttachTile(
                                icon: Icons.favorite_rounded,
                                label: s.tr('تپش قلب', 'Heartbeat'),
                                color: const Color(0xFFFF2A85),
                                onTap: _sendHeartbeatPulse,
                              ),
                              _buildAttachTile(
                                icon: Icons.visibility_off_rounded,
                                label: s.tr('فلش محو ۵s', '5s Vanish'),
                                color: const Color(0xFF38BDF8),
                                active: _sendNextTextAsFlash && _burnTimerSeconds == 5,
                                onTap: () {
                                  setState(() {
                                    _sendNextTextAsFlash = true;
                                    _burnTimerSeconds = 5;
                                    _showAttachDock = false;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                      // Sleek Modern Input Bar
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0D0F18),
                          border: Border(top: BorderSide(color: Colors.white10)),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  _showAttachDock
                                      ? Icons.close_rounded
                                      : Icons.add_circle_outline_rounded,
                                  color: _showAttachDock
                                      ? const Color(0xFFFF007A)
                                      : const Color(0xFF00E5FF),
                                  size: 28,
                                ),
                                onPressed: () =>
                                    setState(() => _showAttachDock = !_showAttachDock),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.emoji_emotions_rounded,
                                  color: Color(0xFFFFD60A),
                                  size: 24,
                                ),
                                tooltip: s.tr('استیکرها', 'Stickers'),
                                onPressed: _openStickerSheet,
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _textController,
                                  onChanged: _onTextChanged,
                                  style: const TextStyle(color: Colors.white, fontSize: 15),
                                  decoration: InputDecoration(
                                    hintText: _sendNextTextAsFlash
                                        ? s.tr(
                                            '⚡ پیام فلش روی صفحه قفل...',
                                            '⚡ Flash message on lock screen...',
                                          )
                                        : s.tr(
                                            'پیام خود را بنویسید...',
                                            'Message...',
                                          ),
                                    hintStyle: TextStyle(
                                      color: _sendNextTextAsFlash
                                          ? const Color(0xFFFF007A)
                                          : Colors.white38,
                                      fontSize: 13,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFF171A26),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 11,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: _sendNextTextAsFlash
                                          ? const BorderSide(
                                              color: Color(0xFFFF007A),
                                              width: 1.4,
                                            )
                                          : BorderSide.none,
                                    ),
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: hasText ? _sendMessage : _openVoiceRecorder,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: _sendNextTextAsFlash
                                          ? [const Color(0xFFFF007A), const Color(0xFFFF5E00)]
                                          : (hasText
                                              ? [const Color(0xFF00FFA3), const Color(0xFF00E5FF)]
                                              : [const Color(0xFF9D4EDD), const Color(0xFF5E5CE6)]),
                                    ),
                                  ),
                                  child: Icon(
                                    hasText
                                        ? (_sendNextTextAsFlash
                                            ? Icons.bolt_rounded
                                            : Icons.send_rounded)
                                        : Icons.mic_rounded,
                                    color: hasText && !_sendNextTextAsFlash
                                        ? Colors.black
                                        : Colors.white,
                                    size: 21,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_activeFlashHologram != null)
                  Positioned.fill(
                    child: FlashHologramOverlay(
                      message: _activeFlashHologram!,
                      isFa: s.isFa,
                      onDismiss: () => setState(() => _activeFlashHologram = null),
                      onQuickReplySketch: () => _openSketchPad(initialFlash: true),
                    ),
                  ),

                if (_showHeartbeatWave)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedScale(
                          scale: _showHeartbeatWave ? 1.1 : 0.6,
                          duration: const Duration(milliseconds: 350),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  const Color(0xFFFF007A).withOpacity(0.55),
                                  const Color(0xFFFF007A).withOpacity(0.12),
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF2A85).withOpacity(0.55),
                                  blurRadius: 48,
                                  spreadRadius: 12,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.favorite_rounded,
                                  color: Color(0xFFFF2A85),
                                  size: 84,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  s.tr('❤️‍🔥 تپش قلب زنده', '❤️‍🔥 Live Heartbeat'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      Shadow(color: Colors.black, blurRadius: 8),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.28) : color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(active ? 1.0 : 0.45)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 17),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
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

    final isSticker = msg.contentType == ChatContentType.sticker && sticker != null;

    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSticker
              ? LinearGradient(
                  colors: [
                    sticker.neonColor.withOpacity(0.24),
                    const Color(0xFF121628).withOpacity(0.92),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : (msg.isMe
                  ? const LinearGradient(
                      colors: [Color(0xFF007CF0), Color(0xFF00B4D8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [Color(0xFF15192B), Color(0xFF1D233B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(msg.isMe ? 20 : 5),
            bottomRight: Radius.circular(msg.isMe ? 5 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: (isSticker
                      ? sticker.neonColor
                      : (msg.isMe ? const Color(0xFF0099FF) : Colors.black))
                  .withOpacity(isSticker ? 0.22 : 0.20),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
          border: msg.isFlashScreen
              ? Border.all(color: const Color(0xFFFF007A), width: 1.6)
              : (remainingBurnSec != null
                  ? Border.all(color: const Color(0xFFFF9F0A), width: 1.5)
                  : Border.all(
                      color: isSticker
                          ? sticker.neonColor.withOpacity(0.6)
                          : Colors.white.withOpacity(msg.isMe ? 0.14 : 0.08),
                    )),
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
                          const Icon(Icons.local_fire_department_rounded,
                              color: Color(0xFFFF9F0A), size: 14),
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
                        isPlayingVoice
                            ? Icons.graphic_eq_rounded
                            : Icons.play_circle_fill_rounded,
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
                              '${msg.isCyberPitch ? s.tr("🤖 صدای سایبری • ", "🤖 Cyber Pitch • ") : ""}${msg.isOneTimeVoice ? s.tr("💥 یک‌بارمصرف", "💥 One-Time") : s.tr("پخش", "Play")}',
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
                    Text(sticker.emoji, style: const TextStyle(fontSize: 54)),
                    const SizedBox(height: 4),
                    Text(
                      s.isFa ? sticker.titleFa : sticker.titleEn,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if ((msg.contentType == ChatContentType.drawing ||
                    msg.contentType == ChatContentType.image) &&
                msg.mediaBase64 != null) ...[
              GestureDetector(
                onTap: () => _openImageLightbox(msg.mediaBase64!),
                child: ClipRRect(
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
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
              ),
            ],

            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(color: Colors.white60, fontSize: 10),
                ),
                if (msg.isMe) ...[
                  const SizedBox(width: 4),
                  if (msg.status == MessageDeliveryStatus.failed)
                    GestureDetector(
                      onTap: () => ref.read(chatSessionProvider.notifier).resendFailedMessage(msg.id),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline_rounded, color: Color(0xFFFF453A), size: 14),
                          SizedBox(width: 2),
                          Text('تلاش مجدد', style: TextStyle(color: Color(0xFFFF453A), fontSize: 10)),
                        ],
                      ),
                    )
                  else
                    Icon(
                      msg.status == MessageDeliveryStatus.relayed
                          ? Icons.done_all_rounded
                          : (msg.status == MessageDeliveryStatus.sent
                              ? Icons.done_rounded
                              : Icons.schedule_rounded),
                      color: msg.status == MessageDeliveryStatus.relayed
                          ? const Color(0xFF00FFA3)
                          : Colors.white70,
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
