import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../cryptography/crypto_service.dart';
import '../networking/websocket_client.dart';
import '../security/auto_lock_service.dart';
import '../security/keystore_service.dart';
import 'chat_message.dart';

class ChatSessionNotifier extends StateNotifier<List<EphemeralChatMessage>> {
  final CryptoService _cryptoService;
  final SecretPlayWebSocketClient _wsClient;
  final AutoLockService _autoLockService;
  final KeystoreService _keystore = KeystoreService();

  String? _myDeviceId;
  String? _peerDeviceId;
  String? _peerPublicKeyBase64;
  SimpleKeyPair? _myIdentityKeyPair;
  String _currentRoomToken = 'default';
  final Map<String, List<EphemeralChatMessage>> _roomHistories = {};
  final Set<String> _seenMsgIds = {};
  final Map<String, Map<String, dynamic>> _unackedEnvelopes = {};

  StreamSubscription? _msgSub;
  StreamSubscription? _termSub;
  StreamSubscription? _statusSub;
  Timer? _burnSweepTimer;
  int _tickCount = 0;

  final StreamController<EphemeralChatMessage> _flashStreamController =
      StreamController<EphemeralChatMessage>.broadcast();

  /// Fires whenever an incoming Flash Hologram / Lock-Screen message arrives
  Stream<EphemeralChatMessage> get onFlashMessage => _flashStreamController.stream;

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
      // Only wipe chat memory on explicit revocation or manual exit, never on transient network errors
      if (reason == 'revoked' || reason == 'manual_exit') {
        clearSession();
      }
    });

    _statusSub = _wsClient.onStatusChange.listen((status) {
      if (status == ConnectionStatus.authenticated || status == ConnectionStatus.peerOnline) {
        if (status == ConnectionStatus.peerOnline) {
          _cryptoService.resetMessageInboundSequence();
        }
        _retryUnackedEnvelopes();
      }
    });

    // Periodic 1-second sweep to auto-destroy expired Burn-After-Reading messages & retry unacked envelopes every 5s
    _burnSweepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (state.any((m) => m.expiresAtMs != null && m.expiresAtMs! <= now)) {
        final filtered = state.where((m) => m.expiresAtMs == null || m.expiresAtMs! > now).toList();
        state = filtered;
        _roomHistories[_currentRoomToken] = filtered;
      }
      _tickCount++;
      if (_tickCount % 5 == 0 && _unackedEnvelopes.isNotEmpty) {
        _retryUnackedEnvelopes();
      }
    });
  }

  Future<void> switchRoom(String roomToken) async {
    final clean = roomToken.trim().toUpperCase();
    final nextRoom = clean.isEmpty ? 'default' : clean;
    if (_currentRoomToken == nextRoom && state.isNotEmpty) return;

    _roomHistories[_currentRoomToken] = state;
    _currentRoomToken = nextRoom;

    var loaded = _roomHistories[nextRoom];
    if (loaded == null || loaded.isEmpty) {
      try {
        final raw = await _keystore.getRoomChatHistory(nextRoom);
        if (raw != null && raw.isNotEmpty) {
          final list = jsonDecode(raw) as List<dynamic>;
          loaded = list
              .map((e) => EphemeralChatMessage.fromStorageJson(e as Map<String, dynamic>))
              .toList();
          _roomHistories[nextRoom] = loaded;
        }
      } catch (_) {}
    }

    final loadedList = List<EphemeralChatMessage>.from(loaded ?? const []);
    for (final m in loadedList) {
      _seenMsgIds.add(m.id);
    }
    state = loadedList;
  }

  void _retryUnackedEnvelopes() {
    if (_unackedEnvelopes.isEmpty) return;
    if (_wsClient.status != ConnectionStatus.authenticated &&
        _wsClient.status != ConnectionStatus.peerOnline) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in _unackedEnvelopes.entries.toList()) {
      final ts = entry.value['timestamp'] as int? ?? 0;
      if (now - ts >= 4000) {
        _wsClient.sendRaw(entry.value);
      }
    }
  }

  void _setRoomState(List<EphemeralChatMessage> next) {
    state = next;
    _roomHistories[_currentRoomToken] = next;
    // Persist messages locally unless explicitly deleted by the user (keep up to last 200 per room)
    try {
      final toSave = next
          .where((m) => m.burnAfterSeconds == null && !m.isOneTimeVoice)
          .toList();
      final trimmed = toSave.length > 200 ? toSave.sublist(toSave.length - 200) : toSave;
      var encoded = jsonEncode(trimmed.map((m) => m.toStorageJson()).toList());
      // Guard against Web localStorage 5MB quota exhaustion if many large media blobs are sent
      if (encoded.length > 1500000) {
        final compact = trimmed.map((m) {
          final j = m.toStorageJson();
          if (j['mediaBase64'] is String && (j['mediaBase64'] as String).length > 50000) {
            j.remove('mediaBase64');
          }
          return j;
        }).toList();
        encoded = jsonEncode(compact);
      }
      _keystore.saveRoomChatHistory(_currentRoomToken, encoded);
    } catch (_) {}
  }

  Future<void> clearCurrentRoomHistoryPermanently() async {
    state = [];
    _roomHistories.remove(_currentRoomToken);
    await _keystore.deleteRoomChatHistory(_currentRoomToken);
  }

  void removeMessageById(String msgId) {
    _setRoomState(state.where((m) => m.id != msgId).toList());
  }

  void initializeSession({
    required String myDeviceId,
    required String peerDeviceId,
    required String peerPublicKeyBase64,
    required SimpleKeyPair myIdentityKeyPair,
  }) {
    final peerChanged = _peerDeviceId != peerDeviceId || _peerPublicKeyBase64 != peerPublicKeyBase64;
    _myDeviceId = myDeviceId;
    _peerDeviceId = peerDeviceId;
    _peerPublicKeyBase64 = peerPublicKeyBase64;
    _myIdentityKeyPair = myIdentityKeyPair;
    if (peerChanged) {
      _cryptoService.resetSequence();
    } else {
      // Reset inbound replay watermarks on reconnect so a restarted peer can send from seq=1
      _cryptoService.resetInboundSequence();
    }
  }

  Future<bool> sendMessage(
    String text, {
    ChatContentType contentType = ChatContentType.text,
    String? mediaBase64,
    String? stickerId,
    bool isFlashScreen = false,
    int? burnAfterSeconds,
    bool isOneTimeVoice = false,
    bool isCyberPitch = false,
    int? voiceDurationSec,
  }) async {
    if (contentType == ChatContentType.text && text.trim().isEmpty) return false;
    if (_peerPublicKeyBase64 == null || _myIdentityKeyPair == null) {
      debugPrint('[Chat] Cannot send message: peer public key not yet exchanged.');
      return false;
    }
    final rawEpoch = _wsClient.sessionEpoch;
    final activeEpoch = (rawEpoch != null && rawEpoch.isNotEmpty)
        ? rawEpoch
        : 'offline-$_currentRoomToken';
    final now = DateTime.now().millisecondsSinceEpoch;

    final outgoingMsg = EphemeralChatMessage(
      senderDeviceId: _myDeviceId ?? 'me',
      text: text,
      contentType: contentType,
      mediaBase64: mediaBase64,
      stickerId: stickerId,
      isFlashScreen: isFlashScreen,
      burnAfterSeconds: burnAfterSeconds,
      expiresAtMs: (burnAfterSeconds != null && burnAfterSeconds > 0)
          ? now + (burnAfterSeconds * 1000)
          : null,
      isOneTimeVoice: isOneTimeVoice,
      isCyberPitch: isCyberPitch,
      voiceDurationSec: voiceDurationSec,
      timestamp: now,
      isMe: true,
      status: MessageDeliveryStatus.sending,
    );

    // Append to memory state
    _setRoomState([...state, outgoingMsg]);

    try {
      final serializedPayload = outgoingMsg.toEncryptedPayloadString();
      final envelope = await _cryptoService.encryptMessage(
        plaintext: serializedPayload,
        recipientPublicIdentityKeyBase64: _peerPublicKeyBase64!,
        senderIdentityKeyPair: _myIdentityKeyPair!,
        sessionEpoch: activeEpoch,
      );

      final wirePayload = <String, dynamic>{
        'type': 'msg',
        'version': 1,
        'msgId': outgoingMsg.id,
        'senderDeviceId': _myDeviceId,
        'recipientDeviceId': _peerDeviceId,
        'sessionEpoch': activeEpoch,
        'ciphertext': envelope.ciphertextBase64,
        'iv': envelope.ivBase64,
        'authTag': envelope.authTagBase64,
        'ephemeralPubKey': envelope.ephemeralPubKeyBase64,
        'seq': envelope.seq,
        'signature': envelope.signatureBase64,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _unackedEnvelopes[outgoingMsg.id] = wirePayload;
      _wsClient.sendRaw(wirePayload);

      _setRoomState([
        for (final m in state)
          if (m.id == outgoingMsg.id) m.copyWith(status: MessageDeliveryStatus.sent) else m
      ]);
      return true;
    } catch (e) {
      debugPrint('[Chat] Encryption error: $e');
      _setRoomState([
        for (final m in state)
          if (m.id == outgoingMsg.id) m.copyWith(status: MessageDeliveryStatus.failed) else m
      ]);
      return false;
    }
  }

  Future<void> _handleIncomingMessage(Map<String, dynamic> payload) async {
    final type = payload['type'] as String?;
    if (type == 'msg_ack') {
      final msgId = payload['msgId'] as String?;
      final ackStatus = payload['status'] as String?;
      if (msgId != null) {
        _unackedEnvelopes.remove(msgId);
        _setRoomState([
          for (final m in state)
            if (m.id == msgId)
              m.copyWith(
                status: (ackStatus == 'relayed' || ackStatus == 'delivered')
                    ? MessageDeliveryStatus.relayed
                    : (ackStatus == 'queued_offline'
                        ? MessageDeliveryStatus.sent
                        : MessageDeliveryStatus.failed),
              )
            else
              m
        ]);
      }
      return;
    }

    if (type != null && type != 'msg') return;
    final incomingMsgId = payload['msgId'] as String?;
    if (incomingMsgId != null && _seenMsgIds.contains(incomingMsgId)) {
      return;
    }
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

      final candidateEpochs = <String>{
        if (payload['sessionEpoch'] is String && (payload['sessionEpoch'] as String).isNotEmpty)
          payload['sessionEpoch'] as String,
        if (_wsClient.sessionEpoch != null && _wsClient.sessionEpoch!.isNotEmpty)
          _wsClient.sessionEpoch!,
        'offline-$_currentRoomToken',
        'offline-room',
        '',
      }.toList();

      String? decrypted;
      Object? lastErr;
      for (final epoch in candidateEpochs) {
        try {
          decrypted = await _cryptoService.decryptMessage(
            envelope: envelope,
            recipientIdentityKeyPair: _myIdentityKeyPair!,
            senderPublicIdentityKeyBase64: _peerPublicKeyBase64!,
            sessionEpoch: epoch,
          );
          break;
        } catch (e) {
          lastErr = e;
          if (e.toString().contains('Replay attack detected') &&
              incomingMsgId != null &&
              !_seenMsgIds.contains(incomingMsgId)) {
            _cryptoService.resetMessageInboundSequence();
            try {
              decrypted = await _cryptoService.decryptMessage(
                envelope: envelope,
                recipientIdentityKeyPair: _myIdentityKeyPair!,
                senderPublicIdentityKeyBase64: _peerPublicKeyBase64!,
                sessionEpoch: epoch,
              );
              break;
            } catch (e2) {
              lastErr = e2;
            }
          }
        }
      }
      if (decrypted == null) {
        throw lastErr ?? Exception('Decryption failed across all candidate epochs');
      }

      final msg = EphemeralChatMessage.fromDecryptedPayload(
        id: incomingMsgId,
        senderDeviceId: payload['senderDeviceId'] as String,
        decryptedText: decrypted,
        timestamp: payload['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        isMe: false,
        status: MessageDeliveryStatus.relayed,
      );
      _seenMsgIds.add(msg.id);

      _setRoomState([...state, msg]);

      if (msg.isFlashScreen) {
        _flashStreamController.add(msg);
        await _autoLockService.wakeScreenForFlashMessage(
          title: '⚡ SecretPlay Live Flash',
          subtitle: msg.text.isNotEmpty ? msg.text : 'پیام هولوگرافیک روی صفحه دریافت شد!',
        );
      }
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
    _roomHistories.clear();
    _seenMsgIds.clear();
    _unackedEnvelopes.clear();
    _myIdentityKeyPair = null;
    _cryptoService.resetSequence();
    debugPrint('[ChatSession] Session wiped cleanly from memory.');
  }

  @override
  void dispose() {
    _autoLockService.removeLockListener(_handleAutoLock);
    _msgSub?.cancel();
    _termSub?.cancel();
    _statusSub?.cancel();
    _burnSweepTimer?.cancel();
    _flashStreamController.close();
    clearSession();
    super.dispose();
  }
}
