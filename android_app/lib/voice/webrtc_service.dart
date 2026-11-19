import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../cryptography/crypto_service.dart';
import '../networking/network_mode.dart';
import '../networking/websocket_client.dart';
import '../security/auto_lock_service.dart';

enum CallState {
  idle,
  outgoingRinging,
  incomingRinging,
  connecting,
  reconnecting,
  connected,
  ended,
}

enum AudioRoute {
  earpiece,
  speaker,
  bluetooth,
}

class WebRtcVoiceService {
  static const MethodChannel _securityChannel = MethodChannel('com.secretplay.app/security');

  final SecretPlayWebSocketClient _wsClient;
  final CryptoService _cryptoService;
  final AutoLockService _autoLockService;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  String _myDeviceId = 'me';
  String _peerDeviceId = 'peer';
  NetworkMode _networkMode = NetworkMode.local;
  SimpleKeyPair? _myIdentityKeyPair;
  String? _peerPublicKeyBase64;

  CallState _callState = CallState.idle;
  CallState get callState => _callState;

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  bool _isSpeakerOn = false;
  bool get isSpeakerOn => _isSpeakerOn;

  AudioRoute _audioRoute = AudioRoute.earpiece;
  AudioRoute get audioRoute => _audioRoute;

  int _callDurationSeconds = 0;
  int get callDurationSeconds => _callDurationSeconds;
  Timer? _durationTimer;
  Timer? _reconnectTimer;

  final StreamController<CallState> _callStateController =
      StreamController<CallState>.broadcast();
  Stream<CallState> get onCallStateChange => _callStateController.stream;

  final StreamController<int> _callDurationController =
      StreamController<int>.broadcast();
  Stream<int> get onCallDuration => _callDurationController.stream;

  StreamSubscription? _signalSub;

  WebRtcVoiceService({
    required SecretPlayWebSocketClient wsClient,
    CryptoService? cryptoService,
    AutoLockService? autoLockService,
  })  : _wsClient = wsClient,
        _cryptoService = cryptoService ?? CryptoService(),
        _autoLockService = autoLockService ?? AutoLockService() {
    _initSignalingListener();
    _autoLockService.addLockListener(_onAutoLock);
  }

  void configureIdentity({
    required String myDeviceId,
    required String peerDeviceId,
    required NetworkMode networkMode,
    SimpleKeyPair? myIdentityKeyPair,
    String? peerPublicKeyBase64,
  }) {
    _myDeviceId = myDeviceId;
    _peerDeviceId = peerDeviceId;
    _networkMode = networkMode;
    _myIdentityKeyPair = myIdentityKeyPair;
    _peerPublicKeyBase64 = peerPublicKeyBase64;
  }

  void _onAutoLock(String reason) {
    endCall(notifyPeer: true);
  }

  void _setCallState(CallState newState) {
    if (_callState != newState) {
      _callState = newState;
      if (!_callStateController.isClosed) {
        _callStateController.add(_callState);
      }

      if (_callState == CallState.connected) {
        _reconnectTimer?.cancel();
        _startTimer();
      } else if (_callState == CallState.idle || _callState == CallState.ended) {
        _reconnectTimer?.cancel();
        _stopTimer();
      }
    }
  }

  void _startTimer() {
    _durationTimer?.cancel();
    _callDurationSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _callDurationSeconds++;
      if (!_callDurationController.isClosed) {
        _callDurationController.add(_callDurationSeconds);
      }
    });
  }

  void _stopTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _callDurationSeconds = 0;
    if (!_callDurationController.isClosed) {
      _callDurationController.add(0);
    }
  }

  Future<void> _startForegroundCallService() async {
    try {
      await _securityChannel.invokeMethod('startVoiceCallService');
    } catch (_) {
      // Ignore on non-Android test environments
    }
  }

  Future<void> _stopForegroundCallService() async {
    try {
      await _securityChannel.invokeMethod('stopVoiceCallService');
    } catch (_) {
      // Ignore on non-Android test environments
    }
  }

  Future<Map<String, dynamic>> _packSignalPayload(String plainJson, int fallbackSeq) async {
    final epoch = _wsClient.sessionEpoch ?? '';
    if (_myIdentityKeyPair != null && _peerPublicKeyBase64 != null && epoch.isNotEmpty) {
      final env = await _cryptoService.encryptSignalingPayload(
        plaintext: plainJson,
        recipientPublicIdentityKeyBase64: _peerPublicKeyBase64!,
        senderIdentityKeyPair: _myIdentityKeyPair!,
        sessionEpoch: epoch,
      );
      return {
        'encryptedPayload': env.ciphertextBase64,
        'iv': env.ivBase64,
        'authTag': env.authTagBase64,
        'ephemeralPubKey': env.ephemeralPubKeyBase64,
        'seq': env.seq,
        'signature': env.signatureBase64,
      };
    }
    return {
      'encryptedPayload': base64Encode(utf8.encode(plainJson)),
      'iv': '',
      'authTag': '',
      'seq': fallbackSeq,
    };
  }

  Future<String> _unpackSignalPayload(Map<String, dynamic> payload) async {
    final enc = payload['encryptedPayload'] as String? ?? '';
    final iv = payload['iv'] as String? ?? '';
    final authTag = payload['authTag'] as String? ?? '';
    final eph = payload['ephemeralPubKey'] as String? ?? '';
    final sig = payload['signature'] as String? ?? '';
    final epoch = _wsClient.sessionEpoch ?? (payload['sessionEpoch'] as String? ?? '');

    if (iv.isNotEmpty &&
        authTag.isNotEmpty &&
        eph.isNotEmpty &&
        sig.isNotEmpty &&
        _myIdentityKeyPair != null &&
        _peerPublicKeyBase64 != null) {
      final env = EncryptedEnvelope(
        ciphertextBase64: enc,
        ivBase64: iv,
        authTagBase64: authTag,
        ephemeralPubKeyBase64: eph,
        seq: (payload['seq'] as int?) ?? 1,
        signatureBase64: sig,
      );
      return await _cryptoService.decryptSignalingPayload(
        envelope: env,
        recipientIdentityKeyPair: _myIdentityKeyPair!,
        senderPublicIdentityKeyBase64: _peerPublicKeyBase64!,
        sessionEpoch: epoch,
      );
    }

    return utf8.decode(base64Decode(enc));
  }

  void _initSignalingListener() {
    _signalSub = _wsClient.onSignal.listen((payload) async {
      final signalType = payload['signalType'] as String?;
      final senderId = payload['senderDeviceId'] as String?;
      if (senderId != null && senderId.isNotEmpty) {
        _peerDeviceId = senderId;
      }

      switch (signalType) {
        case 'call_request':
          if (_callState == CallState.idle) {
            _setCallState(CallState.incomingRinging);
          }
          break;

        case 'call_accept':
          if (_callState == CallState.outgoingRinging) {
            _setCallState(CallState.connecting);
            await _createAndSendOffer(_peerDeviceId);
          }
          break;

        case 'call_reject':
        case 'call_end':
          await endCall(notifyPeer: false);
          break;

        case 'offer':
          await _handleReceivedOffer(payload, _peerDeviceId);
          break;

        case 'answer':
          await _handleReceivedAnswer(payload);
          break;

        case 'ice_candidate':
          await _handleReceivedCandidate(payload);
          break;
      }
    });
  }

  Map<String, dynamic> _getIceServers(NetworkMode mode) {
    if (mode == NetworkMode.local) {
      // Offline mode: No external STUN/TURN queries! Direct LAN host candidates only.
      return {
        'iceServers': <Map<String, dynamic>>[],
        'sdpSemantics': 'unified-plan',
      };
    } else {
      // Cloudflare STUN / Google STUN (DTLS-SRTP P2P media)
      return {
        'iceServers': [
          {'urls': 'stun:stun.cloudflare.com:3478'},
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      };
    }
  }

  Future<void> startCall({
    required String peerDeviceId,
    required String myDeviceId,
    required NetworkMode networkMode,
  }) async {
    _myDeviceId = myDeviceId;
    _peerDeviceId = peerDeviceId;
    _networkMode = networkMode;
    _setCallState(CallState.outgoingRinging);
    await _startForegroundCallService();

    _wsClient.sendRaw({
      'type': 'signal',
      'version': 1,
      'signalType': 'call_request',
      'senderDeviceId': _myDeviceId,
      'recipientDeviceId': _peerDeviceId,
      'sessionEpoch': _wsClient.sessionEpoch,
      'encryptedPayload': '',
      'iv': '',
      'authTag': '',
      'seq': 1,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> acceptCall({
    required String peerDeviceId,
    required String myDeviceId,
    required NetworkMode networkMode,
  }) async {
    _myDeviceId = myDeviceId;
    _peerDeviceId = peerDeviceId;
    _networkMode = networkMode;
    _setCallState(CallState.connecting);
    await _startForegroundCallService();

    _wsClient.sendRaw({
      'type': 'signal',
      'version': 1,
      'signalType': 'call_accept',
      'senderDeviceId': _myDeviceId,
      'recipientDeviceId': _peerDeviceId,
      'sessionEpoch': _wsClient.sessionEpoch,
      'encryptedPayload': '',
      'iv': '',
      'authTag': '',
      'seq': 1,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> rejectCall({
    required String peerDeviceId,
    required String myDeviceId,
  }) async {
    _myDeviceId = myDeviceId;
    _peerDeviceId = peerDeviceId;
    _wsClient.sendRaw({
      'type': 'signal',
      'version': 1,
      'signalType': 'call_reject',
      'senderDeviceId': _myDeviceId,
      'recipientDeviceId': _peerDeviceId,
      'sessionEpoch': _wsClient.sessionEpoch,
      'encryptedPayload': '',
      'iv': '',
      'authTag': '',
      'seq': 1,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await _stopForegroundCallService();
    _setCallState(CallState.idle);
  }

  Future<void> _createAndSendOffer(String peerDeviceId) async {
    await _initPeerConnection(_networkMode, peerDeviceId);

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await _peerConnection!.setLocalDescription(offer);

    final sdpJson = jsonEncode({'sdp': offer.sdp, 'type': offer.type});
    final packed = await _packSignalPayload(sdpJson, 2);

    _wsClient.sendRaw({
      'type': 'signal',
      'version': 1,
      'signalType': 'offer',
      'senderDeviceId': _myDeviceId,
      'recipientDeviceId': peerDeviceId,
      'sessionEpoch': _wsClient.sessionEpoch,
      ...packed,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _handleReceivedOffer(Map<String, dynamic> payload, String peerDeviceId) async {
    try {
      await _initPeerConnection(_networkMode, peerDeviceId);

      final rawSdpJson = await _unpackSignalPayload(payload);
      final map = jsonDecode(rawSdpJson) as Map<String, dynamic>;
      final description = RTCSessionDescription(map['sdp'] as String?, map['type'] as String?);
      await _peerConnection!.setRemoteDescription(description);

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _peerConnection!.setLocalDescription(answer);

      final answerJson = jsonEncode({'sdp': answer.sdp, 'type': answer.type});
      final packed = await _packSignalPayload(answerJson, 3);

      _wsClient.sendRaw({
        'type': 'signal',
        'version': 1,
        'signalType': 'answer',
        'senderDeviceId': _myDeviceId,
        'recipientDeviceId': peerDeviceId,
        'sessionEpoch': _wsClient.sessionEpoch,
        ...packed,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      _setCallState(CallState.connected);
    } catch (e) {
      debugPrint('[WebRTC] Error handling offer: $e');
      await endCall(notifyPeer: false);
    }
  }

  Future<void> _handleReceivedAnswer(Map<String, dynamic> payload) async {
    try {
      final rawSdpJson = await _unpackSignalPayload(payload);
      final map = jsonDecode(rawSdpJson) as Map<String, dynamic>;
      final description = RTCSessionDescription(map['sdp'] as String?, map['type'] as String?);
      await _peerConnection?.setRemoteDescription(description);
      _setCallState(CallState.connected);
    } catch (e) {
      debugPrint('[WebRTC] Error handling answer: $e');
      await endCall(notifyPeer: false);
    }
  }

  Future<void> _handleReceivedCandidate(Map<String, dynamic> payload) async {
    try {
      final rawJson = await _unpackSignalPayload(payload);
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      final candidate = RTCIceCandidate(
        map['candidate'] as String?,
        map['sdpMid'] as String?,
        map['sdpMLineIndex'] as int?,
      );
      await _peerConnection?.addCandidate(candidate);
    } catch (e) {
      debugPrint('[WebRTC] Error adding ICE candidate: $e');
    }
  }

  Future<void> _initPeerConnection(NetworkMode mode, String peerDeviceId) async {
    final config = _getIceServers(mode);
    _peerConnection = await createPeerConnection(config);

    // Audio media stream only - zero video, zero call recording
    final mediaConstraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    for (final track in _localStream!.getAudioTracks()) {
      _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (candidate) async {
      if (candidate.candidate != null) {
        final candJson = jsonEncode({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
        final packed = await _packSignalPayload(candJson, 4);

        _wsClient.sendRaw({
          'type': 'signal',
          'version': 1,
          'signalType': 'ice_candidate',
          'senderDeviceId': _myDeviceId,
          'recipientDeviceId': peerDeviceId,
          'sessionEpoch': _wsClient.sessionEpoch,
          ...packed,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setCallState(CallState.connected);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _attemptIceReconnection();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        endCall(notifyPeer: false);
      }
    };
  }

  Future<void> _attemptIceReconnection() async {
    if (_peerConnection == null) return;
    _setCallState(CallState.reconnecting);
    try {
      await _peerConnection!.restartIce();
    } catch (_) {
      // Ignore if platform does not support restartIce
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      if (_callState == CallState.reconnecting) {
        endCall(notifyPeer: false);
      }
    });
  }

  void toggleMute() {
    if (_localStream != null) {
      _isMuted = !_isMuted;
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
  }

  void toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    setAudioRoute(_isSpeakerOn ? AudioRoute.speaker : AudioRoute.earpiece);
  }

  Future<void> setAudioRoute(AudioRoute route) async {
    _audioRoute = route;
    _isSpeakerOn = route == AudioRoute.speaker;
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enableSpeakerphone(_isSpeakerOn);
      }
    }
    try {
      await _securityChannel.invokeMethod('setAudioRoute', {'route': route.name});
    } catch (_) {
      // Ignore on non-Android environments
    }
  }

  Future<void> endCall({bool notifyPeer = true}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (notifyPeer && _callState != CallState.idle && _callState != CallState.ended) {
      _wsClient.sendRaw({
        'type': 'signal',
        'version': 1,
        'signalType': 'call_end',
        'senderDeviceId': _myDeviceId,
        'recipientDeviceId': _peerDeviceId,
        'sessionEpoch': _wsClient.sessionEpoch,
        'encryptedPayload': '',
        'iv': '',
        'authTag': '',
        'seq': 99,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    _stopTimer();
    await _stopForegroundCallService();

    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    _setCallState(CallState.idle);
  }

  void dispose() {
    _autoLockService.removeLockListener(_onAutoLock);
    _signalSub?.cancel();
    endCall(notifyPeer: false);
    _callStateController.close();
    _callDurationController.close();
  }
}
