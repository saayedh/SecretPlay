import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../cryptography/crypto_service.dart';
import '../networking/websocket_client.dart';
import '../security/auto_lock_service.dart';
import 'chat_message.dart';

class ChatSessionNotifier extends StateNotifier<List<EphemeralChatMessage>> {
  final CryptoService _cryptoService;
  final SecretPlayWebSocketClient _wsClient;
  final AutoLockService _autoLockService;

  String? _myDeviceId;
  String? _peerDeviceId;
  String? _peerPublicKeyBase64;
  SimpleKeyPair? _myIdentityKeyPair;

  StreamSubscription? _msgSub;
  StreamSubscription? _termSub;

  ChatSessionNotifier({
    required CryptoService cryptoService,
    required SecretPlayWebSocketClient wsClient,
    required AutoLockService autoLockService,
  })  : _cryptoService = cryptoService,
        _wsClient = wsClient,
        _autoLockService = autoLockService,
        super([]) {
    _initListeners();
  }

  void _initListeners() {
    _autoLockService.addLockListener(_handleAutoLock);

    _msgSub = _wsClient.onMessage.listen((payload) async {
      await _handleIncomingMessage(payload);
    });

    _termSub = _wsClient.onTerminate.listen((reason) {
      clearSession();
    });
  }

  void initializeSession({
    required String myDeviceId,
    required String peerDeviceId,
    required String peerPublicKeyBase64,
    required SimpleKeyPair myIdentityKeyPair,
  }) {
    _myDeviceId = myDeviceId;
    _peerDeviceId = peerDeviceId;
    _peerPublicKeyBase64 = peerPublicKeyBase64;
    _myIdentityKeyPair = myIdentityKeyPair;
    _cryptoService.resetSequence();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (_peerPublicKeyBase64 == null || _myIdentityKeyPair == null || _wsClient.sessionEpoch == null) {
      debugPrint('[Chat] Cannot send message: active mutual session epoch not established.');
      return;
    }

    final outgoingMsg = EphemeralChatMessage(
      senderDeviceId: _myDeviceId ?? 'me',
      text: text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isMe: true,
      status: MessageDeliveryStatus.sending,
    );

    // Append to memory state
    state = [...state, outgoingMsg];

    try {
      final envelope = await _cryptoService.encryptMessage(
        plaintext: text,
        recipientPublicIdentityKeyBase64: _peerPublicKeyBase64!,
        senderIdentityKeyPair: _myIdentityKeyPair!,
        sessionEpoch: _wsClient.sessionEpoch!,
      );

      _wsClient.sendRaw({
        'type': 'msg',
        'version': 1,
        'msgId': outgoingMsg.id,
        'senderDeviceId': _myDeviceId,
        'recipientDeviceId': _peerDeviceId,
        'sessionEpoch': _wsClient.sessionEpoch,
        'ciphertext': envelope.ciphertextBase64,
        'iv': envelope.ivBase64,
        'authTag': envelope.authTagBase64,
        'ephemeralPubKey': envelope.ephemeralPubKeyBase64,
        'seq': envelope.seq,
        'signature': envelope.signatureBase64,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Update delivery status in memory
      state = [
        for (final m in state)
          if (m.id == outgoingMsg.id) m.copyWith(status: MessageDeliveryStatus.sent) else m
      ];
    } catch (e) {
      debugPrint('[Chat] Encryption error: $e');
      state = [
        for (final m in state)
          if (m.id == outgoingMsg.id) m.copyWith(status: MessageDeliveryStatus.failed) else m
      ];
    }
  }

  Future<void> _handleIncomingMessage(Map<String, dynamic> payload) async {
    final type = payload['type'] as String?;
    if (type == 'msg_ack') {
      final msgId = payload['msgId'] as String?;
      final ackStatus = payload['status'] as String?;
      if (msgId != null) {
        state = [
          for (final m in state)
            if (m.id == msgId)
              m.copyWith(
                status: ackStatus == 'relayed'
                    ? MessageDeliveryStatus.relayed
                    : MessageDeliveryStatus.failed,
              )
            else
              m
        ];
      }
      return;
    }

    if (type != null && type != 'msg') return;
    if (_myIdentityKeyPair == null || _peerPublicKeyBase64 == null) return;

    try {
      final envelope = EncryptedEnvelope(
        ciphertextBase64: payload['ciphertext'] as String,
        ivBase64: payload['iv'] as String,
        authTagBase64: payload['authTag'] as String,
        ephemeralPubKeyBase64: payload['ephemeralPubKey'] as String,
        seq: payload['seq'] as int,
        signatureBase64: payload['signature'] as String,
      );

      final decrypted = await _cryptoService.decryptMessage(
        envelope: envelope,
        recipientIdentityKeyPair: _myIdentityKeyPair!,
        senderPublicIdentityKeyBase64: _peerPublicKeyBase64!,
        sessionEpoch: _wsClient.sessionEpoch ?? (payload['sessionEpoch'] as String? ?? ''),
      );

      final msg = EphemeralChatMessage(
        id: payload['msgId'] as String?,
        senderDeviceId: payload['senderDeviceId'] as String,
        text: decrypted,
        timestamp: payload['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        isMe: false,
        status: MessageDeliveryStatus.relayed,
      );

      state = [...state, msg];
    } catch (e) {
      debugPrint('[Chat] Inbound decryption/integrity failed: $e');
    }
  }

  void _handleAutoLock(String reason) {
    if (_myDeviceId != null) {
      _wsClient.terminateSession(reason, _myDeviceId!);
    }
    clearSession();
  }

  /// Strict memory purge: Wipes all ephemeral messages and key references from memory
  void clearSession() {
    state = [];
    _myIdentityKeyPair = null;
    _cryptoService.resetSequence();
    debugPrint('[ChatSession] Session wiped cleanly from memory.');
  }

  @override
  void dispose() {
    _autoLockService.removeLockListener(_handleAutoLock);
    _msgSub?.cancel();
    _termSub?.cancel();
    clearSession();
    super.dispose();
  }
}
