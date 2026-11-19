import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../security/auto_lock_service.dart';
import '../../security/keystore_service.dart';
import '../../cryptography/crypto_service.dart';
import '../../networking/websocket_client.dart';
import '../chat_message.dart';
import '../chat_session.dart';
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
  const PrivateChatScreen({super.key});

  @override
  ConsumerState<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends ConsumerState<PrivateChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  String _activeToken = '';
  String? _myDeviceId;
  SimpleKeyPair? _myKeyPair;

  StreamSubscription? _statusSub;
  StreamSubscription? _signalSub;
  StreamSubscription? _peerIdSub;
  bool _isShowingIncomingCall = false;

  @override
  void initState() {
    super.initState();
    AutoLockService().addLockListener(_onAutoLock);
    _setupConnection();
  }

  @override
  void dispose() {
    AutoLockService().removeLockListener(_onAutoLock);
    _statusSub?.cancel();
    _signalSub?.cancel();
    _peerIdSub?.cancel();
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

    final savedToken = (await keystore.getPairToken()) ?? '';
    if (savedToken.isNotEmpty) {
      ref.read(networkConfigProvider.notifier).setPairToken(savedToken);
    }
    if (mounted) {
      setState(() => _activeToken = savedToken);
    }

    final peerId = await keystore.getPeerDeviceId();
    final peerPub = await keystore.getPeerPublicKey();

    if (peerId != null && peerPub != null && peerPub.isNotEmpty) {
      ref.read(chatSessionProvider.notifier).initializeSession(
            myDeviceId: deviceId,
            peerDeviceId: peerId,
            peerPublicKeyBase64: peerPub,
            myIdentityKeyPair: keyPair,
          );
    }

    _peerIdSub?.cancel();
    _peerIdSub = wsClient.onPeerIdentity.listen((peerInfo) async {
      final pId = peerInfo['peerDeviceId'];
      final pKey = peerInfo['peerPublicKey'];
      if (pId != null && pKey != null && _myDeviceId != null && _myKeyPair != null) {
        await keystore.savePairedPeer(
          peerDeviceId: pId,
          peerPublicKeyBase64: pKey,
        );
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
      if (signalType == 'call_request' && !_isShowingIncomingCall) {
        _isShowingIncomingCall = true;
        Navigator.of(context)
            .push(
              MaterialPageRoute(
                builder: (_) => const VoiceCallScreen(isIncoming: true),
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

  void _sendMessage() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    ref.read(chatSessionProvider.notifier).sendMessage(text);
    _textController.clear();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _manualLockAndExit() {
    _textController.clear();
    ref.read(autoLockProvider).triggerLock('manual_exit');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const GameHomeScreen()),
      (route) => false,
    );
  }

  void _startVoiceCall() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VoiceCallScreen(isIncoming: false)),
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
        return const Color(0xFF00FFA3); // Green: Mutual active session
      case ConnectionStatus.authenticated:
      case ConnectionStatus.connected:
        return const Color(0xFFFF9500); // Amber: Connected, waiting for peer
      case ConnectionStatus.connecting:
        return const Color(0xFF64D2FF); // Blue: Connecting
      case ConnectionStatus.disconnected:
        return const Color(0xFFFF453A); // Red: Disconnected
    }
  }

  String _getStatusText() {
    switch (_connectionStatus) {
      case ConnectionStatus.peerOnline:
        return 'متصل • رمزنگاری دوطرفه فعال';
      case ConnectionStatus.authenticated:
        return 'آنلاین • منتظر نفر دوم با همین توکن';
      case ConnectionStatus.connected:
        return 'در حال احراز هویت...';
      case ConnectionStatus.connecting:
        return 'در حال اتصال...';
      case ConnectionStatus.disconnected:
        return 'آفلاین / قطع شده';
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatSessionProvider);
    final wsClient = ref.watch(wsClientProvider);

    return Theme(
      data: AppThemes.privateTheme,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.lock_rounded, color: Color(0xFFFF453A)),
            tooltip: 'قفل فوری و پاکسازی حافظه',
            onPressed: _manualLockAndExit,
          ),
          title: GestureDetector(
            onTap: _openConnectionStatus,
            child: Column(
              children: [
                Text(
                  _activeToken.isNotEmpty ? 'اتاق: $_activeToken' : 'SECRETPLAY E2EE',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
                      _getStatusText(),
                      style: TextStyle(
                        color: _getStatusColor(),
                        fontSize: 10,
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
              tooltip: 'تماس صوتی رمزنگاری‌شده',
              onPressed: _connectionStatus == ConnectionStatus.peerOnline ? _startVoiceCall : null,
            ),
            IconButton(
              icon: const Icon(Icons.key_rounded, color: Color(0xFF64D2FF)),
              tooltip: 'تغییر یا اشتراک‌گذاری توکن اتاق',
              onPressed: _openTokenSettings,
            ),
            IconButton(
              icon: const Icon(Icons.router_rounded, color: Colors.white70),
              tooltip: 'حالت شبکه (کلودفلر / لوکال)',
              onPressed: () {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => NetworkModeScreen(wsClient: wsClient),
                      ),
                    )
                    .then((_) => _setupConnection());
              },
            ),
            IconButton(
              icon: const Icon(Icons.security_rounded, color: Colors.white70),
              tooltip: 'تنظیمات امنیتی',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Shared Token quick-copy banner
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
                          ? 'توکن مشترک: $_activeToken • بدون ذخیره تاریخچه چت'
                          : 'بدون ذخیره تاریخچه چت (Session-Only)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ),
                  if (_activeToken.isNotEmpty)
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _activeToken));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('توکن $_activeToken کپی شد!')),
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
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            color: Colors.white.withOpacity(0.12),
                            size: 64,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _connectionStatus == ConnectionStatus.peerOnline
                                ? 'اتصال دوطرفه برقرار شد! پیام خود را بنویسید.'
                                : 'منتظر ورود نفر دوم با توکن $_activeToken...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white38, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        return _buildMessageBubble(msg);
                      },
                    ),
            ),

            // Message Input Field
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF121212),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'پیام رمزنگاری‌شده بنویسید...',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: const Color(0xFF1C1C1E),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF64D2FF)),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(EphemeralChatMessage msg) {
    final timeStr = DateFormat('HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
    );

    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isMe ? const Color(0xFF007AFF) : const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: msg.isMe ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: msg.isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
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
                    color: Colors.white54,
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
