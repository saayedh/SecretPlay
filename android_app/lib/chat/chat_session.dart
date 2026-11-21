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

enum SendError { noPeerKey, tooLarge, encryption }

class ChatSessionNotifier extends StateNotifier<List<EphemeralChatMessage>> {
  /// Reason of the last failed [sendMessage] call (null when the last send succeeded).
  SendError? lastSendError;
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
  final Map<String, int> _lastSentAt = {};
  final List<Map<String, dynamic>> _pendingInbound = [];
  Future<void> _inboundChain = Future.value();
  Timer? _persistDebounce;

  /// Cloudflare WebSockets reject frames > 1 MiB; keep a safe margin.
  static const int maxWireFrameChars = 900000;

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

    // Process inbound frames strictly one-at-a-time, in arrival order. Previously each frame was
    // decrypted concurrently, which scrambled message order and raced the replay-sequence counter.
    _msgSub = _wsClient.onMessage.listen((payload) {
      _inboundChain = _inboundChain
          .then((_) => _handleIncomingMessage(payload))
          .catchError((Object e) => debugPrint('[Chat] inbound error: $e'));
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
        // Fresh connection: resend everything not yet confirmed by the server right away.
        _lastSentAt.clear();
        _retryUnackedEnvelopes();
      }
    });

    // 1s sweep: auto-destroy expired Burn-After-Reading messages & retry unconfirmed envelopes
    _burnSweepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (state.any((m) => m.expiresAtMs != null && m.expiresAtMs! <= now)) {
        final filtered = state.where((m) => m.expiresAtMs == null || m.expiresAtMs! > now).toList();
        state = filtered;
        _roomHistories[_currentRoomToken] = filtered;
      }
      _tickCount++;
      if (_tickCount % 3 == 0 && _unackedEnvelopes.isNotEmpty) {
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

    // Restore this room's persistent outbox (messages written while offline / before app was killed)
    _unackedEnvelopes.clear();
    _lastSentAt.clear();
    try {
      final rawOutbox = await _keystore.getRoomOutbox(nextRoom);
      if (rawOutbox != null && rawOutbox.isNotEmpty) {
        final list = jsonDecode(rawOutbox) as List<dynamic>;
        for (final e in list) {
          final env = Map<String, dynamic>.from(e as Map);
          final id = env['msgId'] as String?;
          if (id != null) _unackedEnvelopes[id] = env;
        }
      }
    } catch (_) {}
    // Any own message still "sending" without a stored envelope can never be delivered: mark it failed
    final fixed = [
      for (final m in loadedList)
        if (m.isMe &&
            m.status == MessageDeliveryStatus.sending &&
            !_unackedEnvelopes.containsKey(m.id))
          m.copyWith(status: MessageDeliveryStatus.failed)
        else
          m
    ];
    state = fixed;
    _retryUnackedEnvelopes();
  }

  void _persistOutbox() {
    final room = _currentRoomToken;
    final snapshot = _unackedEnvelopes.values.toList();
    _keystore.saveRoomOutbox(room, jsonEncode(snapshot)).catchError((_) {});
  }

  void _retryUnackedEnvelopes() {
    if (_unackedEnvelopes.isEmpty) return;
    if (_wsClient.status != ConnectionStatus.authenticated &&
        _wsClient.status != ConnectionStatus.peerOnline) {
      return;
    }
    // Resend each unconfirmed envelope at most every 6s, max 8 per pass, oldest first.
    // (Old code resent EVERY pending message every 5s forever -> on a slow link this flooded the
    // relay, tripped its rate-limit and the server killed the socket permanently.)
    final now = DateTime.now().millisecondsSinceEpoch;
    var sentThisPass = 0;
    for (final entry in _unackedEnvelopes.entries.toList()) {
      if (sentThisPass >= 8) break;
      final last = _lastSentAt[entry.key] ?? 0;
      if (now - last < 6000) continue;
      _lastSentAt[entry.key] = now;
      _wsClient.sendRaw(entry.value);
      sentThisPass++;
    }
  }

  void _setRoomState(List<EphemeralChatMessage> next) {
    state = next;
    _roomHistories[_currentRoomToken] = next;
    _schedulePersist();
  }

  /// Debounced history persistence. Writing the whole (possibly multi-MB) history into encrypted
  /// storage on EVERY status change (3x per message) was the main cause of UI lag after a few
  /// messages/images.
  void _schedulePersist() {
    final room = _currentRoomToken;
    final snapshot = state;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 700), () {
      _persistNow(room, snapshot);
    });
  }

  void _persistNow(String room, List<EphemeralChatMessage> snapshot) {
    try {
      final toSave = snapshot
          .where((m) => m.burnAfterSeconds == null && !m.isOneTimeVoice)
          .toList();
      final trimmed = toSave.length > 200 ? toSave.sublist(toSave.length - 200) : toSave;
      // Keep media only for the newest 25 media messages so storage stays small and fast
      var mediaKept = 0;
      final jsonList = <Map<String, dynamic>>[];
      for (final m in trimmed.reversed) {
        final j = m.toStorageJson();
        if (j['mediaBase64'] is String && (j['mediaBase64'] as String).isNotEmpty) {
          mediaKept++;
          if (mediaKept > 25) j.remove('mediaBase64');
        }
        jsonList.add(j);
      }
      _keystore.saveRoomChatHistory(room, jsonEncode(jsonList.reversed.toList())).catchError((_) {});
    } catch (_) {}
  }

  Future<void> clearCurrentRoomHistoryPermanently() async {
    _persistDebounce?.cancel();
    state = [];
    _roomHistories.remove(_currentRoomToken);
    _unackedEnvelopes.clear();
    _lastSentAt.clear();
    await _keystore.deleteRoomChatHistory(_currentRoomToken);
    await _keystore.deleteRoomOutbox(_currentRoomToken);
  }

  void removeMessageById(String msgId) {
    _setRoomState(state.where((m) => m.id != msgId).toList());
  }

  /// Re-sends a message that previously failed (e.g. key not yet known, or it was too large).
  Future<bool> resendFailedMessage(String msgId) async {
    final idx = state.indexWhere((m) => m.id == msgId && m.isMe);
    if (idx < 0) return false;
    final old = state[idx];
    if (_unackedEnvelopes.containsKey(msgId)) {
      _lastSentAt.remove(msgId);
      _retryUnackedEnvelopes();
      return true;
    }
    _setRoomState(state.where((m) => m.id != msgId).toList());
    return sendMessage(
      old.text,
      contentType: old.contentType,
      mediaBase64: old.mediaBase64,
      stickerId: old.stickerId,
      isFlashScreen: old.isFlashScreen,
      burnAfterSeconds: old.burnAfterSeconds,
      isOneTimeVoice: old.isOneTimeVoice,
      isCyberPitch: old.isCyberPitch,
      voiceDurationSec: old.voiceDurationSec,
    );
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
    // Messages that arrived before we knew the partner's key were buffered instead of dropped
    if (_pendingInbound.isNotEmpty) {
      final buffered = List<Map<String, dynamic>>.from(_pendingInbound);
      _pendingInbound.clear();
      for (final p in buffered) {
        _inboundChain = _inboundChain
            .then((_) => _handleIncomingMessage(p))
            .catchError((Object e) => debugPrint('[Chat] buffered inbound error: $e'));
      }
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
      lastSendError = SendError.noPeerKey;
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

      final frameSize = jsonEncode(wirePayload).length;
      if (frameSize > maxWireFrameChars) {
        debugPrint('[Chat] Message too large for relay ($frameSize chars) - not sent');
        _setRoomState([
          for (final m in state)
            if (m.id == outgoingMsg.id) m.copyWith(status: MessageDeliveryStatus.failed) else m
        ]);
        lastSendError = SendError.tooLarge;
        return false;
      }

      _unackedEnvelopes[outgoingMsg.id] = wirePayload;
      _lastSentAt[outgoingMsg.id] = DateTime.now().millisecondsSinceEpoch;
      _persistOutbox();
      _wsClient.sendRaw(wirePayload);
      // Stays "sending" (clock icon) until the relay confirms it has stored/forwarded it.
      lastSendError = null;
      return true;
    } catch (e) {
      debugPrint('[Chat] Encryption error: $e');
      lastSendError = SendError.encryption;
      _setRoomState([
        for (final m in state)
          if (m.id == outgoingMsg.id) m.copyWith(status: MessageDeliveryStatus.failed) else m
      ]);
      return false;
    }
  }

  void _sendReceipt(String msgId) {
    if (_myDeviceId == null) return;
    _wsClient.sendRaw({
      'type': 'msg_received',
      'version': 1,
      'msgId': msgId,
      'senderDeviceId': _myDeviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _updateStatus(String msgId, MessageDeliveryStatus status) {
    var changed = false;
    final next = [
      for (final m in state)
        if (m.id == msgId && m.status != status && m.status != MessageDeliveryStatus.relayed)
          (() {
            changed = true;
            return m.copyWith(status: status);
          })()
        else
          m
    ];
    if (changed) _setRoomState(next);
  }

  Future<void> _handleIncomingMessage(Map<String, dynamic> payload) async {
    final type = payload['type'] as String?;
    if (type == 'msg_ack') {
      final msgId = payload['msgId'] as String?;
      final ackStatus = payload['status'] as String?;
      if (msgId != null) {
        if (ackStatus == 'relayed' || ackStatus == 'queued_offline' || ackStatus == 'delivered') {
          // Server has the envelope safely (stored until the partner confirms receipt)
          if (_unackedEnvelopes.remove(msgId) != null) _persistOutbox();
          _lastSentAt.remove(msgId);
          _updateStatus(msgId, MessageDeliveryStatus.sent);
        }
        // 'dropped_*' acks keep the envelope queued so it is retried automatically.
      }
      return;
    }
    if (type == 'msg_delivered') {
      final msgId = payload['msgId'] as String?;
      if (msgId != null) {
        if (_unackedEnvelopes.remove(msgId) != null) _persistOutbox();
        _updateStatus(msgId, MessageDeliveryStatus.relayed);
      }
      return;
    }

    if (type != null && type != 'msg') return;
    final incomingMsgId = payload['msgId'] as String?;
    if (incomingMsgId != null && _seenMsgIds.contains(incomingMsgId)) {
      // Duplicate (re-delivery after reconnect): just confirm again so the relay can drop it
      _sendReceipt(incomingMsgId);
      return;
    }
    if (_myIdentityKeyPair == null || _peerPublicKeyBase64 == null) {
      // Partner key not loaded yet (common right after connect): buffer instead of dropping
      if (_pendingInbound.length < 300) _pendingInbound.add(payload);
      return;
    }

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
      _sendReceipt(msg.id);

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
    _persistDebounce?.cancel();
    state = [];
    _roomHistories.clear();
    _seenMsgIds.clear();
    _unackedEnvelopes.clear();
    _lastSentAt.clear();
    _pendingInbound.clear();
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
