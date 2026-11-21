import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/constants.dart';
import 'network_mode.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  authenticated,
  peerOnline,
}

class SecretPlayWebSocketClient {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _sessionTimeoutTimer;
  Timer? _reconnectTimer;
  Timer? _probeTimer;
  String? _lastUrl;
  bool _manualDisconnect = false;
  int _connGen = 0;
  int _reconnectAttempts = 0;
  String? _lastPeerDeviceId;
  String? _lastPeerPublicKey;
  Future<void> Function()? _reconnectCallback;
  final List<String> _pendingOutboundQueue = [];

  String? get currentUrl => _lastUrl;
  String? get lastPeerDeviceId => _lastPeerDeviceId;
  String? get lastPeerPublicKey => _lastPeerPublicKey;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;

  String? _sessionEpoch;
  String? get sessionEpoch => _sessionEpoch;

  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get onStatusChange => _statusController.stream;

  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  final StreamController<Map<String, dynamic>> _signalController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onSignal => _signalController.stream;

  final StreamController<String> _terminateController =
      StreamController<String>.broadcast();
  Stream<String> get onTerminate => _terminateController.stream;

  final StreamController<Map<String, String>> _peerIdentityController =
      StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get onPeerIdentity => _peerIdentityController.stream;

  final StreamController<Map<String, dynamic>> _appUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onAppUpdate => _appUpdateController.stream;

  void _setStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(_status);
    }
  }

  Future<void> connect({
    required NetworkConfig config,
    required String deviceId,
    String? pairToken,
    String? publicKey,
    FutureOr<String> Function()? signNonce,
    FutureOr<String> Function(String nonce, int timestamp)? signChallenge,
  }) async {
    final activeToken = (pairToken ?? config.pairToken).trim().toUpperCase();
    final effectiveConfig = activeToken.isNotEmpty
        ? config.copyWith(pairToken: activeToken)
        : config;
    final url = effectiveConfig.activeWsUrl;

    // Keep existing live connection if already connected/authenticated to the exact same room
    if (_channel != null &&
        _lastUrl == url &&
        (_status == ConnectionStatus.authenticated || _status == ConnectionStatus.peerOnline)) {
      _statusController.add(_status);
      if (_lastPeerDeviceId != null && _lastPeerPublicKey != null) {
        _peerIdentityController.add({
          'peerDeviceId': _lastPeerDeviceId!,
          'peerPublicKey': _lastPeerPublicKey!,
        });
      }
      return;
    }

    if (_lastUrl != url) {
      _lastPeerDeviceId = null;
      _lastPeerPublicKey = null;
      _pendingOutboundQueue.clear();
    }

    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _reconnectCallback = () => connect(
          config: config,
          deviceId: deviceId,
          pairToken: pairToken,
          publicKey: publicKey,
          signNonce: signNonce,
          signChallenge: signChallenge,
        );

    _closeSocketOnly();
    final gen = ++_connGen;
    _lastUrl = url;
    _setStatus(ConnectionStatus.connecting);

    try {
      final uri = Uri.parse(url);
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (data) {
          if (gen != _connGen) return;
          _handleIncomingRawMessage(data);
        },
        onError: (err) {
          if (gen != _connGen) return;
          debugPrint('[WS] Channel error: $err');
          _handleUnexpectedDrop();
        },
        onDone: () {
          if (gen != _connGen) return;
          debugPrint('[WS] Channel closed');
          _handleUnexpectedDrop();
        },
      );

      // Wait for the WebSocket handshake to complete (critical on Flutter Web / Chrome where WebSocket stays in CONNECTING state until open)
      await _channel!.ready;
      if (gen != _connGen) return;

      _setStatus(ConnectionStatus.connected);

      // Authenticate with server using unique nonce & Ed25519 signature
      final now = DateTime.now().millisecondsSinceEpoch;
      final nonce = const Uuid().v4();
      String signature = '';
      if (signChallenge != null) {
        signature = await signChallenge(nonce, now);
      } else if (signNonce != null) {
        signature = await signNonce();
      }
      if (gen != _connGen) return;

      final authPayload = <String, dynamic>{
        'type': 'auth',
        'version': 1,
        'deviceId': deviceId,
        'nonce': nonce,
        'signature': signature,
        'timestamp': now,
        if (activeToken.isNotEmpty) 'pairToken': activeToken,
        if (publicKey != null && publicKey.isNotEmpty) 'publicKey': publicKey,
      };
      sendRaw(authPayload);

      _startHeartbeat();
    } catch (e) {
      debugPrint('[WS] Connection failed (will retry): $e');
      if (gen == _connGen) {
        _handleUnexpectedDrop();
      }
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(milliseconds: AppConstants.heartbeatIntervalMs),
      (_) {
        if (_status == ConnectionStatus.authenticated ||
            _status == ConnectionStatus.peerOnline) {
          sendRaw({
            'type': 'ping',
            'version': 1,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
      },
    );
  }

  void _checkAndEmitPeerIdentity(Map<String, dynamic> map) {
    final pId = map['peerDeviceId'] as String?;
    final pKey = map['peerPublicKey'] as String?;
    if (pId != null && pId.isNotEmpty && pKey != null && pKey.isNotEmpty) {
      _lastPeerDeviceId = pId;
      _lastPeerPublicKey = pKey;
      _peerIdentityController.add({
        'peerDeviceId': pId,
        'peerPublicKey': pKey,
      });
    }
  }

  String? _normalizeEpoch(dynamic raw) {
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return null;
  }

  void _handleIncomingRawMessage(dynamic data) {
    _resetSessionTimeout();
    try {
      final map = jsonDecode(data.toString()) as Map<String, dynamic>;
      final type = map['type'] as String?;

      switch (type) {
        case 'auth_result':
          final success = map['success'] == true;
          if (success) {
            _reconnectAttempts = 0;
            _sessionEpoch = _normalizeEpoch(map['sessionEpoch']);
            _checkAndEmitPeerIdentity(map);
            final peerConnected = map['peerConnected'] == true;
            _setStatus(peerConnected ? ConnectionStatus.peerOnline : ConnectionStatus.authenticated);
            _flushPendingOutbound();
            if (map['latestUpdate'] is Map<String, dynamic>) {
              _appUpdateController.add(map['latestUpdate'] as Map<String, dynamic>);
            }
          } else {
            disconnect();
          }
          break;

        case 'session_status':
          final peerOnline = map['peerOnline'] == true;
          _sessionEpoch = _normalizeEpoch(map['sessionEpoch']);
          _checkAndEmitPeerIdentity(map);
          _setStatus(peerOnline ? ConnectionStatus.peerOnline : ConnectionStatus.authenticated);
          break;

        case 'app_update':
          _appUpdateController.add(map);
          break;

        case 'pairing_confirm':
          if (map['sessionEpoch'] is String) {
            _sessionEpoch = map['sessionEpoch'] as String?;
            _setStatus(ConnectionStatus.peerOnline);
          }
          _checkAndEmitPeerIdentity(map);
          _messageController.add(map);
          break;

        case 'msg':
        case 'msg_ack':
        case 'msg_delivered':
          _messageController.add(map);
          break;

        case 'signal':
          _signalController.add(map);
          break;

        case 'revoke_confirm':
          _terminateController.add('revoked');
          disconnect();
          break;

        case 'terminate':
          // A server-side terminate (rate limit, stale epoch, peer lock) must NEVER permanently kill
          // the chat. Only an explicit revocation stops reconnecting; everything else reconnects.
          final reason = map['reason'] as String? ?? 'peer_lock';
          _terminateController.add(reason);
          if (reason == 'revoked') {
            disconnect();
          } else {
            _handleUnexpectedDrop();
          }
          break;

        case 'pong':
          _probeTimer?.cancel();
          _probeTimer = null;
          break;
      }
    } catch (e) {
      debugPrint('[WS] Error parsing message: $e');
    }
  }

  void _resetSessionTimeout() {
    _sessionTimeoutTimer?.cancel();
    _sessionTimeoutTimer = Timer(
      const Duration(milliseconds: AppConstants.sessionTimeoutMs),
      () {
        debugPrint('[WS] Server heartbeat timed out! Reconnecting...');
        _handleUnexpectedDrop();
      },
    );
  }

  void _flushPendingOutbound() {
    if (_channel == null || _pendingOutboundQueue.isEmpty) return;
    final toSend = List<String>.from(_pendingOutboundQueue);
    _pendingOutboundQueue.clear();
    for (final raw in toSend) {
      try {
        _channel!.sink.add(raw);
      } catch (_) {
        _pendingOutboundQueue.add(raw);
      }
    }
  }

  /// Sends a ping and forces a reconnect if the server doesn't answer within 6s.
  /// Called when the app returns to foreground, because mobile OSes silently kill sockets in background.
  void probeConnection() {
    if (_manualDisconnect || _reconnectCallback == null) return;
    if (_channel == null || _status == ConnectionStatus.disconnected) {
      _reconnectTimer?.cancel();
      _reconnectAttempts = 0;
      _reconnectCallback?.call();
      return;
    }
    if (_status != ConnectionStatus.authenticated && _status != ConnectionStatus.peerOnline) return;
    _probeTimer?.cancel();
    _probeTimer = Timer(const Duration(seconds: 6), () {
      _probeTimer = null;
      debugPrint('[WS] Probe got no pong -> socket is dead, reconnecting');
      _reconnectAttempts = 0;
      _handleUnexpectedDrop();
    });
    try {
      _channel!.sink.add(jsonEncode({
        'type': 'ping',
        'version': 1,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (_) {
      _handleUnexpectedDrop();
    }
  }

  void sendRaw(Map<String, dynamic> payload) {
    final encoded = jsonEncode(payload);
    final type = payload['type'];
    final isAuthOrPing = type == 'auth' || type == 'ping';
    if (_channel != null &&
        (isAuthOrPing ||
            _status == ConnectionStatus.authenticated ||
            _status == ConnectionStatus.peerOnline)) {
      try {
        _channel!.sink.add(encoded);
        return;
      } catch (_) {}
    }
    // Never queue ephemeral signals (typing / call SDP): stale ones are useless and used to fill the
    // queue so real chat messages got silently dropped. Chat messages are additionally kept by
    // ChatSessionNotifier until the server acknowledges them, so nothing is lost here.
    if (type == 'msg' || type == 'msg_received') {
      if (_pendingOutboundQueue.length >= 300) _pendingOutboundQueue.removeAt(0);
      _pendingOutboundQueue.add(encoded);
    }
    if (!isAuthOrPing && _status == ConnectionStatus.disconnected && !_manualDisconnect) {
      _reconnectTimer?.cancel();
      _reconnectCallback?.call();
    }
  }

  void terminateSession(String reason, String deviceId) {
    sendRaw({
      'type': 'terminate',
      'version': 1,
      'reason': reason,
      'senderDeviceId': deviceId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    disconnect();
  }

  void _handleUnexpectedDrop() {
    _closeSocketOnly();
    _setStatus(ConnectionStatus.disconnected);
    if (!_manualDisconnect && _reconnectCallback != null) {
      _reconnectTimer?.cancel();
      final delaySec = _reconnectAttempts == 0
          ? 1
          : (_reconnectAttempts == 1 ? 2 : (_reconnectAttempts == 2 ? 4 : 6));
      _reconnectAttempts++;
      _reconnectTimer = Timer(Duration(seconds: delaySec), () {
        if (!_manualDisconnect && _status == ConnectionStatus.disconnected) {
          _reconnectCallback?.call();
        }
      });
    }
  }

  void _closeSocketOnly() {
    _connGen++;
    _probeTimer?.cancel();
    _probeTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _sessionTimeoutTimer?.cancel();
    _sessionTimeoutTimer = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pendingOutboundQueue.clear();
    _closeSocketOnly();
    _lastUrl = null;
    _lastPeerDeviceId = null;
    _lastPeerPublicKey = null;
    _sessionEpoch = null;
    _setStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _messageController.close();
    _signalController.close();
    _terminateController.close();
    _peerIdentityController.close();
    _appUpdateController.close();
  }
}
