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
  String? _lastUrl;
  bool _manualDisconnect = false;
  Future<void> Function()? _reconnectCallback;

  String? get currentUrl => _lastUrl;

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
      return;
    }

    _manualDisconnect = false;
    _reconnectCallback = () => connect(
          config: config,
          deviceId: deviceId,
          pairToken: pairToken,
          publicKey: publicKey,
          signNonce: signNonce,
          signChallenge: signChallenge,
        );

    _closeSocketOnly();
    _lastUrl = url;
    _setStatus(ConnectionStatus.connecting);

    try {
      final uri = Uri.parse(url);
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (data) {
          _handleIncomingRawMessage(data);
        },
        onError: (err) {
          debugPrint('[WS] Channel error: $err');
          _handleUnexpectedDrop();
        },
        onDone: () {
          debugPrint('[WS] Channel closed');
          _handleUnexpectedDrop();
        },
      );

      // Wait for the WebSocket handshake to complete (critical on Flutter Web / Chrome where WebSocket stays in CONNECTING state until open)
      await _channel!.ready;

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
      debugPrint('[WS] Connection failed: $e');
      disconnect();
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
      _peerIdentityController.add({
        'peerDeviceId': pId,
        'peerPublicKey': pKey,
      });
    }
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
            _sessionEpoch = map['sessionEpoch'] as String?;
            _checkAndEmitPeerIdentity(map);
            final peerConnected = map['peerConnected'] == true;
            _setStatus(peerConnected ? ConnectionStatus.peerOnline : ConnectionStatus.authenticated);
          } else {
            disconnect();
          }
          break;

        case 'session_status':
          final peerOnline = map['peerOnline'] == true;
          _sessionEpoch = map['sessionEpoch'] as String?;
          _checkAndEmitPeerIdentity(map);
          _setStatus(peerOnline ? ConnectionStatus.peerOnline : ConnectionStatus.authenticated);
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
          final reason = map['reason'] as String? ?? 'peer_lock';
          _terminateController.add(reason);
          disconnect();
          break;

        case 'pong':
          // Heartbeat acknowledged
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
        debugPrint('[WS] Server heartbeat timed out!');
        _terminateController.add('heartbeat_timeout');
        disconnect();
      },
    );
  }

  void sendRaw(Map<String, dynamic> payload) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(payload));
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
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        if (!_manualDisconnect && _status == ConnectionStatus.disconnected) {
          _reconnectCallback?.call();
        }
      });
    }
  }

  void _closeSocketOnly() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _sessionTimeoutTimer?.cancel();
    _sessionTimeoutTimer = null;
    _channel?.sink.close();
    _channel = null;
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeSocketOnly();
    _lastUrl = null;
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
  }
}
