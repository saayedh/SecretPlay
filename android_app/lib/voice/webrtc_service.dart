import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/constants.dart';
import '../core/relay_http_io.dart' if (dart.library.js_interop) '../core/relay_http_web.dart';
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
  MediaStream? _remoteStream;
  bool _remoteDescSet = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersInitialized = false;

  String _myDeviceId = 'me';
  String _peerDeviceId = 'peer';
  NetworkMode _networkMode = NetworkMode.cloud;
  SimpleKeyPair? _myIdentityKeyPair;
  String? _peerPublicKeyBase64;

  CallState _callState = CallState.idle;
  CallState get callState => _callState;

  bool _isVideoCall = false;
  bool get isVideoCall => _isVideoCall;

  bool _isCameraEnabled = true;
  bool get isCameraEnabled => _isCameraEnabled;

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

  final StreamController<void> _videoUpdateController =
      StreamController<void>.broadcast();
  Stream<void> get onVideoStreamUpdate => _videoUpdateController.stream;

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

  Future<void> ensureRenderersInitialized() async {
    if (_renderersInitialized) return;
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _renderersInitialized = true;
    } catch (e) {
      debugPrint('[WebRTC] Renderer init warning: $e');
    }
  }

  void configureIdentity({
    required String myDeviceId,
    required String peerDeviceId,
    required NetworkMode networkMode,
    SimpleKeyPair? myIdentityKeyPair,
    String? peerPublicKeyBase64,
    bool isVideoCall = false,
  }) {
    _myDeviceId = myDeviceId;
    if (peerDeviceId.isNotEmpty && peerDeviceId != 'peer') {
      _peerDeviceId = peerDeviceId;
    }
    _networkMode = networkMode;
    _myIdentityKeyPair = myIdentityKeyPair;
    _peerPublicKeyBase64 = peerPublicKeyBase64;
    _isVideoCall = isVideoCall;
    _isCameraEnabled = isVideoCall;
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
    if (kIsWeb) return;
    try {
      await _securityChannel.invokeMethod('startVoiceCallService');
    } catch (_) {}
  }

  Future<void> _stopForegroundCallService() async {
    if (kIsWeb) return;
    try {
      await _securityChannel.invokeMethod('stopVoiceCallService');
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _packSignalPayload(String plainJson, int fallbackSeq) async {
    final epoch = _wsClient.sessionEpoch ?? 'offline-room';
    if (_myIdentityKeyPair != null &&
        _peerPublicKeyBase64 != null &&
        _peerPublicKeyBase64!.isNotEmpty) {
      try {
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
      } catch (e) {
        debugPrint('[WebRTC] E2EE signal pack fallback: $e');
      }
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
    if (enc.isEmpty) return '{}';
    final iv = payload['iv'] as String? ?? '';
    final authTag = payload['authTag'] as String? ?? '';
    final eph = payload['ephemeralPubKey'] as String? ?? '';
    final sig = payload['signature'] as String? ?? '';
    final epoch = (payload['sessionEpoch'] as String?) ?? (_wsClient.sessionEpoch ?? 'offline-room');

    if (iv.isNotEmpty &&
        authTag.isNotEmpty &&
        eph.isNotEmpty &&
        sig.isNotEmpty &&
        _myIdentityKeyPair != null &&
        _peerPublicKeyBase64 != null &&
        _peerPublicKeyBase64!.isNotEmpty) {
      try {
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
      } catch (e) {
        debugPrint('[WebRTC] Decrypt signal warning: $e');
        return '{}';
      }
    }

    try {
      return utf8.decode(base64Decode(enc));
    } catch (_) {
      return '{}';
    }
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
          try {
            final meta = jsonDecode(await _unpackSignalPayload(payload)) as Map<String, dynamic>;
            if (meta['video'] == true) {
              _isVideoCall = true;
              _isCameraEnabled = true;
            }
          } catch (_) {}
          if (_callState == CallState.idle) {
            _setCallState(CallState.incomingRinging);
          }
          break;

        case 'call_accept':
          if (_callState == CallState.outgoingRinging || _callState == CallState.connecting) {
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

  Future<Map<String, dynamic>> _getIceServers(NetworkMode mode) async {
    if (mode == NetworkMode.local) {
      return {
        'iceServers': <Map<String, dynamic>>[],
        'sdpSemantics': 'unified-plan',
      };
    }
    try {
      final raw = await relayHttpGet('${AppConstants.cloudflareHttpBase}/turn')
          .timeout(const Duration(seconds: 2));
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['iceServers'] is List && (map['iceServers'] as List).isNotEmpty) {
          return {
            'iceServers': map['iceServers'],
            'sdpSemantics': 'unified-plan',
          };
        }
      }
    } catch (_) {}
    return {
      'iceServers': [
        {'urls': 'stun:stun.cloudflare.com:3478'},
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
  }

  Future<void> startCall({
    required String peerDeviceId,
    required String myDeviceId,
    required NetworkMode networkMode,
    bool video = false,
  }) async {
    _cryptoService.resetSignalInboundSequence();
    _myDeviceId = myDeviceId;
    if (peerDeviceId.isNotEmpty) _peerDeviceId = peerDeviceId;
    _networkMode = networkMode;
    _isVideoCall = video;
    _isCameraEnabled = video;
    _setCallState(CallState.outgoingRinging);
    await ensureRenderersInitialized();
    await _startForegroundCallService();

    if (_isVideoCall) {
      await setAudioRoute(AudioRoute.speaker);
      await _ensureLocalStream();
    }

    final reqMeta = jsonEncode({'video': video});
    final packed = await _packSignalPayload(reqMeta, 1);

    _wsClient.sendRaw({
      'type': 'signal',
      'version': 1,
      'signalType': 'call_request',
      'isVideo': video,
      'senderDeviceId': _myDeviceId,
      'recipientDeviceId': _peerDeviceId,
      'sessionEpoch': _wsClient.sessionEpoch ?? 'offline-room',
      ...packed,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> acceptCall({
    required String peerDeviceId,
    required String myDeviceId,
    required NetworkMode networkMode,
  }) async {
    _cryptoService.resetSignalInboundSequence();
    _myDeviceId = myDeviceId;
    if (peerDeviceId.isNotEmpty && peerDeviceId != 'peer') {
      _peerDeviceId = peerDeviceId;
    }
    _networkMode = networkMode;
    _setCallState(CallState.connecting);
    await ensureRenderersInitialized();
    await _startForegroundCallService();

    if (_isVideoCall) {
      await setAudioRoute(AudioRoute.speaker);
    }

    // Pre-initialize local media & PeerConnection so when Offer arrives it answers immediately!
    await _initPeerConnection(_networkMode, _peerDeviceId);

    _wsClient.sendRaw({
      'type': 'signal',
      'version': 1,
      'signalType': 'call_accept',
      'senderDeviceId': _myDeviceId,
      'recipientDeviceId': _peerDeviceId,
      'sessionEpoch': _wsClient.sessionEpoch ?? 'offline-room',
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
    if (peerDeviceId.isNotEmpty && peerDeviceId != 'peer') {
      _peerDeviceId = peerDeviceId;
    }
    _wsClient.sendRaw({
      'type': 'signal',
      'version': 1,
      'signalType': 'call_reject',
      'senderDeviceId': _myDeviceId,
      'recipientDeviceId': _peerDeviceId,
      'sessionEpoch': _wsClient.sessionEpoch ?? 'offline-room',
      'encryptedPayload': '',
      'iv': '',
      'authTag': '',
      'seq': 1,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await _stopForegroundCallService();
    _setCallState(CallState.ended);
    _setCallState(CallState.ended);
    _setCallState(CallState.idle);
  }

  Future<void> _createAndSendOffer(String peerDeviceId) async {
    await _initPeerConnection(_networkMode, peerDeviceId);

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': _isVideoCall ? 1 : 0,
    });
    await _peerConnection!.setLocalDescription(offer);

    final sdpJson = jsonEncode({
      'sdp': offer.sdp,
      'type': offer.type,
      'video': _isVideoCall,
    });
    final packed = await _packSignalPayload(sdpJson, 2);

    _wsClient.sendRaw({
      'type': 'signal',
      'version': 1,
      'signalType': 'offer',
      'senderDeviceId': _myDeviceId,
      'recipientDeviceId': peerDeviceId,
      'sessionEpoch': _wsClient.sessionEpoch ?? 'offline-room',
      ...packed,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _handleReceivedOffer(Map<String, dynamic> payload, String peerDeviceId) async {
    try {
      final rawSdpJson = await _unpackSignalPayload(payload);
      final map = jsonDecode(rawSdpJson) as Map<String, dynamic>;
      if (map['video'] == true && !_isVideoCall) {
        _isVideoCall = true;
        _isCameraEnabled = true;
        await setAudioRoute(AudioRoute.speaker);
      }

      if (_peerConnection == null) {
        await _initPeerConnection(_networkMode, peerDeviceId);
      } else if (_isVideoCall &&
          (_localStream == null || _localStream!.getVideoTracks().isEmpty)) {
        try {
          final camStream = await navigator.mediaDevices.getUserMedia({
            'audio': false,
            'video': {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 24},
            },
          });
          for (final vt in camStream.getVideoTracks()) {
            _localStream?.addTrack(vt);
            await _peerConnection!.addTrack(vt, _localStream ?? camStream);
          }
          localRenderer.srcObject = _localStream ?? camStream;
          if (!_videoUpdateController.isClosed) _videoUpdateController.add(null);
        } catch (_) {}
      }

      final description = RTCSessionDescription(map['sdp'] as String?, map['type'] as String?);
      await _peerConnection!.setRemoteDescription(description);
      _remoteDescSet = true;
      await _flushPendingIceCandidates();

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': _isVideoCall ? 1 : 0,
      });
      await _peerConnection!.setLocalDescription(answer);

      final answerJson = jsonEncode({
        'sdp': answer.sdp,
        'type': answer.type,
        'video': _isVideoCall,
      });
      final packed = await _packSignalPayload(answerJson, 3);

      _wsClient.sendRaw({
        'type': 'signal',
        'version': 1,
        'signalType': 'answer',
        'senderDeviceId': _myDeviceId,
        'recipientDeviceId': peerDeviceId,
        'sessionEpoch': _wsClient.sessionEpoch ?? 'offline-room',
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
      _remoteDescSet = true;
      await _flushPendingIceCandidates();
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
      if (_peerConnection != null && _remoteDescSet) {
        await _peerConnection!.addCandidate(candidate);
      } else {
        _pendingRemoteCandidates.add(candidate);
      }
    } catch (e) {
      debugPrint('[WebRTC] Error adding ICE candidate: $e');
    }
  }

  Future<void> _flushPendingIceCandidates() async {
    if (_peerConnection == null || !_remoteDescSet) return;
    while (_pendingRemoteCandidates.isNotEmpty) {
      final cand = _pendingRemoteCandidates.removeAt(0);
      try {
        await _peerConnection!.addCandidate(cand);
      } catch (_) {}
    }
  }

  Future<void> _ensureLocalStream() async {
    if (_localStream != null) {
      if (!_isVideoCall || _localStream!.getVideoTracks().isNotEmpty) return;
    }
    await ensureRenderersInitialized();
    final mediaConstraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': _isVideoCall
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640, 'max': 1280},
              'height': {'ideal': 480, 'max': 720},
              'frameRate': {'ideal': 24, 'max': 30},
            }
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      debugPrint('[WebRTC] Video/Audio getUserMedia fallback to audio-only: $e');
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
      } catch (_) {}
    }

    if (_localStream != null) {
      localRenderer.srcObject = _localStream;
      if (!_videoUpdateController.isClosed) {
        _videoUpdateController.add(null);
      }
    }
  }

  Future<void> _initPeerConnection(NetworkMode mode, String peerDeviceId) async {
    if (_peerConnection != null) return;
    await ensureRenderersInitialized();

    final config = await _getIceServers(mode);
    _peerConnection = await createPeerConnection(config);
    _remoteDescSet = false;

    await _ensureLocalStream();

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    } else {
      // Ensure SDP still negotiates receive-only audio/video if local mic/camera is unavailable on desktop
      try {
        await _peerConnection!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
        if (_isVideoCall) {
          await _peerConnection!.addTransceiver(
            kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
            init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
          );
        }
      } catch (_) {}
    }

    _peerConnection!.onTrack = (RTCTrackEvent event) async {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      } else {
        _remoteStream ??= await createLocalMediaStream('remote_media');
        await _remoteStream!.addTrack(event.track);
      }
      if (event.track.kind == 'audio') {
        event.track.enabled = true;
      }
      remoteRenderer.srcObject = _remoteStream;
      for (final audioTrack in _remoteStream!.getAudioTracks()) {
        audioTrack.enabled = true;
      }
      if (!_videoUpdateController.isClosed) {
        _videoUpdateController.add(null);
      }
    };

    _peerConnection!.onAddStream = (MediaStream stream) {
      _remoteStream = stream;
      remoteRenderer.srcObject = stream;
      if (!_videoUpdateController.isClosed) {
        _videoUpdateController.add(null);
      }
    };

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
          'sessionEpoch': _wsClient.sessionEpoch ?? 'offline-room',
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

    _peerConnection!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _setCallState(CallState.connected);
      }
    };
  }

  Future<void> _attemptIceReconnection() async {
    if (_peerConnection == null) return;
    _setCallState(CallState.reconnecting);
    try {
      await _peerConnection!.restartIce();
    } catch (_) {}
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

  void toggleCamera() {
    if (_localStream != null) {
      _isCameraEnabled = !_isCameraEnabled;
      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = _isCameraEnabled;
      }
      if (!_videoUpdateController.isClosed) {
        _videoUpdateController.add(null);
      }
    }
  }

  Future<void> switchCamera() async {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        try {
          await Helper.switchCamera(videoTracks.first);
        } catch (_) {}
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
    if (!kIsWeb && _localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        try {
          track.enableSpeakerphone(_isSpeakerOn);
        } catch (_) {}
      }
    }
    if (!kIsWeb) {
      try {
        await _securityChannel.invokeMethod('setAudioRoute', {'route': route.name});
      } catch (_) {}
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
        'sessionEpoch': _wsClient.sessionEpoch ?? 'offline-room',
        'encryptedPayload': '',
        'iv': '',
        'authTag': '',
        'seq': 99,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    _stopTimer();
    await _stopForegroundCallService();

    try {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    } catch (_) {}

    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;
    _remoteStream = null;
    _remoteDescSet = false;
    _pendingRemoteCandidates.clear();

    await _peerConnection?.close();
    _peerConnection = null;

    _setCallState(CallState.ended);
    _setCallState(CallState.idle);
  }

  void dispose() {
    _autoLockService.removeLockListener(_onAutoLock);
    _signalSub?.cancel();
    endCall(notifyPeer: false);
    if (_renderersInitialized) {
      localRenderer.dispose();
      remoteRenderer.dispose();
      _renderersInitialized = false;
    }
    _callStateController.close();
    _callDurationController.close();
    _videoUpdateController.close();
  }
}
